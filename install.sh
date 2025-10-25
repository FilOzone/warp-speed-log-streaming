#!/bin/bash
set -e

# Warp Speed Log Streaming - Curio PDP to Better Stack
# One-command installer for SP logging setup

REPO_URL="https://raw.githubusercontent.com/FilOzone/warp-speed-log-streaming/main"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "  Warp Speed Log Streaming Installer"
echo "  Curio PDP → Better Stack"
echo "=========================================="

# Step 1: Get client ID
echo
read -p "Enter your PDP node name (e.g. ezpdpz-calib): " CLIENT_ID < /dev/tty

if [ -z "$CLIENT_ID" ]; then
    echo -e "${RED}Error: Client ID required${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Client ID: $CLIENT_ID"

# Step 2: Get Better Stack token
echo
read -p "Enter Better Stack token: " BETTER_STACK_TOKEN < /dev/tty

if [ -z "$BETTER_STACK_TOKEN" ]; then
    echo -e "${RED}Error: Better Stack token required${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Token received"

# Step 3: Detect deployment method and setup logging
echo
echo "Detecting Curio deployment method..."
LOG_PATH="/var/log/curio/curio.log"

# Check if running as systemd service
if systemctl is-active --quiet curio 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Curio is running as systemd service"

    # Verify log file exists
    if [ ! -f "$LOG_PATH" ]; then
        echo -e "${RED}Error: $LOG_PATH not found${NC}"
        echo "Your systemd service should create this file automatically."
        echo "Check your service configuration: sudo systemctl status curio"
        exit 1
    fi

    echo -e "${GREEN}✓${NC} Found curio.log: $LOG_PATH"

else
    echo -e "${YELLOW}⚠${NC}  Curio is not running as systemd service (manual deployment)"

    # Create log directory if it doesn't exist
    if [ ! -d "/var/log/curio" ]; then
        echo "Creating /var/log/curio directory..."
        sudo mkdir -p /var/log/curio
        sudo chown $USER:$USER /var/log/curio
        sudo chmod 755 /var/log/curio
        echo -e "${GREEN}✓${NC} Created /var/log/curio"
    fi

    # Check if environment variables are set in profile.d
    ENV_VARS_ADDED=false
    if [ ! -f "/etc/profile.d/curio-logging.sh" ]; then
        echo
        echo "Adding log environment variables to /etc/profile.d/curio-logging.sh..."
        sudo bash -c 'cat > /etc/profile.d/curio-logging.sh <<EOF
# Curio logging configuration (added by warp-speed-log-streaming)
export GOLOG_OUTPUT="file+stdout"
export GOLOG_FILE="/var/log/curio/curio.log"
export GOLOG_LOG_FMT="json"
EOF'
        source /etc/profile.d/curio-logging.sh
        echo -e "${GREEN}✓${NC} Added environment variables to /etc/profile.d/curio-logging.sh"
        ENV_VARS_ADDED=true
    else
        echo -e "${GREEN}✓${NC} Log environment variables already configured"
    fi

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
sudo systemctl stop vector 2>/dev/null || true

# Remove any existing Vector installations
sudo apt-get purge -y vector 2>/dev/null || true
rm -rf ~/.vector 2>/dev/null || true

# Remove Vector from shell configs
sed -i '/\.vector\/bin/d' ~/.bashrc ~/.profile 2>/dev/null || true

echo "Installing Vector via Better Stack..."

# Download Better Stack's Vector installer
curl -sSL https://telemetry.betterstack.com/setup-vector/ubuntu/$BETTER_STACK_TOKEN \
  -o /tmp/setup-vector.sh

# Temporarily disable needrestart prompts (Ubuntu/Debian only, harmless on other distros)
if [ -d "/etc/needrestart" ]; then
    sudo mkdir -p /etc/needrestart/conf.d
    echo "\$nrconf{restart} = 'a';" | sudo tee /etc/needrestart/conf.d/50-local.conf > /dev/null
fi

# Run installer
bash /tmp/setup-vector.sh

# Remove temporary config
sudo rm -f /etc/needrestart/conf.d/50-local.conf 2>/dev/null || true

if command -v vector &> /dev/null && [ -d "/etc/vector" ]; then
    echo -e "${GREEN}✓${NC} Vector installed successfully"
else
    echo -e "${RED}Error: Vector installation failed${NC}"
    exit 1
fi

# Step 5: Download and configure Vector config
echo
echo "Configuring Vector..."
if ! curl -sSL "$REPO_URL/vector.yaml" -o /tmp/vector-warp-speed.yaml; then
    echo -e "${RED}Error: Failed to download Vector configuration${NC}"
    exit 1
fi

# Replace placeholders
if ! sed -i "s|YOUR_CLIENT_ID|$CLIENT_ID|g" /tmp/vector-warp-speed.yaml; then
    echo -e "${RED}Error: Failed to configure client ID${NC}"
    exit 1
fi

if ! sed -i "s|YOUR_BETTER_STACK_TOKEN|$BETTER_STACK_TOKEN|g" /tmp/vector-warp-speed.yaml; then
    echo -e "${RED}Error: Failed to configure Better Stack token${NC}"
    exit 1
fi

# Step 6: Install config
sudo mv /tmp/vector-warp-speed.yaml /etc/vector/vector.yaml
echo -e "${GREEN}✓${NC} Configuration installed"

# Step 7: Enable and start Vector
echo
echo "Starting Vector..."
sudo systemctl enable vector > /dev/null 2>&1
sudo systemctl restart vector

# Step 8: Wait for startup
sleep 2

# Step 9: Verify Vector is running
if systemctl is-active --quiet vector; then
    echo -e "${GREEN}✓${NC} Vector service is running"
else
    echo -e "${RED}Error: Vector failed to start${NC}"
    echo "Check logs with: sudo journalctl -u vector -n 50"
    exit 1
fi

# Step 10: Check for successful file detection
if sudo journalctl -u vector --since "10 seconds ago" | grep -q "Found new file to watch"; then
    echo -e "${GREEN}✓${NC} Vector found and is watching curio.log"
elif sudo journalctl -u vector --since "10 seconds ago" | grep -q "Starting file server"; then
    echo -e "${GREEN}✓${NC} Vector file server started"
else
    echo -e "${YELLOW}⚠${NC}  Could not confirm file watching (this might be okay)"
fi

# Step 11: Display success message
echo
echo "=========================================="
echo -e "${GREEN}  Installation Complete!${NC}"
echo "=========================================="
echo
echo "Your Curio PDP logs are now streaming to Better Stack"
echo
echo "Client ID: $CLIENT_ID"
echo "Log file:  /var/log/curio/curio.log"
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
    echo "  2. Source the environment: source /etc/profile.d/curio-logging.sh"
    echo "     (or start a new shell session)"
    echo "  3. Start Curio again"
    echo
    echo "Logs will only stream after Curio is restarted with the new configuration"
    echo "=========================================="
else
    echo "=========================================="
fi
