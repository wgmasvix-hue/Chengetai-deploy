#!/usr/bin/env bash

set -e

source "$(dirname "$0")/common.sh"

require_engine

banner "Backing Up Repository"

# Backups are taken from the live containers, so the stack must be running.
if ! container_running dspacedb; then
    error "The database container (dspacedb) is not running. Start the repository first: chengetai start"
fi
if ! container_running dspace; then
    error "The backend container (dspace) is not running. Start the repository first: chengetai start"
fi

STAMP=$(date +%Y%m%d-%H%M%S)
DEST="$BACKUP_DIR/chengetai-backup-$STAMP"
mkdir -p "$DEST"

info "Backing up database..."
docker exec dspacedb pg_dump -U "$DB_USER" "$DB_NAME" | gzip > "$DEST/dspace-db.sql.gz"

info "Backing up assetstore (uploaded files)..."
docker exec dspace tar czf - -C /dspace assetstore > "$DEST/assetstore.tar.gz"

echo ""
info "Backup complete: $DEST"
du -sh "$DEST"/* | sed 's/^/  /'
echo ""
echo "Restore later with: chengetai restore $DEST"
echo ""
