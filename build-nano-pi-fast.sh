#!/bin/bash
# Ultra-fast build script optimized specifically for Nano Pi ARM64
# Focuses on minimal context and maximum caching

echo "🚀 Starting ULTRA-FAST Nano Pi build process..."

# Kill any existing containers to free resources
echo "🧹 Cleaning up existing containers..."
docker compose -f docker-compose.prod.optimized.yml down 2>/dev/null || true
docker system prune -f

# Enable all performance optimizations
export DOCKER_BUILDKIT=1
export BUILDKIT_PROGRESS=plain
export DOCKER_DEFAULT_PLATFORM=linux/arm64

echo "⚡ Building services with maximum optimization..."

# Build in stages to maximize cache usage and reduce memory pressure
echo "📦 Building config service (smallest first)..."
docker compose -f docker-compose.prod.optimized.yml build config_service

echo "🕐 Building time-fix service..."
docker compose -f docker-compose.prod.optimized.yml build time-fix

echo "🐍 Building Python app..."
docker compose -f docker-compose.prod.optimized.yml build pythonapp

echo "🌐 Building Laravel app (largest - last)..."
docker compose -f docker-compose.prod.optimized.yml build laravelapp

echo "🎯 Starting all services..."
docker compose -f docker-compose.prod.optimized.yml up -d

echo "✅ Build complete! Services status:"
docker compose -f docker-compose.prod.optimized.yml ps

echo "🎉 Your optimized application is now running!"
echo "📊 Access points:"
echo "   - Laravel News App: http://localhost:8000"
echo "   - Python API: http://localhost:5000"
echo "   - Config Service: http://localhost:5002"