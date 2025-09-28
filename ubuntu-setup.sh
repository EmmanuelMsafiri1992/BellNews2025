#!/bin/bash
# Ubuntu Setup Script for FBellNewsV3
# Automatically sets up the application with time fix on any Ubuntu system

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/fbellnews-setup.log"
REQUIRED_PACKAGES=("docker.io" "docker-compose" "curl" "wget" "ntpdate" "ntp")

print_banner() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    FBellNews Ubuntu Setup                   ║"
    echo "║            Automated Installation & Time Fix                ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        echo "Usage: sudo $0"
        exit 1
    fi
}

check_ubuntu() {
    if ! command -v lsb_release >/dev/null 2>&1; then
        warn "lsb_release not found, assuming Ubuntu-compatible system"
        return 0
    fi
    
    local os_name=$(lsb_release -si)
    local os_version=$(lsb_release -sr)
    
    info "Detected OS: $os_name $os_version"
    
    if [[ "$os_name" != "Ubuntu" ]] && [[ "$os_name" != "Debian" ]]; then
        warn "This script is designed for Ubuntu/Debian. Your system: $os_name"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

fix_system_time() {
    info "Running comprehensive time fix..."
    
    # Make auto-time-fix script executable
    chmod +x "$SCRIPT_DIR/auto-time-fix.sh"
    
    # Run the time fix script
    if "$SCRIPT_DIR/auto-time-fix.sh"; then
        success "System time fixed successfully"
    else
        warn "Time fix encountered issues but continuing..."
    fi
    
    # Ensure time is reasonable for SSL certificates
    local current_year=$(date +%Y)
    if [ "$current_year" -lt 2020 ] || [ "$current_year" -gt 2030 ]; then
        error "System time is still invalid: $(date)"
        info "Attempting manual time fix..."
        
        # Try manual fix
        ntpdate -s time.google.com 2>/dev/null || ntpdate -s pool.ntp.org 2>/dev/null || true
        hwclock --systohc 2>/dev/null || true
        
        local new_year=$(date +%Y)
        if [ "$new_year" -lt 2020 ] || [ "$new_year" -gt 2030 ]; then
            error "Failed to fix system time. Docker builds may fail due to SSL certificate issues."
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi
    
    info "Current system time: $(date)"
}

update_system() {
    info "Updating system packages..."
    
    # Fix any broken packages first
    apt-get -f install -y 2>/dev/null || true
    
    # Update package lists
    if ! apt-get update; then
        warn "apt-get update failed, trying to fix..."
        apt-get clean
        apt-get update --fix-missing
    fi
    
    # Upgrade system packages
    apt-get upgrade -y
    
    success "System packages updated"
}

install_dependencies() {
    info "Installing required packages..."
    
    local missing_packages=()
    
    # Check which packages are missing
    for package in "${REQUIRED_PACKAGES[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            missing_packages+=("$package")
        fi
    done
    
    if [ ${#missing_packages[@]} -eq 0 ]; then
        info "All required packages are already installed"
        return 0
    fi
    
    info "Installing missing packages: ${missing_packages[*]}"
    
    # Install packages with retry logic
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if apt-get install -y "${missing_packages[@]}"; then
            break
        else
            warn "Installation attempt $attempt failed"
            if [ $attempt -eq $max_attempts ]; then
                error "Failed to install required packages after $max_attempts attempts"
                exit 1
            fi
            attempt=$((attempt + 1))
            sleep 5
        fi
    done
    
    success "All required packages installed"
}

setup_docker() {
    info "Setting up Docker..."
    
    # Start Docker service
    systemctl enable docker
    systemctl start docker
    
    # Add current user to docker group (if not root)
    if [ -n "${SUDO_USER:-}" ]; then
        usermod -aG docker "$SUDO_USER"
        info "Added $SUDO_USER to docker group (requires logout/login)"
    fi
    
    # Test Docker
    if docker --version >/dev/null 2>&1; then
        success "Docker is working: $(docker --version)"
    else
        error "Docker installation failed"
        exit 1
    fi
    
    # Test Docker Compose
    if docker-compose --version >/dev/null 2>&1; then
        success "Docker Compose is working: $(docker-compose --version)"
    elif docker compose version >/dev/null 2>&1; then
        success "Docker Compose (v2) is working: $(docker compose version)"
    else
        error "Docker Compose installation failed"
        exit 1
    fi
}

configure_firewall() {
    info "Configuring firewall for FBellNews ports..."
    
    if command -v ufw >/dev/null 2>&1; then
        # UFW configuration
        ufw --force enable 2>/dev/null || true
        ufw allow 5000/tcp comment "FBellNews Python App" 2>/dev/null || true
        ufw allow 8000/tcp comment "FBellNews Laravel App" 2>/dev/null || true
        ufw allow 5173/tcp comment "FBellNews Vite Dev Server" 2>/dev/null || true
        ufw allow 5002/tcp comment "FBellNews Config Service" 2>/dev/null || true
        success "UFW firewall configured"
    elif command -v iptables >/dev/null 2>&1; then
        # Basic iptables configuration
        iptables -I INPUT -p tcp --dport 5000 -j ACCEPT 2>/dev/null || true
        iptables -I INPUT -p tcp --dport 8000 -j ACCEPT 2>/dev/null || true
        iptables -I INPUT -p tcp --dport 5173 -j ACCEPT 2>/dev/null || true
        iptables -I INPUT -p tcp --dport 5002 -j ACCEPT 2>/dev/null || true
        info "Basic iptables rules added"
    else
        warn "No firewall configuration tool found"
    fi
}

setup_environment() {
    info "Setting up application environment..."
    
    cd "$SCRIPT_DIR"
    
    # Make scripts executable
    chmod +x auto-time-fix.sh
    chmod +x *.sh 2>/dev/null || true
    
    # Create necessary directories
    mkdir -p config_service_logs
    mkdir -p bellapp/logs
    
    # Set proper permissions
    chown -R ${SUDO_USER:-root}:${SUDO_USER:-root} "$SCRIPT_DIR" 2>/dev/null || true
    
    success "Environment setup completed"
}

test_installation() {
    info "Testing installation..."
    
    cd "$SCRIPT_DIR"
    
    # Test time fix script
    if ./auto-time-fix.sh >/dev/null 2>&1; then
        success "Time fix script is working"
    else
        warn "Time fix script test failed (this may be normal)"
    fi
    
    # Test Docker Compose file
    if docker-compose -f docker-compose.dev.yml config >/dev/null 2>&1; then
        success "Docker Compose configuration is valid"
    elif docker compose -f docker-compose.dev.yml config >/dev/null 2>&1; then
        success "Docker Compose (v2) configuration is valid"
    else
        error "Docker Compose configuration is invalid"
        exit 1
    fi
    
    info "Installation test completed"
    
    # Install and start network monitor
    info "Setting up network monitoring service..."
    chmod +x "$SCRIPT_DIR/network-monitor.sh"
    chmod +x "$SCRIPT_DIR/network-config-handler.sh"
    
    # Create systemd service for network monitor
    cat > /etc/systemd/system/fbellnews-network-monitor.service << EOF
[Unit]
Description=FBellNews Network Monitor & Auto-Recovery
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=forking
PIDFile=/var/run/fbellnews-network-monitor.pid
ExecStart=$SCRIPT_DIR/network-monitor.sh start
ExecStop=$SCRIPT_DIR/network-monitor.sh stop
Restart=always
RestartSec=10
User=root
WorkingDirectory=$SCRIPT_DIR

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable fbellnews-network-monitor.service
    systemctl start fbellnews-network-monitor.service
    
    success "Network monitoring service installed and started"
}

show_usage() {
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                     Installation Complete!                  ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo "Your FBellNews application is now ready!"
    echo ""
    echo -e "${YELLOW}To start the application:${NC}"
    echo "  cd $(realpath "$SCRIPT_DIR")"
    echo "  docker-compose -f docker-compose.dev.yml up -d"
    echo ""
    echo -e "${YELLOW}To stop the application:${NC}"
    echo "  docker-compose -f docker-compose.dev.yml down"
    echo ""
    echo -e "${YELLOW}To view logs:${NC}"
    echo "  docker-compose -f docker-compose.dev.yml logs -f"
    echo ""
    echo -e "${YELLOW}Application URLs (after starting):${NC}"
    echo "  • News App:      http://localhost:8000"
    echo "  • Python API:    http://localhost:5000"
    echo "  • Config Service: http://localhost:5002"
    echo "  • Vite Dev:      http://localhost:5173"
    echo ""
    echo -e "${YELLOW}Time Fix Log:${NC}"
    echo "  • Log file: /var/log/fbellnews-time-fix.log"
    echo "  • Manual run: ./auto-time-fix.sh"
    echo ""
    echo -e "${YELLOW}Network Monitoring:${NC}"
    echo "  • Monitor status: ./network-monitor.sh status"
    echo "  • Network config: ./network-config-handler.sh help"
    echo "  • Monitor log: /var/log/fbellnews-network-monitor.log"
    echo ""
    echo -e "${GREEN}The system will automatically handle:${NC}"
    echo "  ✅ Time synchronization issues"
    echo "  ✅ Network configuration changes (DHCP ↔ Static IP)"
    echo "  ✅ Docker service recovery"
    echo "  ✅ Application URL updates"
    echo "  ✅ No reboot required for IP changes!"
    
    if [ -n "${SUDO_USER:-}" ]; then
        echo ""
        echo -e "${YELLOW}Note:${NC} Please logout and login again to use Docker without sudo"
    fi
}

main() {
    print_banner
    
    # Setup logging
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    info "Starting FBellNews Ubuntu Setup..."
    info "Script directory: $SCRIPT_DIR"
    info "Log file: $LOG_FILE"
    
    # Pre-flight checks
    check_root
    check_ubuntu
    
    # Main installation steps
    info "Step 1/8: Fixing system time..."
    fix_system_time
    
    info "Step 2/8: Updating system packages..."
    update_system
    
    info "Step 3/8: Installing dependencies..."
    install_dependencies
    
    info "Step 4/8: Setting up Docker..."
    setup_docker
    
    info "Step 5/8: Configuring firewall..."
    configure_firewall
    
    info "Step 6/8: Setting up environment..."
    setup_environment
    
    info "Step 7/8: Testing installation..."
    test_installation
    
    info "Step 8/8: Installation completed!"
    
    success "FBellNews setup completed successfully!"
    
    show_usage
    
    log "INFO" "Setup completed at $(date)"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi