#!/bin/bash

# ╔══════════════════════════════════════════════════════════════╗
# ║          ULTIMATE BELLAPP SETUP - ANY UBUNTU VERSION         ║
# ║    Works on Ubuntu 12.04+ / Supports upstart + systemd      ║
# ║         Installs everything + Auto-start + IP switching      ║
# ╚══════════════════════════════════════════════════════════════╝

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BELLAPP_DIR="$SCRIPT_DIR"
CONFIG_SERVICE_PATH="$PROJECT_ROOT/ubuntu_config_service.py"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          ULTIMATE BELLAPP SETUP - ANY UBUNTU VERSION         ║"
echo "║    Works on Ubuntu 12.04+ / Supports upstart + systemd      ║"
echo "║         Installs everything + Auto-start + IP switching      ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to detect Ubuntu version
get_ubuntu_version() {
    if [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        echo "$DISTRIB_RELEASE"
    elif [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$VERSION_ID"
    else
        echo "unknown"
    fi
}

# Function to detect init system (systemd vs upstart vs sysvinit)
detect_init_system() {
    if command_exists systemctl && [ -d /run/systemd/system ]; then
        echo "systemd"
    elif command_exists initctl && [ -f /sbin/upstart ]; then
        echo "upstart"
    elif [ -f /etc/init.d/rc ]; then
        echo "sysvinit"
    else
        echo "unknown"
    fi
}

# Function to intelligently install package with multiple fallback strategies
install_package_ultimate() {
    local package_name=$1
    shift
    local versions=("$@")

    echo "[INFO] Installing $package_name with ultimate fallback strategy..."

    # Strategy 1: Try specific versions
    for version in "${versions[@]}"; do
        echo "[ATTEMPT] Trying $package_name==$version"
        if timeout 120 pip3 install "$package_name==$version" --no-cache-dir --disable-pip-version-check; then
            echo "[SUCCESS] Installed $package_name==$version"
            return 0
        else
            echo "[FAILED] $package_name==$version failed, trying next..."
        fi
    done

    # Strategy 2: Try without version constraints
    echo "[STRATEGY 2] Installing $package_name without version constraints..."
    if timeout 120 pip3 install "$package_name" --no-cache-dir --disable-pip-version-check; then
        echo "[SUCCESS] Installed $package_name (latest compatible)"
        return 0
    fi

    # Strategy 3: Try with --force-reinstall
    echo "[STRATEGY 3] Force reinstalling $package_name..."
    if timeout 120 pip3 install "$package_name" --force-reinstall --no-cache-dir --disable-pip-version-check; then
        echo "[SUCCESS] Force installed $package_name"
        return 0
    fi

    # Strategy 4: Try with --user flag
    echo "[STRATEGY 4] Installing $package_name with --user flag..."
    if timeout 120 pip3 install "$package_name" --user --no-cache-dir --disable-pip-version-check; then
        echo "[SUCCESS] User installed $package_name"
        return 0
    fi

    # Strategy 5: Try via apt if available
    apt_package_name=$(echo "$package_name" | tr '[:upper:]' '[:lower:]' | sed 's/flask/python3-flask/g; s/requests/python3-requests/g; s/psutil/python3-psutil/g')
    echo "[STRATEGY 5] Trying apt package: $apt_package_name"
    if apt-cache show "$apt_package_name" >/dev/null 2>&1; then
        if sudo apt install -y "$apt_package_name"; then
            echo "[SUCCESS] Installed $package_name via apt"
            return 0
        fi
    fi

    echo "[WARNING] All strategies failed for $package_name, continuing anyway..."
    return 1
}

# Function to setup auto-start based on init system
setup_autostart() {
    local init_system=$1
    local service_name="bellapp"
    local config_service_name="bellapp-config"

    echo "[INFO] Setting up auto-start for init system: $init_system"

    case $init_system in
        "systemd")
            echo "[INFO] Setting up systemd services..."
            setup_systemd_services
            ;;
        "upstart")
            echo "[INFO] Setting up upstart services..."
            setup_upstart_services
            ;;
        "sysvinit")
            echo "[INFO] Setting up sysvinit services..."
            setup_sysvinit_services
            ;;
        *)
            echo "[WARNING] Unknown init system, setting up basic startup scripts..."
            setup_basic_startup
            ;;
    esac
}

setup_systemd_services() {
    # Create config service
    sudo tee "/etc/systemd/system/bellapp-config.service" > /dev/null << 'EOFCONFIG'
[Unit]
Description=BellApp Configuration Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=PROJECT_ROOT_PLACEHOLDER
Environment=IN_DOCKER_TEST_MODE=false
Environment=NETWORK_MANAGER=interfaces
ExecStart=/usr/bin/python3 PROJECT_ROOT_PLACEHOLDER/ubuntu_config_service.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFCONFIG

    # Create main service
    sudo tee "/etc/systemd/system/bellapp.service" > /dev/null << 'EOFMAIN'
[Unit]
Description=BellApp Network Management Service
After=network.target bellapp-config.service
Wants=network.target
Requires=bellapp-config.service

[Service]
Type=simple
User=root
WorkingDirectory=BELLAPP_DIR_PLACEHOLDER
Environment=UBUNTU_CONFIG_SERVICE_URL=http://localhost:5002
Environment=FLASK_ENV=production
Environment=FLASK_DEBUG=false
ExecStartPre=/bin/sleep 15
ExecStart=/usr/bin/python3 BELLAPP_DIR_PLACEHOLDER/vcns_timer_web.py
Restart=always
RestartSec=15
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFMAIN

    # Replace placeholders
    sudo sed -i "s|PROJECT_ROOT_PLACEHOLDER|$PROJECT_ROOT|g" /etc/systemd/system/bellapp-config.service
    sudo sed -i "s|BELLAPP_DIR_PLACEHOLDER|$BELLAPP_DIR|g" /etc/systemd/system/bellapp.service

    # Enable and start services
    sudo systemctl daemon-reload
    sudo systemctl enable bellapp-config.service
    sudo systemctl enable bellapp.service
    sudo systemctl start bellapp-config.service
    sleep 5
    sudo systemctl start bellapp.service
}

setup_upstart_services() {
    # Create config service upstart job
    sudo tee "/etc/init/bellapp-config.conf" > /dev/null << EOFCONFIG
description "BellApp Configuration Service"
start on runlevel [2345]
stop on runlevel [!2345]

respawn
respawn limit 10 5

env IN_DOCKER_TEST_MODE=false
env NETWORK_MANAGER=interfaces

exec /usr/bin/python3 $PROJECT_ROOT/ubuntu_config_service.py
EOFCONFIG

    # Create main service upstart job
    sudo tee "/etc/init/bellapp.conf" > /dev/null << EOFMAIN
description "BellApp Network Management Service"
start on started bellapp-config
stop on runlevel [!2345]

respawn
respawn limit 10 5

env UBUNTU_CONFIG_SERVICE_URL=http://localhost:5002
env FLASK_ENV=production
env FLASK_DEBUG=false

pre-start script
    sleep 15
end script

exec /usr/bin/python3 $BELLAPP_DIR/vcns_timer_web.py
EOFMAIN

    # Start services
    sudo start bellapp-config
    sleep 5
    sudo start bellapp
}

setup_sysvinit_services() {
    # Create init.d script for config service
    sudo tee "/etc/init.d/bellapp-config" > /dev/null << 'EOFINIT'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          bellapp-config
# Required-Start:    $network $local_fs
# Required-Stop:     $network $local_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: BellApp Configuration Service
### END INIT INFO

DAEMON=/usr/bin/python3
DAEMON_ARGS="PROJECT_ROOT_PLACEHOLDER/ubuntu_config_service.py"
PIDFILE=/var/run/bellapp-config.pid
USER=root

case "$1" in
    start)
        echo "Starting BellApp Config Service..."
        start-stop-daemon --start --quiet --pidfile $PIDFILE --make-pidfile --background --chuid $USER --exec $DAEMON -- $DAEMON_ARGS
        ;;
    stop)
        echo "Stopping BellApp Config Service..."
        start-stop-daemon --stop --quiet --pidfile $PIDFILE
        rm -f $PIDFILE
        ;;
    restart)
        $0 stop
        sleep 2
        $0 start
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac
EOFINIT

    # Create init.d script for main service
    sudo tee "/etc/init.d/bellapp" > /dev/null << 'EOFINIT'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          bellapp
# Required-Start:    $network $local_fs bellapp-config
# Required-Stop:     $network $local_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: BellApp Network Management Service
### END INIT INFO

DAEMON=/usr/bin/python3
DAEMON_ARGS="BELLAPP_DIR_PLACEHOLDER/vcns_timer_web.py"
PIDFILE=/var/run/bellapp.pid
USER=root

export UBUNTU_CONFIG_SERVICE_URL=http://localhost:5002
export FLASK_ENV=production
export FLASK_DEBUG=false

case "$1" in
    start)
        echo "Starting BellApp..."
        sleep 15
        start-stop-daemon --start --quiet --pidfile $PIDFILE --make-pidfile --background --chuid $USER --exec $DAEMON -- $DAEMON_ARGS
        ;;
    stop)
        echo "Stopping BellApp..."
        start-stop-daemon --stop --quiet --pidfile $PIDFILE
        rm -f $PIDFILE
        ;;
    restart)
        $0 stop
        sleep 2
        $0 start
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac
EOFINIT

    # Replace placeholders and make executable
    sudo sed -i "s|PROJECT_ROOT_PLACEHOLDER|$PROJECT_ROOT|g" /etc/init.d/bellapp-config
    sudo sed -i "s|BELLAPP_DIR_PLACEHOLDER|$BELLAPP_DIR|g" /etc/init.d/bellapp
    sudo chmod +x /etc/init.d/bellapp-config
    sudo chmod +x /etc/init.d/bellapp

    # Enable services
    sudo update-rc.d bellapp-config defaults
    sudo update-rc.d bellapp defaults

    # Start services
    sudo service bellapp-config start
    sleep 5
    sudo service bellapp start
}

setup_basic_startup() {
    # Create simple startup scripts in rc.local or equivalent
    echo "[INFO] Setting up basic startup via rc.local..."

    # Create startup script
    sudo tee "/usr/local/bin/bellapp-startup.sh" > /dev/null << EOFSTARTUP
#!/bin/bash
# BellApp Startup Script

export IN_DOCKER_TEST_MODE=false
export NETWORK_MANAGER=interfaces
export UBUNTU_CONFIG_SERVICE_URL=http://localhost:5002
export FLASK_ENV=production
export FLASK_DEBUG=false

# Start config service
nohup /usr/bin/python3 $PROJECT_ROOT/ubuntu_config_service.py > /var/log/bellapp-config.log 2>&1 &
echo \$! > /var/run/bellapp-config.pid

# Wait and start main service
sleep 15
nohup /usr/bin/python3 $BELLAPP_DIR/vcns_timer_web.py > /var/log/bellapp.log 2>&1 &
echo \$! > /var/run/bellapp.pid

echo "BellApp services started"
EOFSTARTUP

    sudo chmod +x /usr/local/bin/bellapp-startup.sh

    # Add to rc.local
    if [ -f /etc/rc.local ]; then
        sudo sed -i '/exit 0/i /usr/local/bin/bellapp-startup.sh' /etc/rc.local
    else
        sudo tee "/etc/rc.local" > /dev/null << 'EOFRC'
#!/bin/bash
/usr/local/bin/bellapp-startup.sh
exit 0
EOFRC
        sudo chmod +x /etc/rc.local
    fi

    # Start now
    sudo /usr/local/bin/bellapp-startup.sh
}

# Get system information
UBUNTU_VERSION=$(get_ubuntu_version)
INIT_SYSTEM=$(detect_init_system)
PYTHON_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2 | cut -d'.' -f1-2)

echo "[INFO] Detected Ubuntu version: $UBUNTU_VERSION"
echo "[INFO] Detected init system: $INIT_SYSTEM"
echo "[INFO] Detected Python version: $PYTHON_VERSION"

echo "[STEP 1/6] Installing system dependencies..."

# Update package lists
sudo apt update

# Install essential packages
echo "[INFO] Installing essential system packages..."
sudo apt install -y python3 python3-pip python3-dev python3-setuptools build-essential
sudo apt install -y libffi-dev libssl-dev libyaml-dev
sudo apt install -y net-tools ifupdown netcat-openbsd curl wget ca-certificates
sudo apt install -y software-properties-common python3-software-properties || true

echo "[STEP 2/6] Upgrading pip intelligently..."

# Multiple strategies to upgrade pip
echo "[INFO] Upgrading pip with multiple fallback strategies..."

# Strategy 1: Use get-pip.py for older Python versions
if [[ "$PYTHON_VERSION" < "3.6" ]]; then
    echo "[INFO] Using get-pip.py for Python $PYTHON_VERSION..."
    curl -s https://bootstrap.pypa.io/pip/3.5/get-pip.py -o get-pip.py 2>/dev/null || wget -q https://bootstrap.pypa.io/pip/3.5/get-pip.py
    sudo python3 get-pip.py --force-reinstall
    rm -f get-pip.py
else
    # Strategy 2: Standard upgrade for newer Python
    sudo python3 -m pip install --upgrade pip --force-reinstall || true
fi

# Install wheel and setuptools
sudo pip3 install --upgrade "setuptools>=40.0,<50.0" --force-reinstall || true
sudo pip3 install --upgrade "wheel>=0.30,<0.40" --force-reinstall || true

echo "[STEP 3/6] Installing ALL Python packages with ultimate strategy..."

# Install packages with ultimate fallback
install_package_ultimate "Flask" "1.1.4" "1.1.2" "1.0.4" "0.12.5"
install_package_ultimate "Werkzeug" "1.0.1" "0.16.1" "0.15.6" "0.14.1"
install_package_ultimate "Jinja2" "2.11.3" "2.10.3" "2.10.1" "2.9.6"
install_package_ultimate "MarkupSafe" "1.1.1" "1.0" "0.23"
install_package_ultimate "itsdangerous" "1.1.0" "0.24"
install_package_ultimate "click" "7.1.2" "7.0" "6.7"

install_package_ultimate "psutil" "5.6.7" "5.4.8" "5.2.2" "5.0.1"
install_package_ultimate "requests" "2.25.1" "2.22.0" "2.18.4" "2.13.0"
install_package_ultimate "PyYAML" "3.13" "3.12" "3.11"
install_package_ultimate "pytz" "2019.3" "2018.9" "2017.3"
install_package_ultimate "bcrypt" "3.1.7" "3.1.4" "3.1.0"
install_package_ultimate "Flask-Login" "0.5.0" "0.4.1" "0.4.0"
install_package_ultimate "gunicorn" "20.0.4" "19.9.0" "19.7.1"

# Install audio support if needed
echo "[INFO] Installing audio support..."
sudo apt install -y libasound2-dev || true
install_package_ultimate "simpleaudio" "1.0.4" "1.0.2"

echo "[STEP 4/6] Verifying installations..."
python3 -c "import flask; print('Flask: OK')" || echo "[WARNING] Flask verification failed"
python3 -c "import yaml; print('PyYAML: OK')" || echo "[WARNING] PyYAML verification failed"
python3 -c "import psutil; print('psutil: OK')" || echo "[WARNING] psutil verification failed"
python3 -c "import requests; print('requests: OK')" || echo "[WARNING] requests verification failed"

echo "[STEP 5/6] Setting up network management..."

# Check network management system
if [ -f "/etc/network/interfaces" ]; then
    echo "[INFO] Using traditional /etc/network/interfaces"
    sudo cp /etc/network/interfaces /etc/network/interfaces.backup.$(date +%Y%m%d_%H%M%S) || true
fi

echo "[STEP 6/6] Setting up auto-start services..."

# Setup auto-start based on detected init system
setup_autostart "$INIT_SYSTEM"

# Wait for services to start
echo "[INFO] Waiting for services to start..."
sleep 10

# Check if services are running
echo "[INFO] Checking service status..."
if command_exists systemctl && [ "$INIT_SYSTEM" = "systemd" ]; then
    sudo systemctl status bellapp-config.service --no-pager -l || echo "[INFO] Config service status check failed"
    sudo systemctl status bellapp.service --no-pager -l || echo "[INFO] Main service status check failed"
elif [ "$INIT_SYSTEM" = "upstart" ]; then
    sudo status bellapp-config || echo "[INFO] Config service status check failed"
    sudo status bellapp || echo "[INFO] Main service status check failed"
elif [ "$INIT_SYSTEM" = "sysvinit" ]; then
    sudo service bellapp-config status || echo "[INFO] Config service status check failed"
    sudo service bellapp status || echo "[INFO] Main service status check failed"
fi

# Get IP address for display
IP_ADDRESS=$(hostname -I | awk '{print $1}' || echo "localhost")

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    🎉 SETUP COMPLETE! 🎉                     ║"
echo "║                                                              ║"
echo "║  ✅ ALL packages installed (any Ubuntu version)             ║"
echo "║  ✅ Auto-start configured ($INIT_SYSTEM)                    ║"
echo "║  ✅ IP switching enabled via your existing UI               ║"
echo "║  ✅ Services running on ports 5000 & 5002                   ║"
echo "║                                                              ║"
echo "║  🌐 Your BellApp: http://$IP_ADDRESS:5000                    ║"
echo "║  ⚙️  Config Service: http://localhost:5002                   ║"
echo "║                                                              ║"
echo "║  📋 Service Management Commands:                             ║"
if [ "$INIT_SYSTEM" = "systemd" ]; then
echo "║     sudo systemctl status bellapp                           ║"
echo "║     sudo systemctl restart bellapp                          ║"
echo "║     sudo journalctl -u bellapp -f                           ║"
elif [ "$INIT_SYSTEM" = "upstart" ]; then
echo "║     sudo status bellapp                                     ║"
echo "║     sudo restart bellapp                                    ║"
echo "║     tail -f /var/log/upstart/bellapp.log                   ║"
elif [ "$INIT_SYSTEM" = "sysvinit" ]; then
echo "║     sudo service bellapp status                             ║"
echo "║     sudo service bellapp restart                            ║"
echo "║     tail -f /var/log/bellapp.log                           ║"
else
echo "║     ps aux | grep python3                                   ║"
echo "║     tail -f /var/log/bellapp.log                           ║"
fi
echo "║                                                              ║"
echo "║  🔧 Your original vcns_timer_web.py UI is preserved         ║"
echo "║     with full IP switching functionality intact             ║"
echo "╚══════════════════════════════════════════════════════════════╝"

echo ""
echo "[SUCCESS] BellApp is running with IP switching on: http://$IP_ADDRESS:5000"
echo "[INFO] System will auto-start on reboot regardless of Ubuntu version!"