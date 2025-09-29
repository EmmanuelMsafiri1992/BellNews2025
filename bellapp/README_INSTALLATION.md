# 🔔 Bell News - Complete Installation Guide

## 🚀 One-Command Installation

### Method 1: Local Installation (Recommended)

1. **Transfer files to your NanoPi NEO3**
   ```bash
   # Copy all Bell News files to your NanoPi
   scp -r bellapp/ user@nanopi-ip:/home/user/
   ```

2. **Run the installer**
   ```bash
   cd /home/user/bellapp
   sudo bash bellnews_installer.sh install
   ```

### Method 2: Quick Install from Directory
```bash
cd /path/to/bellapp
sudo bash quick_install.sh
```

## 📋 What the Installer Does

### ✅ Automatic System Detection
- Detects NanoPi NEO3, Orange Pi, or Raspberry Pi
- Identifies Ubuntu version and architecture
- Checks available memory and resources

### ✅ Python 3.12 Compilation & Installation
- Downloads Python 3.12.8 source code
- Installs all build dependencies
- Compiles with optimizations enabled
- Creates `python3.12` command
- Preserves system Python 2.7 and Python 3.x

### ✅ Dependency Management
- **System packages**: i2c-tools, alsa-utils, build-essential, etc.
- **Python packages**: Flask, pygame, psutil, pytz, OPi.GPIO, luma.oled
- **Board-specific GPIO**: Automatically selects OPi.GPIO or RPi.GPIO

### ✅ Application Setup
- Copies files to `/opt/bellnews/`
- Sets proper permissions
- Creates configuration files
- Sets up logging directories

### ✅ Auto-Start Service
- Creates systemd service: `bellnews.service`
- Enables auto-start on boot
- Manages both monitor and web timer processes
- Includes automatic restart on failure

## 🎛️ Available Commands

```bash
# Install everything
sudo bash bellnews_installer.sh install

# Check status
sudo bash bellnews_installer.sh status

# Uninstall completely
sudo bash bellnews_installer.sh uninstall
```

## 📊 System Requirements

### ✅ Minimum Requirements
- **RAM**: 512MB (2GB recommended for NanoPi NEO3)
- **Storage**: 2GB free space
- **CPU**: ARM Cortex-A53 or better
- **OS**: Ubuntu 16.04+ or Debian 9+

### ✅ Supported Boards
- **NanoPi NEO3** ⭐ (Primary target)
- NanoPi NEO, NEO2, NEO4
- Orange Pi Zero, One, PC
- Raspberry Pi 3, 4, Zero 2W

## 🔧 Manual Installation Steps

If you prefer manual installation:

### 1. Update System
```bash
sudo apt update && sudo apt upgrade -y
```

### 2. Install Build Dependencies
```bash
sudo apt install -y build-essential libssl-dev zlib1g-dev \
    libncurses5-dev libffi-dev libsqlite3-dev wget make gcc \
    i2c-tools alsa-utils python3-pip python3-dev git
```

### 3. Compile Python 3.12
```bash
cd /usr/src
sudo wget https://www.python.org/ftp/python/3.12.8/Python-3.12.8.tgz
sudo tar xzf Python-3.12.8.tgz
cd Python-3.12.8
sudo ./configure --enable-optimizations
sudo make -j$(nproc)
sudo make altinstall
```

### 4. Install Python Dependencies
```bash
python3.12 -m pip install flask pygame psutil pytz requests \
    bcrypt gunicorn pillow luma.oled OPi.GPIO
```

### 5. Setup Application
```bash
sudo mkdir -p /opt/bellnews
sudo cp -r * /opt/bellnews/
sudo chmod +x /opt/bellnews/*.py
```

### 6. Create Service
```bash
sudo cp bellnews.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable bellnews
sudo systemctl start bellnews
```

## 🖥️ Post-Installation

### Check Status
```bash
sudo systemctl status bellnews
```

### View Logs
```bash
# Service logs
sudo journalctl -u bellnews -f

# Application logs
sudo tail -f /var/log/bellnews/monitor.log
sudo tail -f /var/log/bellnews/webtimer.log
```

### Access Web Interface
- **URL**: `http://your-nanopi-ip:5000`
- **Default port**: 5000
- **Features**: Alarm management, system monitoring

### Configuration
- **Main config**: `/opt/bellnews/config.json`
- **Monitor config**: `/opt/bellnews/nanopi_monitor_config.json`

## 🔌 Hardware Setup

### OLED Display (Optional)
- **Type**: SSD1306 128x64
- **Interface**: I2C
- **Address**: 0x3C or 0x3D
- **Pins**: SDA (Pin 3), SCL (Pin 5), VCC (3.3V), GND

### Buttons (Optional)
- **F1**: GPIO Pin 6 (Mode switch)
- **F2**: GPIO Pin 1 (Timezone change)
- **F3**: GPIO Pin 67 (NTP sync)
- **Connection**: Pin to GND via button

### Audio Output
- **3.5mm jack**: Built-in audio output
- **HDMI audio**: Available if HDMI connected
- **USB audio**: Supported via USB sound cards

## 🛠️ Troubleshooting

### Python Issues
```bash
# Check Python installation
python3.12 --version

# Check Python modules
python3.12 -c "import flask, pygame, psutil; print('OK')"

# Reinstall Python packages
python3.12 -m pip install --force-reinstall flask pygame psutil
```

### Service Issues
```bash
# Check service status
sudo systemctl status bellnews

# Restart service
sudo systemctl restart bellnews

# Check logs for errors
sudo journalctl -u bellnews --no-pager -n 50
```

### GPIO Issues
```bash
# Check GPIO library
python3.12 -c "import OPi.GPIO; print('OPi.GPIO OK')"

# Check I2C devices
sudo i2cdetect -y 1

# Test OLED display
python3.12 -c "from luma.oled.device import ssd1306; print('OLED OK')"
```

### Audio Issues
```bash
# Check audio devices
aplay -l

# Test audio
speaker-test -c 2 -t wav

# Fix audio permissions
sudo usermod -a -G audio root
```

## 🔄 Updates

### Update Bell News
```bash
cd /opt/bellnews
sudo git pull  # If using git
sudo systemctl restart bellnews
```

### Update Python Dependencies
```bash
python3.12 -m pip install --upgrade flask pygame psutil pytz
sudo systemctl restart bellnews
```

## 📱 Remote Management

### SSH Access
```bash
ssh user@nanopi-ip
```

### Web Interface
- **Alarm Management**: Set, edit, delete alarms
- **System Monitor**: CPU, RAM, temperature
- **Configuration**: Network, time settings
- **File Upload**: Upload custom alarm sounds

## 🎵 Adding Custom Alarm Sounds

1. **Via Web Interface**: Upload MP3 files through the web interface
2. **Via SSH**: Copy MP3 files to `/opt/bellnews/static/audio/`
3. **Supported formats**: MP3 (recommended), WAV, OGG

## 🔐 Security Notes

- Service runs as root (required for GPIO/hardware access)
- Web interface has no authentication (LAN use only)
- Firewall recommended for internet exposure
- Regular security updates recommended

## 📞 Support

### Log Files
- **Installer**: `/var/log/bellnews_installer.log`
- **Monitor**: `/var/log/bellnews/monitor.log`
- **Web Timer**: `/var/log/bellnews/webtimer.log`
- **System**: `sudo journalctl -u bellnews`

### Common Issues
1. **"Permission denied"**: Run with `sudo`
2. **"Module not found"**: Run installer again
3. **"Service failed"**: Check logs with `journalctl`
4. **"GPIO error"**: Check hardware connections
5. **"Audio not working"**: Check ALSA configuration

---

## 🎉 Success!

After installation:
- ✅ Bell News starts automatically on boot
- ✅ Web interface available at `http://nanopi-ip:5000`
- ✅ OLED display shows system information
- ✅ Alarms work with audio output
- ✅ All components monitored and auto-restart

**Your NanoPi NEO3 is now a complete Bell News alarm system!**