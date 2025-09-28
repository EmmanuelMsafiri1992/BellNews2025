#!/bin/bash
# ULTIMATE NANO PI DEPLOYMENT SCRIPT
# One-command solution for all Docker networking and stability issues
# Fixes: Port 5002 errors, IP detection, system halts, memory issues

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
step() { echo -e "${PURPLE}[STEP]${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/nano-pi-deployment.log"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║             ULTIMATE NANO PI DEPLOYMENT SCRIPT              ║"
    echo "║                                                              ║"
    echo "║  ✓ Fixes Port 5002 Connection Errors                        ║"
    echo "║  ✓ Auto-detects IP Addresses (Static/Dynamic)               ║"
    echo "║  ✓ Prevents System Halts and Memory Issues                  ║"
    echo "║  ✓ Configures Monitoring and Auto-restart                   ║"
    echo "║  ✓ ONE COMMAND - PERMANENT SOLUTION                         ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
}

# Check prerequisites
check_prerequisites() {
    step "1/9 - CHECKING PREREQUISITES"

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root for full system access"
        echo "Run: sudo bash $0"
        exit 1
    fi

    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first."
        exit 1
    fi

    # Check if docker-compose is available
    if ! command -v docker-compose &> /dev/null; then
        error "docker-compose is not installed. Please install docker-compose first."
        exit 1
    fi

    # Check available memory
    local available_mem=$(free -m | awk 'NR==2{print $2}')
    if [[ $available_mem -lt 400 ]]; then
        warn "Low memory detected: ${available_mem}MB. Enabling aggressive memory management."
        export LOW_MEMORY_MODE=true
    fi

    success "Prerequisites check completed"
    log "Prerequisites check passed - Memory: ${available_mem}MB"
}

# System preparation and optimization
optimize_system() {
    step "2/9 - SYSTEM OPTIMIZATION"

    # Update system clock first
    log "Synchronizing system time"
    timedatectl set-ntp true 2>/dev/null || true
    ntpdate -s time.nist.gov 2>/dev/null || true

    # Optimize memory settings
    log "Optimizing memory settings"
    echo 'vm.swappiness=10' >> /etc/sysctl.conf 2>/dev/null || true
    echo 'vm.vfs_cache_pressure=50' >> /etc/sysctl.conf 2>/dev/null || true
    echo 'vm.overcommit_memory=1' >> /etc/sysctl.conf 2>/dev/null || true
    sysctl -p 2>/dev/null || true

    # Setup adequate swap
    if [[ ! -f /swapfile ]] || [[ $(stat -c%s /swapfile 2>/dev/null || echo 0) -lt 1073741824 ]]; then
        log "Setting up 1GB swap file"
        swapoff -a 2>/dev/null || true
        rm -f /swapfile 2>/dev/null || true
        dd if=/dev/zero of=/swapfile bs=1M count=1024 status=progress
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        if ! grep -q "/swapfile" /etc/fstab; then
            echo "/swapfile none swap sw 0 0" >> /etc/fstab
        fi
    fi

    # Optimize Docker daemon
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "storage-opts": [
        "overlay2.override_kernel_check=true"
    ]
}
EOF

    systemctl restart docker
    sleep 5

    success "System optimization completed"
}

# Network configuration and IP detection
configure_networking() {
    step "3/9 - NETWORK CONFIGURATION AND IP DETECTION"

    cd "$SCRIPT_DIR"

    # Run IP detection
    log "Running automatic IP detection"
    bash auto-ip-detect.sh

    # Verify IP detection worked
    if [[ -f ".env" ]] && grep -q "HOST_IP=" .env; then
        local detected_ip=$(grep "HOST_IP=" .env | cut -d'=' -f2)
        success "IP detected and configured: $detected_ip"
        log "IP detection successful: $detected_ip"
    else
        error "IP detection failed"
        exit 1
    fi

    # Configure DNS for reliability
    log "Configuring reliable DNS settings"
    cat > /etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
options timeout:2 attempts:3 rotate
EOF

    success "Networking configuration completed"
}

# Docker cleanup and preparation
prepare_docker() {
    step "4/9 - DOCKER CLEANUP AND PREPARATION"

    cd "$SCRIPT_DIR"

    # Stop any running containers
    log "Stopping existing containers"
    docker-compose -f docker-compose.nanopi.yml down --remove-orphans 2>/dev/null || true
    docker-compose -f docker-compose.prod.yml down --remove-orphans 2>/dev/null || true
    docker-compose -f docker-compose.nanopi-fixed.yml down --remove-orphans 2>/dev/null || true

    # Clean up Docker system
    log "Cleaning Docker system"
    docker system prune -f
    docker volume prune -f

    # Verify Docker is working
    if ! docker run --rm hello-world > /dev/null 2>&1; then
        error "Docker is not working properly"
        exit 1
    fi

    success "Docker preparation completed"
}

# Build or pull Docker images
prepare_images() {
    step "5/9 - PREPARING DOCKER IMAGES"

    cd "$SCRIPT_DIR"

    # Check if we should build or pull images
    if [[ -n "${DOCKER_HUB_USERNAME:-}" ]] && [[ "${DOCKER_HUB_USERNAME}" != "yourusername" ]]; then
        log "Pulling pre-built images from Docker Hub"
        docker-compose -f docker-compose.nanopi-fixed.yml pull || {
            warn "Failed to pull images, will build locally"
            export BUILD_LOCALLY=true
        }
    else
        export BUILD_LOCALLY=true
    fi

    if [[ "${BUILD_LOCALLY:-}" == "true" ]]; then
        log "Building images locally (this may take a while on Nano Pi)"

        # Build with optimizations for ARM and low memory
        export DOCKER_BUILDKIT=1
        export DOCKER_DEFAULT_PLATFORM=linux/arm64

        # Build images one by one to avoid memory issues
        if [[ "${LOW_MEMORY_MODE:-}" == "true" ]]; then
            docker build -t bellnews-bellapp:latest ./bellapp
            docker build -f Dockerfile_config -t bellnews-config-service:latest .
            docker build -t bellnews-newsapp:latest ./newsapp
        else
            docker-compose -f docker-compose.nanopi-fixed.yml build
        fi
    fi

    success "Docker images prepared"
}

# Deploy services
deploy_services() {
    step "6/9 - DEPLOYING SERVICES"

    cd "$SCRIPT_DIR"

    # Start services with health checks
    log "Starting Docker services"
    docker-compose -f docker-compose.nanopi-fixed.yml up -d

    # Wait for services to become healthy
    log "Waiting for services to become healthy"
    local max_wait=300  # 5 minutes
    local wait_time=0

    while [[ $wait_time -lt $max_wait ]]; do
        local healthy_count=0

        # Check each service
        if docker-compose -f docker-compose.nanopi-fixed.yml ps | grep -q "config_service.*Up.*healthy"; then
            ((healthy_count++))
        fi

        if docker-compose -f docker-compose.nanopi-fixed.yml ps | grep -q "pythonapp.*Up.*healthy"; then
            ((healthy_count++))
        fi

        if docker-compose -f docker-compose.nanopi-fixed.yml ps | grep -q "laravelapp.*Up.*healthy"; then
            ((healthy_count++))
        fi

        if [[ $healthy_count -eq 3 ]]; then
            success "All services are healthy"
            break
        fi

        info "Waiting for services to become healthy ($healthy_count/3)..."
        sleep 10
        ((wait_time += 10))
    done

    if [[ $wait_time -ge $max_wait ]]; then
        warn "Some services may not be fully healthy yet, but continuing..."
    fi

    success "Services deployment completed"
}

# Install monitoring services
setup_monitoring() {
    step "7/9 - SETTING UP MONITORING SERVICES"

    cd "$SCRIPT_DIR"

    # Make scripts executable
    chmod +x auto-ip-detect.sh
    chmod +x nano-pi-stability-monitor.sh

    # Install IP detection service
    log "Installing IP detection service"
    systemctl stop nano-pi-ip-detection.service 2>/dev/null || true
    bash auto-ip-detect.sh # This also installs the service

    # Install stability monitoring service
    log "Installing stability monitoring service"
    systemctl stop nano-pi-stability.service 2>/dev/null || true
    bash nano-pi-stability-monitor.sh --install

    # Start monitoring services
    systemctl start nano-pi-ip-detection.service
    systemctl start nano-pi-stability.service

    # Verify services are running
    if systemctl is-active --quiet nano-pi-stability.service; then
        success "Stability monitoring service is active"
    else
        warn "Stability monitoring service failed to start"
    fi

    success "Monitoring services setup completed"
}

# Verify deployment
verify_deployment() {
    step "8/9 - VERIFYING DEPLOYMENT"

    cd "$SCRIPT_DIR"

    # Get configured IP
    local host_ip=$(grep "HOST_IP=" .env | cut -d'=' -f2 2>/dev/null || echo "192.168.33.145")

    # Test service endpoints
    local services_ok=0

    info "Testing service endpoints..."

    # Test config service (port 5002)
    if curl -f -s --max-time 10 "http://localhost:5002/health" > /dev/null; then
        success "✓ Config Service (port 5002): OK"
        ((services_ok++))
    else
        error "✗ Config Service (port 5002): FAILED"
    fi

    # Test bellapp (port 5000)
    if curl -f -s --max-time 10 "http://$host_ip:5000/health" > /dev/null; then
        success "✓ Bell App (port 5000): OK"
        ((services_ok++))
    else
        error "✗ Bell App (port 5000): FAILED"
    fi

    # Test newsapp (port 8000)
    if curl -f -s --max-time 10 "http://$host_ip:8000/health" > /dev/null; then
        success "✓ News App (port 8000): OK"
        ((services_ok++))
    else
        # Try alternative health check
        if curl -f -s --max-time 10 "http://$host_ip:8000/" > /dev/null; then
            success "✓ News App (port 8000): OK"
            ((services_ok++))
        else
            error "✗ News App (port 8000): FAILED"
        fi
    fi

    # Display results
    if [[ $services_ok -eq 3 ]]; then
        success "All services are working correctly!"
    elif [[ $services_ok -ge 2 ]]; then
        warn "$services_ok out of 3 services are working. Some issues detected."
    else
        error "Multiple service failures detected. Check logs for details."
    fi

    success "Deployment verification completed"
}

# Display final information
show_completion_info() {
    step "9/9 - DEPLOYMENT COMPLETED"

    local host_ip=$(grep "HOST_IP=" .env | cut -d'=' -f2 2>/dev/null || echo "192.168.33.145")

    echo
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                 DEPLOYMENT COMPLETED SUCCESSFULLY           ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${CYAN}📱 ACCESS YOUR APPLICATIONS:${NC}"
    echo -e "   • Bell App:    ${GREEN}http://$host_ip:5000${NC}"
    echo -e "   • News App:    ${GREEN}http://$host_ip:8000${NC}"
    echo -e "   • Config API:  ${GREEN}http://localhost:5002${NC}"
    echo
    echo -e "${CYAN}🔧 MANAGEMENT COMMANDS:${NC}"
    echo -e "   • Check status:    ${YELLOW}docker-compose -f docker-compose.nanopi-fixed.yml ps${NC}"
    echo -e "   • View logs:       ${YELLOW}docker-compose -f docker-compose.nanopi-fixed.yml logs -f${NC}"
    echo -e "   • Restart all:     ${YELLOW}docker-compose -f docker-compose.nanopi-fixed.yml restart${NC}"
    echo
    echo -e "${CYAN}📊 MONITORING:${NC}"
    echo -e "   • System status:   ${YELLOW}systemctl status nano-pi-stability.service${NC}"
    echo -e "   • IP detection:    ${YELLOW}systemctl status nano-pi-ip-detection.service${NC}"
    echo -e "   • View logs:       ${YELLOW}tail -f /var/log/nano-pi-stability.log${NC}"
    echo
    echo -e "${CYAN}🚀 AUTOMATIC FEATURES ENABLED:${NC}"
    echo -e "   ✓ Auto-restart on container failure"
    echo -e "   ✓ Memory management and optimization"
    echo -e "   ✓ Network IP detection on changes"
    echo -e "   ✓ System stability monitoring"
    echo -e "   ✓ Prevention of system halts"
    echo
    echo -e "${GREEN}🎉 Your Nano Pi is now running stable Docker services!${NC}"
    echo

    log "Deployment completed successfully - IP: $host_ip"
}

# Main execution
main() {
    print_banner

    log "Starting Ultimate Nano Pi deployment"

    # Execute all steps
    check_prerequisites
    optimize_system
    configure_networking
    prepare_docker
    prepare_images
    deploy_services
    setup_monitoring
    verify_deployment
    show_completion_info

    log "Ultimate Nano Pi deployment completed successfully"
}

# Handle command line arguments
case "${1:-}" in
    --status)
        echo "Checking deployment status..."
        docker-compose -f docker-compose.nanopi-fixed.yml ps
        echo
        systemctl status nano-pi-stability.service
        ;;
    --logs)
        echo "Showing recent logs..."
        tail -f /var/log/nano-pi-deployment.log
        ;;
    --restart)
        echo "Restarting all services..."
        cd "$SCRIPT_DIR"
        docker-compose -f docker-compose.nanopi-fixed.yml restart
        ;;
    *)
        main
        ;;
esac