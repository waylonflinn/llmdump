# To enable, copy into your home directory and add a line to .bashrc:
#
# mkdir -p $HOME/.config/bash
# cp llmdump.sh $HOME/.config/bash/
# source "$HOME/.config/bash/llmdump.sh"
#
# ==============================================================================
# 📂 GLOBAL CONFIGURATION: Shared Paths (used internally, in the systemd service, and available in the user environment)
# ==============================================================================
export LLMDUMP_CAPTURE_DIR="$HOME/data/capture/"
export LLMDUMP_FLAG_FILE="$HOME/.mitmproxy/capture.flag"


# 🎯 Main Multiplexer Function
llmdump() {
    case "$1" in
        on)
            _llmdump_system_on
            _llmdump_session_on
            _llmdump_status "full"
            ;;
        off)
            _llmdump_system_off
            _llmdump_session_off
            _llmdump_status "compact"
            ;;
        session)
            if [ "$2" = "on"  ]; then
                _llmdump_system_on
                _llmdump_session_on
                _llmdump_status "full"
            elif [ "$2" = "off" ]; then
                _llmdump_session_off
                _llmdump_status "full"
            else
                _llmdump_help
            fi
            ;;
        system)
            if [ "$2" = "on" ]; then
                _llmdump_system_on
                _llmdump_status "full"
            elif [ "$2" = "off" ]; then
                _llmdump_system_off
                _llmdump_session_off
                _llmdump_status "compact"
            else
                _llmdump_help
            fi
            ;;
        status)
            _llmdump_status "full"
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
    echo -e "\e[1;34m======================================================================\e[0m"
    echo -e "🎯 \e[1;36mLLMDUMP HELP\e[0m"
    echo -e "\e[1;34m======================================================================\e[0m"
    echo -e "📋 \e[1mInfrastructure Paths:\e[0m"
    echo -e "   • Capture Directory : \e[35m$LLMDUMP_CAPTURE_DIR\e[0m"
    echo -e "   • mitmdump Flag File: \e[35m$LLMDUMP_FLAG_FILE\e[0m"
    echo -e ""
    echo -e "🛠️  \e[1mAvailable Commands:\e[0m"
    echo -e "   • \e[1;32mllmdump on\e[0m"
    echo -e "     Enables systemd service, creates flag, and sets session variables."
    echo -e ""
    echo -e "   • \e[1;31mllmdump off\e[0m"
    echo -e "     Disables systemd service, removes flag, and unsets session variables."
    echo -e ""
    echo -e "   • \e[1;32mllmdump session on\e[0m"
    echo -e "     Alias for \e[1;32mllmdump on\e[0m."
    echo -e ""
    echo -e "   • \e[1;93mllmdump session off\e[0m"
    echo -e "     Disables session variables only. Leaves system level as-is."
    echo -e ""
    echo -e "   • \e[1;93mllmdump system on\e[0m"
    echo -e "     Enables systemd service and flag. Leaves session variables as-is."
    echo -e ""
    echo -e "   • \e[1;31mllmdump system off\e[0m"
    echo -e "     Alias for \e[1;31mllmdump off\e[0m"
    echo -e ""
    echo -e "   • \e[1;36mllmdump status\e[0m"
    echo -e "     Displays current session and systemd status."
    echo -e "\e[1;34m======================================================================\e[0m"
}

# 🔍 Internal Status Checker
_llmdump_status() {
    local mode="${1:-full}"
    local has_flag=0
    local has_proxy=0
    local service_active=0

    [ -f "$LLMDUMP_FLAG_FILE" ] && has_flag=1
    [ -n "$HTTPS_PROXY" ] && has_proxy=1

    if [[ "$OSTYPE" == darwin* ]]; then
        # On macOS, check if the service label is running
        launchctl list com.user.llmdump &>/dev/null && service_active=1
    else
        # On Linux, use standard systemctl
        systemctl --user is-active --quiet llmdump.service && service_active=1
    fi

    # Print combined high-level state
    if [ $has_flag -eq 1 ] && [ $has_proxy -eq 1 ] && [ $service_active -eq 1 ]; then
        echo -e "🌐 LLM Dump Status: \e[32mFULLY ENABLED\e[0m (System & Session)"
    elif [ $service_active -eq 1 ] && [ $has_proxy -eq 0 ]; then
        echo -e "🌐 LLM Dump Status: \e[93mSYSTEM ONLY\e[0m (not proxied in this shell session)"
    elif [ $service_active -eq 0 ] && [ $has_flag -eq 0 ] && [ $has_proxy -eq 0 ] || ; then
        echo -e "🌐 LLM Dump Status: \e[31mDISABLED\e[0m"
    else
        echo -e "🌐 LLM Dump Status: \e[31mDISABLED / PARTIAL\e[0m"
    fi

    if [ "$mode" = "full" ]; then
        echo -e "   • systemd service : $([ $service_active -eq 1 ] && echo -e "\e[32mactive\e[0m" || echo -e "\e[31minactive\e[0m")"
        echo -e "   • capture.flag    : $([ $has_flag -eq 1 ] && echo -e "\e[32mpresent\e[0m" || echo -e "\e[31mmissing\e[0m")"
        echo -e "   • Session Proxy   : $([ -n "$HTTPS_PROXY" ] && echo "$HTTPS_PROXY" || echo "not set")"
    fi
}

# 🟢 Internal Helper: Enable Session Variables
_llmdump_session_on() {
    export HTTPS_PROXY="http://127.0.0.1:9501"
    export NODE_EXTRA_CA_CERTS="$HOME/.mitmproxy/mitmproxy-ca-cert.pem"
    export REQUESTS_CA_BUNDLE="$HOME/.mitmproxy/mitmproxy-ca-cert.pem"
    export DENO_TLS_CA_STORE="system"
}

# 🔴 Internal Helper: Disable Session Variables
_llmdump_session_off() {
    unset HTTPS_PROXY NODE_EXTRA_CA_CERTS REQUESTS_CA_BUNDLE DENO_TLS_CA_STORE
}

# 🟢 Internal Helper: Enable System Service
_llmdump_system_on() {
    touch "$LLMDUMP_FLAG_FILE"

    if [[ "$OSTYPE" == darwin* ]]; then
        launchctl load "$HOME/Library/LaunchAgents/com.user.llmdump.plist" 2>/dev/null
        launchctl start com.user.llmdump
    else
        # Push variables to the systemd user session BEFORE starting the service
        systemctl --user import-environment LLMDUMP_FLAG_FILE LLMDUMP_CAPTURE_DIR
        systemctl --user start llmdump.service
    fi
}

# 🔴 Internal Helper: Disable System Service
_llmdump_system_off() {
    rm -f "$LLMDUMP_FLAG_FILE"

    if [[ "$OSTYPE" == darwin* ]]; then
        launchctl stop com.user.llmdump 2>/dev/null
        launchctl unload "$HOME/Library/LaunchAgents/com.user.llmdump.plist" 2>/dev/null
    else
        systemctl --user stop llmdump.service
    fi
}
