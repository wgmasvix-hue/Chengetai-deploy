#!/usr/bin/env bash
# ChengetAi Koha Engine — restore.sh
# Restores the MariaDB database, uploads and configuration from a backup
# produced by backup.sh.
# Usage: restore.sh [backup-directory]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ENGINE_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()   { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()    { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
confirm(){ local ans; read -rp "$1 (Y/N): " ans; [[ "$ans" =~ ^[Yy]$ ]]; }

# Load environment
[ -f "$ENGINE_DIR/.env" ] || die ".env not found. Run install.sh first."
set -a; source "$ENGINE_DIR/.env"; set +a

INSTANCE="${KOHA_INSTANCE:-library}"
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-koha}"
DB_CONTAINER="${PROJECT_NAME}-db-1"
KOHA_CONTAINER="${PROJECT_NAME}-koha-1"

# Resolve backup directory
BACKUP="${1:-}"
if [ -z "$BACKUP" ]; then
    BACKUP=$(ls -1d "${BACKUP_DIR:-$ENGINE_DIR/backups}"/koha-backup-* 2>/dev/null | sort | tail -1)
    [ -n "$BACKUP" ] || die "No backups found. Create one first: scripts/backup.sh"
    info "No backup specified — using most recent: $BACKUP"
fi

[ -d "$BACKUP" ]                       || die "Backup directory not found: $BACKUP"
[ -f "$BACKUP/koha-db.sql.gz" ]        || die "Database dump not found: $BACKUP/koha-db.sql.gz"

docker inspect -f '{{.State.Running}}' "$DB_CONTAINER" 2>/dev/null | grep -q true \
    || die "Database container is not running. Start the stack first."

echo ""
echo "  Backup  : $BACKUP"
echo "  Target  : koha_${INSTANCE} on ${DB_CONTAINER}"
echo ""
confirm "This will REPLACE the current database and files. Proceed?" \
    || { echo "Restore cancelled."; exit 0; }
echo ""

# ── Stop Koha (keep DB running) ───────────────────────────────────────────────
info "Pausing Koha ..."
docker compose --env-file "$ENGINE_DIR/.env" \
    -f "$ENGINE_DIR/docker-compose.yml" \
    --project-directory "$ENGINE_DIR" \
    stop koha

# ── Restore database ──────────────────────────────────────────────────────────
info "Dropping and recreating database koha_${INSTANCE} ..."
docker exec "$DB_CONTAINER" mysql \
    -u root -p"${MYSQL_ROOT_PASSWORD}" \
    -e "DROP DATABASE IF EXISTS \`koha_${INSTANCE}\`;
        CREATE DATABASE \`koha_${INSTANCE}\`
            CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        GRANT ALL PRIVILEGES ON \`koha_${INSTANCE}\`.*
            TO 'koha_${INSTANCE}'@'%';
        FLUSH PRIVILEGES;"

info "Restoring database ..."
gunzip -c "$BACKUP/koha-db.sql.gz" | \
    docker exec -i "$DB_CONTAINER" \
        mysql -u "koha_${INSTANCE}" -p"${MYSQL_PASSWORD}" "koha_${INSTANCE}"
info "Database restored."

# ── Restore uploads ───────────────────────────────────────────────────────────
if [ -f "$BACKUP/koha-uploads.tar.gz" ]; then
    info "Restoring uploads ..."
    local_image=$(docker inspect "$KOHA_CONTAINER" --format '{{.Config.Image}}' 2>/dev/null || true)
    if [ -n "$local_image" ]; then
        docker run --rm -i \
            --volumes-from "$KOHA_CONTAINER" \
            --entrypoint bash "$local_image" \
            -c "rm -rf /var/lib/koha/${INSTANCE}/uploads/*
                tar xzf - -C /var/lib/koha/${INSTANCE}" \
            < "$BACKUP/koha-uploads.tar.gz"
        info "Uploads restored."
    else
        warn "Could not determine Koha image — skipping uploads restore."
    fi
fi

# ── Restore configuration ─────────────────────────────────────────────────────
if [ -f "$BACKUP/koha-config.tar.gz" ]; then
    info "Restoring Koha configuration ..."
    docker run --rm -i \
        --volumes-from "$KOHA_CONTAINER" \
        --entrypoint bash "$(docker inspect "$KOHA_CONTAINER" --format '{{.Config.Image}}' 2>/dev/null)" \
        -c "tar xzf - -C /etc/koha/sites" \
        < "$BACKUP/koha-config.tar.gz" 2>/dev/null || warn "Config restore skipped."
fi

# ── Restart Koha ─────────────────────────────────────────────────────────────
info "Starting Koha ..."
docker compose --env-file "$ENGINE_DIR/.env" \
    -f "$ENGINE_DIR/docker-compose.yml" \
    --project-directory "$ENGINE_DIR" \
    start koha

echo ""
info "Restore complete."
echo "Koha may take a few minutes to come up. Run: scripts/healthcheck.sh"
echo ""
