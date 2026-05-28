# Copy into your home directory and load by adding the following line to .zshrc:
# mkdir -p $HOME/.config/zsh
# cp proxy_manager.zsh $HOME/.config/zsh/
# source "$HOME/.config/zsh/proxy_manager.zsh"
# ==============================================================================
# 📂 GLOBAL CONFIGURATION (File-Level Shared Paths)
# ==============================================================================
typeset -g -r PROXY_FLAG_FILE="$HOME/.mitmproxy/capture.flag"
typeset -g -r PROXY_CAPTURE_DIR="$HOME/data/capture/"

# ❓ Interactive Command Reference Manual
proxy_help() {
    echo "\e[1;34m======================================================================\e[0m"
    echo "🎯 \e[1;36mLLM PROXY MANAGER MAN PAGE & CLI COMMANDS\e[0m"
    echo "\e[1;34m======================================================================\e[0m"
    echo "📋 \e[1mInfrastructure Paths:\e[0m"
    echo "   • Capture Directory : \e[35m$PROXY_CAPTURE_DIR\e[0m"
    echo "   • mitmdump Flag File: \e[35m$PROXY_FLAG_FILE\e[0m"
    echo ""
    echo "🛠️  \e[1mAvailable Commands:\e[0m"
    echo "   • \e[1;32mproxy_on\e[0m"
    echo "     Enables proxy routing in this session AND enables system level logging."
    echo ""
    echo "   • \e[1;93mproxy_off_local\e[0m"
    echo "     Disables proxy routing in this session only. Leaves system level logging on."
    echo ""
    echo "   • \e[1;93mproxy_off\e[0m"
    echo "     Alias for \e[1;93mproxy_off_local\e[0m"
    echo ""
    echo "   • \e[1;93mproxy_on_system\e[0m"
    echo "     Enables system level logging but disables proxy routing in this session."
    echo ""
    echo "   • \e[1;31mproxy_off_system\e[0m"
    echo "     Completely disables proxy routing here and system-wide."
    echo ""
    echo "   • \e[1;36mproxy_status\e[0m"
    echo "     Displays current proxy status."
    echo ""
    echo "   • \e[1;36mproxy_help\e[0m"
    echo "     Renders this information layout panel."
    echo "\e[1;34m======================================================================\e[0m"
    echo ""
    # Execute a live assessment for convenience right after showing instructions
    proxy_status "full"
}

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
        echo "🌐 Proxy & 💾 Capture: \e[32mENABLED\e[0m"
        if [ "$mode" = "full" ]; then
            echo "   • Traffic routes to: $HTTPS_PROXY"
            echo "   • Captures are in: $PROXY_CAPTURE_DIR"
            echo "   • Dump script capture flag: $PROXY_FLAG_FILE"
            echo "   • Type \e[93mproxy_off\e[0m to disable only in this session or \e[31mproxy_off_system\e[0m to disable system-wide."
        fi
    # 2. Local Off State: Shell bypassed but background capturing remains active
    elif [ $has_flag -eq 1 ] && [ $has_proxy -eq 0 ]; then
        echo "🌐 Proxy & 💾 Capture: \e[93mNOT ACTIVE IN THIS SESSION\e[0m"
        if [ "$mode" = "full" ]; then
            echo "   • mitmdump flag is present, but HTTPS_PROXY is not set."
            echo "   • Type \e[32mproxy_on\e[0m to enable here or \e[31mproxy_off_system\e[0m to disable system-wide."
        fi

    # 3. Mismatch State: Proxy variables set but background flag missing
    elif [ $has_flag -eq 0 ] && [ $has_proxy -eq 1 ]; then
        echo "⚠️ Proxy & 💾 Capture: \e[31mCONFIGURATION MISMATCH\e[0m"
        if [ "$mode" = "full" ]; then
            echo "   • \e[31mIssue:\e[0m HTTPS_PROXY is present, but mitmdump flag is missing."
            echo "   • Run \e[32mproxy_on\e[0m to enable, \e[93mproxy_off\e[0m to disable or \e[31mproxy_off_system\e[0m to disable system-wide."
        fi

    else
        echo "🌐 Proxy & 💾 Capture: \e[31mDISABLED\e[0m"
        if [ "$mode" = "full" ]; then
            echo "   • Type \e[32mproxy_on\e[0m to enable here or \e[93mproxy_on_system\e[0m to enable only for the system."
        fi
    fi
}

# 🟢 Turn proxy intercept and disk capture ON
proxy_on() {
    # Proxy intercept
    export HTTPS_PROXY="http://127.0.0.1:9501"
    #export HTTP_PROXY="$HTTPS_PROXY"
    #export https_proxy="$HTTPS_PROXY"
    #export http_proxy="$HTTPS_PROXY"

    # Runtime certificate trust
    export NODE_EXTRA_CA_CERTS="$HOME/.mitmproxy/mitmproxy-ca-cert.pem"
    export REQUESTS_CA_BUNDLE="$HOME/.mitmproxy/mitmproxy-ca-cert.pem"
    export DENO_TLS_CA_STORE="system"
    # additional redirects for old tools that fallback to OpenSSL
    #export SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt"
    #export SSL_CERT_DIR="/etc/ssl/certs"

    # flag file used by mitmdump script
    touch "$HOME/.mitmproxy/capture.flag"
    
    # Call status with explicit argument
    proxy_status "full"
}

# 🟡 Turn off proxy routing in this session only (Leaves disk capture flag alone)
proxy_off_local() {
    # Unset Intercept
    unset HTTPS_PROXY #HTTP_PROXY https_proxy http_proxy

    # Unset Runtimes
    unset NODE_EXTRA_CA_CERTS REQUESTS_CA_BUNDLE DENO_TLS_CA_STORE # SSL_CERT_FILE SSL_CERT_DIR 

    proxy_status "full"
}

alias proxy_off="proxy_off_local"

# 🟡 Turn proxy intercept and disk capture ON for the system (disk capture flag created) but disabled here
proxy_on_system() {
    # Unset Intercept
    unset HTTPS_PROXY #HTTP_PROXY https_proxy http_proxy
    
    # Unset Runtimes
    unset NODE_EXTRA_CA_CERTS REQUESTS_CA_BUNDLE DENO_TLS_CA_STORE # SSL_CERT_FILE SSL_CERT_DIR 

    # flag file used by mitmdump script
    touch "$HOME/.mitmproxy/capture.flag"
    
    # Call status with explicit argument
    proxy_status "full"
}

# 🔴 Turn proxy intercept and disk capture OFF system-wide
proxy_off_system() {
    # Unset Intercept
    unset HTTPS_PROXY #HTTP_PROXY https_proxy http_proxy
    
    # Unset Runtimes
    unset NODE_EXTRA_CA_CERTS REQUESTS_CA_BUNDLE DENO_TLS_CA_STORE # SSL_CERT_FILE SSL_CERT_DIR 
    
    rm -f "$HOME/.mitmproxy/capture.flag"
    
    # Call status with explicit argument
    proxy_status "compact"
}
