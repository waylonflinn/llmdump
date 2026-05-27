"""
dump_llm.py — mitmproxy addon to capture LLM API requests/responses as JSON files.
Supports streaming (SSE) responses — chunks pass through immediately, no latency added.

Usage:
    mitmdump -p 8080 -s ~/.mitmproxy/dump_llm_stream.py

Toggle capture without restarting anything:
    touch ~/.mitmproxy/capture.flag    # enable
    rm ~/.mitmproxy/capture.flag       # disable

Each captured request is written to:
    ~/data/capture/<timestamp>_<host>/request|respose|metadata.json

The request_body field contains the full prompt including cache_control blocks.
The response_body field contains the full SSE stream reassembled as a string.

Deploy to ~/scripts/ to update the mitmdump proxy
"""

import gzip
import json
import os
import time
import zlib
from datetime import datetime, timezone

from mitmproxy import http


def decode_body(raw: bytes, content_encoding: str) -> bytes:
    """Decompress a response body based on its Content-Encoding header."""
    encoding = (content_encoding or "").lower().strip()
    if encoding in ("", "identity"):
        return raw
    if encoding == "gzip":
        return gzip.decompress(raw)
    if encoding == "deflate":
        try:
            return zlib.decompress(raw)
        except zlib.error:
            return zlib.decompress(raw, -zlib.MAX_WBITS)
    if encoding == "br":
        import brotli
        return brotli.decompress(raw)
    if encoding == "zstd":
        import zstandard
        return zstandard.ZstdDecompressor().decompress(raw)
    print(f"[dump_llm] unknown Content-Encoding {encoding!r}; storing raw bytes")
    return raw

OUTPUT_DIR = os.path.expanduser("~/data/capture")
FLAG = os.path.expanduser("~/.mitmproxy/capture.flag")
HOSTS = {"openrouter.ai", "api.anthropic.com"}

os.makedirs(OUTPUT_DIR, exist_ok=True)


def is_llm_flow(flow: http.HTTPFlow) -> bool:
    return any(h in flow.request.pretty_host for h in HOSTS)

def parse_sse(body: str) -> list:
    """
    Parse Server-Sent Events (SSE) streams into a clean list of JSON objects.
    Compatible with both OpenAI/OpenRouter and native Anthropic (Claude Code) schemas.
    """
    events = []
    for line in body.splitlines():
        line = line.strip()

        # Skip empty lines, comments, and event-type lines used by Anthropic
        if not line or line.startswith(":") or line.startswith("event:"):
            continue

        if line.startswith("data:"):
            # Strip out "data: " marker (handles 'data:' and 'data: ')
            data_content = line[5:].strip()

            # Skip standard termination tokens
            if data_content in ("[DONE]", ""):
                continue

            try:
                events.append(json.loads(data_content))
            except json.JSONDecodeError:
                pass

    return events

def extract_last_user_text(request_body: dict) -> str:
    """Extract text content from the last user message in the request."""
    messages = request_body.get("messages", []) if isinstance(request_body, dict) else []
    for msg in reversed(messages):
        if msg.get("role") == "user":
            content = msg.get("content", "")
            if isinstance(content, str):
                return content
            if isinstance(content, list):
                return "\n".join(
                    block["text"] for block in content
                    if isinstance(block, dict) and block.get("type") == "text" and "text" in block
                )
    return ""


def extract_response_text(events: list) -> str:
    """
    Build a tagged transcript of the assistant turn.

    Visible text is emitted inline; extended thinking and tool-use inputs are
    wrapped in [thinking]...[/thinking] and [tool_use name="..."]...[/tool_use]
    blocks. Handles both Anthropic native and OpenAI/OpenRouter SSE formats.
    """
    parts = []
    anth_block = {}  # Anthropic: index -> (block_type, name)
    or_mode = None   # OpenRouter: None | "text" | "reasoning"
    or_tools = {}    # OpenRouter: tool_call index -> name (while open)

    def close_or_reasoning():
        nonlocal or_mode
        if or_mode == "reasoning":
            parts.append("\n[/thinking]\n")
            or_mode = None

    def close_or_tools():
        for _ in list(or_tools):
            parts.append("\n[/tool_use]\n")
            or_tools.popitem()

    for event in events:
        et = event.get("type")

        # --- Anthropic native format ---
        if et == "content_block_start":
            idx = event.get("index", 0)
            cb = event.get("content_block", {}) or {}
            cb_type = cb.get("type")
            name = cb.get("name")
            anth_block[idx] = (cb_type, name)
            if cb_type == "thinking":
                parts.append("\n[thinking]\n")
            elif cb_type == "tool_use":
                parts.append(f'\n[tool_use name="{name}"]\n')
            continue

        if et == "content_block_delta":
            delta = event.get("delta", {}) or {}
            dt = delta.get("type")
            if dt == "text_delta":
                parts.append(delta.get("text", ""))
            elif dt == "thinking_delta":
                parts.append(delta.get("thinking", ""))
            elif dt == "input_json_delta":
                parts.append(delta.get("partial_json", ""))
            continue

        if et == "content_block_stop":
            block = anth_block.pop(event.get("index", 0), None)
            if block:
                cb_type, _ = block
                if cb_type == "thinking":
                    parts.append("\n[/thinking]\n")
                elif cb_type == "tool_use":
                    parts.append("\n[/tool_use]\n")
            continue

        # --- OpenAI / OpenRouter format ---
        for choice in event.get("choices", []):
            delta = choice.get("delta", {}) or {}

            reasoning = delta.get("reasoning") or delta.get("reasoning_content")
            if reasoning:
                if or_mode != "reasoning":
                    close_or_tools()
                    parts.append("\n[thinking]\n")
                    or_mode = "reasoning"
                parts.append(reasoning)

            content = delta.get("content")
            if content:
                close_or_reasoning()
                close_or_tools()
                or_mode = "text"
                parts.append(content)

            for tc in delta.get("tool_calls") or []:
                tc_idx = tc.get("index", 0)
                fn = tc.get("function", {}) or {}
                name = fn.get("name")
                args = fn.get("arguments", "")
                if name and tc_idx not in or_tools:
                    close_or_reasoning()
                    parts.append(f'\n[tool_use name="{name}"]\n')
                    or_tools[tc_idx] = name
                if args:
                    parts.append(args)

            if choice.get("finish_reason") is not None:
                close_or_reasoning()
                close_or_tools()

    # Close anything still open at stream end
    close_or_reasoning()
    close_or_tools()
    for cb_type, _ in anth_block.values():
        if cb_type == "thinking":
            parts.append("\n[/thinking]\n")
        elif cb_type == "tool_use":
            parts.append("\n[/tool_use]\n")

    return "".join(parts)


class DumpLLM:
    def request(self, flow: http.HTTPFlow):
        """Capture request body before response begins."""
        if not is_llm_flow(flow):
            return
        # Store on flow object — available later in response hook
        flow._llm_ts = int(time.time() * 1000)
        flow._llm_request_headers = dict(flow.request.headers)
        flow._llm_request_body = flow.request.get_text(strict=False)

    def responseheaders(self, flow: http.HTTPFlow):
        """
        Enable streaming. Chunks pass through to the client immediately
        (no first-token latency), but are also accumulated for the trace file.
        Only set up collection if capture flag is present at stream start.
        """
        if not is_llm_flow(flow):
            return
        if not os.path.exists(FLAG):
            return

        flow._llm_chunks = []

        def collect(chunk: bytes) -> bytes:
            flow._llm_chunks.append(chunk)
            return chunk  # unmodified passthrough

        flow.response.stream = collect

    def response(self, flow: http.HTTPFlow):
        """
        Fires after all chunks have been transmitted. Write the trace file.
        flow.response.content is empty when streaming; use _llm_chunks instead.
        """
        if not is_llm_flow(flow):
            return
        if not hasattr(flow, "_llm_request_body"):
            return
        if not hasattr(flow, "_llm_chunks"):
            # Capture flag wasn't set at stream start — skip
            return

        raw = b"".join(flow._llm_chunks)
        try:
            decoded = decode_body(raw, flow.response.headers.get("Content-Encoding", ""))
        except Exception as e:
            print(f"[dump_llm] failed to decompress response: {e}; falling back to raw bytes")
            decoded = raw
        response_body = decoded.decode("utf-8", errors="replace")
        host = flow.request.pretty_host
        ts = flow._llm_ts
        ts_iso = datetime.fromtimestamp(ts / 1000).strftime('%Y%m%dT%H%M%S')

        dirname = f"{OUTPUT_DIR}/{ts_iso}_{host.replace('.', '_')}"
        os.makedirs(dirname, exist_ok=True)

        # request.json — parsed
        try:
            request_body = json.loads(flow._llm_request_body)
        except json.JSONDecodeError:
            request_body = flow._llm_request_body
        with open(f"{dirname}/request.json", "w") as f:
            json.dump(request_body, f, indent=2) #  sort_keys=True

        # response.json — SSE parsed into array of events
        with open(f"{dirname}/response.json", "w") as f:
            json.dump(parse_sse(response_body), f, indent=2)

        # request.txt — last user message text
        with open(f"{dirname}/request.txt", "w") as f:
            f.write(extract_last_user_text(request_body))

        # response.txt — assistant response text
        with open(f"{dirname}/response.txt", "w") as f:
            f.write(extract_response_text(parse_sse(response_body)))

        # metadata.json — headers, status, timing
        metadata = {
            "timestamp": ts_iso,
            "host": host,
            "path": flow.request.path,
            "method": flow.request.method,
            "status": flow.response.status_code,
            "request_headers": flow._llm_request_headers,
            "response_headers": dict(flow.response.headers),
        }
        with open(f"{dirname}/metadata.json", "w") as f:
            json.dump(metadata, f, indent=2)

        print(f"[dump_llm] {flow.request.method} {host}{flow.request.path} "
            f"status={flow.response.status_code} → {dirname}/")


addons = [DumpLLM()]
