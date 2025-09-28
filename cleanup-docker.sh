#!/bin/bash
# Docker cleanup script for Nano Pi optimization

echo "🧹 Starting Docker cleanup for Nano Pi..."

# Clean up build cache (7.2GB freed)
echo "Cleaning Docker build cache..."
docker builder prune -af

# Remove unused images
echo "Removing unused Docker images..."
docker image prune -af

# Remove unused containers
echo "Removing stopped containers..."
docker container prune -f

# Remove unused volumes
echo "Removing unused volumes..."
docker volume prune -f

# Remove unused networks
echo "Removing unused networks..."
docker network prune -f

# System cleanup - remove everything not in use
echo "Running system-wide cleanup..."
docker system prune -af --volumes

echo "✅ Docker cleanup complete!"
echo "💾 Disk space reclaimed. Run 'docker system df' to see current usage."