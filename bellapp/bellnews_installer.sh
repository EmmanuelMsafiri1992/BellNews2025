#!/bin/bash
# Bell News Smart Installer for NanoPi
# Handles Python 3.12 compilation, dependencies, and auto-start setup
# Compatible with Ubuntu 16.04+ and all ARM boards

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_VERSION="3.12.8"
PYTHON_CMD="python3.12"
SERVICE_NAME="bellnews"
LOG_FILE="/var/log/bellnews_installer.log"
INSTALL_DIR="/opt/bellnews"
USER_HOME="/home/$(logname 2>/dev/null || echo $USER)"

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

# Banner
show_banner() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    🔔 BELL NEWS INSTALLER                   ║"
    echo "║              Intelligent Setup for NanoPi & ARM             ║"
    echo "║                     Version 2.0.0                           ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        echo "Usage: sudo bash $0 [install|uninstall|status]"
        exit 1
    fi
}

# Detect system information
detect_system() {
    log_info "Detecting system information..."

    # OS Detection
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_NAME="$NAME"
        OS_VERSION="$VERSION_ID"
    else
        OS_NAME="Unknown"
        OS_VERSION="Unknown"
    fi

    # Architecture
    ARCH=$(uname -m)

    # Board detection
    BOARD_TYPE="Generic ARM"
    if [[ -f /proc/device-tree/model ]]; then
        MODEL=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')
        if [[ "$MODEL" =~ [Nn]ano[Pp]i ]]; then
            BOARD_TYPE="NanoPi"
        elif [[ "$MODEL" =~ [Oo]range ]]; then
            BOARD_TYPE="Orange Pi"
        elif [[ "$MODEL" =~ [Rr]aspberry ]]; then
            BOARD_TYPE="Raspberry Pi"
        fi
    fi

    # Memory check
    TOTAL_MEM=$(free -m | awk 'NR==2{printf "%.0f", $2}')

    log "System Detection Complete:"
    log "  OS: $OS_NAME $OS_VERSION"
    log "  Architecture: $ARCH"
    log "  Board: $BOARD_TYPE"
    log "  Memory: ${TOTAL_MEM}MB"

    # Compatibility check
    if [[ "$TOTAL_MEM" -lt 512 ]]; then
        log_warning "Low memory detected. Bell News needs at least 512MB"
    fi

    if [[ "$ARCH" != "armv7l" && "$ARCH" != "aarch64" && "$ARCH" != "x86_64" ]]; then
        log_warning "Untested architecture: $ARCH"
    fi
}

# Check Python version
check_python() {
    log_info "Checking Python installation..."

    # Check if Python 3.12 is already installed
    if command -v python3.12 &> /dev/null; then
        CURRENT_PYTHON_VERSION=$(python3.12 --version | cut -d' ' -f2)
        log "Python 3.12 found: $CURRENT_PYTHON_VERSION"
        PYTHON_INSTALLED=true
        return 0
    fi

    # Check system Python
    if command -v python3 &> /dev/null; then
        SYSTEM_PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
        log "System Python: $SYSTEM_PYTHON_VERSION"

        # Check if system python is 3.12+
        if python3 -c "import sys; exit(0 if sys.version_info >= (3, 12) else 1)" 2>/dev/null; then
            log "System Python is sufficient (3.12+)"
            PYTHON_CMD="python3"
            PYTHON_INSTALLED=true
            return 0
        fi
    fi

    log_warning "Python 3.12 not found. Will compile from source."
    PYTHON_INSTALLED=false
}

# Install system dependencies
install_system_deps() {
    log_info "Installing system dependencies..."

    # Update package lists
    apt-get update -qq

    # Essential build tools for Python compilation
    BUILD_DEPS=(
        "build-essential"
        "libssl-dev"
        "zlib1g-dev"
        "libncurses5-dev"
        "libffi-dev"
        "libsqlite3-dev"
        "libbz2-dev"
        "libreadline-dev"
        "libgdbm-dev"
        "liblzma-dev"
        "tk-dev"
        "wget"
        "curl"
        "make"
        "gcc"
        "git"
    )

    # System dependencies for Bell News
    SYSTEM_DEPS=(
        "i2c-tools"
        "alsa-utils"
        "pulseaudio"
        "ntpdate"
        "systemd"
        "rsyslog"
        "python3-pip"
        "python3-dev"
    )

    # Combine all dependencies
    ALL_DEPS=("${BUILD_DEPS[@]}" "${SYSTEM_DEPS[@]}")

    log "Installing ${#ALL_DEPS[@]} system packages..."

    # Install packages with retry logic
    for package in "${ALL_DEPS[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            log_info "Installing $package..."
            for attempt in {1..3}; do
                if apt-get install -y "$package" -qq; then
                    break
                else
                    log_warning "Attempt $attempt failed for $package, retrying..."
                    sleep 2
                fi

                if [[ $attempt -eq 3 ]]; then
                    log_error "Failed to install $package after 3 attempts"
                fi
            done
        else
            log_info "$package already installed"
        fi
    done

    log "System dependencies installed successfully"
}

# Compile and install Python 3.12
install_python312() {
    if [[ "$PYTHON_INSTALLED" == "true" ]]; then
        log "Python 3.12+ already available, skipping compilation"
        return 0
    fi

    log_info "Compiling Python $PYTHON_VERSION from source..."

    # Create source directory
    mkdir -p /usr/src
    cd /usr/src

    # Download Python source
    PYTHON_TAR="Python-${PYTHON_VERSION}.tgz"
    PYTHON_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/${PYTHON_TAR}"

    if [[ ! -f "$PYTHON_TAR" ]]; then
        log "Downloading Python $PYTHON_VERSION..."
        wget -q --show-progress "$PYTHON_URL" || {
            log_error "Failed to download Python source"
            exit 1
        }
    fi

    # Extract source
    log "Extracting Python source..."
    tar -xzf "$PYTHON_TAR"
    cd "Python-${PYTHON_VERSION}"

    # Configure build
    log "Configuring Python build (this may take a while)..."
    ./configure \
        --enable-optimizations \
        --enable-shared \
        --with-system-ffi \
        --with-computed-gotos \
        --enable-loadable-sqlite-extensions \
        --quiet || {
        log_error "Python configure failed"
        exit 1
    }

    # Compile (use all available cores)
    CORES=$(nproc)
    log "Compiling Python with $CORES cores (this will take 10-30 minutes)..."

    # Show progress for long compilation
    (
        make -j"$CORES" > /tmp/python_build.log 2>&1 &
        BUILD_PID=$!

        while kill -0 $BUILD_PID 2>/dev/null; do
            echo -n "."
            sleep 10
        done
        wait $BUILD_PID
    ) || {
        log_error "Python compilation failed. Check /tmp/python_build.log"
        exit 1
    }

    echo  # New line after dots
    log "Python compilation completed successfully"

    # Install Python
    log "Installing Python 3.12..."
    make altinstall > /tmp/python_install.log 2>&1 || {
        log_error "Python installation failed. Check /tmp/python_install.log"
        exit 1
    }

    # Update shared library cache
    ldconfig

    # Verify installation
    if command -v python3.12 &> /dev/null; then
        INSTALLED_VERSION=$(python3.12 --version)
        log "Python installation successful: $INSTALLED_VERSION"

        # Create symlink for convenience
        ln -sf /usr/local/bin/python3.12 /usr/local/bin/python3
        ln -sf /usr/local/bin/pip3.12 /usr/local/bin/pip3

    else
        log_error "Python installation verification failed"
        exit 1
    fi

    # Cleanup
    log "Cleaning up build files..."
    cd /
    rm -rf "/usr/src/Python-${PYTHON_VERSION}" "/usr/src/${PYTHON_TAR}"
}

# Install Python dependencies
install_python_deps() {
    log_info "Installing Python dependencies..."

    # Upgrade pip first
    $PYTHON_CMD -m pip install --upgrade pip setuptools wheel

    # Core dependencies
    PYTHON_DEPS=(
        "flask>=2.0.0"
        "pygame>=2.1.0"
        "psutil>=5.8.0"
        "pytz>=2021.3"
        "requests>=2.25.0"
        "bcrypt>=3.2.0"
        "gunicorn>=20.1.0"
        "pillow>=8.3.0"
        "luma.oled>=3.8.0"
        "luma.core>=2.4.0"
    )

    # Board-specific GPIO libraries
    case "$BOARD_TYPE" in
        "NanoPi"|"Orange Pi")
            PYTHON_DEPS+=("OPi.GPIO>=0.4.0")
            ;;
        "Raspberry Pi")
            PYTHON_DEPS+=("RPi.GPIO>=0.7.0")
            ;;
        *)
            log_warning "Unknown board type, installing both GPIO libraries"
            PYTHON_DEPS+=("OPi.GPIO>=0.4.0" "RPi.GPIO>=0.7.0")
            ;;
    esac

    # Install dependencies with retry logic
    for package in "${PYTHON_DEPS[@]}"; do
        log_info "Installing Python package: $package"
        for attempt in {1..3}; do
            if $PYTHON_CMD -m pip install "$package" --no-warn-script-location; then
                break
            else
                log_warning "Attempt $attempt failed for $package, retrying..."
                sleep 2
            fi

            if [[ $attempt -eq 3 ]]; then
                log_warning "Failed to install $package after 3 attempts (may work anyway)"
            fi
        done
    done

    log "Python dependencies installation completed"
}

# Setup Bell News application
setup_application() {
    log_info "Setting up Bell News application..."

    # Create installation directory
    mkdir -p "$INSTALL_DIR"

    # Copy application files
    log "Copying application files..."
    cp -r "$SCRIPT_DIR"/* "$INSTALL_DIR"/ || {
        log_error "Failed to copy application files"
        exit 1
    }

    # Set permissions
    chown -R root:root "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"
    chmod +x "$INSTALL_DIR"/*.py

    # Create required directories
    mkdir -p "$INSTALL_DIR/static/audio"
    mkdir -p "$INSTALL_DIR/static/images"
    mkdir -p "$INSTALL_DIR/logs"
    mkdir -p "/var/log/bellnews"

    # Set proper permissions for runtime directories
    chmod 777 "$INSTALL_DIR/static/audio"
    chmod 777 "$INSTALL_DIR/logs"
    chmod 755 "/var/log/bellnews"

    # Create default configuration
    if [[ ! -f "$INSTALL_DIR/config.json" ]]; then
        log "Creating default configuration..."
        cat > "$INSTALL_DIR/config.json" << 'EOF'
{
    "network": {
        "ipType": "dynamic",
        "ssid": "YOUR_WIFI_SSID",
        "password": "YOUR_WIFI_PASSWORD",
        "ipAddress": "",
        "subnetMask": "",
        "gateway": "",
        "dnsServer": ""
    },
    "time": {
        "timeType": "ntp",
        "ntpServer": "pool.ntp.org",
        "manualDate": "",
        "manualTime": ""
    }
}
EOF
    fi

    log "Application setup completed"
}

# Create systemd service
create_service() {
    log_info "Creating systemd service..."

    # Create service file
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Bell News Timer and Alarm System
After=network.target sound.service
Wants=network.target

[Service]
Type=forking
User=root
Group=root
WorkingDirectory=$INSTALL_DIR
Environment=PYTHONUNBUFFERED=1
Environment=DISPLAY=:0
ExecStartPre=/bin/sleep 10
ExecStart=/bin/bash -c 'cd $INSTALL_DIR && $PYTHON_CMD nanopi_monitor.py > /var/log/bellnews/monitor.log 2>&1 & echo \$! > /var/run/bellnews-monitor.pid && $PYTHON_CMD nano_web_timer.py > /var/log/bellnews/webtimer.log 2>&1 & echo \$! > /var/run/bellnews-webtimer.pid'
ExecStop=/bin/bash -c 'kill \$(cat /var/run/bellnews-monitor.pid) \$(cat /var/run/bellnews-webtimer.pid) 2>/dev/null || true'
PIDFile=/var/run/bellnews-monitor.pid
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Create startup script for better process management
    cat > "$INSTALL_DIR/start_bellnews.sh" << EOF
#!/bin/bash
cd "$INSTALL_DIR"

# Kill any existing processes
pkill -f "nanopi_monitor.py" 2>/dev/null || true
pkill -f "nano_web_timer.py" 2>/dev/null || true
sleep 2

# Start monitor
$PYTHON_CMD nanopi_monitor.py > /var/log/bellnews/monitor.log 2>&1 &
echo \$! > /var/run/bellnews-monitor.pid

# Start web timer
$PYTHON_CMD nano_web_timer.py > /var/log/bellnews/webtimer.log 2>&1 &
echo \$! > /var/run/bellnews-webtimer.pid

echo "Bell News started successfully"
EOF

    chmod +x "$INSTALL_DIR/start_bellnews.sh"

    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"

    log "Systemd service created and enabled"
}

# Test installation
test_installation() {
    log_info "Testing installation..."

    # Test Python installation
    if ! $PYTHON_CMD --version &>/dev/null; then
        log_error "Python test failed"
        return 1
    fi

    # Test Python modules
    TEST_MODULES=("flask" "pygame" "psutil" "pytz")
    for module in "${TEST_MODULES[@]}"; do
        if ! $PYTHON_CMD -c "import $module" 2>/dev/null; then
            log_error "Python module test failed: $module"
            return 1
        fi
    done

    # Test GPIO (non-critical)
    GPIO_TEST=false
    if $PYTHON_CMD -c "import OPi.GPIO" 2>/dev/null; then
        GPIO_TEST=true
        log "GPIO test: OPi.GPIO available"
    elif $PYTHON_CMD -c "import RPi.GPIO" 2>/dev/null; then
        GPIO_TEST=true
        log "GPIO test: RPi.GPIO available"
    else
        log_warning "GPIO libraries not available (display will use mock mode)"
    fi

    # Test application files
    REQUIRED_FILES=("nanopi_monitor.py" "nano_web_timer.py" "main.py")
    for file in "${REQUIRED_FILES[@]}"; do
        if [[ ! -f "$INSTALL_DIR/$file" ]]; then
            log_error "Required file missing: $file"
            return 1
        fi
    done

    log "Installation tests passed successfully"
    return 0
}

# Install function
install_bellnews() {
    show_banner
    log "Starting Bell News installation..."

    detect_system
    check_python
    install_system_deps
    install_python312
    install_python_deps
    setup_application
    create_service

    if test_installation; then
        log "✅ Installation completed successfully!"
        echo
        log_info "Next steps:"
        echo "  1. Edit configuration: nano $INSTALL_DIR/config.json"
        echo "  2. Start service: systemctl start $SERVICE_NAME"
        echo "  3. Check status: systemctl status $SERVICE_NAME"
        echo "  4. View logs: journalctl -u $SERVICE_NAME -f"
        echo "  5. Web interface: http://$(hostname -I | awk '{print $1}'):5000"
        echo
        echo "🎉 Bell News will auto-start on system boot!"

        # Ask if user wants to start now
        read -p "Start Bell News now? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            systemctl start "$SERVICE_NAME"
            sleep 3
            systemctl status "$SERVICE_NAME" --no-pager
        fi
    else
        log_error "Installation tests failed"
        exit 1
    fi
}

# Uninstall function
uninstall_bellnews() {
    log_info "Uninstalling Bell News..."

    # Stop and disable service
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true

    # Remove service file
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload

    # Remove installation directory
    rm -rf "$INSTALL_DIR"

    # Remove logs
    rm -rf "/var/log/bellnews"

    # Remove PID files
    rm -f /var/run/bellnews-*.pid

    log "✅ Bell News uninstalled successfully"

    echo
    log_info "Note: Python 3.12 and system packages were left installed"
    log_info "To completely remove Python 3.12: rm -f /usr/local/bin/python3.12*"
}

# Status function
show_status() {
    echo -e "${BLUE}Bell News System Status${NC}"
    echo "========================"

    # Check if installed
    if [[ -d "$INSTALL_DIR" ]]; then
        echo -e "Installation: ${GREEN}✅ Installed${NC}"
        echo "Location: $INSTALL_DIR"
    else
        echo -e "Installation: ${RED}❌ Not installed${NC}"
        return 1
    fi

    # Check Python
    if command -v python3.12 &>/dev/null; then
        VERSION=$(python3.12 --version)
        echo -e "Python: ${GREEN}✅ $VERSION${NC}"
    else
        echo -e "Python: ${RED}❌ Python 3.12 not found${NC}"
    fi

    # Check service
    if systemctl is-enabled "$SERVICE_NAME" &>/dev/null; then
        if systemctl is-active "$SERVICE_NAME" &>/dev/null; then
            echo -e "Service: ${GREEN}✅ Running${NC}"
        else
            echo -e "Service: ${YELLOW}⚠️  Stopped${NC}"
        fi
    else
        echo -e "Service: ${RED}❌ Not enabled${NC}"
    fi

    # Check processes
    if pgrep -f "nanopi_monitor.py" >/dev/null; then
        echo -e "Monitor Process: ${GREEN}✅ Running${NC}"
    else
        echo -e "Monitor Process: ${RED}❌ Not running${NC}"
    fi

    if pgrep -f "nano_web_timer.py" >/dev/null; then
        echo -e "Web Timer Process: ${GREEN}✅ Running${NC}"
    else
        echo -e "Web Timer Process: ${RED}❌ Not running${NC}"
    fi

    # Show recent logs
    echo
    echo "Recent logs:"
    journalctl -u "$SERVICE_NAME" --no-pager -n 5 2>/dev/null || echo "No service logs available"
}

# Main function
main() {
    # Create log file
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"

    case "${1:-""}" in
        "install")
            check_root
            install_bellnews
            ;;
        "uninstall")
            check_root
            uninstall_bellnews
            ;;
        "status")
            show_status
            ;;
        *)
            show_banner
            echo "Bell News Intelligent Installer"
            echo
            echo "Usage: sudo $0 [command]"
            echo
            echo "Commands:"
            echo "  install    - Install Bell News with all dependencies"
            echo "  uninstall  - Remove Bell News completely"
            echo "  status     - Show installation and service status"
            echo
            echo "Examples:"
            echo "  sudo $0 install      # Full installation"
            echo "  sudo $0 status       # Check status"
            echo "  sudo $0 uninstall    # Remove everything"
            echo
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"