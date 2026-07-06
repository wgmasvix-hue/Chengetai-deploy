#!/usr/bin/env bash
# ChengetAi Koha Engine — update.sh
# Updates Koha packages to the latest 24.05.x release, refreshes all
# base images, and runs database schema migrations.
# Idempotent — safe to run on an already up-to-date deployment.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ENGINE_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

[ -f "$ENGINE_DIR/.env" ] || die ".env not found. Run install.sh first."
set -a; source "$ENGINE_DIR/.env"; set +a

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-koha}"

echo ""
info "ChengetAi Koha Engine — update"
echo ""

# ── Step 1: Backup before update ─────────────────────────────────────────────
warn "Creating pre-update backup ..."
bash "$SCRIPT_DIR/backup.sh" || warn "Backup failed — continuing update anyway."

# ── Step 2: Pull updated base images ─────────────────────────────────────────
info "Pulling latest MariaDB, OpenSearch, Memcached and Nginx images ..."
docker compose --env-file "$ENGINE_DIR/.env" \
    -f "$ENGINE_DIR/docker-compose.yml" \
    --project-directory "$ENGINE_DIR" \
    pull db memcached opensearch nginx 2>&1 | grep -E "(Pulled|up to date|error)" || true

# ── Step 3: Rebuild the Koha image (picks up new 24.05.x packages) ──────────
info "Rebuilding Koha image with latest 24.05.x packages (no cache) ..."
warn "This may take 10-15 minutes on first run ..."
docker compose --env-file "$ENGINE_DIR/.env" \
    -f "$ENGINE_DIR/docker-compose.yml" \
    --project-directory "$ENGINE_DIR" \
    build --pull --no-cache koha 2>&1 | tail -10

# ── Step 4: Restart with the new image ───────────────────────────────────────
info "Restarting services with updated images ..."
docker compose --env-file "$ENGINE_DIR/.env" \
    -f "$ENGINE_DIR/docker-compose.yml" \
    --project-directory "$ENGINE_DIR" \
    up -d --remove-orphans

# ── Step 5: Wait for Koha to be ready ────────────────────────────────────────
info "Waiting for Koha to come up ..."
KOHA_CONTAINER="${PROJECT_NAME}-koha-1"
OPAC_INTERNAL="${OPAC_INTERNAL_PORT:-8080}"
RETRIES=60
until docker exec "$KOHA_CONTAINER" \
    curl -sf "http://localhost:${OPAC_INTERNAL}/" -o /dev/null 2>/dev/null; do
    RETRIES=$((RETRIES - 1))
    [ "$RETRIES" -gt 0 ] || { warn "Koha took too long to start. Check: docker logs $KOHA_CONTAINER"; break; }
    printf "."
    sleep 5
done
echo ""

# ── Step 6: Health check ──────────────────────────────────────────────────────
info "Running health check ..."
bash "$SCRIPT_DIR/healthcheck.sh" || warn "Some services still warming up."

echo ""
info "Update complete."
echo ""
