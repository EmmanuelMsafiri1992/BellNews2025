# Bell News Deployment Guide

## 🚀 Complete Installation

### Initial Installation (First Time)
```bash
# 1. Clone/Download the repository
git clone https://github.com/yourusername/BellNews2025.git
cd BellNews2025/bellapp

# 2. Make installer executable
chmod +x bellnews_installer.sh

# 3. Run the installer
sudo ./bellnews_installer.sh install
```

### System Update (After Changes)
```bash
# 1. Navigate to project directory
cd /path/to/BellNews2025/bellapp

# 2. Make update script executable
chmod +x update_system.sh

# 3. Run the update
sudo ./update_system.sh
```

## 🔧 Key Components

### Main Files
- **`vcns_timer_web.py`** - Main web interface (Flask app with login)
- **`nanopi_monitor.py`** - Hardware monitoring and display
- **`alarms.json`** - Alarm configurations (must be array format)

### Service Management
```bash
# Start service
sudo systemctl start bellnews

# Stop service
sudo systemctl stop bellnews

# Restart service
sudo systemctl restart bellnews

# Check status
sudo systemctl status bellnews

# View logs
sudo journalctl -u bellnews -f
```

## 📁 Directory Structure
```
/opt/bellnews/           # Application files
├── vcns_timer_web.py    # Main web server
├── nanopi_monitor.py    # Hardware monitor
├── alarms.json          # Alarm storage (array format)
├── static/              # Web assets
└── templates/           # HTML templates

/var/log/bellnews/       # Log files
├── monitor.log          # Hardware monitor logs
└── webtimer.log         # Web server logs
```

## 🌐 Web Interface
- **URL**: http://[nanopi-ip]:5000
- **Login**: Uses authentication system in vcns_timer_web.py
- **Features**: Timer management, alarms, system monitoring

## 🔊 Audio System
- **Pygame Compatibility**: Uses intelligent stub system
- **Audio Playback**: Falls back to system `aplay` command
- **Sound Files**: Stored in `/opt/bellnews/static/audio/`

## 🛠 Troubleshooting

### Common Issues

#### 1. Login Not Working (404 Error)
**Problem**: Frontend getting 404 on /login endpoint
**Solution**: Ensure service is running `vcns_timer_web.py` not `nano_web_timer.py`
```bash
ps aux | grep vcns_timer_web.py
sudo systemctl restart bellnews
```

#### 2. Alarms File Error
**Problem**: "Alarms file is not a list" error
**Solution**: Fix alarms.json format
```bash
echo '[]' | sudo tee /opt/bellnews/alarms.json
sudo systemctl restart bellnews
```

#### 3. Pygame Import Error
**Problem**: ImportError: No module named pygame
**Solution**: Pygame stub is automatically installed, verify:
```bash
python3 -c "import pygame; pygame.mixer.init(); print('OK')"
```

#### 4. Service Won't Start
**Problem**: systemctl start fails
**Solution**: Check logs and dependencies
```bash
sudo journalctl -u bellnews --no-pager -n 50
sudo systemctl status bellnews
```

### Log Locations
- **Service logs**: `sudo journalctl -u bellnews -f`
- **Web server**: `/var/log/bellnews/webtimer.log`
- **Hardware monitor**: `/var/log/bellnews/monitor.log`

## 🔄 Git Workflow

### Developer Workflow
```bash
# 1. Make changes to code
git add .
git commit -m "Your changes"
git push origin main
```

### NanoPi Update Workflow
```bash
# 1. Pull latest changes
git pull origin main

# 2. Run system update
sudo ./update_system.sh

# 3. Verify everything works
sudo systemctl status bellnews
curl -I http://localhost:5000
```

## 📋 System Requirements
- **OS**: Ubuntu 16.04+ (ARM compatible)
- **Python**: 3.8+ (3.10.6 tested and working)
- **Memory**: 512MB+ recommended
- **Storage**: 2GB+ free space
- **Network**: Internet access for initial setup

## 🎯 Quick Start Commands

```bash
# Complete fresh installation
sudo ./bellnews_installer.sh install

# Update existing installation
sudo ./update_system.sh

# Check system status
sudo systemctl status bellnews

# Access web interface
# http://[your-nanopi-ip]:5000

# View live logs
sudo journalctl -u bellnews -f
```

## ✅ Success Indicators
- ✅ Service shows "active (running)"
- ✅ Both processes visible: `vcns_timer_web.py` and `nanopi_monitor.py`
- ✅ Web interface accessible at port 5000
- ✅ Login functionality works (no 404 errors)
- ✅ No "alarms file" errors in logs
- ✅ Pygame imports successfully