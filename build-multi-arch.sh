#!/bin/bash
# Multi-Architecture Docker Image Build Script
# Builds and pushes images for both AMD64 and ARM64 architectures

set -e

# Configuration
DOCKER_HUB_USERNAME="${DOCKER_HUB_USERNAME:-yourusername}"  # Replace with your Docker Hub username
IMAGE_TAG="${IMAGE_TAG:-latest}"
PUSH_IMAGES="${PUSH_IMAGES:-false}"  # Set to true to push to Docker Hub

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🏗️  Multi-Architecture Docker Build Script${NC}"
echo -e "${BLUE}===========================================${NC}"

# Check if buildx builder exists
if ! docker buildx ls | grep -q "bellnews-builder"; then
    echo -e "${YELLOW}⚠️  Buildx builder not found. Running setup...${NC}"
    ./docker-buildx-setup.sh
fi

# Use the bellnews-builder
docker buildx use bellnews-builder

# Function to build and optionally push an image
build_image() {
    local service_name=$1
    local dockerfile_path=$2
    local context_path=$3
    local image_name="${DOCKER_HUB_USERNAME}/bellnews-${service_name}:${IMAGE_TAG}"
    
    echo -e "${BLUE}🔨 Building ${service_name} for AMD64 and ARM64...${NC}"
    
    if [ "${PUSH_IMAGES}" = "true" ]; then
        echo -e "${GREEN}📤 Building and pushing ${image_name}${NC}"
        docker buildx build \
            --platform linux/amd64,linux/arm64 \
            --file "${dockerfile_path}" \
            --tag "${image_name}" \
            --push \
            "${context_path}"
    else
        echo -e "${YELLOW}🏗️  Building ${image_name} (local only)${NC}"
        docker buildx build \
            --platform linux/amd64,linux/arm64 \
            --file "${dockerfile_path}" \
            --tag "${image_name}" \
            --load \
            "${context_path}" || \
        # If --load fails (multi-platform), build without load
        docker buildx build \
            --platform linux/amd64,linux/arm64 \
            --file "${dockerfile_path}" \
            --tag "${image_name}" \
            "${context_path}"
    fi
    
    echo -e "${GREEN}✅ ${service_name} build completed${NC}"
    echo ""
}

# Build all services
echo -e "${BLUE}🚀 Starting multi-architecture build process...${NC}"
echo ""

# Build newsapp (Laravel)
build_image "newsapp" "./newsapp/Dockerfile.multi-arch" "./newsapp"

# Build bellapp (Python)
build_image "bellapp" "./bellapp/Dockerfile.multi-arch" "./bellapp"

# Build config service
build_image "config-service" "./Dockerfile_config.multi-arch" "."

# Build time-fix service
build_image "time-fix" "./Dockerfile.timefix" "."

echo -e "${GREEN}🎉 All builds completed successfully!${NC}"
echo ""

if [ "${PUSH_IMAGES}" = "true" ]; then
    echo -e "${GREEN}📤 All images have been pushed to Docker Hub${NC}"
    echo -e "${BLUE}🌐 Images are available at:${NC}"
    echo -e "   ${DOCKER_HUB_USERNAME}/bellnews-newsapp:${IMAGE_TAG}"
    echo -e "   ${DOCKER_HUB_USERNAME}/bellnews-bellapp:${IMAGE_TAG}"
    echo -e "   ${DOCKER_HUB_USERNAME}/bellnews-config-service:${IMAGE_TAG}"
    echo -e "   ${DOCKER_HUB_USERNAME}/bellnews-time-fix:${IMAGE_TAG}"
else
    echo -e "${YELLOW}💡 To push images to Docker Hub, run:${NC}"
    echo -e "   ${BLUE}DOCKER_HUB_USERNAME=yourusername PUSH_IMAGES=true ./build-multi-arch.sh${NC}"
fi

echo ""
echo -e "${GREEN}📋 Next steps for Nano Pi deployment:${NC}"
echo -e "   1. Update docker-compose.nanopi.yml with your Docker Hub username"
echo -e "   2. On Nano Pi: docker-compose -f docker-compose.nanopi.yml pull"
echo -e "   3. On Nano Pi: docker-compose -f docker-compose.nanopi.yml up -d"