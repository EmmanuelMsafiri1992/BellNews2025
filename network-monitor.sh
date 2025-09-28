#!/bin/bash
# Network Monitor & Auto-Recovery System for FBellNewsV3
# Monitors network changes and automatically recovers services without reboot

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/fbellnews-network-monitor.log"
PID_FILE="/var/run/fbellnews-network-monitor.pid"
STATE_FILE="/tmp/fbellnews-network-state"
MONITOR_INTERVAL=10  # Check every 10 seconds
RECOVERY_COOLDOWN=60 # Wait 60 seconds between recovery attempts

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Logging functions
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "UNKNOWN")
    echo -e "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
}

info() { 
    echo -e "${BLUE}[INFO]${NC} $*"
    log "INFO" "$*"
}

success() { 
    echo -e "${GREEN}[SUCCESS]${NC} $*"
    log "SUCCESS" "$*"
}

warn() { 
    echo -e "${YELLOW}[WARN]${NC} $*"
    log "WARN" "$*"
}

error() { 
    echo -e "${RED}[ERROR]${NC} $*"
    log "ERROR" "$*"
}

debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $*"
        log "DEBUG" "$*"
    fi
}

print_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                Network Monitor & Auto-Recovery              ║"
    echo "║              FBellNewsV3 Network Guardian                   ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

cleanup() {
    info "Cleaning up network monitor..."
    rm -f "$PID_FILE"
    exit 0
}

# Set up signal handlers
trap cleanup INT TERM EXIT

check_if_running() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "Network monitor already running (PID: $pid)"
            exit 0
        else
            rm -f "$PID_FILE"
        fi
    fi
}

get_network_info() {
    local info_json=""
    
    # Get primary network interface
    local primary_iface=$(ip route | grep '^default' | head -1 | awk '{print $5}' 2>/dev/null || echo "")
    
    if [ -z "$primary_iface" ]; then
        primary_iface=$(ip link show | grep -E '^[0-9]+:' | grep -v lo | head -1 | awk -F': ' '{print $2}' 2>/dev/null || echo "eth0")
    fi
    
    # Get IP address
    local ip_address=$(ip addr show "$primary_iface" 2>/dev/null | grep 'inet ' | head -1 | awk '{print $2}' | cut -d'/' -f1 || echo "")
    
    # Get gateway
    local gateway=$(ip route | grep '^default' | head -1 | awk '{print $3}' 2>/dev/null || echo "")
    
    # Get netmask (convert CIDR to netmask)
    local cidr=$(ip addr show "$primary_iface" 2>/dev/null | grep 'inet ' | head -1 | awk '{print $2}' | cut -d'/' -f2 || echo "24")
    local netmask=$(python3 -c "
import ipaddress
try:
    net = ipaddress.IPv4Network('0.0.0.0/$cidr', strict=False)
    print(str(net.netmask))
except:
    print('255.255.255.0')
" 2>/dev/null || echo "255.255.255.0")
    
    # Get DNS servers
    local dns_servers=$(grep '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\n' ',' | sed 's/,$//' || echo "8.8.8.8,8.8.4.4")
    
    # Determine if DHCP or static
    local config_type="unknown"
    if systemctl is-active dhcpcd >/dev/null 2>&1; then
        config_type="dhcp"
    elif grep -q "iface.*dhcp" /etc/network/interfaces 2>/dev/null; then
        config_type="dhcp"
    elif [ -n "$ip_address" ]; then
        config_type="static"
    fi
    
    # Get connectivity status
    local internet_ok="false"
    if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        internet_ok="true"
    fi
    
    # Create JSON-like string
    info_json=$(cat << EOF
{
    "interface": "$primary_iface",
    "ip_address": "$ip_address",
    "gateway": "$gateway",
    "netmask": "$netmask",
    "cidr": "$cidr",
    "dns_servers": "$dns_servers",
    "config_type": "$config_type",
    "internet_ok": "$internet_ok",
    "timestamp": "$(date '+%s')"
}
EOF
)
    
    echo "$info_json"
}

get_docker_status() {
    local docker_running="false"
    local containers_healthy="false"
    local compose_file="$SCRIPT_DIR/docker-compose.dev.yml"
    
    if systemctl is-active docker >/dev/null 2>&1; then
        docker_running="true"
        
        # Check if our containers are running
        local running_containers=0
        if [ -f "$compose_file" ]; then
            cd "$SCRIPT_DIR"
            local expected_containers=$(docker-compose -f docker-compose.dev.yml config --services 2>/dev/null | wc -l || echo "0")
            running_containers=$(docker-compose -f docker-compose.dev.yml ps -q 2>/dev/null | wc -l || echo "0")
            
            if [ "$running_containers" -gt 0 ] && [ "$running_containers" -ge "$expected_containers" ]; then
                containers_healthy="true"
            fi
        fi
    fi
    
    echo "{\"docker_running\": \"$docker_running\", \"containers_healthy\": \"$containers_healthy\", \"running_containers\": \"$running_containers\"}"
}

load_previous_state() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo "{}"
    fi
}

save_current_state() {
    local network_info="$1"
    local docker_status="$2"
    
    cat > "$STATE_FILE" << EOF
{
    "network": $network_info,
    "docker": $docker_status,
    "last_update": "$(date '+%s')"
}
EOF
}

has_network_changed() {
    local current_network="$1"
    local previous_state="$2"
    
    # Extract current values
    local current_ip=$(echo "$current_network" | grep -o '"ip_address": "[^"]*"' | cut -d'"' -f4)
    local current_gateway=$(echo "$current_network" | grep -o '"gateway": "[^"]*"' | cut -d'"' -f4)
    local current_config=$(echo "$current_network" | grep -o '"config_type": "[^"]*"' | cut -d'"' -f4)
    
    # Extract previous values
    local prev_ip=$(echo "$previous_state" | grep -o '"ip_address": "[^"]*"' | cut -d'"' -f4)
    local prev_gateway=$(echo "$previous_state" | grep -o '"gateway": "[^"]*"' | cut -d'"' -f4)
    local prev_config=$(echo "$previous_state" | grep -o '"config_type": "[^"]*"' | cut -d'"' -f4)
    
    debug "Current: IP=$current_ip, GW=$current_gateway, Type=$current_config"
    debug "Previous: IP=$prev_ip, GW=$prev_gateway, Type=$prev_config"
    
    # Check for changes
    if [ "$current_ip" != "$prev_ip" ] || [ "$current_gateway" != "$prev_gateway" ] || [ "$current_config" != "$prev_config" ]; then
        return 0  # Changed
    fi
    
    return 1  # No change
}

fix_network_configuration() {
    info "Fixing network configuration after change detected..."
    
    # Restart networking services
    systemctl restart systemd-networkd 2>/dev/null || true
    systemctl restart NetworkManager 2>/dev/null || true
    systemctl restart networking 2>/dev/null || true
    
    # Wait for network to stabilize
    sleep 5
    
    # Fix DNS resolution
    if [ ! -f "/etc/resolv.conf" ] || [ ! -s "/etc/resolv.conf" ]; then
        warn "DNS configuration missing, recreating..."
        cat > /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF
    fi
    
    # Restart systemd-resolved if available
    systemctl restart systemd-resolved 2>/dev/null || true
    
    success "Network configuration fix completed"
}

fix_time_after_network_change() {
    info "Fixing time synchronization after network change..."
    
    # Run our comprehensive time fix
    if [ -f "$SCRIPT_DIR/auto-time-fix.sh" ]; then
        bash "$SCRIPT_DIR/auto-time-fix.sh" || warn "Time fix completed with warnings"
    else
        # Fallback time fix
        warn "auto-time-fix.sh not found, using fallback method"
        systemctl stop ntp systemd-timesyncd 2>/dev/null || true
        ntpdate -s 216.239.35.0 2>/dev/null || ntpdate -s pool.ntp.org 2>/dev/null || true
        hwclock --systohc 2>/dev/null || true
        systemctl start systemd-timesyncd 2>/dev/null || true
    fi
    
    success "Time synchronization fix completed"
}

update_application_config() {
    local current_ip="$1"
    
    info "Updating application configuration for new IP: $current_ip"
    
    cd "$SCRIPT_DIR"
    
    # Update Laravel .env file
    if [ -f "newsapp/.env" ]; then
        cp "newsapp/.env" "newsapp/.env.backup.$(date +%s)" 2>/dev/null || true
        
        sed -i "s|APP_URL=.*|APP_URL=http://$current_ip:8000|g" newsapp/.env
        sed -i "s|VITE_API_BASE_URL=.*|VITE_API_BASE_URL=http://$current_ip:8000|g" newsapp/.env
        
        success "Updated Laravel configuration"
    fi
    
    # Update any other configuration files that might contain IP addresses
    for config_file in $(find . -name "*.json" -o -name "*.conf" -o -name "*.cfg" 2>/dev/null | grep -E "(config|settings)" | head -5); do
        if [ -f "$config_file" ] && grep -q "192\.168\." "$config_file" 2>/dev/null; then
            debug "Checking $config_file for IP updates..."
            # This is a simple approach - in production you might want more sophisticated config management
        fi
    done
    
    success "Application configuration update completed"
}

recover_docker_services() {
    local current_ip="$1"
    
    info "Recovering Docker services after network change..."
    
    cd "$SCRIPT_DIR"
    
    # Check if Docker is running
    if ! systemctl is-active docker >/dev/null 2>&1; then
        info "Starting Docker service..."
        systemctl start docker
        sleep 5
    fi
    
    # Stop existing containers gracefully
    if docker ps -q | grep -q .; then
        info "Stopping existing containers..."
        docker-compose -f docker-compose.dev.yml down --remove-orphans 2>/dev/null || true
        sleep 3
    fi
    
    # Clean up Docker networks to force recreation
    info "Cleaning up Docker networks..."
    docker network prune -f 2>/dev/null || true
    
    # Update application configuration before restarting
    update_application_config "$current_ip"
    
    # Restart services with fresh network configuration
    info "Restarting Docker services with new network configuration..."
    
    # Use docker-compose or docker compose based on availability
    local compose_cmd="docker-compose"
    if ! command -v docker-compose >/dev/null 2>&1; then
        compose_cmd="docker compose"
    fi
    
    # Start services
    if $compose_cmd -f docker-compose.dev.yml up -d --force-recreate; then
        success "Docker services restarted successfully"
        
        # Wait for services to be healthy
        sleep 10
        info "Checking service health..."
        $compose_cmd -f docker-compose.dev.yml ps
        
        return 0
    else
        error "Failed to restart Docker services"
        return 1
    fi
}

perform_full_recovery() {
    local current_network="$1"
    local current_ip=$(echo "$current_network" | grep -o '"ip_address": "[^"]*"' | cut -d'"' -f4)
    
    info "Performing full system recovery for network change..."
    
    # Step 1: Fix network configuration
    fix_network_configuration
    
    # Step 2: Fix time synchronization
    fix_time_after_network_change
    
    # Step 3: Recover Docker services
    if recover_docker_services "$current_ip"; then
        success "Full recovery completed successfully"
        
        # Show new status
        info "New network configuration:"
        info "  IP Address: $current_ip"
        info "  Application URLs:"
        info "    News App:      http://$current_ip:8000"
        info "    Python API:    http://$current_ip:5000"
        info "    Config Service: http://$current_ip:5002"
        info "    Vite Dev:      http://$current_ip:5173"
        
        return 0
    else
        error "Recovery failed, may require manual intervention"
        return 1
    fi
}

monitor_loop() {
    info "Starting network monitoring loop (interval: ${MONITOR_INTERVAL}s)"
    
    local last_recovery=0
    
    while true; do
        debug "Checking network status..."
        
        # Get current network and Docker status
        local current_network=$(get_network_info)
        local current_docker=$(get_docker_status)
        local current_time=$(date '+%s')
        
        # Load previous state
        local previous_state=$(load_previous_state)
        local previous_network=$(echo "$previous_state" | jq -r '.network // {}' 2>/dev/null || echo "{}")
        
        # Check for network changes
        if has_network_changed "$current_network" "$previous_network"; then
            local current_ip=$(echo "$current_network" | grep -o '"ip_address": "[^"]*"' | cut -d'"' -f4)
            warn "Network change detected! New IP: $current_ip"
            
            # Check recovery cooldown
            if [ $((current_time - last_recovery)) -gt $RECOVERY_COOLDOWN ]; then
                if perform_full_recovery "$current_network"; then
                    success "Recovery completed successfully"
                    last_recovery=$current_time
                else
                    error "Recovery failed"
                    last_recovery=$current_time  # Still set cooldown to avoid spam
                fi
            else
                warn "Recovery in cooldown period, skipping..."
            fi
        fi
        
        # Check if Docker containers are healthy
        local containers_healthy=$(echo "$current_docker" | grep -o '"containers_healthy": "[^"]*"' | cut -d'"' -f4)
        local internet_ok=$(echo "$current_network" | grep -o '"internet_ok": "[^"]*"' | cut -d'"' -f4)
        
        if [ "$containers_healthy" = "false" ] && [ "$internet_ok" = "true" ]; then
            warn "Docker containers unhealthy but internet is available"
            if [ $((current_time - last_recovery)) -gt $RECOVERY_COOLDOWN ]; then
                info "Attempting Docker service recovery..."
                local current_ip=$(echo "$current_network" | grep -o '"ip_address": "[^"]*"' | cut -d'"' -f4)
                if recover_docker_services "$current_ip"; then
                    success "Docker service recovery completed"
                    last_recovery=$current_time
                fi
            fi
        fi
        
        # Save current state
        save_current_state "$current_network" "$current_docker"
        
        # Sleep until next check
        sleep $MONITOR_INTERVAL
    done
}

start_daemon() {
    echo $$ > "$PID_FILE"
    
    info "Network monitor started as daemon (PID: $$)"
    info "Log file: $LOG_FILE"
    info "State file: $STATE_FILE"
    
    monitor_loop
}

show_status() {
    echo "Network Monitor Status:"
    echo "======================="
    
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Status: RUNNING (PID: $pid)"
        else
            echo "Status: STOPPED (stale PID file)"
        fi
    else
        echo "Status: STOPPED"
    fi
    
    echo ""
    echo "Current Network Info:"
    get_network_info | jq . 2>/dev/null || get_network_info
    
    echo ""
    echo "Docker Status:"
    get_docker_status | jq . 2>/dev/null || get_docker_status
    
    if [ -f "$LOG_FILE" ]; then
        echo ""
        echo "Recent Log Entries:"
        tail -10 "$LOG_FILE"
    fi
}

stop_daemon() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            info "Stopping network monitor (PID: $pid)..."
            kill "$pid"
            sleep 2
            if kill -0 "$pid" 2>/dev/null; then
                warn "Process still running, force killing..."
                kill -9 "$pid"
            fi
            rm -f "$PID_FILE"
            success "Network monitor stopped"
        else
            warn "Process not running, removing stale PID file"
            rm -f "$PID_FILE"
        fi
    else
        info "Network monitor is not running"
    fi
}

show_help() {
    echo "FBellNewsV3 Network Monitor & Auto-Recovery"
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  start         Start network monitoring daemon"
    echo "  stop          Stop network monitoring daemon"
    echo "  restart       Restart network monitoring daemon"
    echo "  status        Show current status"
    echo "  test-recovery Manually test recovery process"
    echo "  help          Show this help"
    echo ""
    echo "Environment Variables:"
    echo "  DEBUG=1       Enable debug output"
    echo ""
    echo "The monitor automatically detects and recovers from:"
    echo "  • IP address changes (DHCP ↔ Static)"
    echo "  • Network configuration changes"
    echo "  • Time synchronization issues"
    echo "  • Docker service failures"
    echo "  • DNS resolution problems"
}

main() {
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    
    case "${1:-help}" in
        "start")
            print_banner
            check_if_running
            start_daemon
            ;;
        "stop")
            stop_daemon
            ;;
        "restart")
            stop_daemon
            sleep 2
            check_if_running
            start_daemon
            ;;
        "status")
            show_status
            ;;
        "test-recovery")
            print_banner
            info "Testing recovery process..."
            local current_network=$(get_network_info)
            perform_full_recovery "$current_network"
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi