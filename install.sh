#!/bin/bash
set -e

echo "📦 Installing llmdump..."
echo ""

# 1. Detect Operating System
OS_TYPE=$(uname -s)
if [ "$OS_TYPE" = "Linux" ]; then
    IS_MAC=false

    # Check if systemd is the active init system
    if [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
        echo "✅ System: Ubuntu/Linux (systemd)"
        HAS_SYSTEMD=true
    else
        echo "⚠️ System: Ubuntu/Linux (non-systemd)"
        echo "    Warning: systemd was not detected as the active init system on this Linux machine."
        echo "    The background service will not be installed automatically."
        HAS_SYSTEMD=false
    fi

elif [ "$OS_TYPE" = "Darwin" ]; then
    echo "✅ System: macOS"
    IS_MAC=true
else
    echo "❌ Unsupported operating system: $OS_TYPE"
    exit 1
fi

# 2. Detect User's Actual Active Shell
if [[ "$SHELL" == *"zsh"* ]]; then
    echo "✅ Shell: Zsh"
    SHELL_RC="$HOME/.zshrc"
    SHELL_SCRIPT_NAME="llmdump.sh"
elif [[ "$SHELL" == *"bash"* ]]; then
    echo "✅ Shell: Bash"
    SHELL_RC="$HOME/.bashrc"
    SHELL_SCRIPT_NAME="llmdump.sh"
else
    # Fallback default if shell cannot be parsed cleanly
    echo "⚠️   Unknown shell ($SHELL). Defaulting to Bash integration."
    SHELL_RC="$HOME/.bashrc"
    SHELL_SCRIPT_NAME="llmdump.sh"
fi

# 3. Check Prerequisites
# Detect absolute location of mitmdump
MITMDUMP_PATH=$(command -v mitmdump || true)

if [ -n "$MITMDUMP_PATH" ]; then
    echo "✅ mitmdump: $MITMDUMP_PATH"
else
    echo "⚠️   Warning: 'mitmdump' (mitmproxy) was not found."
    if [ "$IS_MAC" = true ]; then
        echo "💡   Install it using: brew install mitmproxy"
    else
        echo "💡   Install it with your system package manager (e.g. 'sudo apt install mitmproxy', 'sudo pacman -S mitmproxy')"
    fi
fi

# 4. Select Data Capture Directory
echo ""
echo "📂 Choose a directory to save captures:"

# Print the options manually
echo "   1) $HOME/.cache/llmdump/capture (Default)"
echo "   2) $HOME/.local/share/llmdump/capture"
echo "   3) $HOME/data/capture"
echo "   4) Custom (User Specified)"
echo ""

while true; do
    # Force the read command to pull directly from the keyboard terminal device
    read -r -p "Enter choice [1-4] (Default: 1): " CHOICE </dev/tty

    # If the user just hits Enter, treat it as option 1
    if [ -z "$CHOICE" ]; then
        CHOICE="1"
    fi

    case $CHOICE in
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
            # Force this custom read to use the terminal device as well
            read -r -p "Enter custom absolute path: " custom_path </dev/tty
            # Replace leading ~ with $HOME if present
            CAPTURE_DIR="${custom_path/#\~/$HOME}"
            if [ -z "$CAPTURE_DIR" ]; then
                echo "❌ Invalid path. Falling back to default."
                CAPTURE_DIR="$HOME/.cache/llmdump/capture"
            fi
            break
            ;;
        *) 
            echo "❌ Invalid choice. Please select 1, 2, 3, or 4."
            echo ""
            ;;
    esac
done

echo "✅ Capture directory       $CAPTURE_DIR"
mkdir -p "$CAPTURE_DIR"

# 5. Create Target Directories
SHARE_DIR="$HOME/.local/share/llmdump"
echo "🛠️ Installing into         $SHARE_DIR"

mkdir -p "$SHARE_DIR"


# 5. Download and Install Project Files
#REPO_URL="https://githubusercontent.com"
REPO_URL="https://raw.githubusercontent.com/waylonflinn/llmdump/master/"

#echo "▼ Downloading scripts to $SHARE_DIR..."
curl -sSL "$REPO_URL/service/dump_llm_stream.py" -o "$SHARE_DIR/dump_llm_stream.py"
curl -sSL "$REPO_URL/cache_report.py" -o "$SHARE_DIR/cache_report.py"

# Make the python files executable just in case
chmod +x "$SHARE_DIR/dump_llm_stream.py"
chmod +x "$SHARE_DIR/cache_report.py"

# 6. Handle Platform-Specific Service Files & Configuration

if [ "$IS_MAC" = true ]; then
    SERVICE_DIR="$HOME/Library/LaunchAgents"
else
    SERVICE_DIR="$HOME/.config/systemd/user"
fi

echo "⚙️ Installing service into $SERVICE_DIR"
echo ""

mkdir -p "$SERVICE_DIR"

if [ "$IS_MAC" = true ]; then
    #echo "▼ Downloading macOS Launch Agent..."
    PLIST_FILE="$SERVICE_DIR/com.user.llmdump.plist"
    curl -sSL "$REPO_URL/service/com.user.llmdump.plist" -o "$PLIST_FILE"
    
    # Update actual mitmdump path inside the plist ($HOME is expanded by the wrapper at launch time)
    sed -i '' "s|/opt/homebrew/bin/mitmdump|$MITMDUMP_PATH|g" "$PLIST_FILE"
elif [ "$HAS_SYSTEMD" = true ]; then
    #echo "▼ Downloading Systemd Service..."
    SERVICE_FILE="$SERVICE_DIR/llmdump.service"
    curl -sSL "$REPO_URL/service/llmdump.service" -o "$SERVICE_FILE"
    
    # Update actual mitmdump path inside the systemd service
    sed -i "s|/usr/bin/mitmdump|$MITMDUMP_PATH|g" "$SERVICE_FILE"
    #sed -i "s|/home/USER/|$HOME/|g" "$SERVICE_FILE" 2>/dev/null || sed -i "s|/Users/USER/|$HOME/|g" "$SERVICE_FILE" 2>/dev/null
    
    # Reload the user systemd daemon
    systemctl --user daemon-reload
else
    echo "⚠️   Warning: unsupported system, service not installed."
    echo "     Please run 'mitmdump -p 9501 -s ~/.local/share/llmdump/dump_llm_stream.py' manually"
    echo "     or install an equivalent system service. (service detection in 'llmdump status' will not function)"
fi


# 7. Setup Shell Integration Based on Detected Shell
#echo "▼ Downloading shell integration script..."
curl -sSL "$REPO_URL/$SHELL_SCRIPT_NAME" -o "$SHARE_DIR/$SHELL_SCRIPT_NAME"

# Download the shared env file (consumed by llmdump.sh, the launchd plist
# wrapper, and the systemd unit's EnvironmentFile=) and bake in the chosen
# absolute paths -- systemd does not expand $HOME in EnvironmentFile values.
curl -sSL "$REPO_URL/llmdump.env" -o "$SHARE_DIR/llmdump.env"

if [ "$IS_MAC" = true ]; then
    sed -i '' "s|^LLMDUMP_CAPTURE_DIR=.*|LLMDUMP_CAPTURE_DIR=\"$CAPTURE_DIR\"|g" "$SHARE_DIR/llmdump.env"
    sed -i '' "s|/Users/USER/|$HOME/|g" "$SHARE_DIR/llmdump.env"
else
    sed -i "s|^LLMDUMP_CAPTURE_DIR=.*|LLMDUMP_CAPTURE_DIR=\"$CAPTURE_DIR\"|g" "$SHARE_DIR/llmdump.env"
    sed -i "s|/Users/USER/|$HOME/|g" "$SHARE_DIR/llmdump.env"
fi

SOURCE_LINE="source $SHARE_DIR/$SHELL_SCRIPT_NAME"
if [ -f "$SHELL_RC" ]; then
    if ! grep -Fxq "$SOURCE_LINE" "$SHELL_RC"; then
        #echo "✍️ Adding shortcut to $SHELL_RC..."
        echo "" >> "$SHELL_RC"
        echo "# llmdump proxy configurations" >> "$SHELL_RC"
        echo "$SOURCE_LINE" >> "$SHELL_RC"
    fi
else
    echo "⚠️   Configuration file $SHELL_RC not found. Please add the following line manually:"
    echo "    $SOURCE_LINE"
fi

echo "🎉 Installation complete!"
echo "🗘  Please restart your terminal or run: source $SHELL_RC"
echo ""

echo "💡   To enable OpenClaw see:              https://github.com/waylonflinn/llmdump#3-openclaw-setup-optional"
echo "💡   To change the capture directory:     Set LLMDUMP_CAPTURE_DIR in $SHARE_DIR/llmdump.env"
echo "💡   To print a status reminder on login: Add 'llmdump status' to $SHELL_RC "
