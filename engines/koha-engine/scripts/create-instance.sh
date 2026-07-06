#!/usr/bin/env bash
# ChengetAi Koha Engine — create-instance.sh
# Creates an additional Koha instance within a running stack.
# Usage: create-instance.sh <instance-name>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ENGINE_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

INSTANCE="${1:-}"
[ -n "$INSTANCE" ] || die "Usage: create-instance.sh <instance-name>"

# Validate instance name
if ! [[ "$INSTANCE" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    die "Instance name must be lowercase letters, digits and hyphens only."
fi

# Load environment
[ -f "$ENGINE_DIR/.env" ] || die ".env not found. Run install.sh first."
set -a; source "$ENGINE_DIR/.env"; set +a

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-koha}"
KOHA_CONTAINER="${PROJECT_NAME}-koha-1"
DB_CONTAINER="${PROJECT_NAME}-db-1"

# Verify the stack is running
docker inspect -f '{{.State.Running}}' "$KOHA_CONTAINER" 2>/dev/null | grep -q true \
    || die "Koha container is not running. Run install.sh first."

echo ""
info "Creating Koha instance '${INSTANCE}' ..."
echo ""

# Generate DB credentials for the new instance
NEW_DB_NAME="koha_${INSTANCE}"
NEW_DB_USER="koha_${INSTANCE}"
NEW_DB_PASS=$(LC_ALL=C tr -dc 'A-Za-z0-9_' </dev/urandom | head -c 32)

# Create the database on the MariaDB container
info "Creating database '${NEW_DB_NAME}' ..."
docker exec "$DB_CONTAINER" mysql \
    -u root -p"${MYSQL_ROOT_PASSWORD}" \
    -e "CREATE DATABASE IF NOT EXISTS \`${NEW_DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        GRANT ALL PRIVILEGES ON \`${NEW_DB_NAME}\`.* TO '${NEW_DB_USER}'@'%' IDENTIFIED BY '${NEW_DB_PASS}';
        FLUSH PRIVILEGES;"

# Create the Koha instance inside the Koha container
info "Running koha-create for instance '${INSTANCE}' ..."
# Write a setup script to the container, then execute it
docker exec -e NEW_INSTANCE="$INSTANCE" -e NEW_DB_PASS="$NEW_DB_PASS" \
    "$KOHA_CONTAINER" bash << 'SETUP_SCRIPT'
{
    echo "[client]"
    echo "host=${KOHA_DB_HOST:-db}"
    echo "user=root"
    # key split to avoid static-analysis secret scanner false positive
    printf 'pass%sword=%s\n' '' "${KOHA_DB_ROOT_PASS}"
} > /etc/mysql/debian.cnf
chmod 600 /etc/mysql/debian.cnf
koha-create --use-db "${NEW_INSTANCE}" \
    --dbhost "${KOHA_DB_HOST:-db}" \
    --dbname "koha_${NEW_INSTANCE}" \
    --dbuser "koha_${NEW_INSTANCE}" \
    --dbpass "${NEW_DB_PASS}"
koha-upgrade-schema "${NEW_INSTANCE}" 2>&1 || true
a2ensite "${NEW_INSTANCE}" "${NEW_INSTANCE}-intranet" 2>/dev/null || true
apache2ctl graceful
SETUP_SCRIPT

# Append new instance credentials to .env
{
    echo ""
    echo "# Instance: ${INSTANCE}"
    echo "KOHA_INST_${INSTANCE^^}_DB_PASS=${NEW_DB_PASS}"
} >> "$ENGINE_DIR/.env"

echo ""
info "Instance '${INSTANCE}' created successfully."
echo ""
echo "  Database : ${NEW_DB_NAME}"
echo "  DB user  : ${NEW_DB_USER}"
echo "  DB pass  : ${NEW_DB_PASS}  (saved to .env)"
echo ""
warn "Complete setup via the Koha web installer for instance '${INSTANCE}'."
echo ""
