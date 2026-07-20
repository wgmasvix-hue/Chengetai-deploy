#!/usr/bin/env bash
# chengetai verify [name] [--timeout SECONDS]
#
# Post-deploy smoke test for a deployment: is the engine present, are the
# containers running, and is the web endpoint actually serving? Retries the
# web probe because first boot is slow. Exits non-zero if any check fails, so
# it doubles as a health gate in scripts/CI.
set -e

source "$(dirname "$0")/utils.sh"

NAME="" TIMEOUT=300
while [ $# -gt 0 ]; do
    case "$1" in
        --timeout) TIMEOUT="$2"; shift 2 ;;
        -*)        error "Unknown option: $1" ;;
        *)         NAME="$1"; shift ;;
    esac
done

# Loads the profile and the platform plugin (pcompose, ui_port, ...).
resolve_deployment "$NAME"
require_docker

PASS=0
FAIL=0
pass() { echo -e "${GREEN}✓${NC} $1"; PASS=$((PASS + 1)); }
bad()  { echo -e "${RED}✗${NC} $1"; FAIL=$((FAIL + 1)); }

banner "Verify: $DEPLOY_NAME ($PLATFORM)"

# 1. Engine present.
if [ -f "$DEPLOY_DIR/engine/docker-compose.yml" ] || [ -d "$DEPLOY_DIR/engine/.git" ]; then
    pass "Engine present"
else
    bad "Engine missing — run: chengetai deploy $DEPLOY_NAME"
fi

# 2. Containers running.
if declare -F pcompose >/dev/null; then
    running=$(pcompose ps --status running -q 2>/dev/null | grep -c . || true)
    total=$(pcompose ps -a -q 2>/dev/null | grep -c . || true)
    if [ "${running:-0}" -ge 1 ]; then
        pass "Containers running (${running}/${total})"
    else
        bad "No containers running — start it: chengetai start $DEPLOY_NAME"
    fi
else
    bad "Plugin does not expose a compose stack to check"
fi

# 3. Web endpoint responding (with retries — first boot is slow).
# Plugins may set PLUGIN_HEALTH_PATH; otherwise probe the site root.
path="${PLUGIN_HEALTH_PATH:-/}"
url="http://localhost:$(ui_port)${path}"
echo ""
info "Probing $url (up to ${TIMEOUT}s — first boot can be slow)..."
deadline=$(( $(date +%s) + TIMEOUT ))
ok=0
while [ "$(date +%s)" -lt "$deadline" ]; do
    if curl -sfL -m 5 -o /dev/null "$url"; then ok=1; break; fi
    sleep 10
done
if [ "$ok" = "1" ]; then
    pass "Web responding at $url"
else
    bad "Web not responding within ${TIMEOUT}s ($url) — check: chengetai logs $DEPLOY_NAME"
fi

echo ""
echo "========================================="
if [ "$FAIL" -eq 0 ]; then
    info "VERIFIED — $PASS check(s) passed for '$DEPLOY_NAME'."
    echo ""
    plugin_urls 2>/dev/null || true
    echo "========================================="
    exit 0
else
    warn "$FAIL check(s) FAILED, $PASS passed for '$DEPLOY_NAME'."
    echo "  See docs/VERIFICATION.md for per-platform troubleshooting."
    echo "========================================="
    exit 1
fi
