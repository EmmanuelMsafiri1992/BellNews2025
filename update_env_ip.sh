#!/bin/bash

# Script to automatically update Laravel .env file with current IP address
# Usage: ./update_env_ip.sh [interface_name]

INTERFACE=${1:-eth0}
ENV_FILE="./newsapp/.env"

# Get current IP address
CURRENT_IP=$(ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p')

if [ -z "$CURRENT_IP" ]; then
    echo "Error: Could not detect IP address for interface $INTERFACE"
    exit 1
fi

echo "Detected IP address: $CURRENT_IP"

# Update .env file
if [ -f "$ENV_FILE" ]; then
    # Backup original file
    cp "$ENV_FILE" "$ENV_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Update APP_URL
    sed -i "s|APP_URL=.*|APP_URL=http://$CURRENT_IP:8000|g" "$ENV_FILE"
    
    # Update VITE_API_BASE_URL
    sed -i "s|VITE_API_BASE_URL=.*|VITE_API_BASE_URL=http://$CURRENT_IP:8000|g" "$ENV_FILE"
    
    echo "Updated $ENV_FILE with IP: $CURRENT_IP"
    echo "Backup created: $ENV_FILE.backup.$(date +%Y%m%d_%H%M%S)"
else
    echo "Error: $ENV_FILE not found"
    exit 1
fi

# Restart Docker containers to apply changes
echo "Restarting Docker containers..."
docker-compose down
docker-compose up -d

echo "IP update complete!"