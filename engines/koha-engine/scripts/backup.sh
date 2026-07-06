#!/usr/bin/env bash
# ChengetAi Koha Engine — backup.sh
# Creates a timestamped backup of the MariaDB database, Koha uploads,
# and Koha configuration.  Safe to run while the stack is live.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ENGINE_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# Load environment
[ -f "$ENGINE_DIR/.env" ] || die ".env not found. Run install.sh first."
set -a; source "$ENGINE_DIR/.env"; set +a

INSTANCE="${KOHA_INSTANCE:-library}"
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-koha}"
DB_CONTAINER="${PROJECT_NAME}-db-1"
KOHA_CONTAINER="${PROJECT_NAME}-koha-1"

# Verify the database container is running
docker inspect -f '{{.State.Running}}' "$DB_CONTAINER" 2>/dev/null | grep -q true \
    || die "Database container is not running. Start the stack with: install.sh"

DEST="${BACKUP_DIR:-$ENGINE_DIR/backups}/koha-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DEST"

echo ""
info "Starting backup to: $DEST"
echo ""

# ── Database ──────────────────────────────────────────────────────────────────
info "Backing up database (koha_${INSTANCE}) ..."
docker exec "$DB_CONTAINER" \
    mysqldump \
        -u "koha_${INSTANCE}" \
        -p"${MYSQL_PASSWORD}" \
        --single-transaction \
        --routines \
        --triggers \
        "koha_${INSTANCE}" \
    | gzip > "$DEST/koha-db.sql.gz"
info "Database dump: $(du -sh "$DEST/koha-db.sql.gz" | cut -f1)"

# ── Uploads ───────────────────────────────────────────────────────────────────
if docker inspect -f '{{.State.Running}}' "$KOHA_CONTAINER" 2>/dev/null | grep -q true; then
    info "Backing up uploads ..."
    docker exec "$KOHA_CONTAINER" \
        tar czf - -C "/var/lib/koha/${INSTANCE}" uploads 2>/dev/null \
        > "$DEST/koha-uploads.tar.gz" || warn "No uploads directory yet — skipping."
    [ -f "$DEST/koha-uploads.tar.gz" ] && \
        info "Uploads archive: $(du -sh "$DEST/koha-uploads.tar.gz" | cut -f1)"
fi

# ── Configuration ────────────────────────────────────────────────────────────
info "Backing up Koha configuration ..."
docker exec "$KOHA_CONTAINER" \
    tar czf - -C /etc/koha/sites "$INSTANCE" 2>/dev/null \
    > "$DEST/koha-config.tar.gz" || warn "Configuration not found — skipping."
[ -f "$DEST/koha-config.tar.gz" ] && \
    info "Config archive: $(du -sh "$DEST/koha-config.tar.gz" | cut -f1)"

# ── Metadata ──────────────────────────────────────────────────────────────────
{
    echo "backup_date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "koha_instance=${INSTANCE}"
    echo "db_name=koha_${INSTANCE}"
    echo "engine_version=1.0.0"
} > "$DEST/backup.meta"

echo ""
info "Backup complete: $DEST"
du -sh "$DEST"
echo ""
echo "Restore with: scripts/restore.sh $DEST"
echo ""
