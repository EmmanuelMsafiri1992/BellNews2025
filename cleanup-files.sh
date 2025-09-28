#!/bin/bash
# File cleanup script to remove duplicate Dockerfiles

echo "🗂️ Cleaning up duplicate Docker files..."

# Create backup directory
mkdir -p backup/$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="backup/$(date +%Y%m%d_%H%M%S)"

echo "📦 Creating backup in $BACKUP_DIR..."

# Backup old files before deletion
cp -r newsapp/vendor/laravel/sail/runtimes/ "$BACKUP_DIR/" 2>/dev/null || true
cp bellapp/Dockerfile.bak "$BACKUP_DIR/" 2>/dev/null || true
cp Dockerfile_config.bak "$BACKUP_DIR/" 2>/dev/null || true
cp Dockerfile.timefix "$BACKUP_DIR/" 2>/dev/null || true
cp newsapp/Dockerfile.fast "$BACKUP_DIR/" 2>/dev/null || true
cp newsapp/Dockerfile.multi-arch "$BACKUP_DIR/" 2>/dev/null || true
cp bellapp/Dockerfile.multi-arch "$BACKUP_DIR/" 2>/dev/null || true
cp Dockerfile_config.multi-arch "$BACKUP_DIR/" 2>/dev/null || true
cp docker-compose.override.yml "$BACKUP_DIR/" 2>/dev/null || true
cp docker-compose.minimal.yml "$BACKUP_DIR/" 2>/dev/null || true
cp docker-compose.dev.yml "$BACKUP_DIR/" 2>/dev/null || true
cp docker-compose.prod.yml "$BACKUP_DIR/" 2>/dev/null || true
cp docker-compose.dev.multi-arch.yml "$BACKUP_DIR/" 2>/dev/null || true

echo "🗑️ Removing duplicate files..."

# Remove Laravel Sail runtime Dockerfiles (not needed)
rm -rf newsapp/vendor/laravel/sail/runtimes/

# Remove backup Dockerfiles
rm -f bellapp/Dockerfile.bak
rm -f Dockerfile_config.bak
rm -f Dockerfile.timefix

# Remove old experimental Dockerfiles
rm -f newsapp/Dockerfile.fast
rm -f newsapp/Dockerfile.multi-arch
rm -f bellapp/Dockerfile.multi-arch
rm -f Dockerfile_config.multi-arch

# Remove redundant docker-compose files
rm -f docker-compose.override.yml
rm -f docker-compose.minimal.yml
rm -f docker-compose.dev.yml
rm -f docker-compose.prod.yml
rm -f docker-compose.dev.multi-arch.yml

echo "✅ File cleanup complete!"
echo "📁 Backup created in: $BACKUP_DIR"
echo "🚀 Use the optimized files for faster builds:"
echo "   - newsapp/Dockerfile.optimized"
echo "   - bellapp/Dockerfile.optimized"
echo "   - Dockerfile_config.optimized"
echo "   - docker-compose.fast.yml"