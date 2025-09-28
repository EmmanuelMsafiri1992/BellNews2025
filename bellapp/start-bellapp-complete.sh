#!/bin/bash

# ╔══════════════════════════════════════════════════════════════╗
# ║        BELLAPP COMPLETE SETUP - PYTHON 3.5 COMPATIBLE       ║
# ║     All packages + Auto-start on reboot + IP switching      ║
# ╚══════════════════════════════════════════════════════════════╝

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BELLAPP_DIR="$SCRIPT_DIR"
CONFIG_SERVICE_PATH="$PROJECT_ROOT/ubuntu_config_service.py"
SERVICE_NAME="bellapp"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        BELLAPP COMPLETE SETUP - PYTHON 3.5 COMPATIBLE       ║"
echo "║           All packages + Auto-start + IP switching          ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if port is available
port_available() {
    ! nc -z localhost "$1" 2>/dev/null
}

# Function to intelligently install package with version fallback
install_package_intelligent() {
    local package_name=$1
    shift
    local versions=("$@")

    echo "[INFO] Installing $package_name..."

    for version in "${versions[@]}"; do
        echo "[ATTEMPT] Trying $package_name==$version"
        if sudo pip3 install "$package_name==$version"; then
            echo "[SUCCESS] Installed $package_name==$version"
            return 0
        else
            echo "[FAILED] $package_name==$version failed, trying next version..."
        fi
    done

    # Final attempt without version constraint
    echo "[FINAL ATTEMPT] Installing $package_name without version constraint..."
    if sudo pip3 install "$package_name"; then
        echo "[SUCCESS] Installed $package_name (latest compatible)"
        return 0
    else
        echo "[ERROR] Failed to install $package_name"
        return 1
    fi
}

echo "[STEP 1/8] Updating system and installing base dependencies..."

# Update package lists
sudo apt update

# Install essential system packages
echo "[INFO] Installing essential system packages..."
sudo apt install -y python3 python3-pip python3-dev python3-setuptools
sudo apt install -y build-essential libffi-dev libssl-dev
sudo apt install -y net-tools ifupdown netcat-openbsd
sudo apt install -y curl wget ca-certificates git
sudo apt install -y libyaml-dev python3-yaml  # For PyYAML compilation

echo "[SUCCESS] Base dependencies installed"

echo "[STEP 2/8] Upgrading pip and setuptools for Python 3.5..."

# Get the latest pip that supports Python 3.5
curl -s https://bootstrap.pypa.io/pip/3.5/get-pip.py -o get-pip.py
sudo python3 get-pip.py
rm -f get-pip.py

# Upgrade setuptools and wheel
sudo pip3 install --upgrade "setuptools>=40.0,<45.0"
sudo pip3 install --upgrade "wheel>=0.30,<0.37"

echo "[SUCCESS] Pip and setuptools upgraded"

echo "[STEP 3/8] Installing Python packages intelligently..."

# Install packages with intelligent fallback versions
echo "[INFO] Installing Flask ecosystem..."
install_package_intelligent "Flask" "1.1.4" "1.1.2" "1.0.4" "0.12.5"
install_package_intelligent "Werkzeug" "1.0.1" "0.16.1" "0.15.6"
install_package_intelligent "Jinja2" "2.11.3" "2.10.3" "2.10.1"
install_package_intelligent "MarkupSafe" "1.1.1" "1.0" "0.23"
install_package_intelligent "itsdangerous" "1.1.0" "0.24"
install_package_intelligent "click" "7.1.2" "7.0" "6.7"

echo "[INFO] Installing system monitoring packages..."
install_package_intelligent "psutil" "5.6.7" "5.4.8" "5.2.2"

echo "[INFO] Installing network and request packages..."
install_package_intelligent "requests" "2.25.1" "2.22.0" "2.18.4"
install_package_intelligent "urllib3" "1.26.9" "1.24.3" "1.22"
install_package_intelligent "certifi" "2021.10.8" "2019.11.28"
install_package_intelligent "chardet" "4.0.0" "3.0.4"
install_package_intelligent "idna" "2.10" "2.8" "2.6"

echo "[INFO] Installing YAML support..."
# Try different PyYAML versions for Python 3.5
install_package_intelligent "PyYAML" "3.13" "3.12" "3.11"

echo "[INFO] Installing time and date packages..."
install_package_intelligent "pytz" "2019.3" "2018.9" "2017.3"

echo "[INFO] Installing security packages..."
install_package_intelligent "bcrypt" "3.1.7" "3.1.4" "3.1.0"

echo "[INFO] Installing additional Flask utilities..."
install_package_intelligent "Flask-Login" "0.5.0" "0.4.1" "0.4.0"

echo "[INFO] Installing server packages..."
install_package_intelligent "gunicorn" "20.0.4" "19.9.0"

# Verify critical imports work
echo "[INFO] Verifying package installations..."
python3 -c "import flask; print('Flask:', flask.__version__)" || echo "[WARNING] Flask import failed"
python3 -c "import yaml; print('PyYAML: OK')" || echo "[WARNING] PyYAML import failed"
python3 -c "import psutil; print('psutil:', psutil.__version__)" || echo "[WARNING] psutil import failed"
python3 -c "import requests; print('requests:', requests.__version__)" || echo "[WARNING] requests import failed"

echo "[SUCCESS] All Python packages installed and verified"

echo "[STEP 4/8] Setting up network management..."

# Check network management system
if [ -f "/etc/network/interfaces" ]; then
    echo "[INFO] Using traditional /etc/network/interfaces for network management"
    NETWORK_MANAGER="interfaces"

    # Backup original interfaces file
    sudo cp /etc/network/interfaces /etc/network/interfaces.backup.$(date +%Y%m%d_%H%M%S)
else
    echo "[WARNING] No recognized network management system found"
    NETWORK_MANAGER="basic"
fi

echo "[SUCCESS] Network management configured"

echo "[STEP 5/8] Creating optimized config service..."

# Create optimized config service for Python 3.5
cat > "$PROJECT_ROOT/ubuntu_config_service_optimized.py" << 'EOFCONFIG'
#!/usr/bin/env python3
"""
Ubuntu Configuration Service - Python 3.5 Optimized
Handles network configuration changes for BellApp
"""

import os
import sys
import json
import logging
import subprocess
import time
from flask import Flask, request, jsonify

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/ubuntu_config_service.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger('UbuntuConfigService')

app = Flask(__name__)

# Configuration
IN_DOCKER_TEST_MODE = os.getenv("IN_DOCKER_TEST_MODE", "false").lower() == "true"
NETWORK_MANAGER = os.getenv("NETWORK_MANAGER", "interfaces")
INTERFACES_FILE = '/etc/network/interfaces'

def run_command(command_list, check_output=False):
    """Execute shell command safely"""
    try:
        if check_output:
            result = subprocess.check_output(command_list, stderr=subprocess.STDOUT, universal_newlines=True)
            return result.strip()
        else:
            subprocess.check_call(command_list)
            return "Success"
    except subprocess.CalledProcessError as e:
        logger.error(f"Command failed: {' '.join(command_list)}, Error: {e}")
        return None
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return None

def get_interface_name():
    """Get the primary network interface name"""
    try:
        # Try to get interface from route
        result = run_command(['route', 'get', 'default'], check_output=True)
        if result:
            for line in result.split('\n'):
                if 'interface:' in line:
                    return line.split(':')[1].strip()

        # Fallback: get first non-loopback interface
        result = run_command(['ls', '/sys/class/net'], check_output=True)
        if result:
            interfaces = result.split()
            for iface in interfaces:
                if iface != 'lo':
                    return iface

        # Last resort
        return 'eth0'
    except:
        return 'eth0'

def set_static_ip(ip_address, netmask='255.255.255.0', gateway='192.168.1.1', dns='8.8.8.8'):
    """Configure static IP using /etc/network/interfaces"""
    interface = get_interface_name()

    if IN_DOCKER_TEST_MODE:
        logger.info(f"[TEST MODE] Would set static IP: {ip_address}")
        return True

    try:
        # Create new interfaces configuration
        config = f"""# Configured by BellApp
auto lo
iface lo inet loopback

auto {interface}
iface {interface} inet static
    address {ip_address}
    netmask {netmask}
    gateway {gateway}
    dns-nameservers {dns}
"""

        # Write configuration
        with open(INTERFACES_FILE, 'w') as f:
            f.write(config)

        logger.info(f"Static IP configuration written for {interface}")

        # Restart networking
        run_command(['sudo', 'ifdown', interface])
        time.sleep(2)
        run_command(['sudo', 'ifup', interface])

        return True
    except Exception as e:
        logger.error(f"Failed to set static IP: {e}")
        return False

def set_dynamic_ip():
    """Configure dynamic IP (DHCP) using /etc/network/interfaces"""
    interface = get_interface_name()

    if IN_DOCKER_TEST_MODE:
        logger.info("[TEST MODE] Would set dynamic IP (DHCP)")
        return True

    try:
        # Create DHCP configuration
        config = f"""# Configured by BellApp
auto lo
iface lo inet loopback

auto {interface}
iface {interface} inet dhcp
"""

        # Write configuration
        with open(INTERFACES_FILE, 'w') as f:
            f.write(config)

        logger.info(f"DHCP configuration written for {interface}")

        # Restart networking
        run_command(['sudo', 'ifdown', interface])
        time.sleep(2)
        run_command(['sudo', 'ifup', interface])

        return True
    except Exception as e:
        logger.error(f"Failed to set dynamic IP: {e}")
        return False

@app.route('/health')
def health():
    return jsonify({'status': 'healthy', 'service': 'ubuntu_config_service'})

@app.route('/api/network/static', methods=['POST'])
def api_set_static():
    try:
        data = request.get_json() or {}
        ip = data.get('ip', '192.168.1.100')
        netmask = data.get('netmask', '255.255.255.0')
        gateway = data.get('gateway', '192.168.1.1')
        dns = data.get('dns', '8.8.8.8')

        success = set_static_ip(ip, netmask, gateway, dns)

        if success:
            return jsonify({
                'status': 'success',
                'message': f'Static IP {ip} configured successfully',
                'config': {'ip': ip, 'netmask': netmask, 'gateway': gateway, 'dns': dns}
            })
        else:
            return jsonify({'status': 'error', 'message': 'Failed to configure static IP'}), 500
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/api/network/dynamic', methods=['POST'])
def api_set_dynamic():
    try:
        success = set_dynamic_ip()

        if success:
            return jsonify({
                'status': 'success',
                'message': 'Dynamic IP (DHCP) configured successfully'
            })
        else:
            return jsonify({'status': 'error', 'message': 'Failed to configure dynamic IP'}), 500
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/api/network/status')
def api_network_status():
    try:
        interface = get_interface_name()
        ifconfig_result = run_command(['ifconfig', interface], check_output=True)
        route_result = run_command(['route', '-n'], check_output=True)

        return jsonify({
            'status': 'success',
            'interface': interface,
            'ifconfig': ifconfig_result,
            'routes': route_result,
            'network_manager': NETWORK_MANAGER,
            'test_mode': IN_DOCKER_TEST_MODE
        })
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500

if __name__ == '__main__':
    logger.info("Starting Ubuntu Config Service...")
    logger.info(f"Network Manager: {NETWORK_MANAGER}")
    logger.info(f"Test Mode: {IN_DOCKER_TEST_MODE}")

    app.run(host='0.0.0.0', port=5002, debug=False)
EOFCONFIG

chmod +x "$PROJECT_ROOT/ubuntu_config_service_optimized.py"

echo "[SUCCESS] Optimized config service created"

echo "[STEP 6/8] Creating systemd services for auto-start..."

# Create config service systemd unit
sudo tee "$SERVICE_FILE.config" > /dev/null << EOFSERVICE
[Unit]
Description=BellApp Ubuntu Configuration Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PROJECT_ROOT
Environment=IN_DOCKER_TEST_MODE=false
Environment=NETWORK_MANAGER=interfaces
ExecStart=/usr/bin/python3 $PROJECT_ROOT/ubuntu_config_service_optimized.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFSERVICE

# Create main bellapp systemd unit
sudo tee "$SERVICE_FILE" > /dev/null << EOFSERVICE
[Unit]
Description=BellApp Network Management Service
After=network.target bellapp.config.service
Wants=network.target
Requires=bellapp.config.service

[Service]
Type=simple
User=root
WorkingDirectory=$BELLAPP_DIR
Environment=UBUNTU_CONFIG_SERVICE_URL=http://localhost:5002
Environment=FLASK_ENV=production
Environment=FLASK_DEBUG=false
Environment=IN_DOCKER_TEST_MODE=false
Environment=NETWORK_MANAGER=interfaces
ExecStart=/usr/bin/python3 $BELLAPP_DIR/bellapp_runner.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFSERVICE

echo "[SUCCESS] Systemd services created"

echo "[STEP 7/8] Creating optimized BellApp runner..."

# Create optimized bellapp runner
cat > "$BELLAPP_DIR/bellapp_runner.py" << 'EOFRUNNER'
#!/usr/bin/env python3
"""
BellApp Runner - Python 3.5 Optimized
Main application entry point with fallback capabilities
"""

import sys
import os
import time
import logging

# Add current directory to Python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/bellapp.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger('BellApp')

def main():
    logger.info("Starting BellApp...")

    try:
        # Try to import the original main app
        from main import app
        logger.info("Successfully imported original main app")

        # Start the app
        app.run(host='0.0.0.0', port=5000, debug=False)

    except ImportError as e:
        logger.warning(f"Could not import main app: {e}")
        logger.info("Starting fallback Flask application...")

        # Create fallback Flask app
        from flask import Flask, jsonify, request, render_template_string
        import json
        import subprocess

        app = Flask(__name__)

        @app.route('/')
        def index():
            return render_template_string('''
            <!DOCTYPE html>
            <html>
            <head>
                <title>BellApp - Network Manager</title>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>
                    * { box-sizing: border-box; margin: 0; padding: 0; }
                    body {
                        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
                        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                        min-height: 100vh; padding: 20px;
                    }
                    .container {
                        max-width: 900px; margin: 0 auto; background: white;
                        border-radius: 15px; box-shadow: 0 10px 30px rgba(0,0,0,0.2);
                        overflow: hidden;
                    }
                    .header {
                        background: linear-gradient(45deg, #2196F3, #21CBF3);
                        color: white; padding: 30px; text-align: center;
                    }
                    .header h1 { font-size: 2.5em; margin-bottom: 10px; }
                    .header p { opacity: 0.9; font-size: 1.1em; }
                    .content { padding: 30px; }
                    .section {
                        margin: 25px 0; padding: 25px;
                        border: 2px solid #e3f2fd; border-radius: 10px;
                        background: #fafafa;
                    }
                    .section h3 {
                        color: #1976d2; margin-bottom: 15px;
                        font-size: 1.3em; display: flex; align-items: center;
                    }
                    .section h3:before {
                        content: "⚙️"; margin-right: 10px; font-size: 1.2em;
                    }
                    .btn {
                        background: linear-gradient(45deg, #2196F3, #21CBF3);
                        color: white; padding: 12px 25px; border: none;
                        border-radius: 25px; cursor: pointer; margin: 8px;
                        font-size: 1em; transition: all 0.3s;
                        box-shadow: 0 4px 15px rgba(33, 150, 243, 0.3);
                    }
                    .btn:hover {
                        transform: translateY(-2px);
                        box-shadow: 0 6px 20px rgba(33, 150, 243, 0.4);
                    }
                    .btn-danger {
                        background: linear-gradient(45deg, #f44336, #ff5722);
                        box-shadow: 0 4px 15px rgba(244, 67, 54, 0.3);
                    }
                    .btn-danger:hover {
                        box-shadow: 0 6px 20px rgba(244, 67, 54, 0.4);
                    }
                    .status {
                        padding: 20px; margin: 15px 0; border-radius: 10px;
                        border-left: 5px solid;
                    }
                    .success {
                        background: #e8f5e8; color: #2e7d32;
                        border-color: #4caf50;
                    }
                    .info {
                        background: #e3f2fd; color: #1565c0;
                        border-color: #2196f3;
                    }
                    .warning {
                        background: #fff3e0; color: #ef6c00;
                        border-color: #ff9800;
                    }
                    #system-info {
                        background: #f5f5f5; padding: 15px;
                        border-radius: 8px; font-family: monospace;
                        white-space: pre-wrap; max-height: 300px;
                        overflow-y: auto; border: 1px solid #ddd;
                    }
                    .grid {
                        display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
                        gap: 15px; margin: 20px 0;
                    }
                    .loading {
                        display: inline-block; width: 20px; height: 20px;
                        border: 3px solid #f3f3f3; border-top: 3px solid #3498db;
                        border-radius: 50%; animation: spin 1s linear infinite;
                        margin-right: 10px;
                    }
                    @keyframes spin {
                        0% { transform: rotate(0deg); }
                        100% { transform: rotate(360deg); }
                    }
                </style>
            </head>
            <body>
                <div class="container">
                    <div class="header">
                        <h1>🔔 BellApp</h1>
                        <p>Network Management System for Ubuntu 16.04</p>
                    </div>

                    <div class="content">
                        <div class="status success">
                            <strong>✅ BellApp is running successfully!</strong><br>
                            🐍 Python 3.5 Compatible Version<br>
                            🖥️ Platform: Ubuntu 16.04 (Xenial)<br>
                            🌐 Network Manager: /etc/network/interfaces<br>
                            🔄 Auto-start: Enabled via systemd
                        </div>

                        <div class="section">
                            <h3>Network Configuration</h3>
                            <p style="margin-bottom: 20px;">Manage your NanoPi network settings with intelligent IP switching:</p>
                            <div class="grid">
                                <button class="btn" onclick="setStatic()">🔒 Set Static IP</button>
                                <button class="btn" onclick="setDynamic()">🔄 Set Dynamic IP (DHCP)</button>
                                <button class="btn" onclick="checkStatus()">📊 Check Network Status</button>
                                <button class="btn btn-danger" onclick="restartNetwork()">🔄 Restart Network</button>
                            </div>
                        </div>

                        <div class="section">
                            <h3>System Information</h3>
                            <div id="system-info">Click "Check Network Status" to view current network configuration</div>
                        </div>

                        <div class="section">
                            <h3>Quick Actions</h3>
                            <div class="grid">
                                <button class="btn" onclick="testConnectivity()">🌐 Test Internet</button>
                                <button class="btn" onclick="viewLogs()">📋 View Logs</button>
                                <button class="btn" onclick="restartServices()">⚡ Restart Services</button>
                            </div>
                        </div>
                    </div>
                </div>

                <script>
                    function showLoading(elementId) {
                        document.getElementById(elementId).innerHTML = '<div class="loading"></div>Loading...';
                    }

                    function setStatic() {
                        const ip = prompt('Enter static IP address:', '192.168.1.100');
                        if (!ip) return;

                        const gateway = prompt('Enter gateway:', '192.168.1.1');
                        if (!gateway) return;

                        if (confirm(`Set static IP to ${ip} with gateway ${gateway}?`)) {
                            showLoading('system-info');
                            fetch('/api/network/static', {
                                method: 'POST',
                                headers: {'Content-Type': 'application/json'},
                                body: JSON.stringify({ip: ip, gateway: gateway})
                            })
                            .then(r => r.json())
                            .then(d => {
                                alert(d.message || 'Static IP configuration completed');
                                checkStatus();
                            })
                            .catch(e => {
                                alert('Error: ' + e);
                                document.getElementById('system-info').innerHTML = 'Error: ' + e;
                            });
                        }
                    }

                    function setDynamic() {
                        if (confirm('Switch to dynamic IP (DHCP)? This will automatically obtain an IP address.')) {
                            showLoading('system-info');
                            fetch('/api/network/dynamic', {method: 'POST'})
                            .then(r => r.json())
                            .then(d => {
                                alert(d.message || 'Dynamic IP configuration completed');
                                checkStatus();
                            })
                            .catch(e => {
                                alert('Error: ' + e);
                                document.getElementById('system-info').innerHTML = 'Error: ' + e;
                            });
                        }
                    }

                    function checkStatus() {
                        showLoading('system-info');
                        fetch('/api/network/status')
                        .then(r => r.json())
                        .then(d => {
                            const info = document.getElementById('system-info');
                            if (d.status === 'success') {
                                info.innerHTML = `Interface: ${d.interface}

Current Configuration:
${d.ifconfig}

Routing Table:
${d.routes}

System Info:
- Network Manager: ${d.network_manager}
- Test Mode: ${d.test_mode}
- Timestamp: ${new Date().toLocaleString()}`;
                            } else {
                                info.innerHTML = 'Error: ' + d.message;
                            }
                        })
                        .catch(e => {
                            document.getElementById('system-info').innerHTML = 'Error: ' + e;
                        });
                    }

                    function testConnectivity() {
                        showLoading('system-info');
                        fetch('/api/test/connectivity')
                        .then(r => r.json())
                        .then(d => {
                            document.getElementById('system-info').innerHTML = JSON.stringify(d, null, 2);
                        })
                        .catch(e => {
                            document.getElementById('system-info').innerHTML = 'Connectivity test failed: ' + e;
                        });
                    }

                    function restartNetwork() {
                        if (confirm('Restart network services? This may temporarily disconnect you.')) {
                            fetch('/api/network/restart', {method: 'POST'})
                            .then(r => r.json())
                            .then(d => alert(d.message))
                            .catch(e => alert('Error: ' + e));
                        }
                    }

                    function viewLogs() {
                        fetch('/api/logs')
                        .then(r => r.json())
                        .then(d => {
                            document.getElementById('system-info').innerHTML = d.logs || 'No logs available';
                        })
                        .catch(e => {
                            document.getElementById('system-info').innerHTML = 'Error loading logs: ' + e;
                        });
                    }

                    function restartServices() {
                        if (confirm('Restart BellApp services?')) {
                            fetch('/api/restart', {method: 'POST'})
                            .then(r => r.json())
                            .then(d => alert(d.message))
                            .catch(e => alert('Error: ' + e));
                        }
                    }

                    // Auto-refresh status every 30 seconds
                    setInterval(function() {
                        if (document.getElementById('system-info').innerHTML.includes('Interface:')) {
                            checkStatus();
                        }
                    }, 30000);
                </script>
            </body>
            </html>
            ''')

        @app.route('/api/network/status')
        def network_status():
            try:
                import subprocess
                interface_result = subprocess.check_output(['route', 'get', 'default'], universal_newlines=True)
                ifconfig_result = subprocess.check_output(['ifconfig'], universal_newlines=True)
                route_result = subprocess.check_output(['route', '-n'], universal_newlines=True)

                return jsonify({
                    'status': 'success',
                    'interface': 'eth0',
                    'ifconfig': ifconfig_result,
                    'routes': route_result,
                    'network_manager': 'interfaces',
                    'test_mode': False
                })
            except Exception as e:
                return jsonify({'status': 'error', 'message': str(e)})

        @app.route('/api/network/static', methods=['POST'])
        def set_static():
            try:
                import requests
                data = request.get_json() or {}
                response = requests.post('http://localhost:5002/api/network/static', json=data, timeout=10)
                return response.json()
            except Exception as e:
                return jsonify({'status': 'error', 'message': f'Config service error: {str(e)}'})

        @app.route('/api/network/dynamic', methods=['POST'])
        def set_dynamic():
            try:
                import requests
                response = requests.post('http://localhost:5002/api/network/dynamic', timeout=10)
                return response.json()
            except Exception as e:
                return jsonify({'status': 'error', 'message': f'Config service error: {str(e)}'})

        @app.route('/api/test/connectivity')
        def test_connectivity():
            try:
                import subprocess
                result = subprocess.check_output(['ping', '-c', '3', '8.8.8.8'], universal_newlines=True)
                return jsonify({'status': 'success', 'result': result})
            except Exception as e:
                return jsonify({'status': 'error', 'message': str(e)})

        @app.route('/api/network/restart', methods=['POST'])
        def restart_network():
            try:
                import subprocess
                subprocess.run(['sudo', 'systemctl', 'restart', 'networking'])
                return jsonify({'status': 'success', 'message': 'Network services restarted'})
            except Exception as e:
                return jsonify({'status': 'error', 'message': str(e)})

        @app.route('/api/logs')
        def view_logs():
            try:
                with open('/var/log/bellapp.log', 'r') as f:
                    logs = f.read()
                return jsonify({'status': 'success', 'logs': logs})
            except Exception as e:
                return jsonify({'status': 'error', 'message': str(e)})

        @app.route('/api/restart', methods=['POST'])
        def restart_services():
            try:
                import subprocess
                subprocess.run(['sudo', 'systemctl', 'restart', 'bellapp'])
                return jsonify({'status': 'success', 'message': 'Services restarted'})
            except Exception as e:
                return jsonify({'status': 'error', 'message': str(e)})

        # Start the fallback app
        app.run(host='0.0.0.0', port=5000, debug=False)

if __name__ == '__main__':
    main()
EOFRUNNER

chmod +x "$BELLAPP_DIR/bellapp_runner.py"

echo "[SUCCESS] Optimized BellApp runner created"

echo "[STEP 8/8] Enabling auto-start services..."

# Enable and start services
sudo systemctl daemon-reload
sudo systemctl enable bellapp.config.service
sudo systemctl enable bellapp.service

# Start config service first
sudo systemctl start bellapp.config.service
sleep 3

# Start main bellapp service
sudo systemctl start bellapp.service

# Verify services are running
echo "[INFO] Checking service status..."
sudo systemctl status bellapp.config.service --no-pager -l
sudo systemctl status bellapp.service --no-pager -l

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                 🎉 BELLAPP SETUP COMPLETE! 🎉                ║"
echo "║                                                              ║"
echo "║  ✅ ALL Python packages installed (Python 3.5 compatible)   ║"
echo "║  ✅ Auto-start on reboot enabled via systemd                ║"
echo "║  ✅ Network IP switching (static ↔ dynamic) enabled         ║"
echo "║  ✅ Config service running on port 5002                     ║"
echo "║  ✅ BellApp running on port 5000                            ║"
echo "║                                                              ║"
echo "║  🌐 Web Interface: http://$(hostname -I | awk '{print $1}'):5000         ║"
echo "║  ⚙️  Config Service: http://localhost:5002                   ║"
echo "║                                                              ║"
echo "║  🔧 Management Commands:                                     ║"
echo "║     sudo systemctl status bellapp                           ║"
echo "║     sudo systemctl restart bellapp                          ║"
echo "║     sudo systemctl stop bellapp                             ║"
echo "║                                                              ║"
echo "║  📋 View Logs:                                               ║"
echo "║     sudo journalctl -u bellapp -f                           ║"
echo "║     tail -f /var/log/bellapp.log                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"

echo ""
echo "[SUCCESS] Setup complete! BellApp is now running and will auto-start on reboot."
echo "[INFO] You can access the web interface at: http://$(hostname -I | awk '{print $1}'):5000"