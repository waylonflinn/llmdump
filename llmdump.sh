# To enable, copy into your home directory and add a line to .bashrc or .zshrc:
#
# mkdir -p $HOME/.local/share/llmdump
# cp llmdump.sh $HOME/.local/share/llmdump
#
# (add to .bashrc or .zshrc)
# source "$HOME/.local/share/llmdump/llmdump.sh"
#
# ==============================================================================
# 📂 GLOBAL CONFIGURATION: Shared paths sourced from llmdump.env (the same file
# is loaded directly by the systemd unit's EnvironmentFile= and by the launchd
# plist wrapper, so all three consumers see the same values).
# ==============================================================================
if [ -f "$HOME/.local/share/llmdump/llmdump.env" ]; then
    set -a
    . "$HOME/.local/share/llmdump/llmdump.env"
    set +a
fi


# 🎯 Main Multiplexer Function
llmdump() {
    case "$1" in
        on|enable|start)
            _llmdump_system_on
            _llmdump_session_on
            _llmdump_status "full"
            ;;
        off|disable|stop)
            _llmdump_system_off
            _llmdump_session_off
            _llmdump_status "compact"
            ;;
        session)
            if [ "$2" = "on"  ] || [ "$2" = "enable" ] || [ "$2" = "start" ]; then
                _llmdump_system_on
                _llmdump_session_on
                _llmdump_status "full"
            elif [ "$2" = "off" ] || [ "$2" = "disable" ] || [ "$2" = "stop" ]; then
                _llmdump_session_off
                _llmdump_status "full"
            else
                _llmdump_help
            fi
            ;;
        system)
            if [ "$2" = "on"  ] || [ "$2" = "enable" ] || [ "$2" = "start" ]; then
                _llmdump_system_on
                _llmdump_status "full"
            elif [ "$2" = "off" ] || [ "$2" = "disable" ] || [ "$2" = "stop" ]; then
                _llmdump_system_off
                _llmdump_session_off
                _llmdump_status "compact"
            else
                _llmdump_help
            fi
            ;;
        gui)
            if [ "$2" = "on"  ] || [ "$2" = "enable" ] || [ "$2" = "start" ]; then
                _llmdump_gui_on
            elif [ "$2" = "off" ] || [ "$2" = "disable" ] || [ "$2" = "stop" ]; then
                _llmdump_gui_off
            else
                _llmdump_help
            fi
            ;;
        status)
            _llmdump_status "full"
            ;;
        report)
            if [ "$2" = "help"  ]; then
                _llmdump_report "-h"
            else
                _llmdump_report "${@:2}"
            fi
            ;;
        help|-h|--help)
            _llmdump_help
            ;;
        *)
            _llmdump_help
            ;;
    esac
}

# ❓ Interactive Command Reference Manual
_llmdump_help() {
    echo -e "llmdump"
    echo -e ""
    echo -e "paths:"
    echo -e "   • captures : \e[35m$LLMDUMP_CAPTURE_DIR\e[0m"
    echo -e "   • flag file: \e[35m$LLMDUMP_FLAG_FILE\e[0m"
    echo -e ""
    echo -e "commands:"
    echo -e "   • \e[1;32mllmdump on\e[0m"
    echo -e "     Enables system service, creates flag, and sets session variables."
    echo -e ""
    echo -e "   • \e[1;31mllmdump off\e[0m"
    echo -e "     Disables system service, removes flag, and unsets session variables."
    echo -e ""
    echo -e "   • \e[1;32mllmdump session on\e[0m"
    echo -e "     Alias for \e[1;32mllmdump on\e[0m."
    echo -e ""
    echo -e "   • \e[1;93mllmdump session off\e[0m"
    echo -e "     Disables session variables only. Leaves system level as-is."
    echo -e ""
    echo -e "   • \e[1;93mllmdump system on\e[0m"
    echo -e "     Enables system service and flag. Leaves session variables as-is."
    echo -e ""
    echo -e "   • \e[1;31mllmdump system off\e[0m"
    echo -e "     Alias for \e[1;31mllmdump off\e[0m"
    echo -e ""
    echo -e "   • \e[1;32mllmdump gui on\e[0m (experimental)"
    echo -e "     Enable session variables for current GUI session (requires app restart)."
    echo -e ""
    echo -e "   • \e[1;31mllmdump gui off\e[0m (experimental)"
    echo -e "     Disable session variables for current GUI session."
    echo -e ""
    echo -e "   • \e[1;36mllmdump status\e[0m"
    echo -e "     Displays current session and systemd status."
    echo -e ""
    echo -e "   • \e[1;36mllmdump report\e[0m"
    echo -e "     display a report summarizing any capture activity for today."
    echo -e "     try \e[1;36mllmdump report help\e[0m for additional options."
}

_llmdump_report() {
    # Check if the user provided arguments after the word 'report'
    if [ -z "$1" ]; then
        # This standard format works identically on both Ubuntu (GNU) and macOS (BSD)
        TODAY=$(date +%Y%m%d)

        echo "generating report for today ($TODAY)..."
        python3 "$HOME/.local/share/llmdump/cache_report.py" -d "$TODAY"
    else
        # Arguments provided: pass them all through
        python3 "$HOME/.local/share/llmdump/cache_report.py" "$@"
    fi
}

# 🔍 Internal Status Checker
_llmdump_status() {
    local mode="${1:-full}"
    local has_flag=0
    local has_proxy=0
    local service_active=0
    local has_gui=0
    # Detect OS: 'darwin' covers macOS, 'linux-gnu' covers Linux
    #local is_mac=0

    [ -f "$LLMDUMP_FLAG_FILE" ] && has_flag=1
    [ -n "$HTTPS_PROXY" ] && has_proxy=1
    #[[ "$OSTYPE" == darwin* ]] && is_mac=1

    if [[ "$OSTYPE" == darwin* ]]; then
        # On macOS, check if the service label is running
        launchctl list com.user.llmdump &>/dev/null && service_active=1
        # GUI capture state lives in the Aqua launchd domain, independent of
        # this shell's env -- a non-empty value means it's enabled.
        [ -n "$(launchctl getenv HTTPS_PROXY)" ] && has_gui=1
    else
        # On Linux, use standard systemctl
        systemctl --user is-active --quiet llmdump.service && service_active=1
        # Probe the systemd --user manager env (kept in sync with the D-Bus
        # activation env by _llmdump_gui_on/off). '=.' requires a non-empty value.
        systemctl --user show-environment 2>/dev/null | grep -q '^HTTPS_PROXY=.' && has_gui=1
    fi

    # Print combined high-level state
    if [ $has_flag -eq 1 ] && [ $has_proxy -eq 1 ] && [ $service_active -eq 1 ]; then
        echo -e "llmdump status          : \e[32mENABLED\e[0m"
    elif [ $service_active -eq 1 ] && [ $has_proxy -eq 0 ]; then
        echo -e "llmdump status          : \e[93mSYSTEM ONLY\e[0m (not proxied in this shell session)"
    elif [ $service_active -eq 0 ] && [ $has_flag -eq 0 ] && [ $has_proxy -eq 0 ]; then
        echo -e "llmdump status          : \e[31mDISABLED\e[0m"
    else
        echo -e "llmdump status          : \e[31mDISABLED / PARTIAL\e[0m"
    fi

    if [ "$mode" = "full" ]; then
        echo -e "   • systemd service    : $([ $service_active -eq 1 ] && echo -e "\e[32mactive\e[0m" || echo -e "\e[31minactive\e[0m")"
        echo -e "   • capture.flag       : $([ $has_flag -eq 1 ] && echo -e "\e[32mpresent\e[0m" || echo -e "\e[31mmissing\e[0m")"
        echo -e "   • gui (experimental) : $([ $has_gui -eq 1 ] && echo -e "\e[32menabled\e[0m" || echo -e "\e[31mdisabled\e[0m")"
        echo -e "   • proxy              : $([ -n "$HTTPS_PROXY" ] && echo "$HTTPS_PROXY" || echo "not set")"
    fi
}

# ──────────────────────────────────────────────────────────────────────────
# Single source of truth for the capture environment, emitted as NAME=VALUE
# lines. Every consumer (shell session, GUI/launchd, GUI/systemd+dbus) derives
# its NAMES and VALUES from here, so the proxy/cert config lives in one place.
# ──────────────────────────────────────────────────────────────────────────
_llmdump_capture_pairs() {
    printf '%s\n' \
        "HTTPS_PROXY=http://127.0.0.1:9501" \
        "NODE_EXTRA_CA_CERTS=$HOME/.mitmproxy/mitmproxy-ca-cert.pem" \
        "REQUESTS_CA_BUNDLE=$HOME/.mitmproxy/mitmproxy-ca-cert.pem" \
        "DENO_TLS_CA_STORE=system"
}

# 🟢 Internal Helper: Enable Session Variables
_llmdump_session_on() {
    local kv
    while IFS= read -r kv; do
        export "$kv"
    done <<< "$(_llmdump_capture_pairs)"
}

# 🔴 Internal Helper: Disable Session Variables
_llmdump_session_off() {
    local kv
    while IFS= read -r kv; do
        unset "${kv%%=*}"
    done <<< "$(_llmdump_capture_pairs)"
}

# 🟢 Internal Helper: Enable GUI Session Variables
# Propagates the same variables as _llmdump_session_on into the logged-in GUI
# session, so graphical apps launched afterward inherit them.
#
# Caveats:
#   • Only affects apps launched AFTER this runs -- restart running apps.
#   • Only apps that honor these env vars are captured (Electron/Node, Python
#     requests, Deno, curl). Native macOS (URLSession) apps and any app that
#     pins certs ignore them and read proxy/trust from system settings.
#   • On a bare WM (no systemd/D-Bus app launching) neither command propagates;
#     env must be set at login instead.
_llmdump_gui_on() {
    local -a pairs=()
    local kv
    while IFS= read -r kv; do pairs+=("$kv"); done <<< "$(_llmdump_capture_pairs)"

    if [[ "$OSTYPE" == darwin* ]]; then
        # Sets vars in the per-user Aqua/GUI launchd domain (one call per var,
        # split into NAME / VALUE on the first '=').
        local name value
        for kv in "${pairs[@]}"; do
            name="${kv%%=*}"; value="${kv#*=}"
            launchctl setenv "$name" "$value"
        done
    elif command -v dbus-update-activation-environment >/dev/null 2>&1; then
        # One call updates the D-Bus activation environment (D-Bus-activated
        # apps) and, via --systemd, the systemd --user manager (systemd-scope
        # app launches, e.g. GNOME). Explicit NAME=VALUE pairs avoid any
        # dependency on what the caller happens to have exported.
        dbus-update-activation-environment --systemd "${pairs[@]}"
    else
        # Fallback: no D-Bus tool present, seed the systemd --user manager only.
        systemctl --user set-environment "${pairs[@]}" 2>/dev/null
    fi
    echo -e "llmdump gui          : \e[32mENABLED\e[0m"
    echo -e "   • \e[2mGUI apps must be restarted to pick up capture settings\e[0m"
}

# 🔴 Internal Helper: Disable GUI Session Variables
_llmdump_gui_off() {
    local -a names=() empties=()
    local kv
    while IFS= read -r kv; do
        names+=("${kv%%=*}")     # NAME            (for unset / launchctl unsetenv)
        empties+=("${kv%%=*}=")  # NAME=           (for the D-Bus empty overwrite)
    done <<< "$(_llmdump_capture_pairs)"

    if [[ "$OSTYPE" == darwin* ]]; then
        local name
        for name in "${names[@]}"; do launchctl unsetenv "$name"; done
    else
        # systemd side supports true removal.
        systemctl --user unset-environment "${names[@]}" 2>/dev/null
        # The D-Bus activation environment has no removal API, so overwrite the
        # vars to empty (clients treat empty HTTPS_PROXY as "no proxy"). A true
        # delete only happens on GUI session restart.
        command -v dbus-update-activation-environment >/dev/null 2>&1 && \
            dbus-update-activation-environment "${empties[@]}"
    fi
    echo -e "llmdump gui          : \e[31mDISABLED\e[0m"
    echo -e "   • \e[2mGUI apps started while enabled keep capturing until restarted\e[0m"
}

# 🟢 Internal Helper: Enable System Service
_llmdump_system_on() {
    touch "$LLMDUMP_FLAG_FILE"

    if [[ "$OSTYPE" == darwin* ]]; then
        # The plist's wrapper sources this file at launch, so LLMDUMP_CAPTURE_DIR /
        # LLMDUMP_FLAG_FILE are inherited from here on every (re)start — no setenv needed.

        # Modern launchctl bootstrap registers the service but does NOT start it automatically on boot
        launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.user.llmdump.plist" 2>/dev/null
        # -k forces a restart if already running, so edits to this file are picked up immediately
        launchctl kickstart -k "gui/$(id -u)/com.user.llmdump"
    else
        # The unit's wrapper sources this file at launch, so env vars are
        # inherited from here on every (re)start -- no import-environment needed.
        # restart (vs start) ensures edits to this file are picked up immediately.
        systemctl --user restart llmdump.service
    fi
}

# 🔴 Internal Helper: Disable System Service
_llmdump_system_off() {
    rm -f "$LLMDUMP_FLAG_FILE"

    if [[ "$OSTYPE" == darwin* ]]; then
        # Safely kills the running process instantly
        launchctl kill SIGTERM "gui/$(id -u)/com.user.llmdump" 2>/dev/null
        # Unregisters the agent entirely
        launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.user.llmdump.plist" 2>/dev/null
    else
        systemctl --user stop llmdump.service
    fi
}
