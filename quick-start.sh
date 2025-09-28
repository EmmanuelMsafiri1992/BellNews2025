#!/bin/bash
# FBellNewsV3 Quick Start Script
# One-command setup for any Ubuntu system

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                  FBellNews Quick Start                      ║"
echo "║              One-Command Setup & Launch                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check if we need to run setup
if ! command -v docker >/dev/null 2>&1 || ! command -v docker-compose >/dev/null 2>&1; then
    echo -e "${YELLOW}Docker not found. Running Ubuntu setup...${NC}"
    
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Setup requires root privileges. Restarting with sudo...${NC}"
        exec sudo "$0" "$@"
    fi
    
    ./ubuntu-setup.sh
    
    echo -e "${GREEN}Setup completed! Continuing with application start...${NC}"
    echo "Switching back to regular user for Docker operations..."
    
    # Switch back to the original user for Docker operations
    if [ -n "${SUDO_USER:-}" ]; then
        exec sudo -u "$SUDO_USER" "$0" "$@"
    fi
fi

# Ensure we have the time fix script
if [ ! -f "./auto-time-fix.sh" ]; then
    echo -e "${RED}Error: auto-time-fix.sh not found!${NC}"
    exit 1
fi

# Run time fix
echo -e "${BLUE}🕒 Fixing system time...${NC}"
sudo bash ./auto-time-fix.sh || echo "Time fix completed with warnings"

# Start network monitor if not running
if ! systemctl is-active fbellnews-network-monitor >/dev/null 2>&1; then
    echo -e "${BLUE}🌐 Starting network monitor...${NC}"
    sudo systemctl start fbellnews-network-monitor 2>/dev/null || true
fi

# Make sure we're in the right directory
cd "$SCRIPT_DIR"

# Check if services are already running
if docker ps | grep -q "bellapp\|newsapp\|config_service"; then
    echo -e "${YELLOW}Services are already running. Stopping them first...${NC}"
    docker-compose -f docker-compose.dev.yml down 2>/dev/null || docker compose -f docker-compose.dev.yml down 2>/dev/null || true
fi

# Clean up any previous containers/images
echo -e "${BLUE}🧹 Cleaning up previous installation...${NC}"
docker container prune -f 2>/dev/null || true
docker image prune -f 2>/dev/null || true

# Build and start services
echo -e "${BLUE}🚀 Building and starting FBellNews services...${NC}"

# Try docker-compose first, then docker compose
if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
else
    COMPOSE_CMD="docker compose"
fi

# Build with progress output
$COMPOSE_CMD -f docker-compose.dev.yml build --progress=plain

# Start services
echo -e "${BLUE}🌟 Starting all services...${NC}"
$COMPOSE_CMD -f docker-compose.dev.yml up -d

# Wait for services to start
echo -e "${BLUE}⏳ Waiting for services to start...${NC}"
sleep 10

# Check service status
echo -e "${BLUE}📊 Checking service status...${NC}"
$COMPOSE_CMD -f docker-compose.dev.yml ps

# Get current IP
CURRENT_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")

# Show success message
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                 🎉 SUCCESS! 🎉                               ║"
echo "║              FBellNews is now running!                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}📱 Application URLs:${NC}"
echo "  • News App:       http://$CURRENT_IP:8000"
echo "  • Python API:     http://$CURRENT_IP:5000"
echo "  • Config Service: http://$CURRENT_IP:5002"
echo "  • Vite Dev:       http://$CURRENT_IP:5173"
echo ""

echo -e "${YELLOW}🔧 Management Commands:${NC}"
echo "  • View logs:      $COMPOSE_CMD -f docker-compose.dev.yml logs -f"
echo "  • Stop services:  $COMPOSE_CMD -f docker-compose.dev.yml down"
echo "  • Restart:        $COMPOSE_CMD -f docker-compose.dev.yml restart"
echo "  • Status:         $COMPOSE_CMD -f docker-compose.dev.yml ps"
echo ""

echo -e "${YELLOW}📋 What's Running:${NC}"
echo "  🕒 Time Fix Service (ensures accurate system time)"
echo "  🌐 Network Monitor (handles IP changes automatically)"
echo "  🐍 Python Flask App (BellApp - Timer/Alarm functions)"
echo "  📰 Laravel News App (News display with Vue.js frontend)"
echo "  ⚙️  Ubuntu Config Service (System configuration)"
echo ""

echo -e "${YELLOW}🔄 Network Change Support:${NC}"
echo "  • Automatic DHCP ↔ Static IP handling"
echo "  • No reboot required for network changes"
echo "  • Docker services auto-recover"
echo "  • Application URLs auto-update"
echo ""

# Show time fix log if available
if [ -f "/var/log/fbellnews-time-fix.log" ]; then
    echo -e "${YELLOW}🕒 Time Fix Status:${NC}"
    tail -3 /var/log/fbellnews-time-fix.log 2>/dev/null || echo "Time fix log not accessible"
    echo ""
fi

echo -e "${GREEN}✅ FBellNews is ready! Open http://$CURRENT_IP:8000 in your browser.${NC}"

# Optional: Open browser if on desktop system
if command -v xdg-open >/dev/null 2>&1; then
    read -p "Open in browser now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        xdg-open "http://$CURRENT_IP:8000" 2>/dev/null &
    fi
fi