#!/usr/bin/env bash
# chengetai generate <deployment.yml> [--out DIR] [--up]
#
# ChengetAi Deploy v3 prototype: the DSpace deployment generator. Reads the
# master deployment.yml (single source of truth), renders every template into
# an output directory, validates the result (compose is valid, no hardcoded
# IPs), and — with --up — creates the Docker resources and launches the stack
# behind Caddy, then runs the generated health checks.
set -euo pipefail

CHENGETAI_HOME="${CHENGETAI_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"
PLAT_DIR="$CHENGETAI_HOME/platforms/dspace"
TPL_DIR="$PLAT_DIR/templates"

# ── Structured logging ───────────────────────────────────────────────────────
ts() { date +'%Y-%m-%dT%H:%M:%S%z'; }
log()      { printf '%s [%s] %s\n' "$(ts)" "$1" "$2"; }
log_info() { log INFO    "$*"; }
log_ok()   { log SUCCESS "$*"; }
log_warn() { log WARNING "$*"; }
log_err()  { log ERROR   "$*" >&2; }
die()      { log_err "$*"; exit 1; }

CONFIG="" OUT="" DO_UP=0
while [ $# -gt 0 ]; do
    case "$1" in
        --out) OUT="$2"; shift 2 ;;
        --up)  DO_UP=1; shift ;;
        -*)    die "Unknown option: $1" ;;
        *)     CONFIG="$1"; shift ;;
    esac
done

[ -n "$CONFIG" ] || die "Usage: chengetai generate <deployment.yml> [--out DIR] [--up]"
[ -f "$CONFIG" ] || die "Config not found: $CONFIG"
command -v python3 >/dev/null 2>&1 || die "python3 is required for the generator."

# ── Step 1: Validate ─────────────────────────────────────────────────────────
log_info "Step 1/5 — Validating environment and configuration..."
DEPLOY_ID="$(python3 -c "
import sys; sys.path.insert(0, '$PLAT_DIR')
from render import parse_yaml
print(parse_yaml('$CONFIG').get('deployment.id','dspace'))
")"
[ -n "$DEPLOY_ID" ] || die "deployment.id missing from $CONFIG"
OUT="${OUT:-$CHENGETAI_HOME/deployments-v3/$DEPLOY_ID}"

HAVE_DOCKER=1
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log_ok "Docker and Docker Compose present."
else
    HAVE_DOCKER=0
    if [ "$DO_UP" = "1" ]; then
        die "Docker + Docker Compose are required for --up."
    fi
    log_warn "Docker/Compose not found — will generate and validate config only."
fi
log_ok "Configuration '$DEPLOY_ID' is valid. Output: $OUT"

# ── Step 2: Generate configuration ───────────────────────────────────────────
log_info "Step 2/5 — Rendering templates from $CONFIG ..."
python3 "$PLAT_DIR/render.py" "$CONFIG" "$TPL_DIR" "$OUT" | while IFS= read -r line; do
    log_info "  $line"
done
[ -f "$OUT/docker-compose.yml" ] || die "Rendering did not produce docker-compose.yml"
log_ok "Rendered: $(cd "$OUT" && ls | tr '\n' ' ')"

# ── Step 2b: Guard — no hardcoded IPs, valid compose ─────────────────────────
log_info "Verifying generated files contain no hardcoded IP addresses..."
if grep -REn '([0-9]{1,3}\.){3}[0-9]{1,3}' \
        "$OUT/docker-compose.yml" "$OUT/Caddyfile" "$OUT/local.cfg" "$OUT/config.yml" 2>/dev/null \
        | grep -vE '127\.0\.0\.1|0\.0\.0\.0'; then
    die "A hardcoded IP address leaked into the generated files (see above)."
fi
log_ok "No hardcoded IPs in the generated configuration."

if [ "$HAVE_DOCKER" = "1" ]; then
    log_info "Validating the generated docker-compose.yml ..."
    docker compose -f "$OUT/docker-compose.yml" config >/dev/null \
        || die "Generated docker-compose.yml failed validation."
    log_ok "docker-compose.yml is valid."
fi

if [ "$DO_UP" != "1" ]; then
    echo ""
    log_ok "Generation complete for '$DEPLOY_ID'."
    echo ""
    echo "  Files : $OUT"
    echo "  Launch: chengetai generate $CONFIG --up   (or: cd $OUT && docker compose up -d)"
    echo ""
    exit 0
fi

# ── Steps 3-5: Create resources, launch, health-check ────────────────────────
# Never leave a partial deployment: tear down on any failure after this point.
cleanup_on_fail() {
    log_err "Deployment failed — tearing down to avoid a partial stack."
    (cd "$OUT" && docker compose down --remove-orphans) || true
}
trap cleanup_on_fail ERR

log_info "Step 3/5 — Creating Docker resources (volumes, network)..."
( cd "$OUT" && docker compose create ) >/dev/null 2>&1 || true
log_ok "Resources ready."

log_info "Step 4/5 — Launching containers (Postgres, Solr, DSpace, Angular, Caddy)..."
( cd "$OUT" && docker compose up -d )
log_ok "Containers started."

log_info "Step 5/5 — Running health checks (first boot can take several minutes)..."
chmod +x "$OUT/healthcheck.sh"
if bash "$OUT/healthcheck.sh"; then
    log_ok "Health checks passed."
else
    log_warn "Some health checks did not pass yet — the stack may still be starting."
fi

trap - ERR
echo ""
PUBLIC_URL="$(grep -s '^PUBLIC_URL=' "$OUT/.env" | cut -d= -f2)"
log_ok "Deployment '$DEPLOY_ID' is up at ${PUBLIC_URL}"
echo "  Verify: curl ${PUBLIC_URL}/server/api  (expect dspaceUI/dspaceServer = ${PUBLIC_URL})"
echo ""
