#!/bin/bash
# Quick Bell News Installer - One-line installation
# This script downloads and runs the full installer

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🔔 Bell News Quick Installer${NC}"
echo "=================================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error:${NC} This script must be run with sudo"
    echo "Usage: curl -sSL [URL] | sudo bash"
    exit 1
fi

# Check internet connectivity
echo "Checking internet connectivity..."
if ! ping -c 1 google.com &> /dev/null; then
    echo -e "${RED}Error:${NC} No internet connection"
    exit 1
fi

echo -e "${GREEN}✅${NC} Internet connectivity OK"

# Get the current directory where this script is located
SCRIPT_DIR="$(pwd)"

echo "Script directory: $SCRIPT_DIR"

# Check if bellnews_installer.sh exists in current directory
if [[ -f "$SCRIPT_DIR/bellnews_installer.sh" ]]; then
    echo -e "${GREEN}✅${NC} Found bellnews_installer.sh in current directory"
    chmod +x "$SCRIPT_DIR/bellnews_installer.sh"
    exec "$SCRIPT_DIR/bellnews_installer.sh" install
else
    echo -e "${RED}Error:${NC} bellnews_installer.sh not found in $SCRIPT_DIR"
    echo "Please ensure you're in the Bell News directory with all files"
    exit 1
fi