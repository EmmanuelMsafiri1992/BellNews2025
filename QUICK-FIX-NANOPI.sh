#!/bin/bash
# QUICK FIX FOR NANO PI DOCKER BUILD ISSUES
# Fixes the immediate Docker Hub pull errors and builds locally

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

SCRIPT_DIR="$(pwd)"

echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          QUICK FIX FOR NANO PI               ║${NC}"
echo -e "${GREEN}║       Fixes Docker Build Issues             ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
    echo "Run: sudo bash $0"
    exit 1
fi

# Step 1: Stop any running containers
info "Stopping any running containers..."
docker-compose down --remove-orphans 2>/dev/null || true
docker stop $(docker ps -aq) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true

# Step 2: Clean Docker to free up space
info "Cleaning Docker system to free up space..."
docker system prune -f
docker builder prune -f

# Step 3: Detect IP address
info "Detecting IP address..."
IP=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' | head -1 || echo "192.168.33.145")
success "Detected IP: $IP"

# Step 4: Create/update .env file
info "Creating .env file with detected IP..."
cat > .env << EOF
# Auto-generated configuration
HOST_IP=$IP
DOCKER_HUB_USERNAME=yourusername
IMAGE_TAG=latest
APP_ENV=production
APP_DEBUG=false
VITE_API_BASE_URL=http://$IP:5000
UBUNTU_CONFIG_SERVICE_URL=http://localhost:5002
IN_DOCKER_TEST_MODE=false
NETWORK_SUBNET=172.20.0.0/16
TZ=UTC
EOF

# Step 5: Build images one by one to avoid memory issues
info "Building Docker images individually to avoid memory issues..."

# Set ARM64 platform
export DOCKER_BUILDKIT=1
export DOCKER_DEFAULT_PLATFORM=linux/arm64

# Build time-fix service
if [[ -f "Dockerfile.timefix" ]]; then
    info "Building time-fix service..."
    docker build -f Dockerfile.timefix -t nano-pi-time-fix:latest . --no-cache
    success "Time-fix service built"
else
    warn "Dockerfile.timefix not found, skipping time-fix service"
fi

# Build config service
if [[ -f "Dockerfile_config" ]]; then
    info "Building config service..."
    docker build -f Dockerfile_config -t nano-pi-config:latest . --no-cache
    success "Config service built"
else
    warn "Dockerfile_config not found, skipping config service"
fi

# Build bellapp
if [[ -d "bellapp" ]] && [[ -f "bellapp/Dockerfile" ]]; then
    info "Building bellapp..."
    docker build ./bellapp -t nano-pi-bellapp:latest --no-cache
    success "Bellapp built"
else
    warn "bellapp/Dockerfile not found, skipping bellapp"
fi

# Build newsapp
if [[ -d "newsapp" ]] && [[ -f "newsapp/Dockerfile" ]]; then
    info "Building newsapp..."
    docker build ./newsapp -t nano-pi-newsapp:latest --no-cache
    success "Newsapp built"
else
    warn "newsapp/Dockerfile not found, skipping newsapp"
fi

# Step 6: Create a simple working compose file
info "Creating simplified Docker Compose configuration..."
cat > docker-compose.simple.yml << EOF
version: '3.8'

services:
  # Ubuntu Configuration Service
  config_service:
    build:
      context: .
      dockerfile: Dockerfile_config
    network_mode: "host"
    restart: always
    container_name: config_service
    volumes:
      - /etc/netplan:/etc/netplan
      - ./config_service_logs:/var/log
    privileged: true
    environment:
      IN_DOCKER_TEST_MODE: "false"
    mem_limit: 128m

  # Main Python Flask application (bellapp)
  pythonapp:
    build: ./bellapp
    ports:
      - "5000:5000"
      - "5001:5001"
    restart: always
    container_name: bellapp
    volumes:
      - ./bellapp/logs:/bellapp/logs
    environment:
      UBUNTU_CONFIG_SERVICE_URL: http://localhost:5002
      HOST_IP: $IP
    mem_limit: 200m
    depends_on:
      - config_service

  # Laravel news application
  laravelapp:
    build: ./newsapp
    environment:
      - VITE_API_BASE_URL=http://$IP:5000
      - APP_ENV=production
      - APP_DEBUG=false
      - APP_URL=http://$IP:8000
    ports:
      - "8000:8000"
    restart: always
    container_name: newsapp
    mem_limit: 150m
    depends_on:
      - pythonapp

networks:
  default:
    driver: bridge
EOF

# Step 7: Start services
info "Starting Docker services..."
docker-compose -f docker-compose.simple.yml up -d

# Step 8: Wait and check status
info "Waiting for services to start..."
sleep 30

info "Checking service status..."
docker-compose -f docker-compose.simple.yml ps

# Step 9: Test endpoints
info "Testing service endpoints..."

# Test config service
if curl -f -s --max-time 10 "http://localhost:5002/health" > /dev/null 2>&1; then
    success "✓ Config Service (port 5002): OK"
else
    warn "✗ Config Service (port 5002): Check logs with: docker logs config_service"
fi

# Test bellapp
if curl -f -s --max-time 10 "http://$IP:5000/health" > /dev/null 2>&1 || curl -f -s --max-time 10 "http://$IP:5000/" > /dev/null 2>&1; then
    success "✓ Bell App (port 5000): OK"
else
    warn "✗ Bell App (port 5000): Check logs with: docker logs bellapp"
fi

# Test newsapp
if curl -f -s --max-time 10 "http://$IP:8000/health" > /dev/null 2>&1 || curl -f -s --max-time 10 "http://$IP:8000/" > /dev/null 2>&1; then
    success "✓ News App (port 8000): OK"
else
    warn "✗ News App (port 8000): Check logs with: docker logs newsapp"
fi

echo
success "Quick fix deployment completed!"
echo
echo -e "${GREEN}📱 ACCESS YOUR APPLICATIONS:${NC}"
echo -e "   • Bell App:    ${GREEN}http://$IP:5000${NC}"
echo -e "   • News App:    ${GREEN}http://$IP:8000${NC}"
echo -e "   • Config API:  ${GREEN}http://localhost:5002${NC}"
echo
echo -e "${YELLOW}🔧 USEFUL COMMANDS:${NC}"
echo -e "   • Check status:    ${YELLOW}docker-compose -f docker-compose.simple.yml ps${NC}"
echo -e "   • View all logs:   ${YELLOW}docker-compose -f docker-compose.simple.yml logs -f${NC}"
echo -e "   • View specific:   ${YELLOW}docker logs [container_name]${NC}"
echo -e "   • Restart all:     ${YELLOW}docker-compose -f docker-compose.simple.yml restart${NC}"
echo