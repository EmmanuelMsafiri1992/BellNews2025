#!/bin/bash
# Auto Time & Network Fix Script for FBellNewsV3
# This script automatically detects and fixes system time and network issues
# Compatible with Ubuntu, Debian, and embedded systems
# Includes DNS resolution fixes for Docker registry connectivity

set -euo pipefail

# Configuration
SCRIPT_NAME="FBellNews Auto Time Fix"
LOGFILE="/var/log/fbellnews-time-fix.log"
LOCK_FILE="/var/run/fbellnews-time-fix.lock"
TIME_CHECK_FILE="/tmp/fbellnews_last_time_check"

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
    echo "║                    FBellNews Auto Time Fix                   ║"
    echo "║              Automatic Time Synchronization                 ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_if_running() {
    if [ -f "$LOCK_FILE" ]; then
        local pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            info "Time fix already running (PID: $pid)"
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
        warn "Running without root privileges. Some time sync methods may fail."
        return 1
    fi
    return 0
}

detect_system() {
    if command -v systemctl >/dev/null 2>&1; then
        echo "systemd"
    elif command -v service >/dev/null 2>&1; then
        echo "sysvinit"
    else
        echo "unknown"
    fi
}

check_time_validity() {
    local current_year=$(date +%Y 2>/dev/null || echo "1970")
    local current_timestamp=$(date +%s 2>/dev/null || echo "0")
    
    # Check if year is reasonable (2020-2035)
    if [ "$current_year" -lt 2020 ] || [ "$current_year" -gt 2035 ]; then
        warn "Invalid system year: $current_year"
        return 1
    fi
    
    # Check if timestamp is reasonable (after Jan 1, 2020)
    if [ "$current_timestamp" -lt 1577836800 ]; then
        warn "Invalid system timestamp: $current_timestamp"
        return 1
    fi
    
    info "System time appears valid: $(date)"
    return 0
}

stop_time_services() {
    local system_type=$(detect_system)
    info "Stopping time services..."
    
    local services=("ntp" "ntpd" "systemd-timesyncd" "chronyd" "chrony")
    
    for service in "${services[@]}"; do
        case $system_type in
            "systemd")
                systemctl stop "$service" 2>/dev/null || true
                ;;
            "sysvinit")
                service "$service" stop 2>/dev/null || true
                ;;
        esac
    done
}

start_time_services() {
    local system_type=$(detect_system)
    info "Starting time services..."
    
    case $system_type in
        "systemd")
            # Prefer systemd-timesyncd for modern systems
            systemctl enable systemd-timesyncd 2>/dev/null || true
            systemctl start systemd-timesyncd 2>/dev/null || true
            timedatectl set-ntp true 2>/dev/null || true
            ;;
        "sysvinit")
            service ntp start 2>/dev/null || service ntpd start 2>/dev/null || true
            ;;
    esac
}

sync_with_ntp() {
    info "Attempting NTP synchronization..."
    
    # Multiple NTP servers with IP addresses (DNS-independent)
    local ntp_servers=(
        "216.239.35.0"      # Google Public NTP
        "162.159.200.1"     # Cloudflare NTP
        "132.163.97.1"      # pool.ntp.org
        "129.6.15.28"       # NIST
        "193.79.237.14"     # PTB Germany
        "131.188.3.220"     # PTB Germany backup
        "time.google.com"   # Google (DNS)
        "pool.ntp.org"      # Pool (DNS)
        "time.cloudflare.com" # Cloudflare (DNS)
    )
    
    # Try ntpdate first (most reliable)
    if command -v ntpdate >/dev/null 2>&1; then
        for server in "${ntp_servers[@]}"; do
            info "Trying NTP server: $server"
            if timeout 10 ntpdate -s "$server" 2>/dev/null; then
                success "Successfully synced with NTP server: $server"
                # Update hardware clock if possible
                if command -v hwclock >/dev/null 2>&1 && check_root_privileges; then
                    hwclock --systohc 2>/dev/null || true
                fi
                return 0
            fi
        done
    fi
    
    # Try sntp as fallback
    if command -v sntp >/dev/null 2>&1; then
        for server in "${ntp_servers[@]}"; do
            info "Trying SNTP server: $server"
            if timeout 10 sntp -s "$server" 2>/dev/null; then
                success "Successfully synced with SNTP server: $server"
                return 0
            fi
        done
    fi
    
    warn "NTP synchronization failed with all servers"
    return 1
}

sync_with_http() {
    info "Attempting HTTP time synchronization..."
    
    local http_servers=(
        "google.com"
        "github.com"
        "cloudflare.com"
        "microsoft.com"
        "ubuntu.com"
    )
    
    for server in "${http_servers[@]}"; do
        info "Trying HTTP server: $server"
        local http_date
        http_date=$(timeout 10 curl -sI "http://$server" 2>/dev/null | grep -i '^date:' | cut -d' ' -f2- | head -1)
        
        if [ -n "$http_date" ] && date -s "$http_date" 2>/dev/null; then
            success "Successfully set time from HTTP server $server: $http_date"
            # Update hardware clock if possible
            if command -v hwclock >/dev/null 2>&1 && check_root_privileges; then
                hwclock --systohc 2>/dev/null || true
            fi
            return 0
        fi
    done
    
    # Try wget as fallback
    for server in "${http_servers[@]}"; do
        info "Trying wget with server: $server"
        local http_date
        http_date=$(timeout 10 wget --server-response --spider "http://$server" 2>&1 | grep -i 'date:' | cut -d' ' -f4- | head -1)
        
        if [ -n "$http_date" ] && date -s "$http_date" 2>/dev/null; then
            success "Successfully set time via wget from $server: $http_date"
            return 0
        fi
    done
    
    warn "HTTP time synchronization failed"
    return 1
}

configure_persistent_ntp() {
    info "Configuring persistent NTP settings..."
    
    local system_type=$(detect_system)
    
    case $system_type in
        "systemd")
            # Configure systemd-timesyncd
            if [ -d "/etc/systemd" ]; then
                cat > /etc/systemd/timesyncd.conf << 'EOF'
[Time]
NTP=216.239.35.0 162.159.200.1 pool.ntp.org time.google.com
FallbackNTP=time.cloudflare.com time.nist.gov 132.163.97.1
PollIntervalMinSec=32
PollIntervalMaxSec=2048
EOF
                systemctl daemon-reload 2>/dev/null || true
            fi
            ;;
        "sysvinit")
            # Configure traditional NTP
            if [ -f "/etc/ntp.conf" ]; then
                cp /etc/ntp.conf /etc/ntp.conf.bak.$(date +%s) 2>/dev/null || true
                cat >> /etc/ntp.conf << 'EOF'

# FBellNews Auto-added NTP servers
server 216.239.35.0 iburst
server 162.159.200.1 iburst
server pool.ntp.org iburst
server time.google.com iburst
EOF
            fi
            ;;
    esac
    
    success "NTP configuration updated"
}

install_ntp_tools() {
    info "Installing NTP tools if missing..."
    
    if ! command -v ntpdate >/dev/null 2>&1 && check_root_privileges; then
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -qq 2>/dev/null || true
            apt-get install -y ntpdate ntp 2>/dev/null || true
        elif command -v yum >/dev/null 2>&1; then
            yum install -y ntpdate ntp 2>/dev/null || true
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y ntpdate ntp 2>/dev/null || true
        elif command -v pacman >/dev/null 2>&1; then
            pacman -Sy --noconfirm ntp 2>/dev/null || true
        fi
    fi
}

fix_time_comprehensive() {
    info "Starting comprehensive time fix..."
    
    # Install tools if needed
    install_ntp_tools
    
    # Stop conflicting services
    if check_root_privileges; then
        stop_time_services
        sleep 2
    fi
    
    # Try NTP synchronization first
    if sync_with_ntp; then
        configure_persistent_ntp
        if check_root_privileges; then
            start_time_services
        fi
        return 0
    fi
    
    # Fallback to HTTP time sync
    if sync_with_http; then
        configure_persistent_ntp
        if check_root_privileges; then
            start_time_services
        fi
        return 0
    fi
    
    error "All time synchronization methods failed"
    return 1
}

create_autofix_service() {
    if ! check_root_privileges; then
        return 0
    fi
    
    info "Creating auto time-fix service..."
    
    local system_type=$(detect_system)
    
    case $system_type in
        "systemd")
            cat > /etc/systemd/system/fbellnews-time-fix.service << EOF
[Unit]
Description=FBellNews Auto Time Fix
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$(realpath "$0")
RemainAfterExit=false
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

            cat > /etc/systemd/system/fbellnews-time-fix.timer << 'EOF'
[Unit]
Description=FBellNews Auto Time Fix Timer
Requires=fbellnews-time-fix.service

[Timer]
OnBootSec=2min
OnUnitActiveSec=30min
Persistent=true

[Install]
WantedBy=timers.target
EOF

            systemctl daemon-reload
            systemctl enable fbellnews-time-fix.timer 2>/dev/null || true
            systemctl start fbellnews-time-fix.timer 2>/dev/null || true
            ;;
        
        "sysvinit")
            # Add to crontab
            (crontab -l 2>/dev/null | grep -v fbellnews-time-fix || true; echo "*/30 * * * * $(realpath "$0") >/dev/null 2>&1") | crontab -
            ;;
    esac
    
    success "Auto time-fix service created"
}

should_run_periodic_check() {
    # Always run if no previous check file exists
    if [ ! -f "$TIME_CHECK_FILE" ]; then
        return 0
    fi
    
    # Run if last check was more than 30 minutes ago
    if [ $(find "$TIME_CHECK_FILE" -mmin +30 2>/dev/null | wc -l) -gt 0 ]; then
        return 0
    fi
    
    return 1
}

# Network fix functions (embedded from auto-network-fix.sh)
run_network_fix() {
    info "Running network connectivity check and fixes..."

    # Test DNS resolution for Docker registry
    local test_domains=("registry-1.docker.io" "docker.io" "google.com")
    local dns_failed=0

    for domain in "${test_domains[@]}"; do
        if ! timeout 5 nslookup "$domain" >/dev/null 2>&1; then
            warn "DNS lookup failed for: $domain"
            ((dns_failed++))
        fi
    done

    # If DNS is failing, apply fixes
    if [ $dns_failed -gt 0 ]; then
        info "DNS issues detected, applying network fixes..."

        # Backup current resolv.conf
        [ -f /etc/resolv.conf ] && cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%s) 2>/dev/null || true

        # Create new resolv.conf with reliable DNS servers
        cat > /etc/resolv.conf << 'EOF'
# FBellNews Auto-generated DNS configuration
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
nameserver 1.0.0.1
nameserver 9.9.9.9
options timeout:2
options attempts:3
EOF

        # Configure Docker daemon DNS
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json << 'EOF'
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

        # Configure systemd-resolved if available
        if [ -d "/etc/systemd" ]; then
            mkdir -p /etc/systemd/resolved.conf.d
            cat > /etc/systemd/resolved.conf.d/fbellnews.conf << 'EOF'
[Resolve]
DNS=8.8.8.8 8.8.4.4 1.1.1.1 1.0.0.1
FallbackDNS=9.9.9.9 208.67.222.222
DNSSEC=no
Cache=yes
EOF

            # Restart systemd-resolved
            systemctl restart systemd-resolved 2>/dev/null || true
        fi

        # Restart Docker if running
        if systemctl is-active --quiet docker 2>/dev/null; then
            info "Restarting Docker daemon with new DNS configuration..."
            systemctl restart docker
            sleep 3
        fi

        # Flush DNS cache
        if command -v systemd-resolve >/dev/null 2>&1; then
            systemd-resolve --flush-caches 2>/dev/null || true
        fi

        success "Network fixes applied"

        # Test again
        sleep 2
        if timeout 5 nslookup "registry-1.docker.io" >/dev/null 2>&1; then
            success "Docker registry DNS resolution now working"
        else
            warn "DNS resolution still having issues, but fixes have been applied"
        fi
    else
        success "DNS resolution is working properly"
    fi
}

main() {
    print_banner

    # Ensure log directory exists
    mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null || true

    info "Starting $SCRIPT_NAME with Network Fix..."
    info "System: $(uname -a)"
    info "Current time: $(date 2>/dev/null || echo 'UNKNOWN')"

    check_if_running
    create_lock

    # First run network fix (critical for NTP and Docker)
    if check_root_privileges; then
        run_network_fix
    else
        warn "Skipping network fix (requires root privileges)"
    fi

    # Check if time is valid
    if check_time_validity; then
        if should_run_periodic_check; then
            info "Running periodic time check..."
            sync_with_ntp || info "Periodic NTP sync failed (this is normal)"
        else
            info "System time is valid and recent check exists, skipping time fix"
            # Still run network check for Docker
            if check_root_privileges; then
                info "Running network connectivity check..."
                timeout 5 nslookup "registry-1.docker.io" >/dev/null 2>&1 || run_network_fix
            fi
        fi
    else
        info "Time validity check failed, running comprehensive fix..."
        if ! fix_time_comprehensive; then
            error "Failed to fix system time"
            exit 1
        fi
    fi

    # Update check timestamp
    touch "$TIME_CHECK_FILE" 2>/dev/null || true

    # Create auto-fix service for future runs
    create_autofix_service

    success "Time and network fix completed successfully"
    info "Final system time: $(date)"

    # Final connectivity test
    if timeout 5 nslookup "registry-1.docker.io" >/dev/null 2>&1; then
        success "Docker registry connectivity confirmed"
    else
        warn "Docker registry connectivity still having issues"
    fi

    cleanup
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi