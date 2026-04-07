"""
dump_llm.py — mitmproxy addon to capture LLM API requests/responses as JSON files.

Usage:
    mitmdump -p 8080 -s ~/.mitmproxy/dump_llm.py

Toggle capture without restarting anything:
    touch ~/.mitmproxy/capture.flag    # enable
    rm ~/.mitmproxy/capture.flag       # disable

Each intercepted request to OpenRouter or Anthropic is written to:
    ~/data/capture/<timestamp>_<host>/request|respose|metadata.json
"""

import json
import os
import time

from mitmproxy import http

OUTPUT_DIR = os.path.expanduser("~/data/capture/")
FLAG = os.path.expanduser("~/.mitmproxy/capture.flag")
HOSTS = {"openrouter.ai", "api.anthropic.com"}

os.makedirs(OUTPUT_DIR, exist_ok=True)



class DumpLLM:
    def request(self, flow: http.HTTPFlow):
        if not any(h in flow.request.pretty_host for h in HOSTS):
            return
        flow._llm_ts = int(time.time() * 1000)

    def response(self, flow: http.HTTPFlow):
        host = flow.request.pretty_host

        if not any(h in host for h in HOSTS):
            return
        if not os.path.exists(FLAG):
            return

        ts = getattr(flow, "_llm_ts", int(time.time() * 1000))
        out = {
            "timestamp": ts,
            "host": host,
            "path": flow.request.path,
            "method": flow.request.method,
            "request_headers": dict(flow.request.headers),
            "request_body": flow.request.get_text(strict=False),
            "status": flow.response.status_code,
            "response_headers": dict(flow.response.headers),
            "response_body": flow.response.get_text(strict=False),
        }

        fname = f"{OUTPUT_DIR}/{ts}_{host.replace('.', '_')}.json"
        with open(fname, "w") as f:
            json.dump(out, f, indent=2)

        print(f"[dump_llm] captured {flow.request.method} {host}{flow.request.path} → {fname}")


addons = [DumpLLM()]
