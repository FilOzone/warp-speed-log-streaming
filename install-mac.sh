#!/bin/bash
set -e

# Warp Speed Log Streaming - Curio PDP to Better Stack (macOS)
# One-command installer for SP logging setup on macOS

REPO_URL="https://raw.githubusercontent.com/FilOzone/warp-speed-log-streaming/main"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "  Warp Speed Log Streaming Installer"
echo "  Curio PDP → Better Stack (macOS)"
echo "=========================================="

# Detect macOS architecture and set Homebrew prefix
if [[ $(uname -m) == "arm64" ]]; then
    HOMEBREW_PREFIX="/opt/homebrew"
    ARCH="Apple Silicon"
else
    HOMEBREW_PREFIX="/usr/local"
    ARCH="Intel"
fi

echo
echo -e "${GREEN}✓${NC} Detected: macOS $ARCH"
echo -e "${GREEN}✓${NC} Homebrew prefix: $HOMEBREW_PREFIX"

# Set architecture-aware paths
VECTOR_CONFIG_DIR="$HOMEBREW_PREFIX/etc/vector"
LOG_PATH="$HOMEBREW_PREFIX/var/log/curio/curio.log"
LOG_DIR="$HOMEBREW_PREFIX/var/log/curio"

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo -e "${RED}Error: Homebrew is not installed${NC}"
    echo "Install Homebrew first: https://brew.sh"
    echo "Run: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    exit 1
fi

echo -e "${GREEN}✓${NC} Homebrew is installed"

# Step 1: Get client ID
echo
read -r -p "Enter your PDP node name (e.g. ezpdpz-calib): " CLIENT_ID < /dev/tty

if [ -z "$CLIENT_ID" ]; then
    echo -e "${RED}Error: Client ID required${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Client ID: $CLIENT_ID"

# Step 2: Get Better Stack token
echo
read -r -p "Enter Better Stack token: " BETTER_STACK_TOKEN < /dev/tty

if [ -z "$BETTER_STACK_TOKEN" ]; then
    echo -e "${RED}Error: Better Stack token required${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Token received"

# Step 3: Detect deployment method and setup logging
echo
echo "Detecting Curio deployment method..."

ENV_VARS_ADDED=false

# Check if running as launchd service or brew service
if launchctl list 2>/dev/null | grep -q "curio"; then
    echo -e "${GREEN}✓${NC} Curio is running as launchd service"

    # Verify log file exists
    if [ ! -f "$LOG_PATH" ]; then
        echo -e "${RED}Error: $LOG_PATH not found${NC}"
        echo "Your launchd service should create this file automatically."
        echo "Check your service configuration with: launchctl list | grep curio"
        exit 1
    fi

    echo -e "${GREEN}✓${NC} Found curio.log: $LOG_PATH"

elif brew services list 2>/dev/null | grep -q "^curio.*started"; then
    echo -e "${GREEN}✓${NC} Curio is running via brew services"

    # Verify log file exists
    if [ ! -f "$LOG_PATH" ]; then
        echo -e "${RED}Error: $LOG_PATH not found${NC}"
        echo "Your brew service should create this file automatically."
        echo "Check your service configuration: brew services list"
        exit 1
    fi

    echo -e "${GREEN}✓${NC} Found curio.log: $LOG_PATH"

else
    echo -e "${YELLOW}⚠${NC}  Curio is not running as a service (manual deployment)"

    # Create log directory if it doesn't exist
    if [ ! -d "$LOG_DIR" ]; then
        echo "Creating $LOG_DIR directory..."
        mkdir -p "$LOG_DIR"
        chmod 755 "$LOG_DIR"
        echo -e "${GREEN}✓${NC} Created $LOG_DIR"
    fi

    # Detect user's shell
    USER_SHELL=$(basename "$SHELL")

    if [[ "$USER_SHELL" == "zsh" ]]; then
        SHELL_RC="$HOME/.zshrc"
    elif [[ "$USER_SHELL" == "bash" ]]; then
        SHELL_RC="$HOME/.bashrc"
    else
        SHELL_RC="$HOME/.profile"
    fi

    # Remove any existing curio logging config and add fresh config
    echo
    echo "Configuring log environment variables in $SHELL_RC..."
    # Remove old config block if it exists
    sed -i.bak '/# Curio logging configuration/,/GOLOG_LOG_LEVEL/d' "$SHELL_RC" 2>/dev/null || true
    # Add fresh config
    cat >> "$SHELL_RC" <<EOF

# Curio logging configuration (added by warp-speed-log-streaming)
export GOLOG_OUTPUT="file+stdout"
export GOLOG_FILE="$LOG_PATH"
export GOLOG_LOG_FMT="json"
export GOLOG_LOG_LEVEL="debug"
EOF
    echo -e "${GREEN}✓${NC} Configured environment variables in $SHELL_RC"
    ENV_VARS_ADDED=true

    # Source the configuration in current shell
    export GOLOG_OUTPUT="file+stdout"
    export GOLOG_FILE="$LOG_PATH"
    export GOLOG_LOG_FMT="json"
    export GOLOG_LOG_LEVEL="debug"

    # Create empty log file if it doesn't exist
    if [ ! -f "$LOG_PATH" ]; then
        touch "$LOG_PATH"
        chmod 644 "$LOG_PATH"
        echo -e "${GREEN}✓${NC} Created empty log file: $LOG_PATH"
    else
        echo -e "${GREEN}✓${NC} Found existing curio.log"
    fi
fi

# Verify log format if file has content
if [ -f "$LOG_PATH" ] && [ -s "$LOG_PATH" ]; then
    if ! head -1 "$LOG_PATH" | grep -q "^{"; then
        echo -e "${YELLOW}⚠${NC}  Warning: Log file doesn't appear to be JSON formatted"
        echo "   Make sure GOLOG_LOG_FMT=json is set for Curio"
    fi
fi

# Step 4: Clean install of Vector
echo
echo "Ensuring clean Vector installation..."

# Stop vector service if running
brew services stop vector 2>/dev/null || true

# Remove any existing Vector installations
brew uninstall --force vector 2>/dev/null || true
rm -rf ~/.vector 2>/dev/null || true

# Remove Vector from shell configs (BSD sed syntax)
sed -i.bak '/\.vector\/bin/d' ~/.bashrc ~/.profile ~/.zshrc 2>/dev/null || true

echo "Installing Vector via Homebrew..."

# Add Vector tap if not already added
brew tap vectordotdev/brew 2>/dev/null || true

# Install Vector
if ! brew install vector; then
    echo -e "${RED}Error: Failed to install Vector via Homebrew${NC}"
    exit 1
fi

if command -v vector &> /dev/null && [ -d "$VECTOR_CONFIG_DIR" ]; then
    echo -e "${GREEN}✓${NC} Vector installed successfully"
else
    echo -e "${RED}Error: Vector installation failed${NC}"
    echo "Check: command -v vector"
    echo "Check: ls -la $VECTOR_CONFIG_DIR"
    exit 1
fi

# Step 5: Download and configure Vector config
echo
echo "Configuring Vector..."
if ! curl -sSL "$REPO_URL/vector.yaml" -o /tmp/vector-warp-speed.yaml; then
    echo -e "${RED}Error: Failed to download Vector configuration${NC}"
    exit 1
fi

# Replace placeholders (using BSD sed syntax with backup)
if ! sed -i.bak "s|YOUR_CLIENT_ID|$CLIENT_ID|g" /tmp/vector-warp-speed.yaml; then
    echo -e "${RED}Error: Failed to configure client ID${NC}"
    exit 1
fi

if ! sed -i.bak "s|YOUR_BETTER_STACK_TOKEN|$BETTER_STACK_TOKEN|g" /tmp/vector-warp-speed.yaml; then
    echo -e "${RED}Error: Failed to configure Better Stack token${NC}"
    exit 1
fi

# Replace log file path with macOS-specific path
if ! sed -i.bak "s|/var/log/curio/curio.log|$LOG_PATH|g" /tmp/vector-warp-speed.yaml; then
    echo -e "${RED}Error: Failed to configure log path${NC}"
    exit 1
fi

# Clean up backup files
rm -f /tmp/vector-warp-speed.yaml.bak

# Step 6: Install config
mv /tmp/vector-warp-speed.yaml "$VECTOR_CONFIG_DIR/vector.yaml"
echo -e "${GREEN}✓${NC} Configuration installed to $VECTOR_CONFIG_DIR/vector.yaml"

# Step 7: Validate Vector configuration
echo
echo "Validating Vector configuration..."
if vector validate --config "$VECTOR_CONFIG_DIR/vector.yaml"; then
    echo -e "${GREEN}✓${NC} Vector configuration is valid"
else
    echo -e "${RED}Error: Vector configuration validation failed${NC}"
    exit 1
fi

# Step 8: Start Vector service
echo
echo "Starting Vector..."
brew services start vector

# Wait for startup
sleep 3

# Step 9: Verify Vector is running
if brew services list | grep -q "^vector.*started"; then
    echo -e "${GREEN}✓${NC} Vector service is running"
else
    echo -e "${RED}Error: Vector failed to start${NC}"
    echo "Check with: brew services list"
    echo "View logs with: tail -f $HOMEBREW_PREFIX/var/log/vector.log"
    exit 1
fi

# Step 10: Check if Vector has the log file open
sleep 2
if pgrep -q vector; then
    echo -e "${GREEN}✓${NC} Vector process is running (PID: $(pgrep vector))"

    if lsof -p "$(pgrep vector)" 2>/dev/null | grep -q "curio.log"; then
        echo -e "${GREEN}✓${NC} Vector is watching curio.log"
    else
        echo -e "${YELLOW}⚠${NC}  Could not confirm Vector is watching curio.log"
        echo "   This might be okay - check manually with: lsof -p \$(pgrep vector) | grep curio"
    fi
else
    echo -e "${YELLOW}⚠${NC}  Could not find Vector process"
fi

# Step 11: Display success message
echo
echo "=========================================="
echo -e "${GREEN}  Installation Complete!${NC}"
echo "=========================================="
echo
echo "Your Curio PDP logs are now streaming to Better Stack"
echo
echo "Client ID:    $CLIENT_ID"
echo "Log file:     $LOG_PATH"
echo "Vector config: $VECTOR_CONFIG_DIR/vector.yaml"
echo "Architecture: macOS $ARCH"
echo
echo "Questions? Contact the FilOz Team in #fil-warp-speed"

# Display restart warning for manual deployments
if [ "$ENV_VARS_ADDED" = true ]; then
    echo
    echo "=========================================="
    echo -e "${RED}⚠  ACTION REQUIRED${NC}"
    echo "=========================================="
    echo
    echo "You must restart your Curio process to enable logging:"
    echo
    echo "  1. Stop your current Curio process"
    echo "  2. Start a new terminal session (to load new environment)"
    echo "     OR run: source $SHELL_RC"
    echo "  3. Start Curio again"
    echo
    echo "Logs will only stream after Curio is restarted with the new configuration"
    echo "=========================================="
else
    echo
    echo "=========================================="
    echo "Verification:"
    echo
    echo "  # Check Vector status"
    echo "  brew services list | grep vector"
    echo
    echo "  # Check if Vector is watching your log"
    echo "  lsof -p \$(pgrep vector) | grep curio"
    echo
    echo "  # View recent Vector logs (macOS 10.12+)"
    echo "  log show --predicate 'process == \"vector\"' --last 1m --style compact"
    echo
    echo "Logs appear in Better Stack within ~1 minute"
    echo "Filter by: client_id:\"$CLIENT_ID\""
    echo "=========================================="
fi
