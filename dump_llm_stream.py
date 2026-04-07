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
"""

import json
import os
import time
from datetime import datetime, timezone

from mitmproxy import http

OUTPUT_DIR = os.path.expanduser("~/data/capture")
FLAG = os.path.expanduser("~/.mitmproxy/capture.flag")
HOSTS = {"openrouter.ai", "api.anthropic.com"}

os.makedirs(OUTPUT_DIR, exist_ok=True)


def is_llm_flow(flow: http.HTTPFlow) -> bool:
    return any(h in flow.request.pretty_host for h in HOSTS)

def parse_sse(body: str) -> list:
    events = []
    for line in body.splitlines():
        if line.startswith("data: ") and line != "data: [DONE]":
            try:
                events.append(json.loads(line[6:]))
            except json.JSONDecodeError:
                pass
    return events

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

        response_body = b"".join(flow._llm_chunks).decode("utf-8", errors="replace")
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
