# NanoPi NEO Setup & Management Guide

This guide provides setup and management instructions for your Bell News applications running on a NanoPi NEO with Ubuntu 16.04.

## 🔧 System Requirements

- **Device**: NanoPi NEO (or similar ARM-based mini PC)
- **OS**: Ubuntu 16.04 LTS
- **RAM**: 512MB minimum
- **Storage**: 8GB+ microSD card
- **Network**: Ethernet connection

## 🚀 Quick Start

### 1. Make Scripts Executable
```bash
chmod +x docker-management.sh update_env_ip.sh
chmod +x health_check.py
```

### 2. Start Services
```bash
# Easy way using management script
./docker-management.sh start

# Or manually
docker-compose -f docker-compose.prod.yml up -d
```

### 3. Check Status
```bash
./docker-management.sh status
# or
./docker-management.sh health
```

## 📱 Service URLs

Replace `192.168.33.3` with your actual IP address:

- **BellApp (Main)**: `http://192.168.33.3:5000`
- **NewsApp (Laravel)**: `http://192.168.33.3:8000`
- **Config Service**: `http://192.168.33.3:5002`
- **Vite Dev Server**: `http://192.168.33.3:5173`

## 🌐 IP Address Management

### Switching Between Static and Dynamic IP

#### Option 1: Using the Web Interface
1. Access Config Service: `http://your-ip:5002`
2. Send POST request to `/apply_network_settings` with:
```json
{
  "ipType": "static",
  "ipAddress": "192.168.1.100",
  "subnetMask": "255.255.255.0", 
  "gateway": "192.168.1.1",
  "dnsServer": "8.8.8.8"
}
```

#### Option 2: Manual Configuration (Ubuntu 16.04)
Edit `/etc/network/interfaces`:

**For Static IP:**
```bash
sudo nano /etc/network/interfaces
```
```ini
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address 192.168.33.145
    netmask 255.255.255.0
    gateway 192.168.33.254
    dns-nameservers 8.8.8.8
```

**For Dynamic IP (DHCP):**
```ini
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
```

**Apply Changes:**
```bash
sudo service networking restart
# or
sudo ifdown eth0 && sudo ifup eth0
```

### Update Application Configuration After IP Change
```bash
# Update .env files automatically
./update_env_ip.sh

# Or manually update and restart
./docker-management.sh ip-update
./docker-management.sh restart
```

## 🛠️ Management Commands

### Docker Management Script
```bash
# Start all services
./docker-management.sh start

# Stop all services  
./docker-management.sh stop

# Restart services
./docker-management.sh restart

# Show status
./docker-management.sh status

# View logs
./docker-management.sh logs bellapp
./docker-management.sh logs newsapp
./docker-management.sh logs config_service

# Health check
./docker-management.sh health

# Clean up unused Docker resources
./docker-management.sh cleanup

# Build and update (after code changes)
./docker-management.sh build

# Backup configuration
./docker-management.sh backup
```

### Individual Docker Commands
```bash
# View running containers
docker ps

# View container logs
docker logs -f bellapp
docker logs -f newsapp
docker logs -f config_service

# Enter container shell
docker exec -it bellapp bash
docker exec -it newsapp bash
docker exec -it config_service bash

# Restart individual container
docker restart bellapp
```

## 🔍 Troubleshooting

### Common Issues

#### 1. Services Not Accessible from Other Devices
**Problem**: Can access locally but not from other devices on network.

**Solutions**:
- Check firewall: `sudo ufw status`
- Allow ports: `sudo ufw allow 5000,8000,5002,5173/tcp`
- Verify IP binding in Docker containers
- Check network interface: `ip addr show eth0`

#### 2. IP Address Shows Both Dynamic and Static
**Problem**: `ip addr show eth0` shows multiple IP addresses.

**Solutions**:
```bash
# Remove dynamic IP
sudo ip addr del 192.168.33.3/24 dev eth0

# Stop DHCP client
sudo dhclient -r eth0

# Restart networking
sudo service networking restart
```

#### 3. Docker Containers Won't Start
**Problem**: Containers fail to start or exit immediately.

**Solutions**:
```bash
# Check logs
docker logs container_name

# Check disk space
df -h

# Clean up resources
./docker-management.sh cleanup

# Rebuild containers
./docker-management.sh build
```

#### 4. Laravel API Returns 404
**Problem**: `/api/news` and `/api/settings` return 404 errors.

**Solutions**:
```bash
# Check Laravel routes
docker exec -it newsapp php artisan route:list

# Clear Laravel cache
docker exec -it newsapp php artisan route:clear
docker exec -it newsapp php artisan optimize:clear

# Restart Laravel container
docker restart newsapp
```

### Performance Optimization for Low-Resource Systems

#### 1. Reduce Memory Usage
Add to `docker-compose.prod.yml`:
```yaml
services:
  pythonapp:
    mem_limit: 128m
  laravelapp:
    mem_limit: 256m
  config_service:
    mem_limit: 64m
```

#### 2. Use Swap File (if needed)
```bash
# Create 1GB swap file
sudo fallocate -l 1G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make permanent
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

#### 3. Optimize Docker
```bash
# Limit Docker log size
sudo nano /etc/docker/daemon.json
```
```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

## 📋 Monitoring & Maintenance

### Daily Health Checks
```bash
# Run comprehensive health check
python3 health_check.py

# Continuous monitoring (Ctrl+C to stop)
python3 health_check.py --continuous
```

### Weekly Maintenance
```bash
# Backup configuration
./docker-management.sh backup

# Clean up Docker resources
./docker-management.sh cleanup

# Update system packages
sudo apt update && sudo apt upgrade -y

# Restart services
./docker-management.sh restart
```

### Log Management
```bash
# View recent logs
./docker-management.sh logs bellapp | tail -50

# Archive old logs
sudo journalctl --vacuum-time=7d
```

## 🔐 Security Considerations

### 1. Firewall Configuration
```bash
# Enable firewall
sudo ufw enable

# Allow only necessary ports
sudo ufw allow ssh
sudo ufw allow 5000,8000,5002,5173/tcp
sudo ufw allow from 192.168.0.0/16  # Allow local network
```

### 2. Regular Updates
```bash
# Update system packages monthly
sudo apt update && sudo apt upgrade -y

# Update Docker images
docker-compose pull
./docker-management.sh build
```

### 3. Access Control
- Change default passwords in application settings
- Use HTTPS in production (consider adding nginx proxy)
- Restrict config service access to local network only

## 📞 Support

For issues specific to this setup:

1. Check logs: `./docker-management.sh logs [service]`
2. Run health check: `./docker-management.sh health`
3. Check system resources: `htop` or `free -h`
4. Verify network: `ip addr show eth0`

## 🔄 Backup & Recovery

### Create Backup
```bash
# Full backup
./docker-management.sh backup

# Manual backup
tar -czf backup_$(date +%Y%m%d).tar.gz \
  newsapp/.env \
  bellapp/config.json \
  docker-compose*.yml \
  *.py *.sh
```

### Restore from Backup
```bash
# Stop services
./docker-management.sh stop

# Extract backup
tar -xzf backup_YYYYMMDD.tar.gz

# Restart services  
./docker-management.sh start
```