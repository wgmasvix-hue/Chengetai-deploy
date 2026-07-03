#!/usr/bin/env bash
# Shared helpers for ChengetAi Deploy commands.
# Sourced by the lib/*.sh command scripts — not run directly.

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[INFO]${NC}  $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC}  $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
    exit 1
}

banner() {
    echo ""
    echo "========================================="
    echo " ChengetAi Deploy : $1"
    echo "========================================="
    echo ""
}

# Where deploy.sh installs the deployment engine, and where backups go.
# Both can be overridden via the environment for testing.
ENGINE_DIR="${CHENGETAI_ENGINE_DIR:-/opt/chengetai-engine}"
COMPOSE_FILE="$ENGINE_DIR/docker-compose-campus.yml"
BACKUP_DIR="${CHENGETAI_BACKUP_DIR:-/opt/chengetai-backups}"

# Database credentials inside the dspacedb container
# (dspace/dspace-postgres-pgcrypto defaults).
DB_USER="dspace"
DB_NAME="dspace"

require_engine() {
    if [ ! -f "$COMPOSE_FILE" ]; then
        error "Deployment engine not found at $ENGINE_DIR. Run: chengetai deploy"
    fi
    if ! command -v docker >/dev/null 2>&1; then
        error "Docker is not installed. Run: chengetai doctor"
    fi
    if ! docker info >/dev/null 2>&1; then
        error "Docker daemon is not running. Start Docker and try again."
    fi
}

# All docker compose calls go through here so the engine's .env is used
# no matter which directory the CLI is invoked from.
compose() {
    docker compose -f "$COMPOSE_FILE" --project-directory "$ENGINE_DIR" "$@"
}

container_running() {
    [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]
}

server_ip() {
    local ip
    ip=$(grep -s '^SERVER_IP=' "$ENGINE_DIR/.env" | cut -d= -f2)
    echo "${ip:-localhost}"
}
