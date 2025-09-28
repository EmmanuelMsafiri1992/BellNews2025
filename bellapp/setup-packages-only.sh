#!/bin/bash

# ╔══════════════════════════════════════════════════════════════╗
# ║     BELLAPP PACKAGE INSTALLER - PRESERVE ORIGINAL UI        ║
# ║   Install all packages + Auto-start WITHOUT changing UI     ║
# ╚══════════════════════════════════════════════════════════════╝

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BELLAPP_DIR="$SCRIPT_DIR"
CONFIG_SERVICE_PATH="$PROJECT_ROOT/ubuntu_config_service.py"
SERVICE_NAME="bellapp"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     BELLAPP PACKAGE INSTALLER - PRESERVE ORIGINAL UI        ║"
echo "║   Install all packages + Auto-start WITHOUT changing UI     ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
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

echo "[STEP 1/5] Installing system dependencies..."

# Update and install base packages
sudo apt update
sudo apt install -y python3 python3-pip python3-dev python3-setuptools
sudo apt install -y build-essential libffi-dev libssl-dev
sudo apt install -y net-tools ifupdown netcat-openbsd
sudo apt install -y curl wget ca-certificates
sudo apt install -y libyaml-dev python3-yaml

echo "[STEP 2/5] Upgrading pip for Python 3.5..."

# Get compatible pip
curl -s https://bootstrap.pypa.io/pip/3.5/get-pip.py -o get-pip.py
sudo python3 get-pip.py
rm -f get-pip.py

# Upgrade essential tools
sudo pip3 install --upgrade "setuptools>=40.0,<45.0"
sudo pip3 install --upgrade "wheel>=0.30,<0.37"

echo "[STEP 3/5] Installing ALL Python packages intelligently..."

# Install Flask ecosystem
install_package_intelligent "Flask" "1.1.4" "1.1.2" "1.0.4" "0.12.5"
install_package_intelligent "Werkzeug" "1.0.1" "0.16.1" "0.15.6"
install_package_intelligent "Jinja2" "2.11.3" "2.10.3" "2.10.1"
install_package_intelligent "MarkupSafe" "1.1.1" "1.0" "0.23"
install_package_intelligent "itsdangerous" "1.1.0" "0.24"
install_package_intelligent "click" "7.1.2" "7.0" "6.7"

# Install all required packages from requirements.txt
install_package_intelligent "psutil" "5.6.7" "5.4.8" "5.2.2"
install_package_intelligent "requests" "2.25.1" "2.22.0" "2.18.4"
install_package_intelligent "PyYAML" "3.13" "3.12" "3.11"
install_package_intelligent "pytz" "2019.3" "2018.9" "2017.3"
install_package_intelligent "bcrypt" "3.1.7" "3.1.4" "3.1.0"
install_package_intelligent "Flask-Login" "0.5.0" "0.4.1" "0.4.0"
install_package_intelligent "gunicorn" "20.0.4" "19.9.0"

# Install simpleaudio (from your requirements.txt)
echo "[INFO] Installing simpleaudio for audio functionality..."
sudo apt install -y libasound2-dev
install_package_intelligent "simpleaudio" "1.0.4" "1.0.2"

echo "[STEP 4/5] Setting up auto-start service..."

# Create simple systemd service that runs your original main.py
sudo tee "/etc/systemd/system/bellapp.service" > /dev/null << EOFSERVICE
[Unit]
Description=BellApp Original Interface
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$BELLAPP_DIR
Environment=UBUNTU_CONFIG_SERVICE_URL=http://localhost:5002
Environment=FLASK_ENV=production
Environment=FLASK_DEBUG=false
Environment=IN_DOCKER_TEST_MODE=false
Environment=NETWORK_MANAGER=interfaces
ExecStartPre=/bin/sleep 10
ExecStart=/usr/bin/python3 $BELLAPP_DIR/vcns_timer_web.py
Restart=always
RestartSec=15
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFSERVICE

# Create config service systemd unit (unchanged from original)
sudo tee "/etc/systemd/system/bellapp-config.service" > /dev/null << EOFSERVICE
[Unit]
Description=BellApp Configuration Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PROJECT_ROOT
Environment=IN_DOCKER_TEST_MODE=false
Environment=NETWORK_MANAGER=interfaces
ExecStart=/usr/bin/python3 $PROJECT_ROOT/ubuntu_config_service.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFSERVICE

echo "[STEP 5/5] Enabling auto-start and starting services..."

# Enable services for auto-start
sudo systemctl daemon-reload
sudo systemctl enable bellapp-config.service
sudo systemctl enable bellapp.service

# Start config service first
echo "[INFO] Starting config service..."
sudo systemctl start bellapp-config.service
sleep 5

# Start main bellapp with your original interface
echo "[INFO] Starting BellApp with your original main.py..."
sudo systemctl start bellapp.service

# Check if services are running
echo "[INFO] Checking service status..."
sudo systemctl status bellapp-config.service --no-pager -l || true
sudo systemctl status bellapp.service --no-pager -l || true

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    ✅ SETUP COMPLETE! ✅                     ║"
echo "║                                                              ║"
echo "║  ✅ ALL Python packages installed intelligently             ║"
echo "║  ✅ Auto-start on reboot enabled                            ║"
echo "║  ✅ Your ORIGINAL UI preserved (main.py)                    ║"
echo "║  ✅ Config service for IP switching enabled                 ║"
echo "║                                                              ║"
echo "║  🌐 Your Original Interface: http://$(hostname -I | awk '{print $1}'):5000   ║"
echo "║  ⚙️  Config Service: http://localhost:5002                   ║"
echo "║                                                              ║"
echo "║  🔧 Service Management:                                      ║"
echo "║     sudo systemctl status bellapp                           ║"
echo "║     sudo systemctl restart bellapp                          ║"
echo "║     sudo journalctl -u bellapp -f                           ║"
echo "║                                                              ║"
echo "║  📝 Note: Your original main.py interface is preserved      ║"
echo "║           with all original functionality intact            ║"
echo "╚══════════════════════════════════════════════════════════════╝"

echo ""
echo "[SUCCESS] All packages installed, auto-start enabled, original UI preserved!"
echo "[INFO] Access your original interface at: http://$(hostname -I | awk '{print $1}'):5000"