# FBellNewsV3 - Automatic Setup & Time Fix

This application now includes **automatic time synchronization** to prevent SSL certificate and Docker build issues when transferring to Ubuntu systems.

## 🚀 One-Command Setup

For **new Ubuntu installations**, run this single command:

```bash
chmod +x quick-start.sh && ./quick-start.sh
```

This will:
- ✅ Automatically detect and install missing dependencies (Docker, Docker Compose)
- ✅ Fix system time issues that cause SSL/Docker problems  
- ✅ Configure firewall and environment
- ✅ Build and start all services
- ✅ Show you the application URLs

## 📁 Files Added for Auto Time Fix

### Core Files
- `auto-time-fix.sh` - Main time synchronization script
- `network-monitor.sh` - Network change detection & auto-recovery
- `network-config-handler.sh` - Handles DHCP ↔ Static IP changes
- `ubuntu-setup.sh` - Complete Ubuntu system setup
- `quick-start.sh` - One-command launch script
- `README_AUTO_SETUP.md` - This documentation

### Updated Files
- `docker-compose.dev.yml` - Added time-fix service and dependencies
- `docker-management.sh` - Added auto time fix before Docker operations
- `ubuntu-setup.sh` - Added network monitoring service installation

## 🕒 How Auto-Recovery Works

### Automatic Triggers
The system automatically handles:
- **Time synchronization issues** - Before Docker operations, at startup, every 30 minutes
- **Network configuration changes** - DHCP ↔ Static IP changes without reboot
- **Docker service failures** - Auto-restart containers after network changes
- **Application URL updates** - Updates Laravel config with new IP addresses

### Recovery Methods
1. **Time Sync** - Multiple NTP servers (Google, Cloudflare, NIST) + HTTP fallback
2. **Network Config** - Detects and handles NetworkManager, systemd-networkd, Netplan, dhcpcd
3. **Docker Recovery** - Graceful container restart with fresh network configuration
4. **Service Monitoring** - Continuous health checking every 10 seconds

### Supported Systems
- ✅ Ubuntu 18.04, 20.04, 22.04, 24.04
- ✅ Debian 10, 11, 12
- ✅ NanoPi NEO and other ARM devices
- ✅ Virtual machines and containers
- ✅ Systems with incorrect/missing RTC

## 📋 Manual Usage

### Setup on Fresh Ubuntu System
```bash
# Make scripts executable
chmod +x *.sh

# Run full Ubuntu setup (requires sudo)
sudo ./ubuntu-setup.sh

# Or just start if already set up
./quick-start.sh
```

### Fix Time Issues Only
```bash
# Run time fix manually
sudo ./auto-time-fix.sh

# Check time fix log
tail -f /var/log/fbellnews-time-fix.log
```

### Network Configuration Management
```bash
# Change to static IP (no reboot needed!)
sudo ./network-config-handler.sh static 192.168.1.100 255.255.255.0 192.168.1.1

# Change to DHCP (no reboot needed!)
sudo ./network-config-handler.sh dhcp

# Monitor network changes automatically
./network-monitor.sh status
sudo ./network-monitor.sh start  # Runs as daemon
```

### Docker Management with Auto Time Fix
```bash
# All Docker operations now include automatic time fix
./docker-management.sh start
./docker-management.sh restart
./docker-management.sh status
```

## 🔧 Service URLs

After startup, access your application at:

- **News App**: `http://YOUR_IP:8000` (Main application)
- **Python API**: `http://YOUR_IP:5000` (Backend services)  
- **Config Service**: `http://YOUR_IP:5002` (System config)
- **Vite Dev**: `http://YOUR_IP:5173` (Development server)

## 📊 Monitoring & Logs

### View Service Status
```bash
docker-compose -f docker-compose.dev.yml ps
```

### View Application Logs
```bash
# All services
docker-compose -f docker-compose.dev.yml logs -f

# Specific service
docker-compose -f docker-compose.dev.yml logs -f newsapp
docker-compose -f docker-compose.dev.yml logs -f bellapp
```

### View Logs
```bash
# Time fix activity log
tail -f /var/log/fbellnews-time-fix.log

# Network monitoring log
tail -f /var/log/fbellnews-network-monitor.log

# Network configuration log
tail -f /var/log/fbellnews-network-config.log

# Setup log
tail -f /var/log/fbellnews-setup.log
```

## 🛠️ Troubleshooting

### Common Issues

**Docker build fails with SSL errors:**
```bash
# Run time fix manually
sudo ./auto-time-fix.sh
# Then retry Docker build
```

**Services won't start after IP change:**
```bash
# Check network monitor status
./network-monitor.sh status
# Manually test recovery
sudo ./network-monitor.sh test-recovery
```

**Network change not detected:**
```bash
# Check if network monitor is running
systemctl status fbellnews-network-monitor
# Restart network monitor
sudo systemctl restart fbellnews-network-monitor
```

**IP change requires reboot:**
```bash
# Use the network config handler instead
sudo ./network-config-handler.sh static 192.168.1.100 255.255.255.0 192.168.1.1
# Or for DHCP
sudo ./network-config-handler.sh dhcp
# No reboot needed!
```

**Time keeps reverting:**
```bash
# Check if hardware clock battery needs replacement
sudo hwclock --show
# The auto-fix service will handle most time sync issues
```

### Force Clean Restart
```bash
# Stop all services
docker-compose -f docker-compose.dev.yml down --volumes --rmi all

# Clean Docker system  
docker system prune -a -f

# Restart with fresh build
./quick-start.sh
```

## ⚙️ Advanced Configuration

### Customize NTP Servers
Edit `auto-time-fix.sh` and modify the `ntp_servers` array:
```bash
local ntp_servers=(
    "your.custom.ntp.server"
    "216.239.35.0"      # Google
    "162.159.200.1"     # Cloudflare
)
```

### Disable Auto Time Fix
To disable automatic time fixing:
1. Remove time-fix service from `docker-compose.dev.yml`
2. Remove time fix calls from `docker-management.sh`

### Custom Setup Options
The setup script supports environment variables:
```bash
# Skip firewall configuration
SKIP_FIREWALL=1 sudo ./ubuntu-setup.sh

# Use different Docker Compose file
COMPOSE_FILE=docker-compose.prod.yml ./quick-start.sh
```

## 🎯 What This Solves

This automatic setup eliminates all the issues you mentioned:

- ❌ **Before**: Manual dependency installation  
- ✅ **After**: Automatic detection and installation

- ❌ **Before**: SSL certificate errors due to wrong system time  
- ✅ **After**: Automatic time synchronization before any operations

- ❌ **Before**: Docker build failures on embedded systems  
- ✅ **After**: Robust time fix with multiple fallback methods

- ❌ **Before**: Reboot required for IP changes (DHCP ↔ Static)  
- ✅ **After**: Automatic network reconfiguration without reboot

- ❌ **Before**: Docker containers lose connectivity after IP change  
- ✅ **After**: Automatic Docker service recovery with new network config

- ❌ **Before**: Manual application URL updates after IP change  
- ✅ **After**: Automatic Laravel .env updates with new IP

- ❌ **Before**: Time/date lost after network changes  
- ✅ **After**: Automatic time resync after network recovery

- ❌ **Before**: Manual service restart after network issues  
- ✅ **After**: Continuous monitoring with automatic recovery

## 📞 Support

If you encounter issues:

1. Check the logs: `/var/log/fbellnews-time-fix.log` and `/var/log/fbellnews-setup.log`
2. Run manual time fix: `sudo ./auto-time-fix.sh`  
3. Try clean restart: `docker-compose -f docker-compose.dev.yml down && ./quick-start.sh`
4. Check system time: `date` (should be current year 2024/2025)

The auto-fix system is designed to handle most time-related issues automatically, making your application truly portable across different Ubuntu systems!