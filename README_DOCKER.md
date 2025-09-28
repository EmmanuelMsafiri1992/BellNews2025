# BellNews V3 - Multi-Architecture Docker Deployment

A comprehensive news application with Python backend, Laravel frontend, and Ubuntu configuration service, optimized for deployment on ARM64 devices like Nano Pi.

## 🏗️ Architecture

- **Python App (bellapp)**: Flask-based backend service with timer and monitoring functionality
- **Laravel App (newsapp)**: Modern frontend with Vue.js, optimized for TV compatibility  
- **Config Service**: Ubuntu network configuration management
- **Time Fix**: System time synchronization service

## 🚀 Quick Start for Nano Pi

### Prerequisites
- Docker and docker-compose installed
- At least 2GB available disk space
- Network connection for pulling images

### One-Command Deployment
```bash
# Clone repository and navigate to project
git clone <your-repo-url>
cd BellNewsV3/v7

# Deploy with pre-built images (no building required!)
./deploy-nanopi.sh
```

### Manual Deployment
```bash
# 1. Set up environment
cp .env.docker .env
# Edit .env and set your DOCKER_HUB_USERNAME

# 2. Pull and start services
docker-compose -f docker-compose.nanopi.yml pull
docker-compose -f docker-compose.nanopi.yml up -d

# 3. Check status
docker-compose -f docker-compose.nanopi.yml ps
```

## 🛠️ Development Setup

### Local Development with Multi-Architecture Support
```bash
# Set up Docker buildx for multi-architecture builds
./docker-buildx-setup.sh

# Build images locally
./build-multi-arch.sh

# Start development environment
docker-compose -f docker-compose.dev.multi-arch.yml --profile dev up -d
```

### Building and Pushing Images
```bash
# Set your Docker Hub username and build + push
DOCKER_HUB_USERNAME=yourusername PUSH_IMAGES=true ./build-multi-arch.sh
```

## 📁 File Structure

```
v7/
├── bellapp/                          # Python Flask application
│   ├── Dockerfile.multi-arch        # Multi-arch Python Dockerfile
│   └── .dockerignore.optimized      # Optimized Docker ignore
├── newsapp/                          # Laravel application  
│   ├── Dockerfile.multi-arch        # Multi-arch Laravel Dockerfile
│   └── .dockerignore.optimized      # Optimized Docker ignore
├── docker-compose.nanopi.yml        # Production deployment (Nano Pi)
├── docker-compose.dev.multi-arch.yml # Development environment
├── docker-buildx-setup.sh           # Buildx configuration
├── build-multi-arch.sh              # Multi-architecture build script
├── deploy-nanopi.sh                 # Nano Pi deployment script
└── .github/workflows/docker-build.yml # GitHub Actions CI/CD
```

## 🌐 Available Services

| Service | Port | Description |
|---------|------|-------------|
| Python App | 5000 | Main backend API and monitoring |
| Laravel App | 8000 | Frontend web interface |
| Config Service | 5002 | Network configuration management |

## 🔄 Update Workflow

### For Developers
```bash
# 1. Make code changes
# 2. Push to GitHub
git add .
git commit -m "Your changes"
git push

# 3. GitHub Actions automatically builds and pushes images
```

### For Nano Pi Deployment  
```bash
# Simply pull and restart - no building required!
./deploy-nanopi.sh
```

## 📊 Performance Comparison

| Method | Time | Description |
|--------|------|-------------|
| **Traditional Build** | 10-15 min | Build all services on Nano Pi |
| **Pre-built Images** | 2-3 min | Pull and run (recommended) |

## 🛠️ Management Commands

```bash
# View logs
docker-compose -f docker-compose.nanopi.yml logs -f

# Stop services
./deploy-nanopi.sh stop

# Restart services  
./deploy-nanopi.sh restart

# Check status
./deploy-nanopi.sh status

# Clean up old resources
./deploy-nanopi.sh cleanup
```

## 🔧 Customization

### Environment Variables (.env)
```bash
DOCKER_HUB_USERNAME=yourusername
IMAGE_TAG=latest
APP_ENV=production
UBUNTU_CONFIG_SERVICE_URL=http://localhost:5002
```

### Service Profiles
```bash
# Start only apps (no config service)
docker-compose -f docker-compose.dev.multi-arch.yml --profile app-only up -d

# Full development environment
docker-compose -f docker-compose.dev.multi-arch.yml --profile full up -d
```

## 🐛 Troubleshooting

### Common Issues

**Services not starting:**
```bash
# Check logs
docker-compose -f docker-compose.nanopi.yml logs

# Check system resources
df -h
free -h
```

**Image pull failures:**
```bash
# Check Docker Hub username in .env
cat .env | grep DOCKER_HUB_USERNAME

# Test connectivity
docker pull hello-world
```

**Port conflicts:**
```bash
# Check what's using ports
sudo netstat -tulpn | grep :8000
sudo netstat -tulpn | grep :5000
```

## 📋 Health Checks

All services include health checks:
- **Python App**: `http://localhost:5000/health`
- **Laravel App**: `http://localhost:8000/health`  
- **Config Service**: `http://localhost:5002/health`

## 🏷️ Image Tags

| Tag | Description |
|-----|-------------|
| `latest` | Latest stable release |
| `main` | Latest from main branch |
| `develop` | Development branch |
| `commit-<hash>` | Specific commit |

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes and test locally
4. Push changes (GitHub Actions will build images)
5. Create a Pull Request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

- Create an issue on GitHub
- Check the troubleshooting section above
- Review container logs for detailed error information