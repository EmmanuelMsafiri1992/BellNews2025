# 🚀 Nano Pi Deployment Instructions

## 🔧 ARCHITECTURE FIX
**IMPORTANT**: The `exec format error` was caused by platform conflicts. All `--platform=linux/arm64` specifications have been removed to let Docker auto-detect ARM64.

## Quick Commands for Nano Pi

After you `git pull` the latest changes, run these commands on your Nano Pi:

### 1. Complete Cleanup First
```bash
# Stop everything and clean up
sudo docker-compose -f docker-compose.prod.yml down --remove-orphans
sudo docker system prune -a -f
sudo docker builder prune -a -f

# Kill any stuck processes
sudo pkill -f docker-compose
```

### 2. Fix DNS (if needed)
```bash
# Quick DNS fix
sudo bash -c 'cat > /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
options timeout:2
options attempts:3
EOF'

# Restart Docker
sudo systemctl restart docker
sleep 5
```

### 3. Build and Run
```bash
# Option A: Use the ultimate fix script
sudo bash ULTIMATE-NANO-PI-FIX.sh

# Option B: Manual build (if script has issues)
sudo docker-compose -f docker-compose.prod.yml build --no-cache
sudo docker-compose -f docker-compose.prod.yml up -d
```

### 4. Check Status
```bash
# View running containers
docker-compose -f docker-compose.prod.yml ps

# View logs if needed
docker-compose -f docker-compose.prod.yml logs -f [service-name]
```

## Service URLs
- **Laravel App**: http://[nano-pi-ip]:8000
- **Python App**: http://[nano-pi-ip]:5000
- **Config Service**: http://[nano-pi-ip]:5002
- **Vite Dev**: http://[nano-pi-ip]:5173

## Troubleshooting

### If APT cache error still occurs:
```bash
# Nuclear Docker cleanup
sudo systemctl stop docker
sudo rm -rf /var/lib/docker/tmp/*
sudo systemctl start docker

# Then rebuild
sudo docker-compose -f docker-compose.prod.yml build --no-cache laravelapp
```

### If DNS issues persist:
```bash
# Test DNS
nslookup registry-1.docker.io

# If fails, run the network fix
sudo bash auto-network-fix.sh
```

### If memory issues:
```bash
# Add swap if not present
sudo fallocate -l 1G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

## Files Updated for ARM64 Compatibility:
- ✅ `newsapp/Dockerfile` - Fixed APT cache issues
- ✅ `ULTIMATE-NANO-PI-FIX.sh` - Complete automated solution
- ✅ `auto-network-fix.sh` - DNS resolution fixes
- ✅ `build-nano-pi-fast.sh` - Fast build with ARM64 detection
- ✅ `docker-compose.nano-pi-fast.yml` - ARM64-optimized override