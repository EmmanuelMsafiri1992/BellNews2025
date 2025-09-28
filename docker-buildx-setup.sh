#!/bin/bash
# Docker Buildx Setup Script for Multi-Architecture Builds
# This script sets up Docker buildx for building multi-architecture images

set -e

echo "🏗️  Setting up Docker Buildx for Multi-Architecture Builds"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Enable Docker experimental features if not already enabled
echo "📋 Checking Docker experimental features..."
if ! docker version --format '{{.Client.Experimental}}' | grep -q true; then
    echo "⚠️  Docker experimental features not enabled. Please enable them in Docker Desktop settings."
    echo "   Go to Settings > Docker Engine and add: \"experimental\": true"
fi

# Create a new buildx builder instance
echo "🔧 Creating buildx builder instance..."
if docker buildx ls | grep -q "bellnews-builder"; then
    echo "✅ Builder 'bellnews-builder' already exists"
    docker buildx use bellnews-builder
else
    docker buildx create --name bellnews-builder --driver docker-container --bootstrap
    docker buildx use bellnews-builder
    echo "✅ Created and activated builder 'bellnews-builder'"
fi

# Inspect the builder to ensure it supports multiple platforms
echo "📊 Inspecting builder capabilities..."
docker buildx inspect --bootstrap

# List available platforms
echo "🌐 Available platforms:"
docker buildx ls

echo ""
echo "✅ Docker Buildx setup complete!"
echo ""
echo "📝 Next steps:"
echo "   1. Build multi-architecture images using the build script"
echo "   2. Push images to Docker Hub"
echo "   3. Deploy on Nano Pi using the optimized docker-compose file"
echo ""
echo "🚀 Ready to build for AMD64 and ARM64 architectures!"