#!/bin/bash
set -e

echo "📦 Starting llmdump installation..."

# 1. Detect Operating System
OS_TYPE=$(uname -s)
if [ "$OS_TYPE" = "Linux" ]; then
    echo "💻 Detected System: Ubuntu/Linux"
    IS_MAC=false

    # Check if systemd is the active init system
    if [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
        echo "⚙️  Detected Init: systemd"
        HAS_SYSTEMD=true
    else
        echo "⚠️  Warning: systemd was not detected as the active init system on this Linux machine."
        echo "   The background service will not be installed automatically."
        HAS_SYSTEMD=false
    fi

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
    SHELL_SCRIPT_NAME="llmdump.sh"
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
# 2b. Select Data Capture Directory
echo ""
echo "📁 Choose a data capture directory:"
options=(
    "$HOME/.cache/llmdump/capture (Default)"
    "$HOME/.local/share/llmdump/capture"
    "$HOME/data/capture"
    "Custom (User Specified)"
)

# Set the prompt for the select menu
PS3="Enter choice [1-4]: "

select opt in "${options[@]}"
do
    case $REPLY in
        1)
            CAPTURE_DIR="$HOME/.cache/llmdump/capture"
            break
            ;;
        2)
            CAPTURE_DIR="$HOME/.local/share/llmdump/capture"
            break
            ;;
        3)
            CAPTURE_DIR="$HOME/data/capture"
            break
            ;;
        4)
            echo ""
            read -r -p "Enter custom absolute path: " custom_path
            # Replace leading ~ with $HOME if present
            CAPTURE_DIR="${custom_path/#\~/$HOME}"
            if [ -z "$CAPTURE_DIR" ]; then
                echo "❌ Invalid path. Falling back to default."
                CAPTURE_DIR="$HOME/.cache/llmdump/capture"
            fi
            break
            ;;
        *) 
            # If user enters an empty line or invalid option, fallback safely to option 1
            echo "📝 Defaulting to choice 1."
            CAPTURE_DIR="$HOME/.cache/llmdump/capture"
            break
            ;;
    esac
done

echo "✅ Selected capture directory: $CAPTURE_DIR"
mkdir -p "$CAPTURE_DIR"
echo ""

# 3. Check Prerequisites
# Detect absolute location of mitmdump
MITMDUMP_PATH=$(command -v mitmdump || true)

if [ -n "$MITMDUMP_PATH" ]; then
    echo "🔍 Detected mitmdump executable path: $MITMDUMP_PATH"
else
    echo "⚠️ Warning: 'mitmdump' (mitmproxy) was not found."
    if [ "$IS_MAC" = true ]; then
        echo "💡 Install it using: brew install mitmproxy"
    else
        echo "💡 Install it with your system package manager (e.g. 'sudo apt install mitmproxy', 'sudo pacman -S mitmproxy')"
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
    
    # Update actual mitmdump path and home directory paths inside the plist
    sed -i '' "s|/opt/homebrew/bin/mitmdump|$MITMDUMP_PATH|g" "$PLIST_FILE"
    sed -i '' "s|/Users/USER/|$HOME/|g" "$PLIST_FILE"
elif [ "$HAS_SYSTEMD" = true]; then
    echo "📥 Downloading Systemd Service..."
    SERVICE_FILE="$SERVICE_DIR/llmdump.service"
    curl -sSL "$REPO_URL/llmdump.service" -o "$SERVICE_FILE"
    
    # Update actual mitmdump path inside the systemd service
    sed -i "s|/usr/bin/mitmdump|$MITMDUMP_PATH|g" "$SERVICE_FILE"
    #sed -i "s|/home/USER/|$HOME/|g" "$SERVICE_FILE" 2>/dev/null || sed -i "s|/Users/USER/|$HOME/|g" "$SERVICE_FILE" 2>/dev/null
    
    # Reload the user systemd daemon
    systemctl --user daemon-reload
    echo "💡 If using this service with OpenClaw you should run 'systemctl --user enable llmdump'"
    echo "   then edit $SERVICE_DIR/openclaw-gateway.service to include the necessary environment variables."
    echo "   see https://github.com"
else
    echo "⚠️  Warning: service not installed."
    echo "    Please run 'mitmdump -p 9501 -s ~/.local/share/llmdump/dump_llm_stream.py' manually"
    echo "    or install an equivalent system service. (service detection in 'llmdump status' will not function)"
fi


# 7. Setup Shell Integration Based on Detected Shell
echo "📥 Downloading shell integration script..."
curl -sSL "$REPO_URL/$SHELL_SCRIPT_NAME" -o "$SHARE_DIR/$SHELL_SCRIPT_NAME"

# Modify the capture path directly inside the downloaded script
if [ "$IS_MAC" = true ]; then
    sed -i '' "s|^export LLMDUMP_CAPTURE_DIR=.*|export LLMDUMP_CAPTURE_DIR=\"$CAPTURE_DIR\"|g" "$SHARE_DIR/$SHELL_SCRIPT_NAME"
else
    sed -i "s|^export LLMDUMP_CAPTURE_DIR=.*|export LLMDUMP_CAPTURE_DIR=\"$CAPTURE_DIR\"|g" "$SHARE_DIR/$SHELL_SCRIPT_NAME"
fi

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

echo "💡 To change the capture directory later, edit the variable LLMDUMP_CAPTURE_DIR at the top of $SHARE_DIR/$SHELL_SCRIPT_NAME"
echo "💡 You may also want to add 'llmdump status' to $SHELL_RC to print a status reminder on login"

echo "🎉 Installation complete!"
echo "🔄 Please restart your terminal or run: source $SHELL_RC"
