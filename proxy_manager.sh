# ==============================================================================
# 📂 GLOBAL CONFIGURATION (File-Level Shared Paths)
# ==============================================================================
declare -r PROXY_FLAG_FILE="$HOME/.mitmproxy/capture.flag"
declare -r PROXY_CAPTURE_DIR="$HOME/data/capture/"

# 🔍 Display the current proxy and capture status
# Usage: proxy_status [compact|full] (defaults to full)
proxy_status() {
    # Default to "full" if no argument is passed ($1 is empty)
    local mode="${1:-full}"

    # Check individual conditions
    local has_flag=0
    local has_proxy=0
    [ -f "$PROXY_FLAG_FILE" ] && has_flag=1
    [ -n "$HTTPS_PROXY" ] && has_proxy=1

    # 1. Full State: Environment and File Match
    if [ $has_flag -eq 1 ] && [ $has_proxy -eq 1 ]; then
        echo -e "🌐 Proxy & 💾 Capture: \e[32mENABLED\e[0m"
        if [ "$mode" = "full" ]; then
            echo -e "   • Traffic routes to: $HTTPS_PROXY"
            echo -e "   • Captures are in: $PROXY_CAPTURE_DIR"
            echo -e "   • Type \e[93mproxy_off\e[0m to disable only in this session or \e[31mproxy_off_system\e[0m to disable system-wide."
        fi
    # 2. Local Off State: Shell bypassed but background capturing remains active
    elif [ $has_flag -eq 1 ] && [ $has_proxy -eq 0 ]; then
        echo -e "🌐 Proxy & 💾 Capture: \e[93mNOT ACTIVE IN THIS SESSION\e[0m"
        if [ "$mode" = "full" ]; then
            echo -e "   • mitmdump flag is present, but HTTPS_PROXY is not set."
            echo -e "   • Type \e[32mproxy_on\e[0m to enable here or \e[31mproxy_off_system\e[0m to disable system-wide."
        fi

    # 3. Mismatch State: Proxy variables set but background flag missing
    elif [ $has_flag -eq 0 ] && [ $has_proxy -eq 1 ]; then
        echo -e "⚠️ Proxy & 💾 Capture: \e[31mCONFIGURATION MISMATCH\e[0m"
        if [ "$mode" = "full" ]; then
            echo -e "   • \e[31mIssue:\e[0m HTTPS_PROXY is present, but mitmdump flag is missing."
            echo -e "   • Run \e[32mproxy_on\e[0m to enable, \e[93mproxy_off\e[0m to disable or \e[31mproxy_off_system\e[0m to disable system-wide."
        fi

    else
        echo -e "🌐 Proxy & 💾 Capture: \e[31mDISABLED\e[0m"
        if [ "$mode" = "full" ]; then
            echo -e "   • Type \e[32mproxy_on\e[0m to enable here or \e[93mproxy_on_system\e[0m to enable only for the system."
        fi
    fi
}

# 🟢 Turn proxy intercept and disk capture ON
proxy_on() {
    # Proxy intercept
    export HTTPS_PROXY="http://127.0.0.1:9501"

    # Runtime certificate trust
    export NODE_EXTRA_CA_CERTS="$HOME/.mitmproxy/mitmproxy-ca-cert.pem"
    export REQUESTS_CA_BUNDLE="$HOME/.mitmproxy/mitmproxy-ca-cert.pem"
    export DENO_TLS_CA_STORE="system"

    # flag file used by mitmdump script
    touch "$PROXY_FLAG_FILE"
    
    # Call status with explicit argument
    proxy_status "full"
}

# 🟡 Turn off proxy routing in this session only (Leaves disk capture flag alone)
proxy_off() {
    # Unset Intercept
    unset HTTPS_PROXY

    # Unset Runtimes
    unset NODE_EXTRA_CA_CERTS REQUESTS_CA_BUNDLE DENO_TLS_CA_STORE 

    proxy_status "full"
}

# 🟡 Turn proxy intercept and disk capture ON for the system (disk capture flag created) but disabled here
proxy_on_system() {
    # Unset Intercept
    unset HTTPS_PROXY
    
    # Unset Runtimes
    unset NODE_EXTRA_CA_CERTS REQUESTS_CA_BUNDLE DENO_TLS_CA_STORE 

    # flag file used by mitmdump script
    touch "$PROXY_FLAG_FILE"
    
    # Call status with explicit argument
    proxy_status "full"
}

# 🔴 Turn proxy intercept and disk capture OFF system-wide
proxy_off_system() {
    # Unset Intercept
    unset HTTPS_PROXY
    
    # Unset Runtimes
    unset NODE_EXTRA_CA_CERTS REQUESTS_CA_BUNDLE DENO_TLS_CA_STORE 
    
    rm -f "$PROXY_FLAG_FILE"
    
    # Call status with explicit argument
    proxy_status "compact"
}

# ❓ Interactive Command Reference Manual
proxy_help() {
    echo -e "\e[1;34m======================================================================\e[0m"
    echo -e "🎯 \e[1;36mLLM PROXY MANAGER MAN PAGE & CLI COMMANDS (BASH)\e[0m"
    echo -e "\e[1;34m======================================================================\e[0m"
    echo -e "📋 \e[1mInfrastructure Paths:\e[0m"
    echo -e "   • Capture Directory : \e[35m$PROXY_CAPTURE_DIR\e[0m"
    echo -e "   • mitmdump Flag File: \e[35m$PROXY_FLAG_FILE\e[0m"
    echo ""
    echo -e "🛠️  \e[1mAvailable Commands:\e[0m"
    echo -e "   • \e[1;32mproxy_on\e[0m"
    echo -e "     Enables proxy routing in this session AND sets the global system flag."
    echo ""
    echo -e "   • \e[1;93mproxy_off\e[0m"
    echo -e "     Bypasses proxy routing in this session only. Leaves background logging on."
    echo ""
    echo -e "   • \e[1;93mproxy_on_system\e[0m"
    echo -e "     Sets the global logging flag but bypasses intercept routing in this session."
    echo ""
    echo -e "   • \e[1;31mproxy_off_system\e[0m"
    echo -e "     Completely disables proxy routing here and wipes the system-wide logging flag."
    echo ""
    echo -e "   • \e[1;36mproxy_status\e[0m"
    echo -e "     Runs the active diagnostic analyzer tool for current session settings."
    echo ""
    echo -e "   • \e[1;36mproxy_help\e[0m"
    echo -e "     Renders this information layout panel."
    echo -e "\e[1;34m======================================================================\e[0m"
    echo ""
    # Execute a live assessment right after showing instructions
    proxy_status "full"
}
