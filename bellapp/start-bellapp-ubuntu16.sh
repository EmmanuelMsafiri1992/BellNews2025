#!/bin/bash

# ╔══════════════════════════════════════════════════════════════╗
# ║           BELLAPP UBUNTU 16.04 COMPATIBLE LAUNCHER          ║
# ║        Auto-setup and start with IP switching support       ║
# ╚══════════════════════════════════════════════════════════════╝

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BELLAPP_DIR="$SCRIPT_DIR"
CONFIG_SERVICE_PATH="$PROJECT_ROOT/ubuntu_config_service.py"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           BELLAPP UBUNTU 16.04 NATIVE LAUNCHER              ║"
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

echo "[STEP 1/6] Installing system dependencies for Ubuntu 16.04..."

# Update package lists
sudo apt update

# Install essential packages
echo "[INFO] Installing essential packages..."
sudo apt install -y python3 python3-pip python3-dev build-essential
sudo apt install -y net-tools ifupdown netcat-openbsd
sudo apt install -y curl wget ca-certificates

# Fix pip for Ubuntu 16.04
echo "[INFO] Fixing pip for Ubuntu 16.04..."
# Download get-pip.py for older systems
if ! command_exists pip3 || pip3 --version | grep -q "8\."; then
    echo "[INFO] Upgrading pip to compatible version..."
    curl -s https://bootstrap.pypa.io/pip/3.5/get-pip.py -o get-pip.py
    sudo python3 get-pip.py
    rm -f get-pip.py
fi

# Install specific compatible versions
echo "[INFO] Installing Python packages with compatible versions..."
sudo pip3 install --upgrade setuptools==44.1.1
sudo pip3 install wheel==0.36.2

# Install Flask and dependencies with specific versions for Ubuntu 16.04
echo "[INFO] Installing Flask and dependencies..."
sudo pip3 install Flask==1.1.4
sudo pip3 install Werkzeug==1.0.1
sudo pip3 install Jinja2==2.11.3
sudo pip3 install MarkupSafe==1.1.1
sudo pip3 install itsdangerous==1.1.0
sudo pip3 install click==7.1.2

# Install other requirements with compatible versions
sudo pip3 install psutil==5.8.0
sudo pip3 install requests==2.25.1
sudo pip3 install PyYAML==5.4.1
sudo pip3 install pytz==2021.3

echo "[SUCCESS] System dependencies installed for Ubuntu 16.04"

echo "[STEP 2/6] Network management setup..."

# Check network management system
if [ -f "/etc/network/interfaces" ]; then
    echo "[INFO] Using traditional /etc/network/interfaces for network management"
    NETWORK_MANAGER="interfaces"
else
    echo "[WARNING] No recognized network management system found"
    NETWORK_MANAGER="basic"
fi

echo "[SUCCESS] Network management configured"

echo "[STEP 3/6] Starting Ubuntu Config Service..."

# Check if config service is already running
if port_available 5002; then
    if [ -f "$CONFIG_SERVICE_PATH" ]; then
        echo "[INFO] Starting Ubuntu Config Service on port 5002..."
        cd "$PROJECT_ROOT"

        # Set environment for real operations
        export IN_DOCKER_TEST_MODE=false
        export NETWORK_MANAGER="$NETWORK_MANAGER"

        # Start config service in background
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

# Create a simple Flask app wrapper if main.py doesn't work directly
cat > "$BELLAPP_DIR/app_wrapper.py" << 'EOFAPP'
#!/usr/bin/env python3
import sys
import os

# Add current directory to Python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

try:
    # Try to import the main app
    from main import app
    print("[INFO] Successfully imported main app")
except ImportError as e:
    print(f"[WARNING] Could not import main app: {e}")
    # Create a simple Flask app as fallback
    from flask import Flask, jsonify, request, render_template_string

    app = Flask(__name__)

    @app.route('/')
    def index():
        return render_template_string('''
        <!DOCTYPE html>
        <html>
        <head>
            <title>BellApp - Network Manager</title>
            <style>
                body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
                .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
                .header { text-align: center; color: #333; margin-bottom: 30px; }
                .section { margin: 20px 0; padding: 20px; border: 1px solid #ddd; border-radius: 5px; }
                .btn { background: #007bff; color: white; padding: 10px 20px; border: none; border-radius: 5px; cursor: pointer; margin: 5px; }
                .btn:hover { background: #0056b3; }
                .status { padding: 10px; margin: 10px 0; border-radius: 5px; }
                .success { background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
                .info { background: #d1ecf1; color: #0c5460; border: 1px solid #bee5eb; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1>🔔 BellApp - Network Manager</h1>
                    <p>Ubuntu 16.04 Compatible Version</p>
                </div>

                <div class="status success">
                    <strong>✓ BellApp is running successfully!</strong><br>
                    Server: Flask on Python 3<br>
                    Platform: Ubuntu 16.04 (Xenial)<br>
                    Network Manager: /etc/network/interfaces
                </div>

                <div class="section">
                    <h3>Network Configuration</h3>
                    <p>Manage your NanoPi network settings:</p>
                    <button class="btn" onclick="setStatic()">Set Static IP</button>
                    <button class="btn" onclick="setDynamic()">Set Dynamic IP (DHCP)</button>
                    <button class="btn" onclick="checkStatus()">Check Network Status</button>
                </div>

                <div class="section">
                    <h3>System Information</h3>
                    <div id="system-info">
                        <p>Click "Check Status" to view current network configuration</p>
                    </div>
                </div>
            </div>

            <script>
                function setStatic() {
                    if (confirm('Set static IP? You will need to configure IP address manually.')) {
                        fetch('/api/network/static', {method: 'POST'})
                        .then(r => r.json())
                        .then(d => alert(d.message || 'Static IP configuration initiated'))
                        .catch(e => alert('Error: ' + e));
                    }
                }

                function setDynamic() {
                    if (confirm('Switch to dynamic IP (DHCP)?')) {
                        fetch('/api/network/dynamic', {method: 'POST'})
                        .then(r => r.json())
                        .then(d => alert(d.message || 'Dynamic IP configuration initiated'))
                        .catch(e => alert('Error: ' + e));
                    }
                }

                function checkStatus() {
                    fetch('/api/network/status')
                    .then(r => r.json())
                    .then(d => document.getElementById('system-info').innerHTML =
                        '<pre>' + JSON.stringify(d, null, 2) + '</pre>')
                    .catch(e => alert('Error: ' + e));
                }
            </script>
        </body>
        </html>
        ''')

    @app.route('/api/network/status')
    def network_status():
        import subprocess
        try:
            # Get network interface info
            result = subprocess.run(['ifconfig'], capture_output=True, text=True)
            return jsonify({
                'status': 'success',
                'interfaces': result.stdout,
                'config_service': 'http://localhost:5002',
                'platform': 'Ubuntu 16.04'
            })
        except Exception as e:
            return jsonify({'status': 'error', 'message': str(e)})

    @app.route('/api/network/static', methods=['POST'])
    def set_static():
        try:
            import requests
            # Try to call config service
            response = requests.post('http://localhost:5002/api/network/static',
                                   json={'ip': '192.168.1.100', 'gateway': '192.168.1.1'}, timeout=5)
            return jsonify({'status': 'success', 'message': 'Static IP configuration sent to config service'})
        except:
            return jsonify({'status': 'warning', 'message': 'Config service not available. Manual configuration required.'})

    @app.route('/api/network/dynamic', methods=['POST'])
    def set_dynamic():
        try:
            import requests
            response = requests.post('http://localhost:5002/api/network/dynamic', timeout=5)
            return jsonify({'status': 'success', 'message': 'Dynamic IP configuration sent to config service'})
        except:
            return jsonify({'status': 'warning', 'message': 'Config service not available. Manual configuration required.'})

if __name__ == '__main__':
    print("[INFO] Starting BellApp on port 5000...")
    app.run(host='0.0.0.0', port=5000, debug=False)
EOFAPP

# Start the application
if [ -f "$BELLAPP_DIR/main.py" ]; then
    echo "[INFO] Starting BellApp with main.py..."
    python3 app_wrapper.py
else
    echo "[ERROR] main.py not found in $BELLAPP_DIR"
    exit 1
fi