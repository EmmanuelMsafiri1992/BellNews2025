#!/bin/bash
# Nano Pi Deployment Script
# Optimized deployment script for pulling and running pre-built images

set -e

# Configuration
COMPOSE_FILE="docker-compose.nanopi.yml"
ENV_FILE=".env"
DOCKER_HUB_USERNAME="${DOCKER_HUB_USERNAME:-yourusername}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🚀 Nano Pi Deployment Script${NC}"
echo -e "${BLUE}============================${NC}"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Docker is not running. Please start Docker first.${NC}"
    exit 1
fi

# Check if docker-compose is available
if ! command -v docker-compose > /dev/null 2>&1; then
    echo -e "${RED}❌ docker-compose not found. Please install docker-compose.${NC}"
    exit 1
fi

# Create environment file if it doesn't exist
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${YELLOW}📝 Creating environment file...${NC}"
    cp .env.docker .env
    echo -e "${GREEN}✅ Environment file created. Please update Docker Hub username in .env${NC}"
fi

# Load environment variables
if [ -f "$ENV_FILE" ]; then
    export $(cat $ENV_FILE | sed 's/#.*//g' | xargs)
fi

# Function to check system resources
check_system_resources() {
    echo -e "${BLUE}🔍 Checking system resources...${NC}"
    
    # Check available disk space (at least 2GB)
    available_space=$(df / | awk 'NR==2 {print $4}')
    required_space=$((2 * 1024 * 1024))  # 2GB in KB
    
    if [ "$available_space" -lt "$required_space" ]; then
        echo -e "${RED}⚠️  Warning: Low disk space. Available: $(df -h / | awk 'NR==2 {print $4}')${NC}"
        echo -e "${YELLOW}   Consider cleaning up old Docker images with: docker system prune -a${NC}"
    else
        echo -e "${GREEN}✅ Sufficient disk space available${NC}"
    fi
    
    # Check available memory
    available_memory=$(free -m | awk 'NR==2{printf "%.1f", $7/1024}')
    echo -e "${BLUE}💾 Available memory: ${available_memory}GB${NC}"
}

# Function to cleanup old containers and images
cleanup_old_resources() {
    echo -e "${BLUE}🧹 Cleaning up old resources...${NC}"
    
    # Stop and remove old containers
    docker-compose -f "$COMPOSE_FILE" down 2>/dev/null || true
    
    # Remove unused images (keeping recent ones)
    docker image prune -f
    
    echo -e "${GREEN}✅ Cleanup completed${NC}"
}

# Function to pull latest images
pull_images() {
    echo -e "${BLUE}📥 Pulling latest images...${NC}"
    
    # Pull all images defined in docker-compose
    if docker-compose -f "$COMPOSE_FILE" pull; then
        echo -e "${GREEN}✅ All images pulled successfully${NC}"
    else
        echo -e "${RED}❌ Failed to pull some images. Check your Docker Hub username and network connection.${NC}"
        exit 1
    fi
}

# Function to start services
start_services() {
    echo -e "${BLUE}🚀 Starting services...${NC}"
    
    # Start all services
    if docker-compose -f "$COMPOSE_FILE" up -d; then
        echo -e "${GREEN}✅ All services started successfully${NC}"
    else
        echo -e "${RED}❌ Failed to start services${NC}"
        exit 1
    fi
}

# Function to check service health
check_service_health() {
    echo -e "${BLUE}🏥 Checking service health...${NC}"
    
    # Wait for services to be ready
    sleep 30
    
    # Check each service
    services=("bellapp" "newsapp" "config_service")
    
    for service in "${services[@]}"; do
        if docker-compose -f "$COMPOSE_FILE" ps "$service" | grep -q "Up"; then
            echo -e "${GREEN}✅ $service is running${NC}"
        else
            echo -e "${YELLOW}⚠️  $service may not be ready yet${NC}"
        fi
    done
    
    # Check HTTP endpoints
    echo -e "${BLUE}🌐 Checking HTTP endpoints...${NC}"
    
    # Check Python app
    if curl -f http://localhost:5000/health > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Python app (port 5000) is responding${NC}"
    else
        echo -e "${YELLOW}⚠️  Python app not responding yet (may still be starting)${NC}"
    fi
    
    # Check Laravel app
    if curl -f http://localhost:8000 > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Laravel app (port 8000) is responding${NC}"
    else
        echo -e "${YELLOW}⚠️  Laravel app not responding yet (may still be starting)${NC}"
    fi
}

# Function to show deployment summary
show_deployment_summary() {
    echo ""
    echo -e "${GREEN}🎉 Deployment completed!${NC}"
    echo -e "${BLUE}==================${NC}"
    echo ""
    echo -e "${BLUE}📋 Service URLs:${NC}"
    echo -e "   🐍 Python App:  http://localhost:5000"
    echo -e "   🌐 Laravel App: http://localhost:8000"
    echo -e "   ⚙️  Config Service: http://localhost:5002"
    echo ""
    echo -e "${BLUE}🛠️  Management Commands:${NC}"
    echo -e "   View logs:    docker-compose -f $COMPOSE_FILE logs -f"
    echo -e "   Stop all:     docker-compose -f $COMPOSE_FILE stop"
    echo -e "   Restart:      docker-compose -f $COMPOSE_FILE restart"
    echo -e "   Update:       ./deploy-nanopi.sh"
    echo ""
    echo -e "${YELLOW}💡 Tip: Services may take a few minutes to fully initialize${NC}"
}

# Main deployment process
main() {
    check_system_resources
    cleanup_old_resources
    pull_images
    start_services
    check_service_health
    show_deployment_summary
}

# Handle script arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "pull-only")
        pull_images
        ;;
    "start")
        start_services
        ;;
    "stop")
        docker-compose -f "$COMPOSE_FILE" stop
        echo -e "${GREEN}✅ Services stopped${NC}"
        ;;
    "restart")
        docker-compose -f "$COMPOSE_FILE" restart
        echo -e "${GREEN}✅ Services restarted${NC}"
        ;;
    "logs")
        docker-compose -f "$COMPOSE_FILE" logs -f
        ;;
    "status")
        docker-compose -f "$COMPOSE_FILE" ps
        ;;
    "cleanup")
        cleanup_old_resources
        ;;
    *)
        echo "Usage: $0 [deploy|pull-only|start|stop|restart|logs|status|cleanup]"
        echo ""
        echo "Commands:"
        echo "  deploy     - Full deployment (default)"
        echo "  pull-only  - Only pull latest images"
        echo "  start      - Start services"
        echo "  stop       - Stop all services"
        echo "  restart    - Restart all services"
        echo "  logs       - Show service logs"
        echo "  status     - Show service status"
        echo "  cleanup    - Clean up old resources"
        exit 1
        ;;
esac