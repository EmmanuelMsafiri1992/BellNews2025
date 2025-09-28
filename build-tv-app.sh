#!/bin/bash

# Build Script for TV-Compatible NewsApp
# This script builds the frontend with all TV browser optimizations

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
NEWSAPP_DIR="$PROJECT_DIR/newsapp"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the right directory
if [[ ! -d "$NEWSAPP_DIR" ]]; then
    print_error "NewsApp directory not found at: $NEWSAPP_DIR"
    exit 1
fi

print_status "Building TV-Compatible NewsApp"
print_status "Project Directory: $PROJECT_DIR"
print_status "NewsApp Directory: $NEWSAPP_DIR"

# Navigate to NewsApp directory
cd "$NEWSAPP_DIR"

# Check if package.json exists
if [[ ! -f "package.json" ]]; then
    print_error "package.json not found in $NEWSAPP_DIR"
    exit 1
fi

# Install dependencies if node_modules doesn't exist or is outdated
if [[ ! -d "node_modules" ]] || [[ "package.json" -nt "node_modules" ]]; then
    print_status "Installing/updating dependencies..."
    npm install
    if [[ $? -ne 0 ]]; then
        print_error "Failed to install dependencies"
        exit 1
    fi
    print_success "Dependencies installed successfully"
else
    print_status "Dependencies are up to date"
fi

# Clean previous build
print_status "Cleaning previous build..."
rm -rf public/build
rm -rf public/hot
rm -rf storage/framework/cache/*
print_success "Previous build cleaned"

# Build for TV browsers
print_status "Building for TV browsers..."
npm run build

if [[ $? -ne 0 ]]; then
    print_error "Build failed"
    exit 1
fi

print_success "TV-compatible build completed successfully"

# Verify build output
if [[ -d "public/build" ]]; then
    BUILD_SIZE=$(du -sh public/build | cut -f1)
    print_success "Build output created: public/build ($BUILD_SIZE)"
    
    # List generated files
    print_status "Generated files:"
    find public/build -name "*.js" -o -name "*.css" | while read file; do
        SIZE=$(du -h "$file" | cut -f1)
        echo "  - $(basename "$file") ($SIZE)"
    done
else
    print_warning "Build directory not found, but build reported success"
fi

# Clear Laravel caches
print_status "Clearing Laravel caches..."
php artisan route:clear
php artisan config:clear
php artisan view:clear

# Optimize Laravel for production
print_status "Optimizing Laravel..."
php artisan route:cache
php artisan config:cache
php artisan view:cache

print_success "Laravel optimization completed"

# Copy test files to public directory
print_status "Copying test files..."
cp ../tv-browser-test.html public/tv-test.html 2>/dev/null || print_warning "TV browser test file not found"
cp ../test-ip-detection.html public/ip-test.html 2>/dev/null || print_warning "IP detection test file not found"

# Set proper permissions
print_status "Setting file permissions..."
chmod -R 755 public/build
chmod 644 public/*.html

# Generate build information
BUILD_INFO_FILE="public/build-info.json"
cat > "$BUILD_INFO_FILE" << EOF
{
    "build_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "build_type": "tv-compatible",
    "node_version": "$(node --version)",
    "npm_version": "$(npm --version)",
    "git_commit": "$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')",
    "optimizations": [
        "tv-polyfills",
        "legacy-browser-support",
        "ip-auto-detection",
        "network-recovery",
        "tv-remote-navigation"
    ],
    "supported_browsers": [
        "Samsung Tizen TV",
        "LG WebOS TV",
        "Android TV",
        "Generic TV browsers"
    ]
}
EOF

print_success "Build information saved to $BUILD_INFO_FILE"

# Display final summary
echo
print_success "=== BUILD COMPLETED SUCCESSFULLY ==="
echo
print_status "Your TV-compatible NewsApp is ready!"
print_status "Key features enabled:"
echo "  ✅ Automatic IP detection"
echo "  ✅ Network recovery system"
echo "  ✅ TV browser compatibility"
echo "  ✅ Remote navigation support"
echo "  ✅ Legacy browser polyfills"
echo
print_status "Test URLs (replace with your actual IP):"
echo "  📱 Main App:        http://your-ip:8000"
echo "  🧪 TV Browser Test: http://your-ip:8000/tv-test.html"
echo "  🌐 IP Detection:    http://your-ip:8000/ip-test.html"
echo
print_status "To start the application:"
echo "  cd $PROJECT_DIR"
echo "  ./docker-management.sh start"
echo

# Optional: Show current IP
CURRENT_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "unknown")
if [[ "$CURRENT_IP" != "unknown" && "$CURRENT_IP" != "" ]]; then
    print_status "Current server IP: $CURRENT_IP"
    echo "  📱 Direct access: http://$CURRENT_IP:8000"
fi

print_success "Build script completed!"