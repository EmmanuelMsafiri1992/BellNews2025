#!/bin/bash

# Docker Management Script for NanoPi NEO
# This script provides easy management of your Docker services

set -e

# Auto-fix time before running any Docker operations
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
if [ -f "$SCRIPT_DIR/auto-time-fix.sh" ]; then
    echo "🕒 Running auto time fix..."
    bash "$SCRIPT_DIR/auto-time-fix.sh" || echo "Time fix completed with warnings"
fi

PROJECT_NAME="fbellnewsupdatedv3"

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

# Check if we're running as root (recommended for NanoPi)
check_permissions() {
    if [[ $EUID -eq 0 ]]; then
        print_status "Running as root - good for NanoPi management"
    else
        print_warning "Not running as root - some operations may require sudo"
    fi
}

# Get current IP address
get_current_ip() {
    IP=$(hostname -I | awk '{print $1}')
    echo $IP
}

# Update environment files with current IP
update_ip_config() {
    local current_ip=$(get_current_ip)
    print_status "Updating configuration with IP: $current_ip"
    
    # Update Laravel .env file
    if [[ -f "newsapp/.env" ]]; then
        # Backup current .env
        cp newsapp/.env newsapp/.env.backup.$(date +%Y%m%d_%H%M%S)
        
        # Update IP addresses
        sed -i "s|APP_URL=.*|APP_URL=http://$current_ip:8000|g" newsapp/.env
        sed -i "s|VITE_API_BASE_URL=.*|VITE_API_BASE_URL=http://$current_ip:8000|g" newsapp/.env
        
        print_success "Updated Laravel .env file with IP: $current_ip"
    else
        print_error "Laravel .env file not found"
    fi
}

# Start services
start_services() {
    print_status "Starting Docker services..."
    update_ip_config
    
    # Use production compose file
    docker-compose -f docker-compose.prod.yml up -d
    
    print_success "Services started"
    sleep 5
    
    # Show status
    show_status
}

# Stop services
stop_services() {
    print_status "Stopping Docker services..."
    docker-compose -f docker-compose.prod.yml down
    print_success "Services stopped"
}

# Restart services
restart_services() {
    print_status "Restarting Docker services..."
    stop_services
    sleep 2
    start_services
}

# Show service status
show_status() {
    print_status "Current service status:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    echo
    print_status "Service URLs (replace with your actual IP):"
    local current_ip=$(get_current_ip)
    echo "  📱 BellApp:      http://$current_ip:5000"
    echo "  📰 NewsApp:      http://$current_ip:8000"
    echo "  ⚙️  Config:       http://$current_ip:5002"
    echo "  🔧 Vite Dev:     http://$current_ip:5173"
}

# Show logs
show_logs() {
    local service=${1:-""}
    
    if [[ -n "$service" ]]; then
        print_status "Showing logs for $service..."
        docker logs -f --tail 50 "$service"
    else
        print_status "Available services:"
        echo "  - bellapp"
        echo "  - newsapp" 
        echo "  - config_service"
        echo
        echo "Usage: $0 logs <service_name>"
    fi
}

# Clean up old containers and images
cleanup() {
    print_status "Cleaning up Docker resources..."
    
    # Remove stopped containers
    docker container prune -f
    
    # Remove unused images
    docker image prune -f
    
    # Remove unused volumes
    docker volume prune -f
    
    print_success "Cleanup completed"
}

# Health check
health_check() {
    print_status "Running health check..."
    
    if [[ -f "health_check.py" ]]; then
        python3 health_check.py
    else
        print_warning "health_check.py not found, running basic checks..."
        
        # Basic container check
        if docker ps | grep -q "${PROJECT_NAME}"; then
            print_success "Containers are running"
        else
            print_error "No containers running"
        fi
        
        # Basic connectivity check
        local current_ip=$(get_current_ip)
        if curl -s "http://$current_ip:5000" > /dev/null; then
            print_success "BellApp is responding"
        else
            print_error "BellApp is not responding"
        fi
    fi
}

# Build and update
build_update() {
    print_status "Building and updating services..."
    update_ip_config
    
    # Build with no cache to ensure latest changes
    docker-compose -f docker-compose.prod.yml build --no-cache
    
    # Restart services
    docker-compose -f docker-compose.prod.yml down
    docker-compose -f docker-compose.prod.yml up -d
    
    print_success "Build and update completed"
}

# Backup configuration
backup_config() {
    local backup_dir="backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    print_status "Creating configuration backup in $backup_dir..."
    
    # Backup important files
    cp -r newsapp/.env "$backup_dir/" 2>/dev/null || true
    cp -r bellapp/config.json "$backup_dir/" 2>/dev/null || true
    cp -r docker-compose*.yml "$backup_dir/"
    cp -r *.py "$backup_dir/" 2>/dev/null || true
    
    print_success "Backup created: $backup_dir"
}

# Show help
show_help() {
    echo "NanoPi NEO Docker Management Script"
    echo "Usage: $0 [COMMAND]"
    echo
    echo "Commands:"
    echo "  start         Start all services"
    echo "  stop          Stop all services" 
    echo "  restart       Restart all services"
    echo "  status        Show service status"
    echo "  logs [name]   Show logs for a service"
    echo "  health        Run health check"
    echo "  cleanup       Clean up Docker resources"
    echo "  build         Build and update services"
    echo "  backup        Backup configuration"
    echo "  ip-update     Update IP configuration"
    echo "  help          Show this help"
    echo
    echo "Examples:"
    echo "  $0 start"
    echo "  $0 logs bellapp"
    echo "  $0 health"
}

# Main script logic
main() {
    cd "$SCRIPT_DIR"
    check_permissions
    
    case "${1:-help}" in
        "start")
            start_services
            ;;
        "stop")
            stop_services
            ;;
        "restart")
            restart_services
            ;;
        "status")
            show_status
            ;;
        "logs")
            show_logs "$2"
            ;;
        "health")
            health_check
            ;;
        "cleanup")
            cleanup
            ;;
        "build")
            build_update
            ;;
        "backup")
            backup_config
            ;;
        "ip-update")
            update_ip_config
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

main "$@"