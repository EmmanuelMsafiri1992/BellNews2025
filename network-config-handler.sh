#!/bin/bash
# Network Configuration Handler for FBellNewsV3
# Handles dynamic ↔ static IP changes automatically without reboot

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/fbellnews-network-config.log"
BACKUP_DIR="/var/backups/fbellnews-network"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

get_primary_interface() {
    # Find the primary network interface
    local iface
    
    # Method 1: From default route
    iface=$(ip route | grep '^default' | head -1 | awk '{print $5}' 2>/dev/null || echo "")
    
    # Method 2: First non-loopback interface
    if [ -z "$iface" ]; then
        iface=$(ip link show | grep -E '^[0-9]+:' | grep -v lo | head -1 | awk -F': ' '{print $2}' 2>/dev/null || echo "")
    fi
    
    # Method 3: Common interface names
    if [ -z "$iface" ]; then
        for candidate in eth0 enp0s3 ens33 wlan0; do
            if ip link show "$candidate" >/dev/null 2>&1; then
                iface="$candidate"
                break
            fi
        done
    fi
    
    # Fallback
    if [ -z "$iface" ]; then
        iface="eth0"
    fi
    
    echo "$iface"
}

backup_network_config() {
    info "Backing up current network configuration..."
    
    mkdir -p "$BACKUP_DIR"
    local backup_time=$(date '+%Y%m%d_%H%M%S')
    local backup_path="$BACKUP_DIR/backup_$backup_time"
    
    mkdir -p "$backup_path"
    
    # Backup various network configuration files
    for config_file in \
        "/etc/network/interfaces" \
        "/etc/dhcpcd.conf" \
        "/etc/netplan/01-netcfg.yaml" \
        "/etc/netplan/50-cloud-init.yaml" \
        "/etc/systemd/network/10-eth0.network" \
        "/etc/NetworkManager/system-connections"/* \
        "/etc/resolv.conf"; do
        
        if [ -f "$config_file" ] || [ -d "$config_file" ]; then
            cp -r "$config_file" "$backup_path/" 2>/dev/null || true
        fi
    done
    
    # Save current network state
    ip addr show > "$backup_path/ip_addr.txt" 2>/dev/null || true
    ip route show > "$backup_path/ip_route.txt" 2>/dev/null || true
    
    success "Network configuration backed up to: $backup_path"
    echo "$backup_path"
}

detect_network_manager() {
    # Detect which network management system is in use
    local manager="unknown"
    
    if systemctl is-active NetworkManager >/dev/null 2>&1; then
        manager="NetworkManager"
    elif systemctl is-active systemd-networkd >/dev/null 2>&1; then
        manager="systemd-networkd"
    elif [ -f "/etc/netplan"/*.yaml ] 2>/dev/null; then
        manager="netplan"
    elif systemctl is-active dhcpcd >/dev/null 2>&1; then
        manager="dhcpcd"
    elif [ -f "/etc/network/interfaces" ] && grep -q "auto\|iface" /etc/network/interfaces; then
        manager="interfaces"
    fi
    
    echo "$manager"
}

configure_static_ip() {
    local interface="$1"
    local ip="$2"
    local netmask="$3"
    local gateway="$4"
    local dns1="${5:-8.8.8.8}"
    local dns2="${6:-8.8.4.4}"
    
    info "Configuring static IP: $ip/$netmask on $interface"
    
    local manager=$(detect_network_manager)
    local backup_path=$(backup_network_config)
    
    case "$manager" in
        "NetworkManager")
            configure_static_networkmanager "$interface" "$ip" "$netmask" "$gateway" "$dns1" "$dns2"
            ;;
        "systemd-networkd")
            configure_static_systemd_networkd "$interface" "$ip" "$netmask" "$gateway" "$dns1" "$dns2"
            ;;
        "netplan")
            configure_static_netplan "$interface" "$ip" "$netmask" "$gateway" "$dns1" "$dns2"
            ;;
        "dhcpcd")
            configure_static_dhcpcd "$interface" "$ip" "$netmask" "$gateway" "$dns1" "$dns2"
            ;;
        "interfaces")
            configure_static_interfaces "$interface" "$ip" "$netmask" "$gateway" "$dns1" "$dns2"
            ;;
        *)
            error "Unknown network manager: $manager"
            return 1
            ;;
    esac
    
    # Apply configuration and restart services
    apply_network_changes "$manager"
}

configure_dhcp() {
    local interface="$1"
    
    info "Configuring DHCP on $interface"
    
    local manager=$(detect_network_manager)
    local backup_path=$(backup_network_config)
    
    case "$manager" in
        "NetworkManager")
            configure_dhcp_networkmanager "$interface"
            ;;
        "systemd-networkd")
            configure_dhcp_systemd_networkd "$interface"
            ;;
        "netplan")
            configure_dhcp_netplan "$interface"
            ;;
        "dhcpcd")
            configure_dhcp_dhcpcd "$interface"
            ;;
        "interfaces")
            configure_dhcp_interfaces "$interface"
            ;;
        *)
            error "Unknown network manager: $manager"
            return 1
            ;;
    esac
    
    # Apply configuration and restart services
    apply_network_changes "$manager"
}

# NetworkManager configurations
configure_static_networkmanager() {
    local interface="$1" ip="$2" netmask="$3" gateway="$4" dns1="$5" dns2="$6"
    
    # Convert netmask to CIDR if needed
    local cidr=$(netmask_to_cidr "$netmask")
    
    # Remove existing connection
    nmcli connection delete "$interface" 2>/dev/null || true
    
    # Create new static connection
    nmcli connection add \
        type ethernet \
        con-name "$interface" \
        ifname "$interface" \
        ip4 "$ip/$cidr" \
        gw4 "$gateway" \
        ipv4.dns "$dns1,$dns2" \
        ipv4.method manual
    
    info "NetworkManager static configuration created"
}

configure_dhcp_networkmanager() {
    local interface="$1"
    
    # Remove existing connection
    nmcli connection delete "$interface" 2>/dev/null || true
    
    # Create new DHCP connection
    nmcli connection add \
        type ethernet \
        con-name "$interface" \
        ifname "$interface" \
        ipv4.method auto
    
    info "NetworkManager DHCP configuration created"
}

# systemd-networkd configurations
configure_static_systemd_networkd() {
    local interface="$1" ip="$2" netmask="$3" gateway="$4" dns1="$5" dns2="$6"
    
    local cidr=$(netmask_to_cidr "$netmask")
    
    cat > "/etc/systemd/network/10-$interface.network" << EOF
[Match]
Name=$interface

[Network]
Address=$ip/$cidr
Gateway=$gateway
DNS=$dns1
DNS=$dns2
EOF
    
    info "systemd-networkd static configuration created"
}

configure_dhcp_systemd_networkd() {
    local interface="$1"
    
    cat > "/etc/systemd/network/10-$interface.network" << EOF
[Match]
Name=$interface

[Network]
DHCP=yes
EOF
    
    info "systemd-networkd DHCP configuration created"
}

# Netplan configurations
configure_static_netplan() {
    local interface="$1" ip="$2" netmask="$3" gateway="$4" dns1="$5" dns2="$6"
    
    local cidr=$(netmask_to_cidr "$netmask")
    
    # Find existing netplan config or create new one
    local netplan_file="/etc/netplan/01-netcfg.yaml"
    if [ ! -f "$netplan_file" ]; then
        netplan_file="/etc/netplan/50-cloud-init.yaml"
    fi
    if [ ! -f "$netplan_file" ]; then
        netplan_file="/etc/netplan/01-fbellnews.yaml"
    fi
    
    cat > "$netplan_file" << EOF
network:
  version: 2
  ethernets:
    $interface:
      addresses:
        - $ip/$cidr
      gateway4: $gateway
      nameservers:
        addresses: [$dns1, $dns2]
EOF
    
    info "Netplan static configuration created"
}

configure_dhcp_netplan() {
    local interface="$1"
    
    local netplan_file="/etc/netplan/01-netcfg.yaml"
    if [ ! -f "$netplan_file" ]; then
        netplan_file="/etc/netplan/50-cloud-init.yaml"
    fi
    if [ ! -f "$netplan_file" ]; then
        netplan_file="/etc/netplan/01-fbellnews.yaml"
    fi
    
    cat > "$netplan_file" << EOF
network:
  version: 2
  ethernets:
    $interface:
      dhcp4: yes
EOF
    
    info "Netplan DHCP configuration created"
}

# dhcpcd configurations
configure_static_dhcpcd() {
    local interface="$1" ip="$2" netmask="$3" gateway="$4" dns1="$5" dns2="$6"
    
    local cidr=$(netmask_to_cidr "$netmask")
    
    # Backup original dhcpcd.conf
    cp /etc/dhcpcd.conf /etc/dhcpcd.conf.backup.$(date +%s) 2>/dev/null || true
    
    # Remove any existing configuration for this interface
    sed -i "/interface $interface/,/^$/d" /etc/dhcpcd.conf
    
    # Add static configuration
    cat >> /etc/dhcpcd.conf << EOF

# Static configuration for $interface (added by FBellNews)
interface $interface
static ip_address=$ip/$cidr
static routers=$gateway
static domain_name_servers=$dns1 $dns2
EOF
    
    info "dhcpcd static configuration created"
}

configure_dhcp_dhcpcd() {
    local interface="$1"
    
    # Backup original dhcpcd.conf
    cp /etc/dhcpcd.conf /etc/dhcpcd.conf.backup.$(date +%s) 2>/dev/null || true
    
    # Remove any existing static configuration for this interface
    sed -i "/interface $interface/,/^$/d" /etc/dhcpcd.conf
    
    info "dhcpcd DHCP configuration restored (static config removed)"
}

# /etc/network/interfaces configurations
configure_static_interfaces() {
    local interface="$1" ip="$2" netmask="$3" gateway="$4" dns1="$5" dns2="$6"
    
    # Backup original interfaces file
    cp /etc/network/interfaces /etc/network/interfaces.backup.$(date +%s) 2>/dev/null || true
    
    # Remove existing configuration for this interface
    sed -i "/iface $interface/,/^$/d" /etc/network/interfaces
    sed -i "/auto $interface/d" /etc/network/interfaces
    
    # Add static configuration
    cat >> /etc/network/interfaces << EOF

# Static configuration for $interface (added by FBellNews)
auto $interface
iface $interface inet static
    address $ip
    netmask $netmask
    gateway $gateway
    dns-nameservers $dns1 $dns2
EOF
    
    info "/etc/network/interfaces static configuration created"
}

configure_dhcp_interfaces() {
    local interface="$1"
    
    # Backup original interfaces file
    cp /etc/network/interfaces /etc/network/interfaces.backup.$(date +%s) 2>/dev/null || true
    
    # Remove existing configuration for this interface
    sed -i "/iface $interface/,/^$/d" /etc/network/interfaces
    sed -i "/auto $interface/d" /etc/network/interfaces
    
    # Add DHCP configuration
    cat >> /etc/network/interfaces << EOF

# DHCP configuration for $interface (added by FBellNews)
auto $interface
iface $interface inet dhcp
EOF
    
    info "/etc/network/interfaces DHCP configuration created"
}

netmask_to_cidr() {
    local netmask="$1"
    
    # Convert netmask to CIDR notation
    local cidr
    case "$netmask" in
        "255.255.255.0") cidr="24" ;;
        "255.255.0.0") cidr="16" ;;
        "255.0.0.0") cidr="8" ;;
        "255.255.255.128") cidr="25" ;;
        "255.255.255.192") cidr="26" ;;
        "255.255.255.224") cidr="27" ;;
        "255.255.255.240") cidr="28" ;;
        "255.255.255.248") cidr="29" ;;
        "255.255.255.252") cidr="30" ;;
        *) 
            # Calculate CIDR from netmask
            cidr=$(python3 -c "
import ipaddress
try:
    net = ipaddress.IPv4Network('0.0.0.0/$netmask', strict=False)
    print(net.prefixlen)
except:
    print('24')
" 2>/dev/null || echo "24")
            ;;
    esac
    
    echo "$cidr"
}

apply_network_changes() {
    local manager="$1"
    
    info "Applying network configuration changes..."
    
    # Update DNS configuration
    cat > /etc/resolv.conf << EOF
# Generated by FBellNews network configuration
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF
    
    case "$manager" in
        "NetworkManager")
            systemctl restart NetworkManager
            sleep 3
            nmcli connection reload
            ;;
        "systemd-networkd")
            systemctl restart systemd-networkd
            systemctl restart systemd-resolved
            ;;
        "netplan")
            netplan apply
            ;;
        "dhcpcd")
            systemctl restart dhcpcd
            ;;
        "interfaces")
            systemctl restart networking
            ;;
    esac
    
    # Additional network service restarts
    systemctl restart systemd-resolved 2>/dev/null || true
    
    # Wait for network to stabilize
    sleep 5
    
    success "Network configuration applied"
}

verify_network_config() {
    info "Verifying network configuration..."
    
    local interface=$(get_primary_interface)
    local current_ip=$(ip addr show "$interface" | grep 'inet ' | head -1 | awk '{print $2}' | cut -d'/' -f1)
    local gateway=$(ip route | grep '^default' | head -1 | awk '{print $3}')
    
    if [ -n "$current_ip" ] && [ "$current_ip" != "127.0.0.1" ]; then
        success "Network interface $interface has IP: $current_ip"
        
        # Test connectivity
        if ping -c 2 -W 3 "$gateway" >/dev/null 2>&1; then
            success "Gateway $gateway is reachable"
            
            if ping -c 2 -W 3 8.8.8.8 >/dev/null 2>&1; then
                success "Internet connectivity confirmed"
                return 0
            else
                warn "Gateway reachable but no internet connectivity"
                return 1
            fi
        else
            warn "Gateway $gateway is not reachable"
            return 1
        fi
    else
        error "No valid IP address found on $interface"
        return 1
    fi
}

show_network_status() {
    echo "Current Network Status:"
    echo "======================"
    
    local interface=$(get_primary_interface)
    local manager=$(detect_network_manager)
    
    echo "Primary Interface: $interface"
    echo "Network Manager: $manager"
    echo ""
    
    echo "IP Configuration:"
    ip addr show "$interface" 2>/dev/null | grep -E "(inet |link/)"
    echo ""
    
    echo "Routing Table:"
    ip route show
    echo ""
    
    echo "DNS Configuration:"
    cat /etc/resolv.conf | grep nameserver
    echo ""
    
    echo "Connectivity Test:"
    if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        echo "✅ Internet connectivity: OK"
    else
        echo "❌ Internet connectivity: FAILED"
    fi
}

show_help() {
    echo "FBellNewsV3 Network Configuration Handler"
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  static IP NETMASK GATEWAY [DNS1] [DNS2]"
    echo "                    Configure static IP address"
    echo "  dhcp              Configure DHCP (automatic IP)"
    echo "  status            Show current network status"
    echo "  verify            Verify network configuration"
    echo "  help              Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 static 192.168.1.100 255.255.255.0 192.168.1.1"
    echo "  $0 static 192.168.1.100 255.255.255.0 192.168.1.1 8.8.8.8 1.1.1.1"
    echo "  $0 dhcp"
    echo "  $0 status"
    echo ""
    echo "Note: This script requires root privileges for network configuration changes."
}

main() {
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    
    local command="${1:-help}"
    
    case "$command" in
        "static")
            if [ $# -lt 4 ]; then
                error "Static configuration requires: IP NETMASK GATEWAY"
                show_help
                exit 1
            fi
            
            if [[ $EUID -ne 0 ]]; then
                error "Static IP configuration requires root privileges"
                exit 1
            fi
            
            local interface=$(get_primary_interface)
            local ip="$2"
            local netmask="$3"
            local gateway="$4"
            local dns1="${5:-8.8.8.8}"
            local dns2="${6:-8.8.4.4}"
            
            configure_static_ip "$interface" "$ip" "$netmask" "$gateway" "$dns1" "$dns2"
            
            if verify_network_config; then
                success "Static IP configuration completed successfully"
                show_network_status
            else
                error "Network configuration verification failed"
                exit 1
            fi
            ;;
            
        "dhcp")
            if [[ $EUID -ne 0 ]]; then
                error "DHCP configuration requires root privileges"
                exit 1
            fi
            
            local interface=$(get_primary_interface)
            configure_dhcp "$interface"
            
            # Wait a bit longer for DHCP to assign IP
            info "Waiting for DHCP lease..."
            sleep 10
            
            if verify_network_config; then
                success "DHCP configuration completed successfully"
                show_network_status
            else
                error "Network configuration verification failed"
                exit 1
            fi
            ;;
            
        "status")
            show_network_status
            ;;
            
        "verify")
            if verify_network_config; then
                success "Network configuration is working correctly"
            else
                error "Network configuration has issues"
                exit 1
            fi
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