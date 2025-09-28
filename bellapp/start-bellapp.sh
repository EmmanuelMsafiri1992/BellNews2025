#!/bin/bash

# ╔══════════════════════════════════════════════════════════════╗
# ║                 BELLAPP NATIVE STARTUP SCRIPT               ║
# ║        Auto-setup and start with IP switching support       ║
# ╚══════════════════════════════════════════════════════════════╝

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BELLAPP_DIR="$SCRIPT_DIR"
VENV_DIR="$BELLAPP_DIR/venv"
CONFIG_SERVICE_PATH="$PROJECT_ROOT/ubuntu_config_service.py"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                 BELLAPP NATIVE LAUNCHER                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if port is available
port_available() {
    ! nc -z localhost "$1" 2>/dev/null
}

# Function to wait for service to be ready
wait_for_service() {
    local port=$1
    local service_name=$2
    local max_attempts=30
    local attempt=0

    echo "[INFO] Waiting for $service_name to be ready on port $port..."
    while [ $attempt -lt $max_attempts ]; do
        if nc -z localhost "$port" 2>/dev/null; then
            echo "[SUCCESS] $service_name is ready!"
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
        echo -n "."
    done
    echo "[WARNING] $service_name may not be fully ready, but continuing..."
    return 1
}

echo "[STEP 1/6] Checking system dependencies..."

# Install system dependencies if missing
if ! command_exists python3; then
    echo "[INFO] Installing Python3..."
    sudo apt update
    sudo apt install -y python3 python3-pip python3-venv python3-dev
else
    # Check if python3-venv is installed
    if ! python3 -c "import venv" 2>/dev/null; then
        echo "[INFO] Installing python3-venv..."
        sudo apt install -y python3-venv
    fi
fi

if ! command_exists nc; then
    echo "[INFO] Installing netcat for port checking..."
    sudo apt install -y netcat-openbsd
fi

# Check network management system (netplan vs ifupdown)
if command_exists netplan; then
    echo "[INFO] Netplan detected for network management"
    NETWORK_MANAGER="netplan"
elif [ -f "/etc/network/interfaces" ]; then
    echo "[INFO] Using traditional /etc/network/interfaces for network management"
    NETWORK_MANAGER="interfaces"
    # Install network tools if missing
    if ! command_exists ifconfig; then
        echo "[INFO] Installing network tools..."
        sudo apt install -y net-tools ifupdown
    fi
else
    echo "[WARNING] No recognized network management system found"
    echo "[INFO] Will attempt to use basic network tools"
    NETWORK_MANAGER="basic"
    sudo apt install -y net-tools || true
fi

echo "[SUCCESS] System dependencies verified"

echo "[STEP 2/6] Setting up Python virtual environment..."

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    echo "[INFO] Creating Python virtual environment..."
    python3 -m venv "$VENV_DIR"
fi

# Activate virtual environment
source "$VENV_DIR/bin/activate"

# Install Python requirements
if [ -f "$BELLAPP_DIR/requirements.txt" ]; then
    echo "[INFO] Installing Python requirements..."
    pip install --upgrade pip
    pip install -r "$BELLAPP_DIR/requirements.txt"

    # Install additional requirements for config service
    pip install flask pyyaml psutil requests gunicorn
else
    echo "[WARNING] requirements.txt not found, installing basic dependencies..."
    pip install flask psutil requests pyyaml gunicorn
fi

echo "[SUCCESS] Python environment ready"

echo "[STEP 3/6] Starting Ubuntu Config Service..."

# Check if config service is already running
if port_available 5002; then
    if [ -f "$CONFIG_SERVICE_PATH" ]; then
        echo "[INFO] Starting Ubuntu Config Service on port 5002..."
        cd "$PROJECT_ROOT"

        # Set environment for real operations (not test mode)
        export IN_DOCKER_TEST_MODE=false
        export NETWORK_MANAGER="$NETWORK_MANAGER"

        # Start config service in background with proper logging
        nohup sudo -E python3 "$CONFIG_SERVICE_PATH" > config_service.log 2>&1 &
        CONFIG_SERVICE_PID=$!
        echo $CONFIG_SERVICE_PID > config_service.pid

        # Wait for config service to be ready
        wait_for_service 5002 "Config Service"
        echo "[SUCCESS] Config Service started (PID: $CONFIG_SERVICE_PID)"
    else
        echo "[WARNING] Config service file not found at $CONFIG_SERVICE_PATH"
        echo "[INFO] IP switching may not work without config service"
    fi
else
    echo "[INFO] Config Service already running on port 5002"
fi

echo "[STEP 4/6] Configuring environment..."

# Set environment variables
export UBUNTU_CONFIG_SERVICE_URL=http://localhost:5002
export FLASK_ENV=production
export FLASK_DEBUG=false

# Create .env file for persistent configuration
cat > "$BELLAPP_DIR/.env" << EOF
UBUNTU_CONFIG_SERVICE_URL=http://localhost:5002
FLASK_ENV=production
FLASK_DEBUG=false
IN_DOCKER_TEST_MODE=false
NETWORK_MANAGER=$NETWORK_MANAGER
EOF

echo "[SUCCESS] Environment configured"

echo "[STEP 5/6] Checking bellapp port availability..."

if ! port_available 5000; then
    echo "[WARNING] Port 5000 is already in use"
    echo "[INFO] Attempting to stop existing bellapp processes..."

    # Try to kill existing processes on port 5000
    sudo fuser -k 5000/tcp 2>/dev/null || true
    sleep 2

    if ! port_available 5000; then
        echo "[ERROR] Could not free port 5000. Please manually stop the service using it."
        exit 1
    fi
fi

echo "[STEP 6/6] Starting BellApp..."

cd "$BELLAPP_DIR"
source "$VENV_DIR/bin/activate"

# Create startup log
STARTUP_LOG="$BELLAPP_DIR/startup.log"
echo "$(date): BellApp starting..." > "$STARTUP_LOG"

echo "[INFO] BellApp will run on http://0.0.0.0:5000"
echo "[INFO] Config Service available on http://localhost:5002"
echo "[INFO] IP switching functionality: ENABLED"
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    BELLAPP IS STARTING                       ║"
echo "║                                                              ║"
echo "║  Web Interface: http://your-nanopi-ip:5000                   ║"
echo "║  Config Service: http://localhost:5002                       ║"
echo "║                                                              ║"
echo "║  Features Available:                                         ║"
echo "║  ✓ Static/Dynamic IP switching                              ║"
echo "║  ✓ Network configuration management                          ║"
echo "║  ✓ Time synchronization                                     ║"
echo "║  ✓ System monitoring                                        ║"
echo "║                                                              ║"
echo "║  Press Ctrl+C to stop all services                          ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# Function to cleanup on exit
cleanup() {
    echo ""
    echo "[INFO] Shutting down services..."

    # Kill config service if we started it
    if [ -f "$PROJECT_ROOT/config_service.pid" ]; then
        CONFIG_PID=$(cat "$PROJECT_ROOT/config_service.pid")
        sudo kill "$CONFIG_PID" 2>/dev/null || true
        rm -f "$PROJECT_ROOT/config_service.pid"
        echo "[INFO] Config service stopped"
    fi

    echo "[INFO] BellApp stopped"
    echo "$(date): BellApp stopped" >> "$STARTUP_LOG"
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Start the main application
if [ -f "$BELLAPP_DIR/main.py" ]; then
    # Start with gunicorn for better performance
    if command_exists gunicorn; then
        echo "[INFO] Starting with Gunicorn (production mode)..."
        gunicorn -w 2 -b 0.0.0.0:5000 --timeout 120 --access-logfile access.log --error-logfile error.log main:app
    else
        echo "[INFO] Starting with Python directly..."
        python3 main.py
    fi
else
    echo "[ERROR] main.py not found in $BELLAPP_DIR"
    exit 1
fi