#!/usr/bin/env python3
"""
cache_report.py — summarize cache usage across mitmproxy captures.

Usage:
    python3 cache_report.py [--start YYYYMMDDTHHMMSS] [--end YYYYMMDDTHHMMSS]

Scans all directories in ~/data/capture/, extracts token/cost/cache info
from response.json, and prints a table sorted by timestamp.
"""

import argparse
import json
import os
import sys
from datetime import datetime, timedelta

CAPTURE_DIR = os.path.expanduser("~/data/capture")
TS_FMT = "%Y%m%dT%H%M%S"
DT_FMT = "%Y%m%d"


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


def extract_usage(response_path: str) -> dict | None:
    """Parse response.json and return the usage block, or None."""
    try:
        with open(response_path) as f:
            events = json.load(f)
        for event in reversed(events):
            if "usage" in event:
                return event["usage"]
    except (json.JSONDecodeError, OSError):
        pass
    return None


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
                msgs = req.get("messages", [])
                if msgs:
                    req_type = "tool" if msgs[-1].get("role") == "tool" else "user"
                agent = agent_from_model(req.get("model", ""))
            except (json.JSONDecodeError, OSError):
                pass

        if args.agent and agent != args.agent:
            continue

        if usage:
            details = usage.get("prompt_tokens_details", {})
            prompt   = usage.get("prompt_tokens")
            cached   = details.get("cached_tokens")
            written  = details.get("cache_write_tokens")
            completion = usage.get("completion_tokens")
            cost     = usage.get("cost")
            hit_pct  = round(100 * cached / prompt, 1) if (cached is not None and prompt) else None
        else:
            prompt = cached = written = completion = cost = hit_pct = None

        rows.append({
            "ts":         ts.strftime(TS_FMT),
            "agent":      agent,
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
    headers = ["timestamp",  "agent",   "type",  "prompt",   "output",  "read",  "written", "hit%", "cost ($)"]

    def row_vals(r):
        return [
            r["ts"],
            r["agent"],
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
        # Left-align timestamp, agent, type; right-align numeric columns
        cells = [vals[0].ljust(col_widths[0]), vals[1].ljust(col_widths[1]), vals[2].ljust(col_widths[2])]
        for v, w in zip(vals[3:], col_widths[3:]):
            cells.append(v.rjust(w))
        print("  ".join(cells))

    print()
    print("Cache Bust Cost Analysis")
    print(f"total: ${total:.2f}\tfixed: ${total_fixed:.2f}\tdelta: ${total-total_fixed:.2f}")

if __name__ == "__main__":
    main()
