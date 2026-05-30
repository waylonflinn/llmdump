# 🔍🤖 llmdump

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
| `llmdump on` | Enables system service, creates `capture.flag` file and sets session variables |
| `llmdump off` | Disables system service, removes `capture.flag` file and unsets session variables |
| `llmdump session off` | Disables session variables only. Leaves system level as-is |
| `llmdump system on` | Enables system service and flag. Leaves session variables as-is |
| `llmdump status` | Displays status for service, flag file and current session variables |
| `llmdump report` | Generate a summary from existing captures (defaults to current day) |

---

## 📊 Analytics and Cost Tracking

`llmdump report` is a helper command that invokes the `cache_report.py` script.

It shows token counts, caching stats, and cost breakdowns against your data dump directory. After install, you can call it directly like this:

```bash
# print the help message for cache_report.py
python ~/.local/share/llmdump/cache_report.py -h
```

You can also access the same functionality via `llmdump report` by adding any arguments `cache_report.py` accepts. By default `llmdump report` just passes `-d <current_day>`.

---

## 🚀 Easy Install

NOTE: requires `mitmproxy` (install before running)

```sh
curl -fsSL https://raw.githubusercontent.com/waylonflinn/llmdump/master/install.sh | bash
```

### What it Does

* create `~/.local/share/llmdump`
* download necessary files from this repo
* create a system service (systemd or launchd)
* create capture dir (default `~/.cache/llmdump/capture`)
* update the system service and shell integration files with correct paths
* add a single line to the 'rc' for your running shell to source the shell integration  (`.zshrc`, `.bashrc`)

(make sure to review the `install.sh` before running, or have your agent take a look)

### 🗑️ Uninstall

```bash
rm -rf ~/.cache/llmdump # or wherever you chose for your capture dir
rm -rf ~/.local/share/llmdump
rm ~/.config/systemd/user/llmdump.service
```
Then remove the `source ~/.local/share/llmdump/llmdump.sh` line from your shell rc file.

## 🔍 Manual Install

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

### 2. Create Directory and Download Files

This directory used by the install script and referenced throughout these instructions (and in the system service file)

```bash
mkdir -p ~/.local/share/llmdump
```

If you use another one, make the changes as necessary.

Download:
* `llmdump.sh`
* `llmdump.env`
* `service/llmdump.service`
* `service/dump_llm_stream.py`
* `cache_report.py`

### 2. Install Shell Environment Script

Most clients require some environment variables to be set for the https proxy method used here to work (e.g. `HTTPS_PROXY`, `NODE_EXTRA_CA_CERTS`).
A shell script is included that manages the entire process of starting and stopping capture: `llmdump.sh`.
It also manages the environment variables (described below) used to set where things are saved and control when to capture. It isn't mandatory but does make setup and usage much easier.

#### For Zsh (`~/.zshrc`)
```zsh
source "$HOME/.local/share/llmdump/llmdump.sh"
llmdump status
```

#### For Bash (`~/.bashrc`)
```bash
if [ -f "$HOME/.local/share/llmdump/llmdump.sh" ]; then
    source "$HOME/.local/share/llmdump/llmdump.sh"
    llmdump status
fi
```

Modify the paths in `llmdump.env`, if desired. The same file is sourced by `llmdump.sh` and loaded directly by the systemd unit (via `EnvironmentFile=`), so all consumers stay in sync.


```sh
LLMDUMP_CAPTURE_DIR="/home/user/data/capture/"
LLMDUMP_FLAG_FILE="/home/user/.local/share/llmdump/capture.flag"
```

- `LLMDUMP_CAPTURE_DIR` determines where captures will be saved (you probably want to change this one).
- `LLMDUMP_FLAG_FILE` determines where the flag file is located (default location is probably fine). captures only happen when this file is present. file is managed by the shell environment script commands

Paths must be absolute -- systemd does not expand `$HOME` in `EnvironmentFile` values.

If you don't want to use the shell script you'll still want to keep `llmdump.env` so the service picks up the right paths. You'll also have to manually set `HTTPS_PROXY` (and probably `NODE_EXTRA_CA_CERTS`) in your shell.

### 3. Setup and Launch the Service
This repository includes an example systemd service file (`service/llmdump.service`) and launchd plist (`service/com.user.llmdump.plist`).


Here's the example systemd (copied from `service/llmdump.service`).
```ini
[Unit]
Description=mitmproxy LLM capture
After=network-online.target

[Service]
EnvironmentFile=%h/.local/share/llmdump/llmdump.env
ExecStart=/usr/bin/mitmdump -p 9501 -s %h/.local/share/llmdump/dump_llm_stream.py
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
```

Instructions below are for Ubuntu.

1. Move the service file into `~/.config/systemd/user/`.
2. Modify the location of `dump_llm_stream.py`, if necessary.
3. `systemctl --user daemon-reload`

NOTE: The service reads `LLMDUMP_CAPTURE_DIR` and `LLMDUMP_FLAG_FILE` directly from `llmdump.env` via `EnvironmentFile=`, so it's safe to `enable` if you want it running at boot (and necessary for OpenClaw -- see below).

Make sure to examine `service/dump_llm_stream.py` before loading it as a service. You can also have your agent check it for security.

### 3. OpenClaw setup (optional)
This is an optional step for running captures for OpenClaw. If you just want to use this with other coding agents or tools, you can skip this.

Add the following to your OpenClaw gateway service (on Ubuntu this is usually found in `~/.config/systemd/user/openclaw-gateway.service`)

```ini
Environment=HTTPS_PROXY=http://127.0.0.1:9501
Environment=NODE_EXTRA_CA_CERTS=%h/.mitmproxy/mitmproxy-ca-cert.pem
```

Then enable the llmdump service (this causes it to start on boot):

```sh
systemctl --user enable llmdump.service
```

If OpenClaw is running as a user service, you probably already have linger enabled. If not, run the following:

```sh
sudo loginctl enable-linger $USER
```

---

NOTE: This project was created with agent/LLM assistance including: OpenClaw, Claude Code and Google AI mode
