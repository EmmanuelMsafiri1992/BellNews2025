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

# Check for running Bell News processes
check_running_processes() {
    log_info "Checking for running Bell News processes..."

    local processes_found=false
    local running_processes=()

    # Check for Bell News Python processes
    if pgrep -f "nanopi_monitor.py" >/dev/null 2>&1; then
        running_processes+=("nanopi_monitor.py")
        processes_found=true
    fi

    if pgrep -f "nano_web_timer.py" >/dev/null 2>&1; then
        running_processes+=("nano_web_timer.py")
        processes_found=true
    fi

    if pgrep -f "main.py" >/dev/null 2>&1; then
        running_processes+=("main.py")
        processes_found=true
    fi

    # Check for Bell News service
    if systemctl is-active "$SERVICE_NAME" >/dev/null 2>&1; then
        running_processes+=("$SERVICE_NAME service")
        processes_found=true
    fi

    if [[ "$processes_found" == "true" ]]; then
        log_warning "Found running Bell News processes:"
        for process in "${running_processes[@]}"; do
            log_warning "  - $process"
        done
        return 0
    else
        log "No running Bell News processes detected"
        return 1
    fi
}

# Stop existing Bell News processes and services
stop_existing_processes() {
    log_info "Stopping existing Bell News processes and services..."

    # Stop systemd service first
    if systemctl is-active "$SERVICE_NAME" >/dev/null 2>&1; then
        log "Stopping $SERVICE_NAME service..."
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        sleep 2
    fi

    # Kill Python processes gracefully first
    local processes=("nanopi_monitor.py" "nano_web_timer.py" "main.py")
    for process in "${processes[@]}"; do
        if pgrep -f "$process" >/dev/null 2>&1; then
            log "Stopping $process processes..."
            pkill -f "$process" 2>/dev/null || true
        fi
    done

    # Wait for graceful shutdown
    sleep 3

    # Force kill if still running
    for process in "${processes[@]}"; do
        if pgrep -f "$process" >/dev/null 2>&1; then
            log_warning "Force killing $process processes..."
            pkill -9 -f "$process" 2>/dev/null || true
        fi
    done

    # Remove stale PID files
    rm -f /var/run/bellnews-*.pid 2>/dev/null || true

    # Wait for cleanup
    sleep 2

    # Verify cleanup
    local still_running=false
    for process in "${processes[@]}"; do
        if pgrep -f "$process" >/dev/null 2>&1; then
            log_error "Failed to stop $process"
            still_running=true
        fi
    done

    if [[ "$still_running" == "false" ]]; then
        log "All Bell News processes stopped successfully"
    else
        log_error "Some processes could not be stopped. Installation may fail."
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Clean existing installation
clean_existing_installation() {
    log_info "Cleaning existing installation..."

    # Remove old installation directory contents but keep the directory
    if [[ -d "$INSTALL_DIR" ]]; then
        log "Cleaning existing installation directory..."
        rm -rf "$INSTALL_DIR"/* 2>/dev/null || true
        rm -rf "$INSTALL_DIR"/.* 2>/dev/null || true
    fi

    # Clean old logs but keep directory
    if [[ -d "/var/log/bellnews" ]]; then
        log "Cleaning old log files..."
        rm -f /var/log/bellnews/* 2>/dev/null || true
    fi

    log "Existing installation cleaned"
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

# Check system compatibility for Python compilation
check_build_requirements() {
    log_info "Checking system compatibility for Python compilation..."

    local requirements_met=true

    # Check available disk space (need at least 1GB for Python build)
    AVAILABLE_SPACE=$(df /usr/src 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
    if [[ $AVAILABLE_SPACE -lt 1048576 ]]; then  # 1GB in KB
        log_error "Insufficient disk space. Need at least 1GB free in /usr/src"
        requirements_met=false
    else
        log "Disk space check: OK ($(($AVAILABLE_SPACE / 1024))MB available)"
    fi

    # Check memory (need at least 512MB for compilation)
    AVAILABLE_MEM=$(free -m | awk 'NR==2{print $7}' || echo "0")
    if [[ $AVAILABLE_MEM -lt 256 ]]; then
        log_warning "Low available memory ($AVAILABLE_MEM MB). Python compilation may be slow"
    else
        log "Memory check: OK (${AVAILABLE_MEM}MB available)"
    fi

    # Check for essential build tools
    REQUIRED_TOOLS=("gcc" "make" "wget")
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_warning "Required build tool missing: $tool (will be installed)"
        fi
    done

    # Check internet connectivity with multiple fallbacks
    log "Testing internet connectivity..."
    CONNECTIVITY_OK=false

    # Test multiple sites to ensure it's not just one site being down
    TEST_URLS=("https://www.python.org" "https://github.com" "https://google.com")

    for url in "${TEST_URLS[@]}"; do
        if wget -q --spider --timeout=5 "$url" 2>/dev/null; then
            log "Internet connectivity check: OK (via $(echo $url | cut -d'/' -f3))"
            CONNECTIVITY_OK=true
            break
        fi
    done

    if [[ "$CONNECTIVITY_OK" == "false" ]]; then
        log_warning "No internet connection detected"
        log_warning "This may be due to:"
        log_warning "  - No internet access"
        log_warning "  - Firewall blocking connections"
        log_warning "  - DNS resolution issues"
        echo
        read -p "Continue anyway? You may need to provide Python source manually (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Installation cancelled due to connectivity issues"
            exit 1
        fi
        log_warning "Continuing without internet connectivity verification..."
    fi

    if [[ "$requirements_met" == "false" ]]; then
        log_error "System requirements not met for Python compilation"
        exit 1
    fi

    log "System compatibility check passed"
}

# Check Python version
check_python() {
    log_info "Checking Python installation..."

    # Check if Python 3.12 is already installed
    if command -v python3.12 &> /dev/null; then
        CURRENT_PYTHON_VERSION=$(python3.12 --version | cut -d' ' -f2)
        log "Python 3.12 found: $CURRENT_PYTHON_VERSION"
        PYTHON_CMD="python3.12"
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
        # Check if system python is 3.8+ (minimum for Bell News)
        elif python3 -c "import sys; exit(0 if sys.version_info >= (3, 8) else 1)" 2>/dev/null; then
            log_warning "System Python $SYSTEM_PYTHON_VERSION is older than 3.12 but may work"
            read -p "Use system Python $SYSTEM_PYTHON_VERSION instead of compiling 3.12? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log "Using system Python $SYSTEM_PYTHON_VERSION"
                PYTHON_CMD="python3"
                PYTHON_INSTALLED=true
                return 0
            fi
        fi
    fi

    # Check if we're in an environment where Python compilation might fail
    if [[ $(free -m | awk 'NR==2{print $2}') -lt 1000 ]]; then
        log_warning "Low memory system detected. Python compilation may fail."
        log_warning "Consider using system Python if available."
    fi

    log_warning "Python 3.12 not found. Will compile from source."
    log_warning "This requires internet access and may take 15-30 minutes."
    PYTHON_INSTALLED=false
}

# Install system dependencies (optimized)
install_system_deps() {
    log_info "Installing system dependencies (optimized)..."

    # Update package lists with network error handling
    if [[ ! -f /var/cache/apt/pkgcache.bin ]] || [[ $(find /var/cache/apt/pkgcache.bin -mmin +60 2>/dev/null) ]]; then
        log "Updating package lists..."
        if ! apt-get update -qq 2>/dev/null; then
            log_warning "Package list update failed (network issue?)"
            log_warning "Continuing with existing package cache..."
        fi
    else
        log "Package lists are recent, skipping update"
    fi

    # Essential build tools for Python compilation (ordered by importance)
    CRITICAL_DEPS=(
        "build-essential"
        "libssl-dev"
        "zlib1g-dev"
        "libffi-dev"
        "libsqlite3-dev"
        "wget"
        "curl"
        "make"
        "gcc"
    )

    IMPORTANT_DEPS=(
        "libncurses5-dev"
        "libbz2-dev"
        "libreadline-dev"
        "libgdbm-dev"
        "liblzma-dev"
        "libexpat1-dev"
        "tk-dev"
        "git"
    )

    OPTIONAL_DEPS=(
        "libmpdec-dev"
        "uuid-dev"
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

    # Pygame-specific dependencies for ARM systems
    PYGAME_DEPS=(
        "libsdl2-dev"
        "libsdl2-image-dev"
        "libsdl2-mixer-dev"
        "libsdl2-ttf-dev"
        "libfreetype6-dev"
        "libportmidi-dev"
        "libavformat-dev"
        "libavcodec-dev"
        "libswscale-dev"
        "libsmpeg-dev"
        "libjpeg-dev"
        "libpng-dev"
        "libx11-dev"
        "libxext-dev"
        "libxrandr-dev"
        "libxinerama-dev"
        "libxi-dev"
        "libxss-dev"
        "libxcursor-dev"
        "libxfixes-dev"
        "libxrender-dev"
        "libxdamage-dev"
    )

    # Install packages in priority order
    log "Installing system packages in priority order..."

    # Install critical dependencies first (must succeed)
    log "Installing critical build dependencies..."
    for package in "${CRITICAL_DEPS[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            log_info "Installing critical package: $package"
            if ! apt-get install -y "$package" -qq; then
                log_error "Failed to install critical package: $package"
                log_error "Python compilation will likely fail without this package"
                exit 1
            fi
        else
            log_info "$package already installed"
        fi
    done

    # Install important dependencies (retry on failure)
    log "Installing important build dependencies..."
    for package in "${IMPORTANT_DEPS[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            log_info "Installing important package: $package"
            for attempt in {1..2}; do
                if apt-get install -y "$package" -qq; then
                    break
                else
                    log_warning "Attempt $attempt failed for $package, retrying..."
                    sleep 1
                fi

                if [[ $attempt -eq 2 ]]; then
                    log_warning "Failed to install $package (Python may still compile)"
                fi
            done
        else
            log_info "$package already installed"
        fi
    done

    # Install optional dependencies (warn on failure)
    log "Installing optional build dependencies..."
    for package in "${OPTIONAL_DEPS[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            log_info "Installing optional package: $package"
            if ! apt-get install -y "$package" -qq 2>/dev/null; then
                log_warning "Failed to install optional $package (not available on this OS version)"
            fi
        else
            log_info "$package already installed"
        fi
    done

    # Install system dependencies for Bell News
    log "Installing Bell News system dependencies..."
    for package in "${SYSTEM_DEPS[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            log_info "Installing system package: $package"
            if ! apt-get install -y "$package" -qq; then
                log_warning "Failed to install $package (may affect Bell News functionality)"
            fi
        else
            log_info "$package already installed"
        fi
    done

    # Install pygame-specific dependencies
    log "Installing pygame dependencies for ARM systems..."
    PYGAME_CRITICAL=true
    for package in "${PYGAME_DEPS[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            log_info "Installing pygame dependency: $package"
            if ! apt-get install -y "$package" -qq 2>/dev/null; then
                log_warning "Failed to install $package (pygame may need compilation)"
                if [[ "$package" == "libsdl2-dev" || "$package" == "libfreetype6-dev" ]]; then
                    PYGAME_CRITICAL=false
                fi
            fi
        else
            log_info "$package already installed"
        fi
    done

    if [[ "$PYGAME_CRITICAL" == "false" ]]; then
        log_warning "Some critical pygame dependencies failed to install"
        log_warning "Pygame will require compilation from source"
    else
        log "All pygame dependencies installed successfully"
    fi

    log "System dependencies installed successfully"
}

# Compile and install Python 3.12 (reliable)
install_python312() {
    if [[ "$PYTHON_INSTALLED" == "true" ]]; then
        log "Python 3.12+ already available, skipping compilation"
        return 0
    fi

    log_info "Compiling Python $PYTHON_VERSION from source (reliable build)..."

    # Create source directory
    mkdir -p /usr/src
    cd /usr/src

    # Download Python source with multiple mirrors
    PYTHON_TAR="Python-${PYTHON_VERSION}.tgz"

    # Multiple download mirrors for reliability
    PYTHON_URLS=(
        "https://www.python.org/ftp/python/${PYTHON_VERSION}/${PYTHON_TAR}"
        "https://github.com/python/cpython/archive/refs/tags/v${PYTHON_VERSION}.tar.gz"
        "https://files.pythonhosted.org/packages/source/P/Python/${PYTHON_TAR}"
    )

    if [[ ! -f "$PYTHON_TAR" ]]; then
        log "Downloading Python $PYTHON_VERSION..."

        DOWNLOAD_SUCCESS=false
        for url in "${PYTHON_URLS[@]}"; do
            log_info "Trying mirror: $(echo $url | cut -d'/' -f3)"

            if wget -q --show-progress --tries=2 --timeout=30 "$url" -O "$PYTHON_TAR" 2>/dev/null; then
                log "Download successful from $(echo $url | cut -d'/' -f3)"
                DOWNLOAD_SUCCESS=true
                break
            else
                log_warning "Failed to download from $(echo $url | cut -d'/' -f3)"
                rm -f "$PYTHON_TAR" 2>/dev/null
            fi
        done

        if [[ "$DOWNLOAD_SUCCESS" == "false" ]]; then
            log_error "Failed to download Python source from all mirrors"
            log_error "Please check your internet connection and try again"
            log_error "Or manually download ${PYTHON_TAR} to /usr/src/ and re-run installer"
            exit 1
        fi

        # Verify download
        if [[ ! -s "$PYTHON_TAR" ]]; then
            log_error "Downloaded file is empty or corrupted"
            rm -f "$PYTHON_TAR"
            exit 1
        fi

        log "Python source downloaded successfully ($(du -h "$PYTHON_TAR" | cut -f1))"
    else
        log "Python source already exists, skipping download"
    fi

    # Extract source with error handling
    log "Extracting Python source..."

    if ! tar -xzf "$PYTHON_TAR" 2>/dev/null; then
        log_error "Failed to extract Python source archive"
        log_error "The downloaded file may be corrupted"
        rm -f "$PYTHON_TAR"
        log_error "Please run the installer again to re-download"
        exit 1
    fi

    # Handle different archive structures
    if [[ -d "Python-${PYTHON_VERSION}" ]]; then
        cd "Python-${PYTHON_VERSION}"
        log "Entered Python source directory"
    elif [[ -d "cpython-${PYTHON_VERSION}" ]]; then
        cd "cpython-${PYTHON_VERSION}"
        log "Entered Python source directory (GitHub archive)"
    else
        log_error "Could not find Python source directory after extraction"
        ls -la
        exit 1
    fi

    # Configure build with multiple fallback options
    log "Configuring Python build..."

    # Try configurations in order of preference (most reliable first)
    if ./configure \
        --enable-shared \
        --enable-loadable-sqlite-extensions \
        --with-system-expat \
        --enable-ipv6 \
        --quiet >/dev/null 2>&1; then
        log "Configuration successful: standard build"
        BUILD_TYPE="standard"
    elif ./configure \
        --enable-shared \
        --enable-loadable-sqlite-extensions \
        --quiet >/dev/null 2>&1; then
        log "Configuration successful: minimal build"
        BUILD_TYPE="minimal"
    elif ./configure \
        --quiet >/dev/null 2>&1; then
        log "Configuration successful: basic build"
        BUILD_TYPE="basic"
    else
        log_error "All Python configure attempts failed"
        log_error "This may be due to missing dependencies or unsupported system"
        exit 1
    fi

    # Determine optimal build settings
    CORES=$(nproc)
    if [[ $CORES -gt 4 ]]; then
        # Use fewer cores on high-core systems to prevent memory issues
        BUILD_CORES=$((CORES / 2))
    elif [[ $CORES -gt 1 ]]; then
        BUILD_CORES=$((CORES - 1))
    else
        BUILD_CORES=1
    fi

    log "Starting Python compilation with $BUILD_CORES cores ($BUILD_TYPE configuration)..."
    log "This may take 10-30 minutes depending on your system..."

    # Build with error handling and progress tracking
    (
        # Use standard make instead of build_all for better compatibility
        make -j"$BUILD_CORES" > /tmp/python_build.log 2>&1 &
        BUILD_PID=$!

        # Progress indicator with time tracking
        START_TIME=$(date +%s)
        while kill -0 $BUILD_PID 2>/dev/null; do
            CURRENT_TIME=$(date +%s)
            ELAPSED=$((CURRENT_TIME - START_TIME))
            echo -n "."

            # Show elapsed time every minute
            if [[ $((ELAPSED % 60)) -eq 0 ]] && [[ $ELAPSED -gt 0 ]]; then
                echo " (${ELAPSED}s)"
            fi
            sleep 10
        done

        wait $BUILD_PID
        BUILD_EXIT_CODE=$?

        TOTAL_TIME=$(($(date +%s) - START_TIME))
        echo
        log "Build completed in ${TOTAL_TIME} seconds"

        exit $BUILD_EXIT_CODE
    ) || {
        log_error "Python compilation failed!"
        log_error "Build log saved to: /tmp/python_build.log"

        # Show last few lines of build log for debugging
        if [[ -f /tmp/python_build.log ]]; then
            log_error "Last 10 lines of build log:"
            tail -10 /tmp/python_build.log | while read line; do
                log_error "  $line"
            done
        fi

        # Try single-core build as fallback
        log_warning "Attempting single-core build as fallback..."
        if make -j1 > /tmp/python_build_fallback.log 2>&1; then
            log "Single-core build succeeded!"
        else
            log_error "Single-core build also failed. Check /tmp/python_build_fallback.log"
            exit 1
        fi
    }

    log "Python compilation completed successfully"

    # Install Python
    log "Installing Python 3.12..."
    if ! make altinstall > /tmp/python_install.log 2>&1; then
        log_error "Python installation failed!"
        log_error "Install log saved to: /tmp/python_install.log"

        if [[ -f /tmp/python_install.log ]]; then
            log_error "Last 5 lines of install log:"
            tail -5 /tmp/python_install.log | while read line; do
                log_error "  $line"
            done
        fi
        exit 1
    fi

    # Update shared library cache
    ldconfig

    # Verify installation
    if command -v python3.12 &> /dev/null; then
        INSTALLED_VERSION=$(python3.12 --version)
        log "Python installation successful: $INSTALLED_VERSION"

        # Test basic functionality
        if python3.12 -c "import sys; print('Python test successful')" >/dev/null 2>&1; then
            log "Python functionality test passed"
        else
            log_warning "Python installed but basic test failed"
        fi

        # Create symlinks for convenience
        ln -sf /usr/local/bin/python3.12 /usr/local/bin/python3
        ln -sf /usr/local/bin/pip3.12 /usr/local/bin/pip3
        log "Created Python symlinks"

    else
        log_error "Python installation verification failed"
        log_error "python3.12 command not found in PATH"
        exit 1
    fi

    # Cleanup build files
    log "Cleaning up build files..."
    cd /
    rm -rf "/usr/src/Python-${PYTHON_VERSION}" "/usr/src/${PYTHON_TAR}"

    log "Python 3.12 installation completed successfully!"
}

# Intelligent pygame installation for ARM systems
install_pygame_intelligent() {
    log_info "Installing pygame with intelligent ARM-optimized methods..."

    # Method 1: Try standard pip installation first
    log "Method 1: Attempting standard pip installation..."
    if $PYTHON_CMD -m pip install --no-cache-dir pygame>=2.1.0 --no-warn-script-location 2>/dev/null; then
        if $PYTHON_CMD -c "import pygame; pygame.mixer.init(); print('pygame test successful')" 2>/dev/null; then
            log "✅ Pygame installed successfully via pip"
            return 0
        else
            log_warning "Pygame installed but failed functionality test"
            $PYTHON_CMD -m pip uninstall -y pygame 2>/dev/null
        fi
    fi

    # Method 2: Try with pre-compiled wheels for ARM
    log "Method 2: Trying ARM-specific wheels..."
    ARM_WHEELS=(
        "https://www.piwheels.org/simple/pygame/pygame-2.1.2-cp310-cp310-linux_armv7l.whl"
        "https://files.pythonhosted.org/packages/pygame"
    )

    for wheel_url in "${ARM_WHEELS[@]}"; do
        log_info "Trying wheel: $(basename $wheel_url)"
        if $PYTHON_CMD -m pip install --no-cache-dir "$wheel_url" --no-warn-script-location 2>/dev/null; then
            if $PYTHON_CMD -c "import pygame; print('pygame wheel test successful')" 2>/dev/null; then
                log "✅ Pygame installed successfully from ARM wheel"
                return 0
            else
                $PYTHON_CMD -m pip uninstall -y pygame 2>/dev/null
            fi
        fi
    done

    # Method 3: Install with specific flags for ARM
    log "Method 3: Installing with ARM-specific compiler flags..."
    export SDL_VIDEODRIVER=dummy
    export PYGAME_HIDE_SUPPORT_PROMPT=1

    if $PYTHON_CMD -m pip install --no-cache-dir --no-binary pygame pygame>=2.1.0 --no-warn-script-location 2>/dev/null; then
        if $PYTHON_CMD -c "import pygame; print('pygame compiled successfully')" 2>/dev/null; then
            log "✅ Pygame compiled and installed successfully"
            return 0
        else
            $PYTHON_CMD -m pip uninstall -y pygame 2>/dev/null
        fi
    fi

    # Method 4: Compile from source with custom configuration
    log "Method 4: Compiling pygame from source with custom ARM configuration..."

    # Create temporary build directory
    PYGAME_BUILD_DIR="/tmp/pygame_build_$$"
    mkdir -p "$PYGAME_BUILD_DIR"
    cd "$PYGAME_BUILD_DIR"

    # Download pygame source
    if wget -q --timeout=30 https://github.com/pygame/pygame/archive/refs/tags/2.1.2.tar.gz -O pygame-2.1.2.tar.gz; then
        tar -xzf pygame-2.1.2.tar.gz
        cd pygame-2.1.2

        # Create custom Setup file for ARM
        cat > Setup << 'EOF'
# Custom pygame Setup for ARM systems
_freetype freetype/ft_wrap.c $(SDL_TTF) $(FREETYPE)
_camera src_c/camera_v4l2.c $(SDL) $(DEBUG)
mixer src_c/mixer.c $(SDL_MIXER) $(SDL) $(DEBUG)
font src_c/font.c $(SDL_TTF) $(SDL) $(FREETYPE) $(DEBUG)
surface src_c/surface.c src_c/alphablit.c src_c/surface_fill.c $(SDL) $(DEBUG)
mixer_music src_c/music.c $(SDL_MIXER) $(SDL) $(DEBUG)
EOF

        # Build with custom configuration
        export CFLAGS="-O2 -march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard"
        export PYGAME_HIDE_SUPPORT_PROMPT=1

        if $PYTHON_CMD setup.py build 2>/tmp/pygame_build.log && $PYTHON_CMD setup.py install 2>>/tmp/pygame_build.log; then
            if $PYTHON_CMD -c "import pygame; print('pygame source build successful')" 2>/dev/null; then
                log "✅ Pygame compiled from source successfully"
                cd /
                rm -rf "$PYGAME_BUILD_DIR"
                return 0
            fi
        fi

        log_warning "Source compilation failed, check /tmp/pygame_build.log"
    fi

    cd /
    rm -rf "$PYGAME_BUILD_DIR"

    # Method 5: Install system package as last resort
    log "Method 5: Trying system package python3-pygame..."
    if apt-get install -y python3-pygame -qq 2>/dev/null; then
        if $PYTHON_CMD -c "import pygame; print('system pygame successful')" 2>/dev/null; then
            log "✅ Pygame installed via system package"
            return 0
        fi
    fi

    # Method 6: Install minimal pygame (audio-only)
    log "Method 6: Installing minimal pygame for audio functionality..."
    if $PYTHON_CMD -m pip install --no-cache-dir pygame-ce>=2.1.0 --no-warn-script-location 2>/dev/null; then
        if $PYTHON_CMD -c "import pygame; pygame.mixer.init(); print('pygame-ce successful')" 2>/dev/null; then
            log "✅ Pygame Community Edition installed successfully"
            return 0
        fi
    fi

    log_error "❌ All pygame installation methods failed"
    return 1
}

# Install Python dependencies (optimized)
install_python_deps() {
    log_info "Installing Python dependencies (optimized)..."

    # Upgrade pip first with optimizations
    $PYTHON_CMD -m pip install --upgrade --no-cache-dir pip setuptools wheel

    # Core dependencies (excluding pygame - handled separately)
    CORE_DEPS=(
        "flask>=2.0.0"
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
    GPIO_DEPS=()
    case "$BOARD_TYPE" in
        "NanoPi"|"Orange Pi")
            GPIO_DEPS+=("OPi.GPIO>=0.4.0")
            ;;
        "Raspberry Pi")
            GPIO_DEPS+=("RPi.GPIO>=0.7.0")
            ;;
        *)
            log_warning "Unknown board type, installing both GPIO libraries"
            GPIO_DEPS+=("OPi.GPIO>=0.4.0" "RPi.GPIO>=0.7.0")
            ;;
    esac

    # Install core dependencies first
    log "Installing core Python packages..."
    if ! $PYTHON_CMD -m pip install --no-cache-dir --no-warn-script-location "${CORE_DEPS[@]}" 2>/dev/null; then
        log_warning "Batch installation failed, installing individually..."

        # Install core dependencies individually
        for package in "${CORE_DEPS[@]}"; do
            log_info "Installing core package: $package"
            for attempt in {1..2}; do
                if $PYTHON_CMD -m pip install --no-cache-dir "$package" --no-warn-script-location 2>/dev/null; then
                    break
                else
                    log_warning "Attempt $attempt failed for $package, retrying..."
                    sleep 1
                fi

                if [[ $attempt -eq 2 ]]; then
                    log_error "Failed to install critical package: $package"
                fi
            done
        done
    else
        log "Core packages installed successfully"
    fi

    # Install GPIO libraries
    log "Installing GPIO libraries..."
    for package in "${GPIO_DEPS[@]}"; do
        log_info "Installing GPIO package: $package"
        if ! $PYTHON_CMD -m pip install --no-cache-dir "$package" --no-warn-script-location 2>/dev/null; then
            log_warning "Failed to install $package (GPIO functionality may be limited)"
        fi
    done

    # Install pygame with intelligent methods
    if ! install_pygame_intelligent; then
        log_error "❌ Pygame installation failed with all automated methods"
        log_warning "Bell News requires pygame for audio functionality"
        echo
        log_warning "An emergency pygame fix script has been created: emergency_pygame_fix.sh"
        log_warning "You can run it manually after installation completes"
        echo
        read -p "Continue installation without pygame? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_warning "Continuing installation without pygame (audio will not work)"
            PYGAME_INSTALLED=false
        else
            log_error "Installation cancelled. Fix pygame and try again."
            exit 1
        fi
    else
        PYGAME_INSTALLED=true
    fi

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

    # Test core Python modules
    CORE_MODULES=("flask" "psutil" "pytz" "requests")
    for module in "${CORE_MODULES[@]}"; do
        if ! $PYTHON_CMD -c "import $module" 2>/dev/null; then
            log_error "Core module test failed: $module"
            return 1
        fi
    done
    log "Core modules test: PASSED"

    # Test pygame specifically with detailed diagnostics
    log_info "Testing pygame installation..."
    if $PYTHON_CMD -c "import pygame; print('Pygame import: OK')" 2>/dev/null; then
        log "✅ Pygame import test: PASSED"

        # Test pygame mixer (critical for Bell News)
        if $PYTHON_CMD -c "import pygame; pygame.mixer.init(); print('Pygame mixer: OK'); pygame.mixer.quit()" 2>/dev/null; then
            log "✅ Pygame mixer test: PASSED"
        else
            log_warning "Pygame mixer test failed (audio may not work)"
        fi

        # Test pygame display (less critical)
        if $PYTHON_CMD -c "import pygame; import os; os.environ['SDL_VIDEODRIVER']='dummy'; pygame.display.init(); print('Pygame display: OK'); pygame.display.quit()" 2>/dev/null; then
            log "✅ Pygame display test: PASSED"
        else
            log_warning "Pygame display test failed (visual features may be limited)"
        fi

    else
        log_error "❌ CRITICAL: Pygame import test failed"
        log_error "This should not happen after intelligent installation"
        return 1
    fi

    # Test GPIO libraries (board-specific)
    GPIO_AVAILABLE=false
    case "$BOARD_TYPE" in
        "NanoPi"|"Orange Pi")
            if $PYTHON_CMD -c "import OPi.GPIO; print('OPi.GPIO available')" 2>/dev/null; then
                GPIO_AVAILABLE=true
                log "✅ OPi.GPIO test: PASSED"
            else
                log_warning "OPi.GPIO not available (hardware control limited)"
            fi
            ;;
        "Raspberry Pi")
            if $PYTHON_CMD -c "import RPi.GPIO; print('RPi.GPIO available')" 2>/dev/null; then
                GPIO_AVAILABLE=true
                log "✅ RPi.GPIO test: PASSED"
            else
                log_warning "RPi.GPIO not available (hardware control limited)"
            fi
            ;;
        *)
            if $PYTHON_CMD -c "import OPi.GPIO" 2>/dev/null; then
                GPIO_AVAILABLE=true
                log "✅ OPi.GPIO test: PASSED"
            elif $PYTHON_CMD -c "import RPi.GPIO" 2>/dev/null; then
                GPIO_AVAILABLE=true
                log "✅ RPi.GPIO test: PASSED"
            else
                log_warning "No GPIO libraries available (hardware control disabled)"
            fi
            ;;
    esac

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

    # Check for running processes first
    if check_running_processes; then
        echo
        log_warning "Bell News is currently running. A clean installation requires stopping all processes."
        read -p "Stop all Bell News processes and continue? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            stop_existing_processes
            clean_existing_installation
        else
            log_error "Installation cancelled by user"
            exit 1
        fi
    fi

    detect_system
    check_build_requirements
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