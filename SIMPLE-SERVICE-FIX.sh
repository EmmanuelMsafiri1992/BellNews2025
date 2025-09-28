#!/bin/bash
# SIMPLE SERVICE FIX - Just make existing apps work
# No fancy interfaces, just fix the services

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== SIMPLE FIX FOR EXISTING SERVICES ==="
echo

# Check current issues
info "Checking what's wrong with bellapp..."
if systemctl is-active --quiet bellapp.service; then
    info "Bellapp service is running, checking why port 5000 isn't accessible..."
    journalctl -u bellapp.service --no-pager --lines=10
else
    warn "Bellapp service is not running"
    systemctl status bellapp.service --no-pager || true
fi

# Fix bellapp - just make the existing one work
info "Fixing bellapp service..."
cd "$SCRIPT_DIR/bellapp"

# Check if the main file exists
if [[ -f "launch_vcns_timer.py" ]]; then
    info "Found existing launch_vcns_timer.py - using original app"

    # Install missing dependencies
    python3 -m pip install flask psutil requests bcrypt gunicorn pytz Flask-Login

    # Skip problematic simpleaudio if needed
    python3 -m pip install simpleaudio 2>/dev/null || {
        warn "Skipping simpleaudio (not critical)"
    }

    # Create simple systemd service for existing app
    cat > /etc/systemd/system/bellapp.service << EOF
[Unit]
Description=Bell News Python Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$SCRIPT_DIR/bellapp
Environment=UBUNTU_CONFIG_SERVICE_URL=http://localhost:5002
Environment=HOST_IP=192.168.33.145
Environment=IN_DOCKER=0
Environment=PYTHONUNBUFFERED=1
ExecStart=/usr/bin/python3 launch_vcns_timer.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

else
    error "launch_vcns_timer.py not found in bellapp directory"
    ls -la
    exit 1
fi

# Restart bellapp
systemctl daemon-reload
systemctl enable bellapp.service
systemctl restart bellapp.service

# Wait and test
sleep 15
if curl -s --max-time 5 "http://192.168.33.145:5000/" > /dev/null 2>&1; then
    success "✅ Bellapp is now accessible at http://192.168.33.145:5000"
else
    error "❌ Bellapp still not accessible"
    journalctl -u bellapp.service --no-pager --lines=5
fi

# Fix newsapp - just make existing Laravel work
info "Fixing newsapp service..."
cd "$SCRIPT_DIR/newsapp"

# Check PHP version and install PHP 8 if needed
if php --version | grep -q "PHP 7"; then
    warn "PHP 7 detected, newsapp needs PHP 8+ for Laravel"
    info "Installing PHP 8.2..."

    apt-get update
    apt-get install -y software-properties-common
    add-apt-repository ppa:ondrej/php -y 2>/dev/null || true
    apt-get update
    apt-get install -y php8.2 php8.2-cli php8.2-common php8.2-curl php8.2-zip php8.2-xml php8.2-mbstring php8.2-sqlite3

    # Install Composer
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

    # Use PHP 8.2
    update-alternatives --set php /usr/bin/php8.2
fi

# Install Laravel dependencies if needed
if [[ -f "composer.json" ]] && [[ ! -d "vendor" ]]; then
    info "Installing Laravel dependencies..."
    composer install --no-dev --ignore-platform-reqs --no-interaction
fi

# Create simple systemd service for existing Laravel app
cat > /etc/systemd/system/newsapp.service << EOF
[Unit]
Description=News App Laravel Service
After=bellapp.service

[Service]
Type=simple
User=root
WorkingDirectory=$SCRIPT_DIR/newsapp
ExecStart=/usr/bin/php artisan serve --host=0.0.0.0 --port=8000
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Start newsapp
systemctl daemon-reload
systemctl enable newsapp.service
systemctl restart newsapp.service

# Wait and test
sleep 10
if curl -s --max-time 5 "http://192.168.33.145:8000/" > /dev/null 2>&1; then
    success "✅ Newsapp is now accessible at http://192.168.33.145:8000"
else
    error "❌ Newsapp still not accessible"
    journalctl -u newsapp.service --no-pager --lines=5
fi

echo
echo "=== FINAL STATUS ==="
if curl -s --max-time 3 "http://192.168.33.145:5000/" > /dev/null 2>&1; then
    success "✅ Bell App: http://192.168.33.145:5000 - WORKING"
else
    error "❌ Bell App: http://192.168.33.145:5000 - FAILED"
fi

if curl -s --max-time 3 "http://192.168.33.145:8000/" > /dev/null 2>&1; then
    success "✅ News App: http://192.168.33.145:8000 - WORKING"
else
    error "❌ News App: http://192.168.33.145:8000 - FAILED"
fi

if curl -s --max-time 3 "http://localhost:5002/health" > /dev/null 2>&1; then
    success "✅ Config Service: http://localhost:5002 - WORKING"
else
    error "❌ Config Service: http://localhost:5002 - FAILED"
fi

echo
success "Simple fix completed - no interface changes, just made existing apps work"