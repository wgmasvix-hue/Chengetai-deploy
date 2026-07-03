#!/usr/bin/env bash

set -e

source "$(dirname "$0")/common.sh"

require_engine

banner "Restoring Repository"

# Pick the backup to restore: the path given on the command line,
# or the most recent backup if none was given.
BACKUP="${1:-}"
if [ -z "$BACKUP" ]; then
    BACKUP=$(ls -1d "$BACKUP_DIR"/chengetai-backup-* 2>/dev/null | sort | tail -1)
    [ -n "$BACKUP" ] || error "No backups found in $BACKUP_DIR. Create one with: chengetai backup"
    info "No backup specified — using most recent: $BACKUP"
fi

DB_DUMP="$BACKUP/dspace-db.sql.gz"
ASSETS="$BACKUP/assetstore.tar.gz"
[ -f "$DB_DUMP" ] || error "Database dump not found: $DB_DUMP"
[ -f "$ASSETS" ] || error "Assetstore archive not found: $ASSETS"

if ! container_running dspacedb; then
    error "The database container (dspacedb) is not running. Start the repository first: chengetai start"
fi

echo "This will REPLACE the current database and all uploaded files"
echo "with the contents of:"
echo ""
echo "  $BACKUP"
echo ""
read -rp "Proceed with restore? (Y/N): " ANSWER
if [[ ! "$ANSWER" =~ ^[Yy]$ ]]; then
    echo "Restore cancelled."
    exit 0
fi

info "Stopping backend and UI while restoring..."
compose stop dspace dspace-angular

info "Restoring database..."
docker exec dspacedb psql -U "$DB_USER" -d postgres \
    -c "DROP DATABASE IF EXISTS $DB_NAME WITH (FORCE);"
docker exec dspacedb psql -U "$DB_USER" -d postgres \
    -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
docker exec dspacedb psql -U "$DB_USER" -d "$DB_NAME" \
    -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
gunzip -c "$DB_DUMP" | docker exec -i dspacedb psql -q -U "$DB_USER" -d "$DB_NAME"

info "Restoring assetstore (uploaded files)..."
# The dspace container is stopped, so unpack into its assetstore volume
# from a throwaway container that shares its volumes. The backend image
# is already present locally, so nothing needs to be pulled.
DSPACE_IMAGE=$(docker inspect dspace --format '{{.Config.Image}}')
docker run --rm -i --volumes-from dspace --entrypoint bash "$DSPACE_IMAGE" \
    -c "rm -rf /dspace/assetstore/* && tar xzf - -C /dspace" < "$ASSETS"

info "Starting services..."
compose start dspace dspace-angular

echo ""
info "Restore complete."
echo "The backend can take 3-5 minutes to come up. Check with: chengetai status"
echo ""
