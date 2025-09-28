#!/bin/bash
# EXTREME MEMORY FIX FOR NANO PI - LAST RESORT
# For devices with extremely limited memory (<512MB)

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
    echo "║          EXTREME MEMORY FIX FOR NANO PI - LAST RESORT       ║"
    echo "║              For devices with <512MB RAM                    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
    echo "Run: sudo bash $0"
    exit 1
fi

print_banner

# Check memory
total_mem=$(free -m | awk 'NR==2{printf "%.0f", $2}')
info "Available memory: ${total_mem}MB"

# FORCE swap creation regardless of memory
info "Creating maximum swap space..."
swapoff -a 2>/dev/null || true
rm -f /swapfile 2>/dev/null || true

# Create 2GB swap (larger than typical for extreme cases)
dd if=/dev/zero of=/swapfile bs=1M count=2048
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# Make swap permanent
grep -v '/swapfile' /etc/fstab > /tmp/fstab.tmp 2>/dev/null || true
mv /tmp/fstab.tmp /etc/fstab 2>/dev/null || true
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Optimize swap usage
echo 'vm.swappiness=60' >> /etc/sysctl.conf
echo 'vm.vfs_cache_pressure=50' >> /etc/sysctl.conf
sysctl -p

success "Swap configured: $(free -h | grep Swap)"

# NUCLEAR Docker cleanup
info "Nuclear Docker cleanup..."
pkill -f docker 2>/dev/null || true
systemctl stop docker 2>/dev/null || true

# Remove everything
docker-compose -f docker-compose.prod.yml down --remove-orphans --volumes 2>/dev/null || true
docker system prune -a -f --volumes 2>/dev/null || true
docker builder prune -a -f 2>/dev/null || true

# Clean Docker directories
rm -rf /var/lib/docker/tmp/* 2>/dev/null || true
rm -rf /var/lib/docker/overlay2/* 2>/dev/null || true

# System cleanup
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/* /var/tmp/*
find /var/cache -type f -delete 2>/dev/null || true

# Force memory cleanup
sync && echo 3 > /proc/sys/vm/drop_caches
sleep 2

systemctl start docker
sleep 10

success "Cleanup complete"

# Configure host system APT (same as container)
info "Configuring host APT for extreme memory..."
cat > /etc/apt/apt.conf.d/01nano-pi-memory << 'EOF'
APT::Cache-Start 25165824;
APT::Cache-Grow 2097152;
APT::Cache-Limit 50331648;
APT::Keep-Downloaded-Packages "false";
Dir::Cache::pkgcache "";
Dir::Cache::srcpkgcache "";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
APT::Get::List-Cleanup "false";
EOF

# DNS configuration
cat > /etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
options timeout:2
options attempts:1
EOF

# Docker daemon for extreme memory constraints
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "dns": ["8.8.8.8", "8.8.4.4"],
  "dns-opts": ["timeout:2", "attempts:1"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "1m",
    "max-file": "1"
  },
  "max-concurrent-downloads": 1,
  "max-concurrent-uploads": 1,
  "storage-driver": "overlay2",
  "default-ulimits": {
    "memlock": {
      "Hard": 67108864,
      "Name": "memlock",
      "Soft": 67108864
    }
  }
}
EOF

systemctl restart docker
sleep 10

success "System configured for extreme memory constraints"

# Build function with extreme monitoring
build_service_extreme() {
    local service=$1
    info "Building $service with extreme memory monitoring..."

    # Pre-build cleanup
    docker system prune -f
    sync && echo 1 > /proc/sys/vm/drop_caches

    # Check available memory
    local available=$(free -m | awk 'NR==2{print $7}')
    info "Available memory before build: ${available}MB"

    if [ "$available" -lt 50 ]; then
        warn "Critically low memory. Forcing cache cleanup..."
        sync && echo 3 > /proc/sys/vm/drop_caches
        sleep 5
    fi

    # Build with minimal resources
    if timeout 1800 docker-compose -f docker-compose.prod.yml build \
        --memory=200m \
        --memory-swap=600m \
        --cpus=0.5 \
        "$service"; then

        success "$service built successfully"

        # Post-build cleanup
        docker image prune -f
        sync && echo 1 > /proc/sys/vm/drop_caches

        return 0
    else
        error "$service build failed or timed out"
        return 1
    fi
}

# Build services in order of resource requirements
info "Building services with extreme resource constraints..."

build_service_extreme "time-fix"
build_service_extreme "config_service"
build_service_extreme "pythonapp"
build_service_extreme "laravelapp"

success "All services built with extreme memory optimization"

# Create ultra-minimal compose override
cat > docker-compose.extreme-memory.yml << 'EOF'
services:
  time-fix:
    mem_limit: 64m
    memswap_limit: 128m
    cpus: 0.25

  config_service:
    mem_limit: 128m
    memswap_limit: 256m
    cpus: 0.25

  pythonapp:
    mem_limit: 128m
    memswap_limit: 256m
    cpus: 0.25

  laravelapp:
    mem_limit: 256m
    memswap_limit: 512m
    cpus: 0.5
EOF

# Start services with extreme constraints
info "Starting services with ultra-minimal resource limits..."

if docker-compose -f docker-compose.prod.yml -f docker-compose.extreme-memory.yml up -d; then
    success "Services started successfully"
else
    error "Failed to start services"
    exit 1
fi

# Monitor startup
info "Monitoring service startup..."
sleep 20

# Check status
docker-compose -f docker-compose.prod.yml ps

# Show memory usage
info "Final system status:"
free -h
echo ""
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"

# Check for failed containers
failed=$(docker-compose -f docker-compose.prod.yml ps --filter "status=exited" --format "{{.Service}}" | head -5)
if [ -n "$failed" ]; then
    warn "Some containers may have failed:"
    echo "$failed"

    info "Quick logs:"
    for service in $failed; do
        if [ -n "$service" ]; then
            echo -e "\n${YELLOW}=== $service logs ===${NC}"
            docker-compose -f docker-compose.prod.yml logs --tail=5 "$service"
        fi
    done
else
    success "🎉 ALL CONTAINERS RUNNING ON NANO PI! 🎉"
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║            EXTREME MEMORY OPTIMIZATION SUCCESSFUL           ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    info "Service URLs:"
    echo "  🐍 Python App:    http://$(hostname -I | awk '{print $1}'):5000"
    echo "  🌐 Laravel App:   http://$(hostname -I | awk '{print $1}'):8000"
    echo "  ⚙️  Config Service: http://$(hostname -I | awk '{print $1}'):5002"
fi

success "🚀 EXTREME MEMORY OPTIMIZATION COMPLETE! 🚀"