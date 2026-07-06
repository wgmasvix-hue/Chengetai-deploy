#!/usr/bin/env bash
# ChengetAi Koha Engine — uninstall.sh
# Stops and removes the Koha stack.  By default volumes (data) are kept.
# Pass --purge to also delete all volumes and the local .env backup.
# Usage: uninstall.sh [--purge]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ENGINE_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()   { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()    { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
confirm(){ local ans; read -rp "$1 (Y/N): " ans; [[ "$ans" =~ ^[Yy]$ ]]; }

PURGE=0
for arg in "$@"; do
    [ "$arg" = "--purge" ] && PURGE=1
done

[ -f "$ENGINE_DIR/.env" ] || die ".env not found. Is the engine installed?"

echo ""
if [ "$PURGE" -eq 1 ]; then
    warn "PURGE mode: ALL data volumes will be permanently deleted."
    echo ""
    confirm "Are you sure you want to permanently delete all Koha data?" \
        || { echo "Uninstall cancelled."; exit 0; }
    echo ""
    confirm "FINAL WARNING: This cannot be undone. Continue?" \
        || { echo "Uninstall cancelled."; exit 0; }
else
    echo "Standard uninstall: containers will be removed, data volumes are preserved."
    echo ""
    confirm "Proceed with uninstall?" \
        || { echo "Uninstall cancelled."; exit 0; }
fi
echo ""

# ── Backup before removing (unless purging) ───────────────────────────────────
if [ "$PURGE" -eq 0 ]; then
    info "Creating final backup before removal ..."
    bash "$SCRIPT_DIR/backup.sh" 2>/dev/null || warn "Backup failed — continuing."
fi

# ── Stop and remove containers ────────────────────────────────────────────────
if [ -f "$ENGINE_DIR/docker-compose.yml" ]; then
    info "Stopping and removing containers ..."
    if [ "$PURGE" -eq 1 ]; then
        docker compose --env-file "$ENGINE_DIR/.env" \
            -f "$ENGINE_DIR/docker-compose.yml" \
            --project-directory "$ENGINE_DIR" \
            down --remove-orphans --volumes 2>/dev/null || true
        info "Containers and volumes removed."
    else
        docker compose --env-file "$ENGINE_DIR/.env" \
            -f "$ENGINE_DIR/docker-compose.yml" \
            --project-directory "$ENGINE_DIR" \
            down --remove-orphans 2>/dev/null || true
        info "Containers removed. Data volumes preserved."
    fi
fi

# ── Clean up SSL certs (purge only) ──────────────────────────────────────────
if [ "$PURGE" -eq 1 ]; then
    rm -rf "$ENGINE_DIR/config/ssl" 2>/dev/null || true
    rm -f  "$ENGINE_DIR/config/nginx.conf" 2>/dev/null || true
    info "SSL certificates and generated config removed."
fi

echo ""
if [ "$PURGE" -eq 1 ]; then
    info "Koha engine purged. All data has been deleted."
else
    info "Koha engine removed. Data volumes and backups are preserved in:"
    echo "  $ENGINE_DIR/backups/"
    echo ""
    echo "Re-deploy with: scripts/install.sh"
fi
echo ""
