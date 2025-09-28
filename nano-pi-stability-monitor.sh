#!/bin/bash
# NANO PI SYSTEM STABILITY MONITOR
# Prevents system halts, manages memory, monitors containers
# Auto-restarts failed services and maintains system health

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

LOG_FILE="/var/log/nano-pi-stability.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    echo -e "$1"
}

print_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           NANO PI SYSTEM STABILITY MONITOR                  ║"
    echo "║         Prevents Halts • Memory Management • Auto-Restart   ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root for full system monitoring"
    echo "Run: sudo bash $0"
    exit 1
fi

print_banner

# Memory management functions
optimize_memory() {
    log "${BLUE}[MEMORY]${NC} Optimizing system memory"

    # Clear caches
    sync
    echo 3 > /proc/sys/vm/drop_caches

    # Optimize swappiness for limited memory
    echo 10 > /proc/sys/vm/swappiness

    # Configure OOM killer to be more conservative
    echo 1 > /proc/sys/vm/overcommit_memory

    # Free up any zombie processes
    pkill -f "defunct" 2>/dev/null || true

    log "${GREEN}[MEMORY]${NC} Memory optimization completed"
}

# Check and ensure adequate swap space
setup_swap() {
    local swap_size="1G"
    local swap_file="/swapfile"

    if ! swapon --show | grep -q "$swap_file"; then
        log "${YELLOW}[SWAP]${NC} Setting up swap space for stability"

        # Remove any existing swap
        swapoff -a 2>/dev/null || true
        rm -f "$swap_file" 2>/dev/null || true

        # Create new swap file
        fallocate -l "$swap_size" "$swap_file" 2>/dev/null || dd if=/dev/zero of="$swap_file" bs=1M count=1024
        chmod 600 "$swap_file"
        mkswap "$swap_file"
        swapon "$swap_file"

        # Add to fstab for persistence
        if ! grep -q "$swap_file" /etc/fstab; then
            echo "$swap_file none swap sw 0 0" >> /etc/fstab
        fi

        log "${GREEN}[SWAP]${NC} Swap space configured: $swap_size"
    fi
}

# Monitor memory usage
check_memory() {
    local available_mem=$(free -m | awk 'NR==2{print $7}')
    local total_mem=$(free -m | awk 'NR==2{print $2}')
    local mem_threshold=50  # MB

    if [[ $available_mem -lt $mem_threshold ]]; then
        warn "LOW MEMORY: Only ${available_mem}MB available out of ${total_mem}MB"
        log "${RED}[MEMORY]${NC} LOW MEMORY WARNING: ${available_mem}MB available"

        # Free memory aggressively
        optimize_memory

        # Kill non-essential processes if still low
        available_mem=$(free -m | awk 'NR==2{print $7}')
        if [[ $available_mem -lt 30 ]]; then
            log "${RED}[MEMORY]${NC} CRITICAL MEMORY: Killing non-essential processes"
            pkill -f "chromium" 2>/dev/null || true
            pkill -f "firefox" 2>/dev/null || true
            pkill -f "telegram" 2>/dev/null || true
        fi

        return 1
    fi

    return 0
}

# Container health monitoring
check_container_health() {
    local container_name=$1
    local expected_status="running"

    if ! docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "^$container_name.*Up"; then
        warn "Container $container_name is not running"
        log "${RED}[DOCKER]${NC} Container $container_name is down - attempting restart"

        # Try to restart the container
        cd "$SCRIPT_DIR"
        docker-compose -f docker-compose.nanopi-fixed.yml up -d "$container_name" 2>/dev/null || {
            error "Failed to restart $container_name"
            log "${RED}[DOCKER]${NC} Failed to restart $container_name"
            return 1
        }

        sleep 10

        # Verify it's running
        if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "^$container_name.*Up"; then
            success "Successfully restarted $container_name"
            log "${GREEN}[DOCKER]${NC} Successfully restarted $container_name"
        else
            error "Container $container_name still not running after restart attempt"
            log "${RED}[DOCKER]${NC} $container_name restart failed"
            return 1
        fi
    fi

    return 0
}

# Service health checks
check_service_health() {
    local service_url=$1
    local service_name=$2

    if ! curl -f -s --max-time 5 "$service_url" > /dev/null; then
        warn "$service_name service is not responding at $service_url"
        log "${RED}[SERVICE]${NC} $service_name not responding at $service_url"
        return 1
    fi

    return 0
}

# Network connectivity check
check_network() {
    if ! ping -c 1 -W 5 8.8.8.8 > /dev/null 2>&1; then
        error "Network connectivity issue detected"
        log "${RED}[NETWORK]${NC} Internet connectivity failed"

        # Try to restart networking
        systemctl restart systemd-networkd 2>/dev/null || true
        systemctl restart networking 2>/dev/null || true

        sleep 5

        if ping -c 1 -W 5 8.8.8.8 > /dev/null 2>&1; then
            success "Network connectivity restored"
            log "${GREEN}[NETWORK]${NC} Network connectivity restored"
        else
            error "Network connectivity still failing"
            log "${RED}[NETWORK]${NC} Network restart failed"
            return 1
        fi
    fi

    return 0
}

# Docker daemon health check
check_docker_daemon() {
    if ! docker ps > /dev/null 2>&1; then
        warn "Docker daemon is not responding"
        log "${RED}[DOCKER]${NC} Docker daemon not responding - restarting"

        systemctl restart docker
        sleep 10

        if docker ps > /dev/null 2>&1; then
            success "Docker daemon restarted successfully"
            log "${GREEN}[DOCKER]${NC} Docker daemon restarted successfully"
        else
            error "Docker daemon restart failed"
            log "${RED}[DOCKER]${NC} Docker daemon restart failed"
            return 1
        fi
    fi

    return 0
}

# System temperature monitoring (if available)
check_temperature() {
    local temp_file="/sys/class/thermal/thermal_zone0/temp"
    if [[ -f "$temp_file" ]]; then
        local temp=$(cat "$temp_file")
        local temp_celsius=$((temp / 1000))

        if [[ $temp_celsius -gt 70 ]]; then
            warn "High system temperature detected: ${temp_celsius}°C"
            log "${YELLOW}[TEMP]${NC} High temperature: ${temp_celsius}°C"

            # Try to reduce load
            docker-compose -f "$SCRIPT_DIR/docker-compose.nanopi-fixed.yml" scale pythonapp=0 2>/dev/null || true
            sleep 30
            docker-compose -f "$SCRIPT_DIR/docker-compose.nanopi-fixed.yml" scale pythonapp=1 2>/dev/null || true
        fi
    fi
}

# Disk space monitoring
check_disk_space() {
    local disk_usage=$(df / | awk 'NR==2{print $5}' | sed 's/%//')

    if [[ $disk_usage -gt 85 ]]; then
        warn "High disk usage detected: ${disk_usage}%"
        log "${YELLOW}[DISK]${NC} High disk usage: ${disk_usage}%"

        # Clean up Docker
        docker system prune -f > /dev/null 2>&1
        docker volume prune -f > /dev/null 2>&1

        # Clean logs
        find /var/log -name "*.log" -size +100M -exec truncate -s 0 {} \;

        log "${GREEN}[DISK]${NC} Disk cleanup completed"
    fi
}

# Main monitoring loop
main_monitor() {
    log "${GREEN}[START]${NC} Starting Nano Pi stability monitoring"

    # Initial setup
    setup_swap
    optimize_memory

    # Get the current IP for health checks
    source "$SCRIPT_DIR/.env" 2>/dev/null || true
    local host_ip=${HOST_IP:-"192.168.33.145"}

    while true; do
        local issues=0

        # Memory check
        if ! check_memory; then
            ((issues++))
        fi

        # Network check
        if ! check_network; then
            ((issues++))
        fi

        # Docker daemon check
        if ! check_docker_daemon; then
            ((issues++))
        fi

        # Container health checks
        for container in config_service pythonapp laravelapp; do
            if ! check_container_health "$container"; then
                ((issues++))
            fi
        done

        # Service health checks
        if ! check_service_health "http://localhost:5002/health" "Config Service"; then
            ((issues++))
        fi

        if ! check_service_health "http://$host_ip:5000/health" "Bell App"; then
            ((issues++))
        fi

        if ! check_service_health "http://$host_ip:8000/health" "News App"; then
            ((issues++))
        fi

        # System health checks
        check_temperature
        check_disk_space

        # Log status
        if [[ $issues -eq 0 ]]; then
            log "${GREEN}[STATUS]${NC} All systems healthy"
        else
            log "${YELLOW}[STATUS]${NC} $issues issues detected and addressed"
        fi

        # Wait before next check
        sleep 60
    done
}

# Install as systemd service
install_service() {
    local service_file="/etc/systemd/system/nano-pi-stability.service"

    cat > "$service_file" << EOF
[Unit]
Description=Nano Pi Stability Monitor
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=$SCRIPT_DIR
ExecStart=$SCRIPT_DIR/nano-pi-stability-monitor.sh --daemon
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable nano-pi-stability.service
    success "Installed stability monitor as systemd service"
}

# Handle command line arguments
case "${1:-}" in
    --daemon)
        main_monitor
        ;;
    --install)
        install_service
        ;;
    --status)
        systemctl status nano-pi-stability.service 2>/dev/null || echo "Service not installed"
        ;;
    *)
        echo "Usage: $0 [--daemon|--install|--status]"
        echo "  --daemon   Run the monitoring loop"
        echo "  --install  Install as systemd service"
        echo "  --status   Check service status"
        exit 1
        ;;
esac