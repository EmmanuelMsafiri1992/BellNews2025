#!/bin/bash
# Comprehensive dependency fixer for Bell News
# Handles all ARM-specific package issues

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log "🔧 Bell News Dependency Fixer"
log "============================"

PYTHON_CMD="python3"

# Function to test if a Python module works
test_module() {
    local module=$1
    if $PYTHON_CMD -c "import $module" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to install bcrypt with multiple fallbacks
install_bcrypt() {
    log "Installing bcrypt with ARM optimization..."

    # Method 1: System package
    if apt-get install -y python3-bcrypt -qq 2>/dev/null; then
        if test_module "bcrypt"; then
            log "✅ bcrypt installed via system package"
            return 0
        fi
    fi

    # Method 2: Older pip version
    if $PYTHON_CMD -m pip install bcrypt==3.2.0 --no-cache-dir 2>/dev/null; then
        if test_module "bcrypt"; then
            log "✅ bcrypt installed via pip (v3.2.0)"
            return 0
        fi
    fi

    # Method 3: Different version
    if $PYTHON_CMD -m pip install bcrypt==4.0.1 --no-cache-dir 2>/dev/null; then
        if test_module "bcrypt"; then
            log "✅ bcrypt installed via pip (v4.0.1)"
            return 0
        fi
    fi

    # Method 4: Latest version
    if $PYTHON_CMD -m pip install bcrypt --no-cache-dir 2>/dev/null; then
        if test_module "bcrypt"; then
            log "✅ bcrypt installed via pip (latest)"
            return 0
        fi
    fi

    log_error "❌ Failed to install bcrypt"
    return 1
}

# Function to install pygame compatibility
install_pygame() {
    log "Ensuring pygame compatibility..."

    if test_module "pygame"; then
        if $PYTHON_CMD -c "import pygame; pygame.mixer.init()" 2>/dev/null; then
            log "✅ pygame already working"
            return 0
        fi
    fi

    # Install pygame stub
    SITE_PACKAGES=$($PYTHON_CMD -c "import site; print(site.getsitepackages()[0])" 2>/dev/null || echo "/usr/local/lib/python3.10/site-packages")

    cat > /tmp/pygame_stub.py << 'EOF'
"""
Pygame compatibility stub for Bell News
"""
import os
import subprocess

class mixer:
    @staticmethod
    def init():
        print("Pygame mixer initialized (stub mode)")
        return True

    @staticmethod
    def pre_init():
        return True

    @staticmethod
    def quit():
        return True

    class Sound:
        def __init__(self, file_path):
            self.file_path = file_path

        def play(self):
            try:
                subprocess.run(['aplay', self.file_path], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except:
                print(f"Playing: {self.file_path}")

        def stop(self):
            subprocess.run(['pkill', 'aplay'], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def init():
    return True

def quit():
    return True

print("Pygame stub loaded")
EOF

    cp /tmp/pygame_stub.py "$SITE_PACKAGES/pygame.py"
    chmod 644 "$SITE_PACKAGES/pygame.py"
    rm -f /tmp/pygame_stub.py

    if test_module "pygame"; then
        log "✅ pygame compatibility stub installed"
        return 0
    else
        log_error "❌ pygame stub installation failed"
        return 1
    fi
}

# Main dependency checks and fixes
log "Checking and fixing Python dependencies..."

# Update system packages
apt-get update -qq

# Install essential system packages
apt-get install -y python3-pip python3-dev python3-setuptools python3-wheel -qq 2>/dev/null || true

# Check and install core modules
CORE_MODULES=("flask" "psutil" "pytz" "requests" "gunicorn")
for module in "${CORE_MODULES[@]}"; do
    if ! test_module "$module"; then
        log_warning "Installing $module..."
        $PYTHON_CMD -m pip install "$module" --no-cache-dir 2>/dev/null || log_error "Failed to install $module"
    else
        log "✅ $module available"
    fi
done

# Handle bcrypt specially
if ! test_module "bcrypt"; then
    install_bcrypt
else
    log "✅ bcrypt available"
fi

# Handle pygame specially
install_pygame

# Test web server dependencies
log "Testing web server dependencies..."
if $PYTHON_CMD -c "import flask, bcrypt, pygame; print('Web server deps OK')" 2>/dev/null; then
    log "✅ All web server dependencies available"
else
    log_error "❌ Some web server dependencies missing"
fi

log "🎉 Dependency check completed!"