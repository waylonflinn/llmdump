#!/bin/bash
set -e

echo "📦 Starting llmdump installation..."

# 1. Detect Operating System
OS_TYPE=$(uname -s)
if [ "$OS_TYPE" = "Linux" ]; then
    echo "💻 Detected System: Ubuntu/Linux"
    IS_MAC=false
elif [ "$OS_TYPE" = "Darwin" ]; then
    echo "🍏 Detected System: macOS"
    IS_MAC=true
else
    echo "❌ Unsupported operating system: $OS_TYPE"
    exit 1
fi

# 2. Detect User's Actual Active Shell
if [[ "$SHELL" == *"zsh"* ]]; then
    echo "🐚 Detected Shell: Zsh"
    SHELL_RC="$HOME/.zshrc"
    SHELL_SCRIPT_NAME="llmdump.zsh"
elif [[ "$SHELL" == *"bash"* ]]; then
    echo "🐚 Detected Shell: Bash"
    SHELL_RC="$HOME/.bashrc"
    SHELL_SCRIPT_NAME="llmdump.sh"
else
    # Fallback default if shell cannot be parsed cleanly
    echo "⚠️ Unknown shell ($SHELL). Defaulting to Bash integration."
    SHELL_RC="$HOME/.bashrc"
    SHELL_SCRIPT_NAME="llmdump.sh"
fi

# 3. Check Prerequisites
if ! command -v mitmdump &> /dev/null; then
    echo "⚠️ Warning: 'mitmdump' (mitmproxy) was not found."
    if [ "$IS_MAC" = true ]; then
        echo "💡 Install it using: brew install mitmproxy"
    else
        echo "💡 Install it using: sudo apt install mitmproxy"
    fi
fi

# 4. Create Target Directories
SHARE_DIR="$HOME/.local/share/llmdump"
mkdir -p "$SHARE_DIR"

if [ "$IS_MAC" = true ]; then
    SERVICE_DIR="$HOME/Library/LaunchAgents"
else
    SERVICE_DIR="$HOME/.config/systemd/user"
fi
mkdir -p "$SERVICE_DIR"

# 5. Download and Install Project Files
#REPO_URL="https://githubusercontent.com"
REPO_url="https://raw.githubusercontent.com/waylonflinn/llmdump/master/"

echo "📥 Downloading scripts to $SHARE_DIR..."
curl -sSL "$REPO_URL/dump_llm_stream.py" -o "$SHARE_DIR/dump_llm_stream.py"
curl -sSL "$REPO_URL/cache_report.py" -o "$SHARE_DIR/cache_report.py"

# Make the python files executable just in case
chmod +x "$SHARE_DIR/dump_llm_stream.py"
chmod +x "$SHARE_DIR/cache_report.py"

# 6. Handle Platform-Specific Service Files & Configuration
if [ "$IS_MAC" = true ]; then
    echo "📥 Downloading macOS Launch Agent..."
    PLIST_FILE="$SERVICE_DIR/com.user.llmdump.plist"
    curl -sSL "$REPO_URL/com.user.llmdump.plist" -o "$PLIST_FILE"
    
    # Dynamically fix paths inside the plist to point to the user's home directory
    sed -i '' "s|/Users/USER/|$HOME/|g" "$PLIST_FILE" 2>/dev/null || sed -i "s|/Users/USER/|$HOME/|g" "$PLIST_FILE"
    sed -i '' "s|/home/USER/|$HOME/|g" "$PLIST_FILE" 2>/dev/null || sed -i "s|/home/USER/|$HOME/|g" "$PLIST_FILE"
else
    echo "📥 Downloading Ubuntu Systemd Service..."
    SERVICE_FILE="$SERVICE_DIR/llmdump.service"
    curl -sSL "$REPO_URL/llmdump.service" -o "$SERVICE_FILE"
    
    # Dynamically fix paths inside the systemd service to point to the user's home directory
    sed -i "s|/home/USER/|$HOME/|g" "$SERVICE_FILE"
    sed -i "s|/Users/USER/|$HOME/|g" "$SERVICE_FILE"
    
    # Reload the user systemd daemon
    systemctl --user daemon-reload
    echo "💡 If using this service with OpenClaw you should run 'systemctl --user enable llmdump'"
    echo "   then edit $SERVICE_DIR/openclaw-gateway.service to include the necessary environment variables."
    echo "   see https://github.com/waylonflinn/llmdump#3-openclaw-setup-optional"
fi

# 7. Setup Shell Integration Based on Detected Shell
echo "📥 Downloading shell integration script..."
curl -sSL "$REPO_URL/$SHELL_SCRIPT_NAME" -o "$SHARE_DIR/$SHELL_SCRIPT_NAME"

SOURCE_LINE="source $SHARE_DIR/$SHELL_SCRIPT_NAME"
if [ -f "$SHELL_RC" ]; then
    if ! grep -Fxq "$SOURCE_LINE" "$SHELL_RC"; then
        echo "✍️ Adding shortcut to $SHELL_RC..."
        echo "" >> "$SHELL_RC"
        echo "# llmdump proxy configurations" >> "$SHELL_RC"
        echo "$SOURCE_LINE" >> "$SHELL_RC"
    fi
else
    echo "⚠️ Configuration file $SHELL_RC not found. Please add the following line manually:"
    echo "   $SOURCE_LINE"
fi

echo "💡 To change the capture directory edit the variable LLMDUMP_CAPTURE_DIR at the top of $SHARE_DIR/$SHELL_SCRIPT_NAME"
echo "💡 You may also want to add 'llmdump status' to $SHELL_RC to print a status reminder on login"

echo "🎉 Installation complete!"
echo "🔄 Please restart your terminal or run: source $SHELL_RC"
