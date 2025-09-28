#!/bin/bash
# FBellNews Fast Build Script for Nano Pi
# Automatically fixes DNS/network issues and runs Docker Compose
# Usage: sudo ./build-nano-pi-fast.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.prod.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

print_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                  FBellNews Fast Build                       ║"
    echo "║              Auto DNS Fix + Docker Build                    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_requirements() {
    info "Checking system requirements..."

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root to fix DNS issues"
        echo "Please run: sudo $0"
        exit 1
    fi

    # Check if Docker is installed
    if ! command -v docker >/dev/null 2>&1; then
        error "Docker is not installed"
        exit 1
    fi

    # Check if Docker Compose is available
    if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
        error "Docker Compose is not available"
        exit 1
    fi

    # Check if compose file exists
    if [ ! -f "$COMPOSE_FILE" ]; then
        error "Docker Compose file not found: $COMPOSE_FILE"
        exit 1
    fi

    success "System requirements check passed"
}

fix_dns_fast() {
    info "Applying fast DNS fixes..."

    # Backup current DNS config
    [ -f /etc/resolv.conf ] && cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%s) 2>/dev/null || true

    # Set reliable DNS servers immediately
    cat > /etc/resolv.conf << 'EOF'
# FBellNews Auto DNS Configuration
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
nameserver 1.0.0.1
options timeout:2
options attempts:3
options rotate
EOF

    # Configure Docker daemon DNS
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << 'EOF'
{
  "dns": ["8.8.8.8", "8.8.4.4", "1.1.1.1"],
  "dns-opts": ["timeout:2", "attempts:3"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

    # Restart Docker daemon
    info "Restarting Docker with new DNS configuration..."
    systemctl restart docker
    sleep 3

    # Test DNS resolution
    info "Testing DNS resolution..."
    if timeout 5 nslookup registry-1.docker.io >/dev/null 2>&1; then
        success "DNS resolution working - Docker registry accessible"
    else
        warn "DNS still having issues, but proceeding with build..."
    fi
}

stop_existing_containers() {
    info "Stopping existing containers..."

    # Stop all running containers for this project
    docker-compose -f "$COMPOSE_FILE" down --remove-orphans 2>/dev/null || true

    # Clean up any dangling containers
    docker container prune -f >/dev/null 2>&1 || true

    success "Existing containers stopped"
}

build_and_start() {
    info "Building and starting FBellNews containers (ARM64 optimized)..."

    # Use docker-compose or docker compose based on availability
    local compose_cmd
    if command -v docker-compose >/dev/null 2>&1; then
        compose_cmd="docker-compose"
    else
        compose_cmd="docker compose"
    fi

    info "Using compose command: $compose_cmd"

    # Check if we're on ARM64 and create ARM64-specific Dockerfile link
    local arch=$(uname -m)
    if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
        info "Detected ARM64 architecture, using optimized Dockerfile"
        if [ -f "newsapp/Dockerfile.arm64" ]; then
            cp newsapp/Dockerfile.arm64 newsapp/Dockerfile.backup
            info "Using ARM64-optimized Laravel Dockerfile"
        fi
    fi

    # Build and start services
    info "Running: $compose_cmd -f $COMPOSE_FILE up --build -d"

    if $compose_cmd -f "$COMPOSE_FILE" up --build -d; then
        success "Docker Compose build and start completed successfully"
    else
        error "Docker Compose build failed"
        # Restore original Dockerfile if backup exists
        if [ -f "newsapp/Dockerfile.backup" ]; then
            mv newsapp/Dockerfile.backup newsapp/Dockerfile.arm64
        fi
        return 1
    fi

    # Wait a moment for containers to stabilize
    sleep 5

    # Check container status
    info "Checking container status..."
    $compose_cmd -f "$COMPOSE_FILE" ps

    # Show logs for any failed containers
    local failed_containers=$($compose_cmd -f "$COMPOSE_FILE" ps --filter "status=exited" --format "table {{.Service}}" | tail -n +2)
    if [ -n "$failed_containers" ]; then
        warn "Some containers failed to start:"
        echo "$failed_containers"

        info "Showing logs for failed containers..."
        while read -r service; do
            if [ -n "$service" ]; then
                echo -e "\n${YELLOW}=== Logs for $service ===${NC}"
                $compose_cmd -f "$COMPOSE_FILE" logs --tail=20 "$service"
            fi
        done <<< "$failed_containers"
    else
        success "All containers are running successfully"
    fi
}

show_service_urls() {
    info "Service URLs:"
    echo "  • Python App (bellapp):    http://localhost:5000"
    echo "  • Laravel App (newsapp):   http://localhost:8000"
    echo "  • Vite Dev Server:         http://localhost:5173"
    echo "  • Config Service:          http://localhost:5002"
    echo ""
    info "To view logs: docker-compose -f docker-compose.prod.yml logs -f [service-name]"
    info "To stop all: docker-compose -f docker-compose.prod.yml down"
}

main() {
    print_banner

    info "Starting FBellNews Fast Build process..."
    info "Working directory: $SCRIPT_DIR"

    # Run all checks and fixes
    check_requirements
    fix_dns_fast
    stop_existing_containers

    if build_and_start; then
        echo ""
        success "🎉 FBellNews deployment completed successfully!"
        show_service_urls
    else
        error "❌ Deployment failed"
        exit 1
    fi
}

# Handle script arguments
case "${1:-}" in
    "stop")
        info "Stopping FBellNews services..."
        docker-compose -f "$COMPOSE_FILE" down --remove-orphans
        success "All services stopped"
        ;;
    "logs")
        if [ -n "${2:-}" ]; then
            docker-compose -f "$COMPOSE_FILE" logs -f "$2"
        else
            docker-compose -f "$COMPOSE_FILE" logs -f
        fi
        ;;
    "status")
        docker-compose -f "$COMPOSE_FILE" ps
        ;;
    "restart")
        info "Restarting FBellNews services..."
        docker-compose -f "$COMPOSE_FILE" restart
        success "Services restarted"
        ;;
    *)
        main "$@"
        ;;
esac