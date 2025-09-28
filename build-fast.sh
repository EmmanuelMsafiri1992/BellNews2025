#!/bin/bash
# Fast build script optimized for Nano Pi

echo "🚀 Starting optimized build for Nano Pi..."

# Enable BuildKit for faster builds
export DOCKER_BUILDKIT=1
export BUILDKIT_PROGRESS=plain

# Set platform for ARM64
export DOCKER_DEFAULT_PLATFORM=linux/arm64

echo "🧹 Cleaning up first..."
./cleanup-docker.sh

echo "🔨 Building with optimized Dockerfiles..."

# Build in parallel with BuildKit cache
docker-compose -f docker-compose.fast.yml build \
    --parallel \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    --build-arg DOCKER_BUILDKIT=1

echo "✅ Fast build complete!"
echo "🏃‍♂️ Starting services..."

# Start services
docker-compose -f docker-compose.fast.yml up -d

echo "🎉 All services started successfully!"
echo "📊 Check status with: docker-compose -f docker-compose.fast.yml ps"