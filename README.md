# llmdump 🔍🤖

Dump LLM requests and responses to a timestamped labeled directory as text and JSON

```
capture
├── 20260515T112851_openrouter_ai
│   └── metadata.json, request.json, request.txt, response.json, response.txt
├── 20260515T112855_openrouter_ai
│   └── metadata.json, request.json, request.txt, response.json, response.txt
└── 20260527T182743_api_anthropic_com
    └── metadata.json, request.json, request.txt, response.json, response.txt
```

Works with OpenClaw and terminal based coding agents like Claude Code, Pi Coding Agent and Forge Code

Uses mitmdump (part of mitmproxy) to intercept native Anthropic, OpenAI, and OpenRouter Server-Sent Events (SSE) traffic (via `HTTPS_PROXY`).

Also includes the ability to analyze traffic and display token usage and caching information for each request.

## 🕹️ Shell Environment Command Cheat-Sheet

The shell environment scripts provide the following commands for managing the capture process:


| Command | Action |
| :--- | :--- |
| `llmdump help` | Print a help message that describes these commands and the configured variables |
| `llmdump on` | Enables systemd service, creates capture.flag file, and sets session variables |
| `llmdump off` | Disables systemd service, removes capture.flag file, and unsets session variables |
| `llmdump session off` | Disables session variables only. Leaves system level as-is |
| `llmdump system on` | Enables systemd service and flag. Leaves session variables as-is |
| `llmdump status` | Displays status for systemd, flag file and current session variables |

---

## 📊 Analytics and Cost Tracking

To see token counts, caching stats, and cost breakdowns, execute the built-in analyzer engine against your data dump directory:

```bash
python cache_report.py
```

---

##  🚀 Easy Install

`curl -fsSL https://raw.githubusercontent.com/waylonflinn/llmdump/master/install.sh | bash`

(make sure to review the install.sh file first, or have your agent take a look)

## 🚀 Manual Install

### 1. Install mitmproxy and Register Certificate
Instructions below are for Ubuntu. Similar steps apply on most linux distributions.

Install mitmproxy.

```bash
sudo apt install mitmproxy
```

(optional) Add the certificate to the system store (necessary to intercept HTTPS traffic for some clients).

```bash
sudo cp ~/.mitmproxy/mitmproxy-ca-cert.pem /usr/local/share/ca-certificates/mitmproxy.crt
sudo update-ca-certificates
```


### 2. Install Shell Environment Script

Most clients require some environment variables to be set for the https proxy method used here to work (e.g. `HTTPS_PROXY`).
Scripts are included for zsh and bash that manage the entire process of starting and stopping capture: `llmdump.zsh` (zsh) and `llmdum.sh` (bash).
They also manage the environment variables (described below) used to set where things are saved and control when to capture. They aren't mandatory but they do make setup and usage much easier.

For zsh save the configuration script to `~/.config/zsh/llmdump.zsh` and reference it inside your `~/.zshrc`:

#### For Zsh (`~/.zshrc`)
```zsh
source "$HOME/.config/zsh/llmdump.zsh"
llmdump status
```

#### For Bash (`~/.bashrc`)
```bash
if [ -f "$HOME/.config/bash/llmdump.sh" ]; then
    source "$HOME/.config/bash/llmdump.sh"
    llmdump status
fi
```

Modify the variables at the top of the script, if desired.


```sh
export LLMDUMP_CAPTURE_DIR="$HOME/data/capture/"
export LLMDUMP_FLAG_FILE="$HOME/.mitmproxy/capture.flag"
```

- `LLMDUMP_CAPTURE_DIR` determines where captures will be saved (you probably want to change this one).
- `LLMDUMP_FLAG_FILE` determines where the flag file is located (default location is probably fine). captures only happen when this file is present. file is managed by the shell environment script commands


If you don't want to use the scripts you can also just set `LLMDUMP_CAPTURE_DIR` in your systemd service definition with an `Environment` line. You'll also have to manually set `HTTPS_PROXY` (and probably `NODE_EXTRA_CA_CERTS`) in your shell.

### 3. Setup and Launch the Service
This repository includes an example systemd service file (`llmdump.service`) and launchd plist (`com.user.llmdump.plist`).


Here's the example systemd (copied from `llmdump.service`).
```ini
[Unit]
Description=mitmproxy LLM capture
After=network-online.target

[Service]
ExecStart=/usr/bin/mitmdump -p 9501 -s %h/scripts/dump_llm_stream.py
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
```

Instructions below are for Ubuntu.

1. Copy the service file into `~/.config/systemd/user/`.
2. Modify the location of `dump_llm_stream.py` in this file to be your clone of this repo or the location of your choice (copy the file there, first).
3. `systemctl --user daemon-reload`
4. `systemctl --user enable llmdump.service`

NOTE: Don't start the service, just enable it. The scripts inject relevant environment varables (via `import-environment`) before starting. If you're not using the scripts and you're managing environment variables yourself (like `LLMDUMP_CAPTURE_DIR`), you can go ahead and start it.

Make sure to examine `dump_llm_stream.py` before loading it as a service. You can also have your agent check it for security vulnerabilities.

### 3. OpenClaw setup (optional)
This is an optional step for running captures for OpenClaw. If you just want to use this with other coding agents or tools, you can skip this.

Add the following to your OpenClaw gateway service (on Ubuntu this is usually found in `~/.config/systemd/user/openclaw-gateway.service`)

```ini
Environment=HTTPS_PROXY=http://127.0.0.1:9501
Environment=NODE_EXTRA_CA_CERTS=%h/.mitmproxy/mitmproxy-ca-cert.pem
```

---

NOTE: This project was created with agent/LLM assistance including: OpenClaw, Claude Code and Google AI mode
