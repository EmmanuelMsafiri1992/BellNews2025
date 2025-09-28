#!/bin/bash
# NANO PI MEMORY-OPTIMIZED DOCKER FIX
# Specifically designed for low-memory ARM64 devices like Nano Pi

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

print_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              NANO PI MEMORY-OPTIMIZED DOCKER FIX            ║"
    echo "║                 For Low-Memory ARM64 Devices                 ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Check root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
    echo "Run: sudo bash $0"
    exit 1
fi

print_banner

# Check available memory
total_mem=$(free -m | awk 'NR==2{printf "%.0f", $2}')
info "Available memory: ${total_mem}MB"

if [ "$total_mem" -lt 512 ]; then
    error "Insufficient memory. Nano Pi needs at least 512MB for Docker builds."
    info "Adding swap space..."

    # Create 1GB swap file if not exists
    if [ ! -f /swapfile ]; then
        dd if=/dev/zero of=/swapfile bs=1M count=1024
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        success "Swap space added"
    fi

    # Verify memory after swap
    total_mem=$(free -m | awk 'NR==2{printf "%.0f", $2}')
    swap_mem=$(free -m | awk 'NR==3{printf "%.0f", $2}')
    info "Memory after swap: ${total_mem}MB RAM + ${swap_mem}MB swap"
fi

# Step 1: AGGRESSIVE CLEANUP
info "Step 1: Aggressive system cleanup..."

# Stop all Docker processes
pkill -f docker 2>/dev/null || true
systemctl stop docker 2>/dev/null || true

# Clean everything
docker-compose -f docker-compose.prod.yml down --remove-orphans --volumes 2>/dev/null || true
docker system prune -a -f --volumes 2>/dev/null || true
docker builder prune -a -f 2>/dev/null || true

# Clean system cache
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*
rm -rf /var/tmp/*
find /var/cache -type f -delete 2>/dev/null || true

# Restart Docker
systemctl start docker
sleep 5

success "System cleaned"

# Step 2: DNS Configuration
info "Step 2: Configuring DNS..."

cat > /etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
options timeout:2
options attempts:2
EOF

# Configure Docker daemon for low memory
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "dns": ["8.8.8.8", "8.8.4.4"],
  "dns-opts": ["timeout:2", "attempts:2"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "5m",
    "max-file": "2"
  },
  "max-concurrent-downloads": 1,
  "max-concurrent-uploads": 1,
  "storage-driver": "overlay2"
}
EOF

systemctl restart docker
sleep 5

success "DNS configured"

# Step 3: Build services one by one with memory monitoring
info "Step 3: Building services with memory optimization..."

build_with_memory_check() {
    local service=$1

    info "Building $service..."

    # Check memory before build
    local available_mem=$(free -m | awk 'NR==2{print $7}')
    if [ "$available_mem" -lt 100 ]; then
        warn "Low memory detected ($available_mem MB). Running cleanup..."
        docker system prune -f
        sync && echo 3 > /proc/sys/vm/drop_caches
        sleep 2
    fi

    # Build with resource limits
    if docker-compose -f docker-compose.prod.yml build --memory=400m "$service"; then
        success "$service built successfully"

        # Cleanup after each build
        docker image prune -f
        sync && echo 1 > /proc/sys/vm/drop_caches

        return 0
    else
        error "$service build failed"
        return 1
    fi
}

# Build services in order of complexity (smallest first)
build_with_memory_check "time-fix"
build_with_memory_check "config_service"
build_with_memory_check "pythonapp"
build_with_memory_check "laravelapp"

success "All services built successfully"

# Step 4: Start services with memory limits
info "Step 4: Starting services with resource limits..."

# Create memory-limited compose override
cat > docker-compose.memory.yml << 'EOF'
services:
  time-fix:
    mem_limit: 128m
    memswap_limit: 256m

  config_service:
    mem_limit: 256m
    memswap_limit: 512m

  pythonapp:
    mem_limit: 256m
    memswap_limit: 512m

  laravelapp:
    mem_limit: 384m
    memswap_limit: 768m
EOF

# Start services
if docker-compose -f docker-compose.prod.yml -f docker-compose.memory.yml up -d; then
    success "Services started successfully"
else
    error "Failed to start services"
    exit 1
fi

# Wait for services to stabilize
info "Waiting for services to stabilize..."
sleep 15

# Step 5: Verify deployment
info "Step 5: Checking deployment status..."

docker-compose -f docker-compose.prod.yml ps

# Check for failed containers
failed_containers=$(docker-compose -f docker-compose.prod.yml ps --filter "status=exited" --format "table {{.Service}}" | tail -n +2)

if [ -n "$failed_containers" ] && [ "$failed_containers" != "Service" ]; then
    warn "Some containers failed to start:"
    echo "$failed_containers"

    info "Showing logs..."
    while read -r service; do
        if [ -n "$service" ] && [ "$service" != "Service" ]; then
            echo -e "\n${YELLOW}=== Logs for $service ===${NC}"
            docker-compose -f docker-compose.prod.yml logs --tail=10 "$service"
        fi
    done <<< "$failed_containers"
else
    success "🎉 ALL CONTAINERS RUNNING ON NANO PI! 🎉"
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║               NANO PI DEPLOYMENT SUCCESSFUL                 ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    info "Service URLs:"
    echo "  🐍 Python App:    http://$(hostname -I | awk '{print $1}'):5000"
    echo "  🌐 Laravel App:   http://$(hostname -I | awk '{print $1}'):8000"
    echo "  ⚙️  Config Service: http://$(hostname -I | awk '{print $1}'):5002"
    echo ""
fi

# Show memory usage
info "Final memory status:"
free -h
echo ""
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"

success "🚀 NANO PI MEMORY-OPTIMIZED DEPLOYMENT COMPLETE! 🚀"