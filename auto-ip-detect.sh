#!/bin/bash
# AUTO IP DETECTION SCRIPT FOR NANO PI
# Automatically detects and configures the correct IP address for Docker services
# Solves: Dynamic IP issues, static/DHCP switching problems

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

print_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              AUTO IP DETECTION FOR NANO PI                  ║"
    echo "║          Fixes Dynamic IP and Docker Networking             ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_banner

# Function to detect the primary IP address
detect_primary_ip() {
    local ip=""

    # Method 1: Check eth0 first (most common on Nano Pi)
    ip=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' | head -1)

    if [[ -n "$ip" && "$ip" != "127.0.0.1" ]]; then
        echo "$ip"
        return 0
    fi

    # Method 2: Check all interfaces for non-loopback IPs
    ip=$(ip addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)

    if [[ -n "$ip" ]]; then
        echo "$ip"
        return 0
    fi

    # Method 3: Fallback to hostname resolution
    ip=$(hostname -I | awk '{print $1}')

    if [[ -n "$ip" && "$ip" != "127.0.0.1" ]]; then
        echo "$ip"
        return 0
    fi

    # Method 4: Check for any IP in common ranges
    for interface in $(ls /sys/class/net/ | grep -v lo); do
        ip=$(ip addr show "$interface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        if [[ -n "$ip" && "$ip" != "127.0.0.1" ]]; then
            echo "$ip"
            return 0
        fi
    done

    # Default fallback
    echo "192.168.33.145"
}

# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Detect current IP
info "Detecting primary IP address..."
DETECTED_IP=$(detect_primary_ip)

if validate_ip "$DETECTED_IP"; then
    success "Detected IP: $DETECTED_IP"
else
    error "Could not detect valid IP address. Using fallback: 192.168.33.145"
    DETECTED_IP="192.168.33.145"
fi

# Create or update .env file with detected IP
ENV_FILE=".env"
if [[ -f "$ENV_FILE" ]]; then
    # Update existing .env file
    if grep -q "HOST_IP=" "$ENV_FILE"; then
        sed -i "s/HOST_IP=.*/HOST_IP=$DETECTED_IP/" "$ENV_FILE"
        info "Updated HOST_IP in existing .env file"
    else
        echo "HOST_IP=$DETECTED_IP" >> "$ENV_FILE"
        info "Added HOST_IP to existing .env file"
    fi
else
    # Create new .env file
    cp .env.docker .env 2>/dev/null || true
    echo "HOST_IP=$DETECTED_IP" >> "$ENV_FILE"
    info "Created new .env file with detected IP"
fi

# Update Docker Compose files with detected IP
info "Updating Docker Compose files..."

# Function to update compose file
update_compose_file() {
    local file=$1
    if [[ -f "$file" ]]; then
        # Create backup
        cp "$file" "${file}.backup.$(date +%s)"

        # Replace IP references
        sed -i "s/192\.168\.33\.145/$DETECTED_IP/g" "$file"
        sed -i "s/\${HOST_IP:-[^}]*}/\${HOST_IP:-$DETECTED_IP}/g" "$file"

        success "Updated $file"
    fi
}

# Update all compose files
update_compose_file "docker-compose.nanopi.yml"
update_compose_file "docker-compose.nanopi-fixed.yml"
update_compose_file "docker-compose.prod.yml"

# Export IP for current session
export HOST_IP="$DETECTED_IP"

# Create IP detection service for automatic updates
info "Creating IP detection service..."
cat > ip-detection-service.sh << 'EOF'
#!/bin/bash
# IP Detection Service - runs every 5 minutes to check for IP changes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

while true; do
    # Run IP detection
    bash auto-ip-detect.sh > /var/log/ip-detection.log 2>&1

    # Check if Docker containers need restart due to IP change
    CURRENT_IP=$(grep "HOST_IP=" .env | cut -d'=' -f2)
    RUNNING_IP=$(docker inspect newsapp 2>/dev/null | grep -o "192\.168\.[0-9]*\.[0-9]*" | head -1 || echo "")

    if [[ "$CURRENT_IP" != "$RUNNING_IP" && -n "$RUNNING_IP" ]]; then
        echo "IP changed from $RUNNING_IP to $CURRENT_IP - restarting containers"
        docker-compose -f docker-compose.nanopi-fixed.yml down
        sleep 5
        docker-compose -f docker-compose.nanopi-fixed.yml up -d
    fi

    sleep 300  # Check every 5 minutes
done
EOF

chmod +x ip-detection-service.sh

# Display current configuration
info "Current Configuration:"
echo -e "${GREEN}Detected IP:${NC} $DETECTED_IP"
echo -e "${GREEN}Network Interface:${NC}"
ip addr show | grep -A 2 "$DETECTED_IP" || echo "Interface details not available"

# Test network connectivity
info "Testing network connectivity..."
if ping -c 1 8.8.8.8 > /dev/null 2>&1; then
    success "Internet connectivity: OK"
else
    warn "Internet connectivity: Failed - check network configuration"
fi

# Create systemd service for automatic IP detection
if [[ -d "/etc/systemd/system" ]]; then
    info "Creating systemd service for automatic IP detection..."
    cat > /etc/systemd/system/nano-pi-ip-detection.service << EOF
[Unit]
Description=Nano Pi IP Detection Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/ip-detection-service.sh
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable nano-pi-ip-detection.service
    success "Created and enabled IP detection service"
fi

success "IP detection and configuration completed!"
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Run: docker-compose -f docker-compose.nanopi-fixed.yml up -d"
echo "2. Access bellapp at: http://$DETECTED_IP:5000"
echo "3. Access newsapp at: http://$DETECTED_IP:8000"
echo "4. Monitor logs: tail -f /var/log/ip-detection.log"