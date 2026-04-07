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
from datetime import datetime

CAPTURE_DIR = os.path.expanduser("~/data/capture")
TS_FMT = "%Y%m%dT%H%M%S"


def parse_ts(dirname: str) -> datetime | None:
    """Extract timestamp from directory name like 20260407T105438_openrouter_ai."""
    part = dirname.split("_")[0]
    try:
        return datetime.strptime(part, TS_FMT)
    except ValueError:
        return None


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
    parser.add_argument("--start", metavar="YYYYMMDDTHHMMSS", help="Include captures at or after this timestamp")
    parser.add_argument("--end",   metavar="YYYYMMDDTHHMMSS", help="Include captures at or before this timestamp")
    parser.add_argument("-n", metavar="N", type=int, help="Show only the most recent N results")
    args = parser.parse_args()

    start_dt = datetime.strptime(args.start, TS_FMT) if args.start else None
    end_dt   = datetime.strptime(args.end,   TS_FMT) if args.end   else None

    try:
        entries = sorted(os.listdir(CAPTURE_DIR))
    except FileNotFoundError:
        print(f"Capture directory not found: {CAPTURE_DIR}", file=sys.stderr)
        sys.exit(1)

    rows = []
    for dirname in entries:
        ts = parse_ts(dirname)
        if ts is None:
            continue
        if start_dt and ts < start_dt:
            continue
        if end_dt and ts > end_dt:
            continue

        response_path = os.path.join(CAPTURE_DIR, dirname, "response.json")
        usage = extract_usage(response_path) if os.path.exists(response_path) else None

        # Determine request type from last message role
        request_path = os.path.join(CAPTURE_DIR, dirname, "request.json")
        req_type = "—"
        if os.path.exists(request_path):
            try:
                with open(request_path) as f:
                    req = json.load(f)
                msgs = req.get("messages", [])
                if msgs:
                    req_type = "tool" if msgs[-1].get("role") == "tool" else "user"
            except (json.JSONDecodeError, OSError):
                pass

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
    headers = ["timestamp",  "type",  "prompt",  "cached",  "written", "hit%",   "completion", "cost ($)"]

    def row_vals(r):
        return [
            r["ts"],
            r["type"],
            fmt(r["prompt"],     "{:,}"),
            fmt(r["cached"],     "{:,}"),
            fmt(r["written"],    "{:,}"),
            fmt(r["hit_pct"],    "{:.1f}%"),
            fmt(r["completion"], "{:,}"),
            fmt(r["cost"],       "{:.6f}"),
        ]

    # Auto-size columns to content
    all_rows = [headers] + [row_vals(r) for r in rows]
    col_widths = [max(len(cell) for cell in col) for col in zip(*all_rows)]

    sep = "  ".join("-" * w for w in col_widths)
    hdr = "  ".join(h.ljust(w) for h, w in zip(headers, col_widths))

    print(hdr)
    print(sep)
    for r in rows:
        vals = row_vals(r)
        # Left-align timestamp and type; right-align numeric columns
        cells = [vals[0].ljust(col_widths[0]), vals[1].ljust(col_widths[1])]
        for v, w in zip(vals[2:], col_widths[2:]):
            cells.append(v.rjust(w))
        print("  ".join(cells))


if __name__ == "__main__":
    main()
