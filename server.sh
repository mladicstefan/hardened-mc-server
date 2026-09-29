#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CONTAINER_NAME="minecraft-server"
IMAGE_NAME="hardened-mc-server:latest"
MC_UID=25565
MC_GID=25565

BASE_DIR="/opt/minecraft"
DATA_DIR="$BASE_DIR/data"
BACKUP_DIR="$BASE_DIR/backups"

# Always operate relative to the repo, wherever the script is called from.
cd "$(dirname "$(readlink -f "$0")")"

print_status() { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "Run this script with sudo"
        exit 1
    fi
}

check_docker() {
    if ! command -v docker &>/dev/null; then
        print_error "Docker is not installed"
        exit 1
    fi
    if ! docker compose version &>/dev/null; then
        print_error "Docker Compose plugin is not installed"
        exit 1
    fi
}

is_running() {
    docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"
}

ensure_image() {
    if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
        print_status "Building image $IMAGE_NAME..."
        docker compose build
    fi
}

# Copy default eula.txt / server.properties from the image into the data dir,
# but only if they don't exist yet (never overwrite user edits).
seed_defaults() {
    local missing=()
    for f in eula.txt server.properties; do
        [ -f "$DATA_DIR/$f" ] || missing+=("$f")
    done
    [ ${#missing[@]} -eq 0 ] && return 0

    print_status "Seeding default config: ${missing[*]}"
    local tmp
    tmp="$(docker create "$IMAGE_NAME")"
    for f in "${missing[@]}"; do
        docker cp "$tmp:/opt/minecraft-server/defaults/$f" "$DATA_DIR/$f"
    done
    docker rm "$tmp" >/dev/null
}

# Runs on EVERY start, not just the first one.
prepare_data_dir() {
    mkdir -p "$DATA_DIR"
    seed_defaults
    chown -R "$MC_UID:$MC_GID" "$DATA_DIR"
    chmod 750 "$DATA_DIR"
}

ensure_player_files() {
    [ -f whitelist.json ] || { print_status "Creating whitelist.json..."; echo '[]' > whitelist.json; }
    [ -f ops.json ] || { print_status "Creating ops.json..."; echo '[]' > ops.json; }
    # Mounted read-only into the container; must be readable by UID 25565.
    chmod 644 whitelist.json ops.json
}

start_server() {
    print_status "Starting Minecraft server..."

    if is_running; then
        print_warning "Server is already running"
        return 0
    fi

    ensure_image
    prepare_data_dir
    ensure_player_files

    docker compose up -d

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
    docker compose build --no-cache --pull
    print_success "Rebuild complete"
    read -p "Restart server now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        restart_server
    fi
}

build_server() {
    print_status "Building server image..."
    docker compose build --pull
    print_success "Build complete"
    read -p "Start server now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        start_server
    fi
}

backup_world() {
    if [ ! -d "$DATA_DIR/world" ]; then
        print_error "No world found at $DATA_DIR/world"
        exit 1
    fi

    local backup_file="$BACKUP_DIR/world-backup-$(date +%Y%m%d-%H%M%S).tar.gz"

    print_status "Creating world backup..."
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"

    if is_running; then
        print_warning "Server is running; backup is taken live (session.lock is excluded)"
    fi

    tar -czf "$backup_file" --exclude='world/session.lock' -C "$DATA_DIR" world

    print_success "Backup created: $backup_file"
    print_status "Backup size: $(du -h "$backup_file" | cut -f1)"
}

show_help() {
    echo "Minecraft Server Control Script"
    echo ""
    echo "Usage: sudo $0 {start|stop|restart|status|logs|build|rebuild|backup}"
    echo ""
    echo "Commands:"
    echo "  start    - Start the Minecraft server"
    echo "  stop     - Stop the Minecraft server"
    echo "  restart  - Restart the Minecraft server"
    echo "  status   - Show server status and stats"
    echo "  logs     - Follow server logs (Ctrl+C to exit)"
    echo "  build    - Build the Docker image"
    echo "  rebuild  - Rebuild Docker image from scratch"
    echo "  backup   - Create world backup in $BACKUP_DIR"
    echo ""
}

case "${1:-}" in
    start)   check_root; check_docker; start_server ;;
    stop)    check_root; check_docker; stop_server ;;
    restart) check_root; check_docker; restart_server ;;
    status)  check_root; check_docker; status_server ;;
    logs)    check_root; check_docker; logs_server ;;
    build)   check_root; check_docker; build_server ;;
    rebuild) check_root; check_docker; rebuild_server ;;
    backup)  check_root; backup_world ;;
    *)       show_help; exit 1 ;;
esac

exit 0
