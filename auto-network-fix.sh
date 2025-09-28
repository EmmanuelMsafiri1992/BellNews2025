#!/bin/bash
# Auto Network Fix Script for FBellNewsV3
# This script automatically detects and fixes DNS resolution and network issues
# Specifically designed for embedded systems like Nano Pi

set -euo pipefail

# Configuration
SCRIPT_NAME="FBellNews Auto Network Fix"
LOGFILE="/var/log/fbellnews-network-fix.log"
LOCK_FILE="/var/run/fbellnews-network-fix.lock"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "UNKNOWN")
    echo -e "[${timestamp}] [${level}] ${message}" | tee -a "$LOGFILE"
}

info() { log "INFO" "$@"; }
warn() { log "WARN" "$@"; }
error() { log "ERROR" "$@"; }
success() { log "SUCCESS" "$@"; }

print_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                  FBellNews Auto Network Fix                 ║"
    echo "║              DNS & Network Troubleshooting                  ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_if_running() {
    if [ -f "$LOCK_FILE" ]; then
        local pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            info "Network fix already running (PID: $pid)"
            exit 0
        else
            rm -f "$LOCK_FILE"
        fi
    fi
}

create_lock() {
    echo $$ > "$LOCK_FILE"
    trap 'cleanup' INT TERM EXIT
}

cleanup() {
    rm -f "$LOCK_FILE"
}

check_root_privileges() {
    if [[ $EUID -ne 0 ]]; then
        warn "Running without root privileges. Some network fixes may fail."
        return 1
    fi
    return 0
}

test_dns_resolution() {
    info "Testing DNS resolution..."

    local test_domains=(
        "registry-1.docker.io"
        "google.com"
        "cloudflare.com"
        "github.com"
        "ubuntu.com"
    )

    local failed_count=0

    for domain in "${test_domains[@]}"; do
        info "Testing DNS lookup for: $domain"
        if timeout 5 nslookup "$domain" >/dev/null 2>&1; then
            success "DNS lookup successful for: $domain"
        else
            warn "DNS lookup failed for: $domain"
            ((failed_count++))
        fi
    done

    if [ $failed_count -eq ${#test_domains[@]} ]; then
        error "All DNS lookups failed"
        return 1
    elif [ $failed_count -gt 0 ]; then
        warn "Some DNS lookups failed ($failed_count/${#test_domains[@]})"
        return 1
    else
        success "All DNS lookups successful"
        return 0
    fi
}

backup_network_configs() {
    info "Backing up network configuration files..."

    local backup_dir="/var/backups/fbellnews-network-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"

    # Backup DNS configurations
    [ -f /etc/resolv.conf ] && cp /etc/resolv.conf "$backup_dir/" 2>/dev/null || true
    [ -f /etc/systemd/resolved.conf ] && cp /etc/systemd/resolved.conf "$backup_dir/" 2>/dev/null || true
    [ -d /etc/netplan ] && cp -r /etc/netplan "$backup_dir/" 2>/dev/null || true
    [ -f /etc/docker/daemon.json ] && cp /etc/docker/daemon.json "$backup_dir/" 2>/dev/null || true

    success "Network configurations backed up to: $backup_dir"
}

fix_resolv_conf() {
    info "Fixing /etc/resolv.conf..."

    backup_network_configs

    # Create new resolv.conf with reliable DNS servers
    cat > /etc/resolv.conf << 'EOF'
# FBellNews Auto-generated DNS configuration
# Google Public DNS
nameserver 8.8.8.8
nameserver 8.8.4.4
# Cloudflare DNS
nameserver 1.1.1.1
nameserver 1.0.0.1
# Quad9 DNS
nameserver 9.9.9.9
# OpenDNS
nameserver 208.67.222.222

# Search domains
search local

# Options
options timeout:2
options attempts:3
options rotate
options single-request-reopen
EOF

    success "Updated /etc/resolv.conf with reliable DNS servers"
}

fix_systemd_resolved() {
    info "Configuring systemd-resolved..."

    if [ -d "/etc/systemd" ]; then
        mkdir -p /etc/systemd/resolved.conf.d

        cat > /etc/systemd/resolved.conf.d/fbellnews.conf << 'EOF'
[Resolve]
DNS=8.8.8.8 8.8.4.4 1.1.1.1 1.0.0.1 9.9.9.9
FallbackDNS=208.67.222.222 208.67.220.220
Domains=~.
DNSSEC=no
DNSOverTLS=no
Cache=yes
DNSStubListener=yes
ReadEtcHosts=yes
EOF

        # Update main resolved.conf
        if [ -f /etc/systemd/resolved.conf ]; then
            sed -i 's/^#DNS=.*/DNS=8.8.8.8 8.8.4.4 1.1.1.1/' /etc/systemd/resolved.conf
            sed -i 's/^#FallbackDNS=.*/FallbackDNS=9.9.9.9 208.67.222.222/' /etc/systemd/resolved.conf
            sed -i 's/^#DNSSEC=.*/DNSSEC=no/' /etc/systemd/resolved.conf
        fi

        success "Configured systemd-resolved"
    fi
}

fix_netplan_dns() {
    info "Checking and fixing Netplan DNS configuration..."

    if [ -d "/etc/netplan" ]; then
        # Find netplan configuration files
        local netplan_files=($(find /etc/netplan -name "*.yaml" -o -name "*.yml" 2>/dev/null))

        if [ ${#netplan_files[@]} -eq 0 ]; then
            # Create a basic netplan configuration
            cat > /etc/netplan/01-fbellnews-dns.yaml << 'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: true
      dhcp6: false
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4, 1.1.1.1, 1.0.0.1]
        search: [local]
    wlan0:
      dhcp4: true
      dhcp6: false
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4, 1.1.1.1, 1.0.0.1]
        search: [local]
    enp*:
      dhcp4: true
      dhcp6: false
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4, 1.1.1.1, 1.0.0.1]
        search: [local]
EOF
            success "Created new Netplan configuration with DNS servers"
        else
            # Update existing netplan files to include DNS servers
            for file in "${netplan_files[@]}"; do
                info "Updating Netplan file: $file"

                # Create a temporary updated file
                python3 -c "
import yaml
import sys

try:
    with open('$file', 'r') as f:
        config = yaml.safe_load(f) or {}

    if 'network' not in config:
        config['network'] = {}
    if 'ethernets' not in config['network']:
        config['network']['ethernets'] = {}

    dns_config = {
        'addresses': ['8.8.8.8', '8.8.4.4', '1.1.1.1', '1.0.0.1'],
        'search': ['local']
    }

    # Add DNS to all ethernet interfaces
    for interface in config['network']['ethernets']:
        if 'nameservers' not in config['network']['ethernets'][interface]:
            config['network']['ethernets'][interface]['nameservers'] = dns_config

    # If no interfaces exist, create a generic one
    if not config['network']['ethernets']:
        config['network']['ethernets']['eth0'] = {
            'dhcp4': True,
            'nameservers': dns_config
        }

    with open('$file', 'w') as f:
        yaml.dump(config, f, default_flow_style=False)

    print('Updated successfully')
except Exception as e:
    print(f'Error: {e}')
    sys.exit(1)
" 2>/dev/null || warn "Could not update $file automatically"
            done
        fi

        # Apply netplan changes
        if command -v netplan >/dev/null 2>&1; then
            netplan apply 2>/dev/null || warn "Netplan apply failed"
        fi
    fi
}

fix_docker_dns() {
    info "Configuring Docker daemon DNS..."

    mkdir -p /etc/docker

    # Create or update Docker daemon configuration
    local docker_config="/etc/docker/daemon.json"

    if [ -f "$docker_config" ]; then
        # Backup existing config
        cp "$docker_config" "${docker_config}.backup.$(date +%s)"

        # Update existing config to include DNS
        python3 -c "
import json
import sys

try:
    with open('$docker_config', 'r') as f:
        config = json.load(f)
except:
    config = {}

config['dns'] = ['8.8.8.8', '8.8.4.4', '1.1.1.1', '1.0.0.1']
config['dns-opts'] = ['timeout:2', 'attempts:3']

with open('$docker_config', 'w') as f:
    json.dump(config, f, indent=2)

print('Docker DNS configuration updated')
" 2>/dev/null || {
        # Fallback if python fails
        cat > "$docker_config" << 'EOF'
{
  "dns": ["8.8.8.8", "8.8.4.4", "1.1.1.1", "1.0.0.1"],
  "dns-opts": ["timeout:2", "attempts:3"]
}
EOF
    }
    else
        # Create new Docker daemon config
        cat > "$docker_config" << 'EOF'
{
  "dns": ["8.8.8.8", "8.8.4.4", "1.1.1.1", "1.0.0.1"],
  "dns-opts": ["timeout:2", "attempts:3"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    fi

    success "Docker DNS configuration updated"
}

restart_network_services() {
    info "Restarting network services..."

    local services=(
        "systemd-resolved"
        "systemd-networkd"
        "networking"
        "NetworkManager"
        "docker"
    )

    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            info "Restarting $service..."
            systemctl restart "$service" 2>/dev/null || warn "Failed to restart $service"
            sleep 2
        fi
    done

    # Flush DNS cache
    if command -v systemd-resolve >/dev/null 2>&1; then
        systemd-resolve --flush-caches 2>/dev/null || true
    fi

    if command -v resolvectl >/dev/null 2>&1; then
        resolvectl flush-caches 2>/dev/null || true
    fi

    success "Network services restarted"
}

test_docker_connectivity() {
    info "Testing Docker registry connectivity..."

    local docker_registries=(
        "registry-1.docker.io"
        "docker.io"
        "index.docker.io"
    )

    for registry in "${docker_registries[@]}"; do
        info "Testing connectivity to: $registry"
        if timeout 10 curl -sI "https://$registry" >/dev/null 2>&1; then
            success "Successfully connected to: $registry"
            return 0
        else
            warn "Failed to connect to: $registry"
        fi
    done

    error "All Docker registry connections failed"
    return 1
}

wait_for_network() {
    info "Waiting for network to become available..."

    local max_wait=30
    local wait_count=0

    while [ $wait_count -lt $max_wait ]; do
        if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
            success "Network connectivity established"
            return 0
        fi

        info "Waiting for network... ($((wait_count + 1))/$max_wait)"
        sleep 2
        ((wait_count++))
    done

    warn "Network connectivity timeout"
    return 1
}

fix_network_comprehensive() {
    info "Starting comprehensive network fix..."

    # Wait for basic network connectivity
    wait_for_network || warn "Basic network connectivity not available"

    # Test current DNS resolution
    if test_dns_resolution; then
        info "DNS resolution is working, checking Docker connectivity..."
        if test_docker_connectivity; then
            success "All network tests passed"
            return 0
        fi
    fi

    # Apply fixes
    info "Applying network fixes..."

    # Fix DNS configurations
    fix_resolv_conf
    fix_systemd_resolved
    fix_netplan_dns
    fix_docker_dns

    # Restart services
    restart_network_services

    # Wait a moment for services to stabilize
    sleep 5

    # Test again
    if test_dns_resolution && test_docker_connectivity; then
        success "Network fixes applied successfully"
        return 0
    else
        error "Network fixes did not resolve all issues"
        return 1
    fi
}

create_network_status_file() {
    local status_file="/tmp/fbellnews_network_status"

    cat > "$status_file" << EOF
# FBellNews Network Status - $(date)
DNS_RESOLUTION=$(test_dns_resolution && echo "OK" || echo "FAILED")
DOCKER_CONNECTIVITY=$(test_docker_connectivity && echo "OK" || echo "FAILED")
LAST_CHECK=$(date +%s)
EOF

    info "Network status written to: $status_file"
}

main() {
    print_banner

    # Ensure log directory exists
    mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null || true

    info "Starting $SCRIPT_NAME..."
    info "System: $(uname -a)"
    info "Current time: $(date 2>/dev/null || echo 'UNKNOWN')"

    # Check if we have root privileges
    if ! check_root_privileges; then
        error "Network fixes require root privileges"
        exit 1
    fi

    check_if_running
    create_lock

    # Run comprehensive network fix
    if fix_network_comprehensive; then
        success "Network configuration completed successfully"
        create_network_status_file
    else
        error "Network configuration failed"
        exit 1
    fi

    info "Network fix completed"
    cleanup
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi