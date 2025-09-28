#!/bin/bash
# MINIMAL NANO PI FIX - CORE SERVICES ONLY
# Skips problematic time-fix and focuses on bellapp + newsapp

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

echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║       MINIMAL NANO PI FIX - CORE ONLY       ║${NC}"
echo -e "${GREEN}║         Bellapp + Newsapp + Config          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
    echo "Run: sudo bash $0"
    exit 1
fi

# Step 1: Complete cleanup
info "Stopping all containers and cleaning up..."
docker-compose down --remove-orphans 2>/dev/null || true
docker stop $(docker ps -aq) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true
docker system prune -f
docker builder prune -f

# Step 2: Detect IP
info "Detecting IP address..."
IP=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' | head -1 || echo "192.168.33.145")
success "Detected IP: $IP"

# Step 3: Create minimal .env
cat > .env << EOF
HOST_IP=$IP
APP_ENV=production
APP_DEBUG=false
VITE_API_BASE_URL=http://$IP:5000
UBUNTU_CONFIG_SERVICE_URL=http://localhost:5002
IN_DOCKER_TEST_MODE=false
EOF

# Step 4: Fix ARM64 platform issues
export DOCKER_BUILDKIT=1
export DOCKER_DEFAULT_PLATFORM=linux/arm64

# Step 5: Create ultra-minimal Docker Compose
info "Creating minimal Docker Compose for core services..."
cat > docker-compose.minimal.yml << EOF
version: '3.8'

services:
  # Minimal config service (if it builds)
  config_service:
    build:
      context: .
      dockerfile: Dockerfile_config
      platforms:
        - linux/arm64
    network_mode: "host"
    restart: always
    container_name: config_service
    volumes:
      - /etc/netplan:/etc/netplan
      - ./config_service_logs:/var/log
    privileged: true
    environment:
      IN_DOCKER_TEST_MODE: "false"
    mem_limit: 100m

  # Main bellapp
  pythonapp:
    build:
      context: ./bellapp
      platforms:
        - linux/arm64
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
    mem_limit: 180m

  # Laravel newsapp
  laravelapp:
    build:
      context: ./newsapp
      platforms:
        - linux/arm64
    environment:
      - VITE_API_BASE_URL=http://$IP:5000
      - APP_ENV=production
      - APP_DEBUG=false
    ports:
      - "8000:8000"
    restart: always
    container_name: newsapp
    mem_limit: 120m
    depends_on:
      - pythonapp

networks:
  default:
    driver: bridge
EOF

# Step 6: Try building config service first
info "Testing config service build..."
if docker build -f Dockerfile_config -t test-config:latest . --platform linux/arm64 2>/dev/null; then
    success "Config service builds successfully"
    CONFIG_WORKS=true
else
    warn "Config service build failed - will skip it"
    CONFIG_WORKS=false
fi

# Step 7: Try building bellapp
info "Testing bellapp build..."
if [[ -d "bellapp" ]] && docker build ./bellapp -t test-bellapp:latest --platform linux/arm64 2>/dev/null; then
    success "Bellapp builds successfully"
    BELLAPP_WORKS=true
else
    warn "Bellapp build failed"
    BELLAPP_WORKS=false
fi

# Step 8: Try building newsapp
info "Testing newsapp build..."
if [[ -d "newsapp" ]] && docker build ./newsapp -t test-newsapp:latest --platform linux/arm64 2>/dev/null; then
    success "Newsapp builds successfully"
    NEWSAPP_WORKS=true
else
    warn "Newsapp build failed"
    NEWSAPP_WORKS=false
fi

# Step 9: Create working compose based on what builds
info "Creating compose file based on working services..."
cat > docker-compose.working.yml << EOF
version: '3.8'
services:
EOF

if [[ "$CONFIG_WORKS" == "true" ]]; then
    cat >> docker-compose.working.yml << EOF
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
    mem_limit: 100m

EOF
fi

if [[ "$BELLAPP_WORKS" == "true" ]]; then
    cat >> docker-compose.working.yml << EOF
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
    mem_limit: 180m
EOF

    if [[ "$CONFIG_WORKS" == "true" ]]; then
        echo "    depends_on:" >> docker-compose.working.yml
        echo "      - config_service" >> docker-compose.working.yml
    fi
    echo "" >> docker-compose.working.yml
fi

if [[ "$NEWSAPP_WORKS" == "true" ]]; then
    cat >> docker-compose.working.yml << EOF
  laravelapp:
    build: ./newsapp
    environment:
      - VITE_API_BASE_URL=http://$IP:5000
      - APP_ENV=production
      - APP_DEBUG=false
    ports:
      - "8000:8000"
    restart: always
    container_name: newsapp
    mem_limit: 120m
EOF

    if [[ "$BELLAPP_WORKS" == "true" ]]; then
        echo "    depends_on:" >> docker-compose.working.yml
        echo "      - pythonapp" >> docker-compose.working.yml
    fi
    echo "" >> docker-compose.working.yml
fi

# Step 10: Start working services
if [[ "$CONFIG_WORKS" == "true" ]] || [[ "$BELLAPP_WORKS" == "true" ]] || [[ "$NEWSAPP_WORKS" == "true" ]]; then
    info "Starting working services..."
    docker-compose -f docker-compose.working.yml up -d

    sleep 20

    # Check what's running
    info "Checking running services..."
    docker ps

    # Test endpoints
    echo
    info "Testing service endpoints..."

    if [[ "$CONFIG_WORKS" == "true" ]]; then
        if curl -f -s --max-time 5 "http://localhost:5002/health" > /dev/null 2>&1; then
            success "✓ Config Service (port 5002): OK"
        else
            warn "✗ Config Service (port 5002): Not responding"
        fi
    fi

    if [[ "$BELLAPP_WORKS" == "true" ]]; then
        if curl -f -s --max-time 5 "http://$IP:5000/health" > /dev/null 2>&1 || curl -f -s --max-time 5 "http://$IP:5000/" > /dev/null 2>&1; then
            success "✓ Bell App (port 5000): OK"
        else
            warn "✗ Bell App (port 5000): Not responding"
        fi
    fi

    if [[ "$NEWSAPP_WORKS" == "true" ]]; then
        if curl -f -s --max-time 5 "http://$IP:8000/" > /dev/null 2>&1; then
            success "✓ News App (port 8000): OK"
        else
            warn "✗ News App (port 8000): Not responding"
        fi
    fi

else
    error "No services could be built successfully"
    echo "Please check:"
    echo "1. ./bellapp/Dockerfile exists"
    echo "2. ./newsapp/Dockerfile exists"
    echo "3. Dockerfile_config exists"
    exit 1
fi

echo
success "Minimal deployment completed!"
echo
echo -e "${GREEN}📱 WORKING SERVICES:${NC}"
if [[ "$CONFIG_WORKS" == "true" ]]; then
    echo -e "   • Config API:  ${GREEN}http://localhost:5002${NC}"
fi
if [[ "$BELLAPP_WORKS" == "true" ]]; then
    echo -e "   • Bell App:    ${GREEN}http://$IP:5000${NC}"
fi
if [[ "$NEWSAPP_WORKS" == "true" ]]; then
    echo -e "   • News App:    ${GREEN}http://$IP:8000${NC}"
fi

echo
echo -e "${YELLOW}🔧 MANAGEMENT:${NC}"
echo -e "   • Check status:    ${YELLOW}docker-compose -f docker-compose.working.yml ps${NC}"
echo -e "   • View logs:       ${YELLOW}docker-compose -f docker-compose.working.yml logs -f${NC}"
echo -e "   • Restart:         ${YELLOW}docker-compose -f docker-compose.working.yml restart${NC}"

if [[ "$BELLAPP_WORKS" != "true" ]] || [[ "$NEWSAPP_WORKS" != "true" ]]; then
    echo
    warn "Some services failed to build. Check individual logs:"
    echo "   docker logs bellapp"
    echo "   docker logs newsapp"
    echo "   docker logs config_service"
fi