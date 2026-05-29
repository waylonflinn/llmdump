#!/usr/bin/env python3
"""
cache_report.py — summarize cache usage across mitmproxy captures.

Usage:
    python3 cache_report.py [--start YYYYMMDDTHHMMSS] [--end YYYYMMDDTHHMMSS] [--n N]

Scans all directories in ~/data/capture/, extracts token/cost/cache info
from response.json, and prints a table sorted by timestamp.
"""

import argparse
import json
import os
import sys
from datetime import datetime, timedelta

CAPTURE_DIR = os.environ.get("LLMDUMP_CAPTURE_DIR", os.path.expanduser("~/.cache/llmdump/capture/"))
TS_FMT = "%Y%m%dT%H%M%S"
DT_FMT = "%Y%m%d"

# Anthropic per-million-token rates ($USD), keyed by model alias prefix.
# Order: input, cache_write_5m, cache_write_1h, cache_read, output.
ANTHROPIC_RATES_USD_PER_MTOK = {
    "claude-opus-4-8":   (5.0, 6.25, 10.0, 0.50, 25.0),
    "claude-opus-4-7":   (5.0, 6.25, 10.0, 0.50, 25.0),
    "claude-opus-4-6":   (5.0, 6.25, 10.0, 0.50, 25.0),
    "claude-sonnet-4-6": (3.0, 3.75,  6.0, 0.30, 15.0),
    "claude-sonnet-4-5": (3.0, 3.75,  6.0, 0.30, 15.0),
    "claude-haiku-4-5":  (1.0, 1.25,  2.0, 0.10,  5.0),
}


def anthropic_rates(model: str):
    """Longest-prefix match of model name against the rate table."""
    if not model:
        return None
    for prefix in sorted(ANTHROPIC_RATES_USD_PER_MTOK, key=len, reverse=True):
        if model.startswith(prefix):
            return ANTHROPIC_RATES_USD_PER_MTOK[prefix]
    return None


def anthropic_cost(merged_usage: dict, model: str) -> float | None:
    """Compute $USD cost from an Anthropic usage block + model alias.

    Splits cache writes into 5m vs 1h tiers when the breakdown is present;
    otherwise lumps the total under the 5m rate (the default TTL).
    """
    rates = anthropic_rates(model)
    if rates is None:
        return None
    in_rate, w5_rate, w1h_rate, read_rate, out_rate = rates
    new_in     = merged_usage.get("input_tokens") or 0
    cache_read = merged_usage.get("cache_read_input_tokens") or 0
    creation   = merged_usage.get("cache_creation") or {}
    w5  = creation.get("ephemeral_5m_input_tokens")
    w1h = creation.get("ephemeral_1h_input_tokens")
    if w5 is None and w1h is None:
        w5  = merged_usage.get("cache_creation_input_tokens") or 0
        w1h = 0
    else:
        w5  = w5  or 0
        w1h = w1h or 0
    out = merged_usage.get("output_tokens") or 0
    return (
        new_in     * in_rate     +
        cache_read * read_rate   +
        w5         * w5_rate     +
        w1h        * w1h_rate    +
        out        * out_rate
    ) / 1_000_000


def parse_dir_ts(dirname: str) -> datetime | None:
    """Extract and parse timestamp from directory name like 20260407T105438_openrouter_ai."""
    part = dirname.split("_")[0]
    try:
        return datetime.strptime(part, TS_FMT)
    except ValueError:
        return None

def parse_user_ts(user_input: str) -> datetime | None:
    """Parse timestamp from user input, matching only date or full ISO 8601 short form."""

    if(user_input is None):
        return None
    try:
        if len(user_input) == 8:
            return datetime.strptime(user_input, DT_FMT)
        if len(user_input) == 15:
            return datetime.strptime(user_input, TS_FMT)
        else:
            return None
    except ValueError:
        return None


def agent_from_model(model: str) -> str:
    """Derive a short agent label from the model string."""
    if not model:
        return "?"
    model = model.lower()
    if "claude" in model:
        return "henry"
    if "qwen" in model or "glm" in model:
        return "heinrich"
    # Fall back to the last path component before any colon
    base = model.split("/")[-1].split(":")[0]
    return base[:10]

# TODO: make this more robust by adding an argument for provider
def normalize_model(model: str) -> str:

    # direct anthropic api: model names start with "claude-"
    if(model.startswith("claude-")):
        model_name = model[7:-4]
        model_version = model[-3:]
        model_version = model_version.replace("-", ".")
        return f"{model_name} {model_version}"

    # openrouter: model names start with the provider
    if(model.startswith("anthropic/claude-")):
        model_name = model[17:-4]
        model_version = model[-3:]
        model_version = model_version.replace("-", ".")
        return f"{model_name} {model_version}"

    if(model.startswith("z-ai/")):
        model_name = model[5:-4]
        model_version = model[-3:]
        model_version = model_version.replace("-", ".")
        return f"{model_name} {model_version}"

    return model

def extract_usage(response_path: str) -> dict | None:
    """
    Parse response.json and return a normalized usage dict, or None.

    Output keys: prompt, cached, written, completion, cost.
    Handles both OpenAI/OpenRouter and Anthropic native schemas.
    """
    try:
        with open(response_path) as f:
            events = json.load(f)
    except (json.JSONDecodeError, OSError):
        return None
    if not isinstance(events, list):
        return None

    # Merge usage from every event that carries one. Walking forward and
    # only overwriting with non-null values means later events (e.g.
    # Anthropic's message_delta) override earlier ones (message_start)
    # while still preserving fields the later event omits.
    merged = {}
    model = None
    for event in events:
        if not isinstance(event, dict):
            continue
        # Anthropic message_start nests usage and model under .message
        msg = event.get("message")
        if isinstance(msg, dict):
            if isinstance(msg.get("usage"), dict):
                merged.update({k: v for k, v in msg["usage"].items() if v is not None})
            if not model and msg.get("model"):
                model = msg["model"]
        # Anthropic message_delta and OpenRouter chunks put usage at the top level
        if isinstance(event.get("usage"), dict):
            merged.update({k: v for k, v in event["usage"].items() if v is not None})
        if not model and event.get("model"):
            model = event["model"]

    if not merged:
        return None

    # Anthropic native schema
    if "input_tokens" in merged or "output_tokens" in merged:
        new_input = merged.get("input_tokens") or 0
        cached    = merged.get("cache_read_input_tokens") or 0
        written   = merged.get("cache_creation_input_tokens") or 0
        return {
            "prompt":     new_input + cached + written,
            "cached":     cached,
            "written":    written,
            "completion": merged.get("output_tokens"),
            "cost":       anthropic_cost(merged, model),
        }

    # OpenAI / OpenRouter schema
    details = merged.get("prompt_tokens_details") or {}
    return {
        "prompt":     merged.get("prompt_tokens"),
        "cached":     details.get("cached_tokens"),
        "written":    details.get("cache_write_tokens"),
        "completion": merged.get("completion_tokens"),
        "cost":       merged.get("cost"),
    }


def fmt(val, fmt_str=None, default="—"):
    if val is None:
        return default
    if fmt_str:
        return fmt_str.format(val)
    return str(val)


def main():
    parser = argparse.ArgumentParser(description="Summarize cache usage from mitmproxy captures.")
    parser.add_argument("-s", "--start", metavar="YYYYMMDDTHHMMSS", help="Include captures at or after this timestamp")
    parser.add_argument("-e", "--end",   metavar="YYYYMMDDTHHMMSS", help="Include captures at or before this timestamp")
    parser.add_argument("-d", "--day",   metavar="YYYYMMDD", help="Include captures after this timestamp and within 24 hrs (overrides -s and -e)")
    parser.add_argument("-n", metavar="N", type=int, help="Show only the most recent N results")
    parser.add_argument("-a", "--agent", metavar="AGENT", help="Filter by agent name (e.g. henry, heinrich)")
    parser.add_argument("-A", "--all", action="store_true", help="Include captures with no usable usage data (telemetry, count_tokens, etc.)")
    args = parser.parse_args()

    if(args.day is not None):
        start_dt = parse_user_ts(args.day)
        end_dt = start_dt + timedelta(days=1)
    else:
        start_dt = parse_user_ts(args.start)
        end_dt   = parse_user_ts(args.end)

    try:
        entries = sorted(os.listdir(CAPTURE_DIR))
    except FileNotFoundError:
        print(f"Capture directory not found: {CAPTURE_DIR}", file=sys.stderr)
        sys.exit(1)

    rows = []
    for dirname in entries:
        ts = parse_dir_ts(dirname)
        if ts is None:
            continue
        if start_dt and ts < start_dt:
            continue
        if end_dt and ts > end_dt:
            continue

        response_path = os.path.join(CAPTURE_DIR, dirname, "response.json")
        usage = extract_usage(response_path) if os.path.exists(response_path) else None

        # Determine request type and agent from request.json
        request_path = os.path.join(CAPTURE_DIR, dirname, "request.json")
        req_type = "—"
        agent = "?"
        if os.path.exists(request_path):
            try:
                with open(request_path) as f:
                    req = json.load(f)
                if type(req) is not dict:
                    #print(f"Invalid capture found {request_path}.")
                    continue
                msgs = req.get("messages", [])
                if msgs:
                    last = msgs[-1]
                    last_content = last.get("content")
                    has_tool_result = isinstance(last_content, list) and any(
                        isinstance(b, dict) and b.get("type") == "tool_result"
                        for b in last_content
                    )
                    if last.get("role") == "tool" or has_tool_result:
                        req_type = "tool"
                    else:
                        req_type = "user"
                agent = agent_from_model(req.get("model", ""))
            except (json.JSONDecodeError, OSError):
                pass

        if args.agent and agent != args.agent:
            continue

        if not usage and not args.all:
            continue

        if usage:
            prompt     = usage["prompt"]
            cached     = usage["cached"]
            written    = usage["written"]
            completion = usage["completion"]
            cost       = usage["cost"]
            hit_pct    = round(100 * cached / prompt, 1) if (cached is not None and prompt) else None
        else:
            prompt = cached = written = completion = cost = hit_pct = None

        rows.append({
            "ts":         ts.strftime(TS_FMT),
            "agent":      agent,
            "model":      normalize_model(req.get("model", "")),
            "type":       req_type,
            "prompt":     prompt,
            "cached":     cached,
            "written":    written,
            "hit_pct":    hit_pct,
            "completion": completion,
            "cost":       cost,
        })

    if not rows:
        print("No captures found in range.")
        return

    if args.n:
        rows = rows[-args.n:]

    # Column widths
    headers = ["timestamp",  "model",   "type",  "prompt",   "output",  "read",  "write", "hit%", "cost ($)"]

    def row_vals(r):
        return [
            r["ts"],
            r["model"],
            r["type"],
            fmt(r["prompt"],     "{:,}"),
            fmt(r["completion"], "{:,}"),
            fmt(r["cached"],     "{:,}"),
            fmt(r["written"],    "{:,}"),
            fmt(r["hit_pct"],    "{:.1f}%"),
            fmt(r["cost"],       "{:.4f}"),
        ]

    # Auto-size columns to content
    all_rows = [headers] + [row_vals(r) for r in rows]
    col_widths = [max(len(cell) for cell in col) for col in zip(*all_rows)]

    sep = "  ".join("-" * w for w in col_widths)
    hdr = "  ".join(h.ljust(w) for h, w in zip(headers, col_widths))

    print(hdr)
    print(sep)
    total = 0 # total cost
    total_fixed = 0 # cost estimate for fixed caching (approximate)
    for r in rows:
        cost = r["cost"] if r["cost"] is not None else 0
        total += cost
        total_fixed += cost if r["cached"] != 0 else cost * 0.1

        vals = row_vals(r)
        # Left-align timestamp, model, type; right-align numeric columns
        cells = [vals[0].ljust(col_widths[0]), vals[1].ljust(col_widths[1]), vals[2].ljust(col_widths[2])]
        for v, w in zip(vals[3:], col_widths[3:]):
            cells.append(v.rjust(w))
        print("  ".join(cells))

    print()
    print("Cache Bust Cost Estimate")
    print(f"current: ${total:.2f}\tfixed: ${total_fixed:.2f}\tdelta: ${total-total_fixed:.2f}")

if __name__ == "__main__":
    main()
