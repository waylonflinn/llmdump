# mitmproxy LLM capture setup

Intercepts OpenClaw's outbound HTTPS requests to OpenRouter/Anthropic and writes
each capture to `~/data/capture/<timestamp>_<host>/` containing three files:
`request.json`, `response.json`, and `metadata.json`. Captures raw `cache_control`
blocks and full SSE streams without adding latency to normal operation.

**Streaming:** chunks pass through to the client immediately — no first-token
latency added. The trace files are written after the stream completes.

**Toggle capture:** via a flag file. No restarts required after initial setup.

## Prerequisites

- `mitmproxy` is already installed at `/usr/bin/mitmdump`
- CA cert already installed at `/usr/local/share/ca-certificates/mitmproxy.crt`

## Step 1 — Generate the mitmproxy CA cert (if ~/.mitmproxy/ is missing)

```bash
mitmdump --no-server &
sleep 2
kill %1
ls ~/.mitmproxy/
```

This creates `~/.mitmproxy/mitmproxy-ca-cert.pem` and related files.
Skip if `~/.mitmproxy/` already exists.

## Step 2 — Install the addon script

```bash
cp /home/henry/shared/mitmproxy/dump_llm_stream.py ~/scripts/dump_llm_stream.py
mkdir -p ~/data/capture
```

## Step 3 — Create the mitmdump systemd user service

Create `/home/henry/.config/systemd/user/openclaw-mitmdump.service`:

```ini
[Unit]
Description=mitmproxy LLM capture (OpenClaw)
After=network-online.target

[Service]
ExecStart=/usr/bin/mitmdump -p 9501 -s /home/henry/scripts/dump_llm_stream.py
Restart=always
RestartSec=5
Environment=HOME=/home/henry

[Install]
WantedBy=default.target
```

Enable and start it:

```bash
systemctl --user daemon-reload
systemctl --user enable openclaw-mitmdump
systemctl --user start openclaw-mitmdump
```

## Step 4 — Add proxy env vars to the gateway service (one-time restart)

Edit `/home/henry/.config/systemd/user/openclaw-gateway.service` and add to the
`[Service]` block:

```ini
Environment=HTTPS_PROXY=http://127.0.0.1:9501
Environment=NODE_EXTRA_CA_CERTS=/home/henry/.mitmproxy/mitmproxy-ca-cert.pem
```

Then reload (**Waylon does this**):

```bash
systemctl --user daemon-reload
systemctl --user restart openclaw-gateway
```

**After this, mitmdump must always be running or the gateway can't reach OpenRouter/Anthropic.**
That's why it's a systemd service with `Restart=always`.

## Toggling capture

```bash
# Enable — start writing trace files
touch ~/.mitmproxy/capture.flag

# Disable — traffic still proxied, but nothing written
rm ~/.mitmproxy/capture.flag
```

The flag is checked per-request in the addon. No restarts needed.

## Output structure

Each captured request produces a directory:

```
~/data/capture/<timestamp>_<host>/
    request.json    — full parsed request body (messages, system, cache_control blocks)
    response.json   — SSE stream parsed into array of events
    metadata.json   — host, path, method, status, headers, timestamp
```

Comparing successive requests with `diff` gives line-level granularity on exactly
what changed between a cache hit and a cache miss.

## Teardown (full removal)

1. Remove the two `Environment=` lines from the gateway service unit
2. `systemctl --user daemon-reload && systemctl --user restart openclaw-gateway`
3. `systemctl --user disable --now openclaw-mitmdump`

## Notes

- `metadata.json` contains `request_headers` including the Authorization header
  (API key) — treat capture directories as sensitive, don't commit them
