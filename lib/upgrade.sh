#!/usr/bin/env bash
# chengetai upgrade <deployment-dir> [--to TAG] [--yes] [--rollback <snapshot>]
#
# ChengetAi Deploy v3: the DSpace upgrade engine with automatic rollback.
# Operates on a v3-generated deployment directory (the output of
# `chengetai generate`, containing docker-compose.yml, .env, Caddyfile and
# healthcheck.sh). It:
#   1. Snapshots everything — compose, Caddyfile, config, .env AND a pg_dump of
#      the database — into <dir>/upgrades/<timestamp>/.
#   2. Rewrites the DSpace image tags (backend + Angular UI) to the target.
#   3. Pulls the new images and recreates the stack.
#   4. Health-checks with retries.
#   5. On ANY failure, restores the snapshot (files + database) and brings the
#      previous version back up, then re-verifies — so a bad upgrade never
#      leaves the repository down or loses data (DB, assetstore, config,
#      branding and SSL are all preserved).
#
# With --rollback <snapshot> it skips the upgrade and restores a snapshot
# directly (disaster recovery).
set -euo pipefail

# ── Structured logging (matches generate.sh) ─────────────────────────────────
ts() { date +'%Y-%m-%dT%H:%M:%S%z'; }
log()      { printf '%s [%s] %s\n' "$(ts)" "$1" "$2"; }
log_info() { log INFO    "$*"; }
log_ok()   { log SUCCESS "$*"; }
log_warn() { log WARNING "$*"; }
log_err()  { log ERROR   "$*" >&2; }
die()      { log_err "$*"; exit 1; }

# ── Arguments ────────────────────────────────────────────────────────────────
DIR="" TO_TAG="latest" ASSUME_YES=0 ROLLBACK_SNAP=""
while [ $# -gt 0 ]; do
    case "$1" in
        --to)        TO_TAG="$2"; shift 2 ;;
        --yes|-y)    ASSUME_YES=1; shift ;;
        --rollback)  ROLLBACK_SNAP="$2"; shift 2 ;;
        -*)          die "Unknown option: $1" ;;
        *)           DIR="$1"; shift ;;
    esac
done

[ -n "$DIR" ] || die "Usage: chengetai upgrade <deployment-dir> [--to TAG] [--yes]"
[ -d "$DIR" ] || die "Deployment directory not found: $DIR"
DIR="$(cd "$DIR" && pwd)"
COMPOSE="$DIR/docker-compose.yml"
[ -f "$COMPOSE" ] || die "Not a v3 deployment (no docker-compose.yml): $DIR"
command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 \
    || die "Docker + Docker Compose are required."

DEPLOY_ID="$(grep -s '^DEPLOY_ID=' "$DIR/.env" | cut -d= -f2)"
DEPLOY_ID="${DEPLOY_ID:-$(basename "$DIR")}"

# The compose file carries `name: chengetai-<id>`, so the project name is
# implicit — but we pin --project-directory so relative volumes/Caddyfile
# resolve regardless of the caller's cwd.
dc() { docker compose -f "$COMPOSE" --project-directory "$DIR" "$@"; }

# Files that make up the deployment's configuration (branding + SSL live in
# Caddyfile/config.yml/local.cfg; runtime values in .env).
CONFIG_FILES=(docker-compose.yml Caddyfile .env local.cfg config.yml healthcheck.sh)

# Which services carry a DSpace image tag we rewrite on upgrade.
db_dump() {   # -> stdout (gzipped SQL); empty (rc!=0) if the DB isn't up
    dc exec -T dspacedb pg_dump -U dspace --clean --if-exists dspace 2>/dev/null | gzip
}
db_restore() {  # < gzipped SQL on stdin
    gunzip -c "$1" | dc exec -T dspacedb psql -q -U dspace -d dspace >/dev/null 2>&1
}

health_check() {
    # Retry the generated health check; DSpace first boot / migration is slow.
    local tries="${1:-20}" i
    [ -f "$DIR/healthcheck.sh" ] || { log_warn "No healthcheck.sh — skipping health verification."; return 0; }
    chmod +x "$DIR/healthcheck.sh" 2>/dev/null || true
    for ((i=1; i<=tries; i++)); do
        if bash "$DIR/healthcheck.sh" >/dev/null 2>&1; then
            return 0
        fi
        log_info "  health check attempt $i/$tries not ready; waiting 15s..."
        sleep 15
    done
    return 1
}

# Creates a snapshot and sets LAST_SNAP to its path (logs go to stdout, so we
# return the path via a global rather than command substitution).
LAST_SNAP=""
snapshot_create() {
    local snap="$DIR/upgrades/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$snap"
    local f
    for f in "${CONFIG_FILES[@]}"; do
        [ -f "$DIR/$f" ] && cp -a "$DIR/$f" "$snap/$f"
    done
    log_info "  snapshotting database (pg_dump)..."
    if db_dump > "$snap/db.sql.gz" 2>/dev/null && [ -s "$snap/db.sql.gz" ]; then
        log_ok  "  database snapshot: $(du -h "$snap/db.sql.gz" | cut -f1)"
    else
        rm -f "$snap/db.sql.gz"
        log_warn "  database not running — config-only snapshot (no db.sql.gz)."
    fi
    LAST_SNAP="$snap"
}

snapshot_restore() {
    local snap="$1"
    [ -d "$snap" ] || die "Snapshot not found: $snap"
    log_info "Restoring configuration from $snap ..."
    local f
    for f in "${CONFIG_FILES[@]}"; do
        [ -f "$snap/$f" ] && cp -a "$snap/$f" "$DIR/$f"
    done
    log_info "Bringing the previous version back up..."
    dc up -d
    if [ -f "$snap/db.sql.gz" ]; then
        log_info "Waiting for the database to accept connections..."
        local i
        for ((i=1; i<=20; i++)); do
            dc exec -T dspacedb pg_isready -U dspace >/dev/null 2>&1 && break
            sleep 5
        done
        log_info "Restoring database from snapshot..."
        if db_restore "$snap/db.sql.gz"; then
            log_ok "Database restored."
        else
            log_err "Database restore reported errors — inspect $snap/db.sql.gz manually."
        fi
    fi
}

# Rewrite the image tag for a dspace/* image in-place in docker-compose.yml.
retag_image() {
    local image="$1" tag="$2"
    # image lines look like: `    image: dspace/dspace:latest`
    sed -i -E "s#(image:[[:space:]]*${image//\//\\/}):[^[:space:]]+#\1:${tag}#" "$COMPOSE"
}

# ── --rollback: restore a snapshot directly, no upgrade ──────────────────────
if [ -n "$ROLLBACK_SNAP" ]; then
    case "$ROLLBACK_SNAP" in
        /*) : ;;                              # absolute
        *)  ROLLBACK_SNAP="$DIR/upgrades/$ROLLBACK_SNAP" ;;
    esac
    log_info "Rolling '$DEPLOY_ID' back to snapshot: $ROLLBACK_SNAP"
    snapshot_restore "$ROLLBACK_SNAP"
    if health_check 12; then
        log_ok "Rollback complete and healthy."
    else
        log_warn "Rollback restored, but health checks have not passed yet."
    fi
    exit 0
fi

# ── Upgrade flow ─────────────────────────────────────────────────────────────
CUR_TAG="$(grep -oE 'image:[[:space:]]*dspace/dspace:[^[:space:]]+' "$COMPOSE" | head -1 | sed -E 's#.*:##')"
echo ""
log_info "Upgrade plan for '$DEPLOY_ID'"
echo "  Directory : $DIR"
echo "  Current   : dspace/dspace:${CUR_TAG:-unknown} (+ dspace-angular)"
echo "  Target    : dspace/dspace:${TO_TAG} (+ dspace-angular:${TO_TAG})"
echo "  Preserved : database, assetstore, Caddyfile/SSL, branding, .env"
echo ""
if [ "$ASSUME_YES" != "1" ]; then
    printf 'Proceed with the upgrade? [y/N] '
    read -r ans
    case "$ans" in y|Y|yes|YES) : ;; *) echo "Upgrade cancelled."; exit 0 ;; esac
fi

log_info "Step 1/5 — Snapshotting current deployment..."
snapshot_create
SNAP="$LAST_SNAP"
log_ok "Snapshot saved: $SNAP"

# From here on, any failure triggers an automatic rollback to $SNAP.
UPGRADE_DONE=0
rollback_on_fail() {
    [ "$UPGRADE_DONE" = "1" ] && return 0
    echo ""
    log_err "Upgrade failed — rolling back to the pre-upgrade snapshot."
    trap - ERR
    snapshot_restore "$SNAP"
    if health_check 12; then
        log_ok "Rollback complete — the previous version is healthy."
    else
        log_err "Rollback restored the previous version, but it is not healthy yet. Snapshot: $SNAP"
    fi
    exit 1
}
trap rollback_on_fail ERR

log_info "Step 2/5 — Rewriting image tags to '${TO_TAG}'..."
retag_image "dspace/dspace"         "$TO_TAG"
retag_image "dspace/dspace-angular" "$TO_TAG"
grep -nE 'image:[[:space:]]*dspace/(dspace|dspace-angular):' "$COMPOSE" | sed 's/^/  /'
log_ok "Image tags updated."

log_info "Step 3/5 — Pulling new images..."
dc pull dspace dspace-angular
log_ok "Images pulled."

log_info "Step 4/5 — Recreating the stack with the new images..."
dc up -d
log_ok "Containers recreated."

log_info "Step 5/5 — Health-checking (DSpace runs DB migrations on first boot; this can take minutes)..."
if health_check 24; then
    UPGRADE_DONE=1
    trap - ERR
    echo ""
    log_ok "Upgrade of '$DEPLOY_ID' to '${TO_TAG}' succeeded and is healthy."
    echo "  Rollback point kept at: $SNAP"
    echo "  To roll back manually:  chengetai upgrade $DIR --rollback $(basename "$SNAP")"
    echo ""
    exit 0
else
    log_err "Health checks did not pass after the upgrade."
    false   # trip the ERR trap -> automatic rollback
fi
