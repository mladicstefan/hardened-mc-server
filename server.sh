#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CONTAINER_NAME="minecraft-server"
COMPOSE_FILE="docker-compose.yml"

print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

check_docker() {
    if ! command -v docker &>/dev/null; then
        print_error "Docker is not installed"
        exit 1
    fi

    if ! docker compose version &>/dev/null 2>&1; then
        print_error "Docker Compose plugin is not installed"
        exit 1
    fi
}

is_running() {
    docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
}

start_server() {
    print_status "Starting Minecraft server..."

    if is_running; then
        print_warning "Server is already running"
        return 0
    fi

    DATA_DIR="/opt/minecraft/data"

    if [ ! -d "$DATA_DIR" ]; then
        print_status "Creating data directory..."
        sudo mkdir -p "$DATA_DIR"
        sudo chown -R 25565:25565 "$DATA_DIR"

        # Extract server files from image on first run
        print_status "Extracting server files..."
        docker compose build --quiet
        docker compose run --rm --entrypoint="" minecraft \
            sh -c "cp /minecraft/server.jar /minecraft/eula.txt /minecraft/server.properties /opt/out/" \
            2>/dev/null || {
            # Alternative: copy from a temporary container
            TEMP_CONTAINER=$(docker create minecraft-server)
            docker cp "$TEMP_CONTAINER":/minecraft/server.jar "$DATA_DIR/"
            docker cp "$TEMP_CONTAINER":/minecraft/eula.txt "$DATA_DIR/"
            docker cp "$TEMP_CONTAINER":/minecraft/server.properties "$DATA_DIR/"
            docker rm "$TEMP_CONTAINER"
        }
        sudo chown -R 25565:25565 "$DATA_DIR"
    fi

    if [ ! -f "whitelist.json" ]; then
        print_status "Creating whitelist.json..."
        echo '[]' >whitelist.json
    fi

    if [ ! -f "ops.json" ]; then
        print_status "Creating ops.json..."
        echo '[]' >ops.json
    fi

    docker compose up -d
    print_success "Server started successfully"

    print_status "Waiting for server to be ready..."
    sleep 10

    if is_running; then
        print_success "Server is running"
        docker compose logs --tail=20
    else
        print_error "Server failed to start"
        docker compose logs --tail=50
        exit 1
    fi
}

stop_server() {
    print_status "Stopping Minecraft server..."

    if ! is_running; then
        print_warning "Server is not running"
        return 0
    fi

    docker compose down

    print_success "Server stopped successfully"
}

restart_server() {
    print_status "Restarting Minecraft server..."
    stop_server
    sleep 3
    start_server
}

status_server() {
    if is_running; then
        print_success "Server is running"
        echo ""
        docker stats --no-stream "$CONTAINER_NAME"
        echo ""
        print_status "Recent logs:"
        docker compose logs --tail=20
    else
        print_warning "Server is not running"
    fi
}

logs_server() {
    if is_running; then
        docker compose logs -f
    else
        print_error "Server is not running"
        exit 1
    fi
}

rebuild_server() {
    print_status "Rebuilding server image..."
    docker compose build --no-cache
    print_success "Rebuild complete"

    read -p "Restart server now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        restart_server
    fi
}

build_server(){
    print_status "Rebuilding server image..."
    docker compose build --no-cache --pull
    print_success "Rebuild complete"

    read -p "Start server now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
       start_server 
    fi
}

backup_world() {
    BACKUP_DIR="/opt/minecraft/world"
    BACKUP_FILE="$BACKUP_DIR/world-backup-$(date +%Y%m%d-%H%M%S).tar.gz"

    print_status "Creating world backup..."

    sudo mkdir -p "$BACKUP_DIR"
    sudo tar -czf "$BACKUP_FILE" -C /opt/minecraft world

    print_success "Backup created: $BACKUP_FILE"

    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    print_status "Backup size: $BACKUP_SIZE"
}

show_help() {
    echo "Minecraft Server Control Script"
    echo ""
    echo "Usage: $0 {start|stop|restart|status|logs|rebuild|backup}"
    echo ""
    echo "Commands:"
    echo "  start    - Start the Minecraft server"
    echo "  stop     - Stop the Minecraft server"
    echo "  restart  - Restart the Minecraft server"
    echo "  status   - Show server status and stats"
    echo "  logs     - Follow server logs (Ctrl+C to exit)"
    echo "  rebuild  - Rebuild Docker image from scratch"
    echo "  backup   - Create world backup"
    echo ""
}

check_docker

case "$1" in
start)
    start_server
    ;;
build)
    build_server
    ;;
stop)
    stop_server
    ;;
restart)
    restart_server
    ;;
status)
    status_server
    ;;
logs)
    logs_server
    ;;
rebuild)
    rebuild_server
    ;;
backup)
    backup_world
    ;;
*)
    show_help
    exit 1
    ;;
esac

exit 0
