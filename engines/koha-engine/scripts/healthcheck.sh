#!/usr/bin/env bash
# ChengetAi Koha Engine — healthcheck.sh
# Checks the health of every service in the stack and validates the
# public OPAC and Staff URLs.  Exits 0 if all checks pass, 1 otherwise.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ENGINE_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✓${NC}  $*"; }
fail() { echo -e "  ${RED}✗${NC}  $*"; FAILURES=$((FAILURES + 1)); }
warn() { echo -e "  ${YELLOW}!${NC}  $*"; }

[ -f "$ENGINE_DIR/.env" ] && { set -a; source "$ENGINE_DIR/.env"; set +a; }

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-koha}"
# shellcheck disable=SC2034  # INSTANCE used in backup path display
INSTANCE="${KOHA_INSTANCE:-library}"
HTTPS_P="${HTTPS_PORT:-443}"
HTTPS_SP="${HTTPS_STAFF_PORT:-8443}"
OPAC_INT="${OPAC_INTERNAL_PORT:-8080}"
STAFF_INT="${STAFF_INTERNAL_PORT:-8081}"
SERVER_IP=$(ip route get 1 2>/dev/null | awk '{print $7; exit}' || echo "localhost")

FAILURES=0

echo ""
echo "  ┌─────────────────────────────────────────────────────┐"
echo "  │        ChengetAi Koha Engine — Health Check         │"
echo "  └─────────────────────────────────────────────────────┘"
echo ""

# ── Docker container status ──────────────────────────────────────────────────
echo "  Container Status"
echo "  ────────────────────────────────────"

for svc in db memcached opensearch koha nginx; do
    container="${PROJECT_NAME}-${svc}-1"
    status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "not found")
    health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' \
        "$container" 2>/dev/null || echo "")

    display="$svc"
    [ -n "$health" ] && display="$svc ($health)"

    case "$status" in
        running)  ok  "$display" ;;
        *)        fail "$display — status: $status" ;;
    esac
done

echo ""
echo "  Service Health Endpoints"
echo "  ────────────────────────────────────"

# ── MariaDB ───────────────────────────────────────────────────────────────────
if docker exec "${PROJECT_NAME}-db-1" \
    mysqladmin -u root -p"${MYSQL_ROOT_PASSWORD:-}" ping --silent 2>/dev/null; then
    ok "MariaDB — accepting connections"
else
    fail "MariaDB — not responding"
fi

# ── Memcached ─────────────────────────────────────────────────────────────────
if docker exec "${PROJECT_NAME}-memcached-1" \
    sh -c "echo stats | nc -w 1 localhost 11211 | grep -q uptime" 2>/dev/null; then
    ok "Memcached — responding"
else
    warn "Memcached — not responding yet (may still be starting)"
fi

# ── OpenSearch ────────────────────────────────────────────────────────────────
OS_STATUS=$(docker exec "${PROJECT_NAME}-opensearch-1" \
    curl -sf "http://localhost:9200/_cluster/health" 2>/dev/null | \
    grep -oP '"status":"\K[^"]+' || echo "unreachable")
case "$OS_STATUS" in
    green|yellow) ok  "OpenSearch — cluster status: $OS_STATUS" ;;
    red)          fail "OpenSearch — cluster status: $OS_STATUS (index issue)" ;;
    *)            warn "OpenSearch — $OS_STATUS (may still be starting)" ;;
esac

# ── Koha OPAC (internal) ──────────────────────────────────────────────────────
if docker exec "${PROJECT_NAME}-koha-1" \
    curl -sf "http://localhost:${OPAC_INT}/" -o /dev/null 2>/dev/null; then
    ok "Koha OPAC (internal :${OPAC_INT}) — responding"
else
    fail "Koha OPAC (internal :${OPAC_INT}) — not responding"
fi

# ── Koha Staff (internal) ────────────────────────────────────────────────────
if docker exec "${PROJECT_NAME}-koha-1" \
    curl -sf "http://localhost:${STAFF_INT}/cgi-bin/koha/mainpage.pl" \
    -o /dev/null 2>/dev/null; then
    ok "Koha Staff (internal :${STAFF_INT}) — responding"
else
    fail "Koha Staff (internal :${STAFF_INT}) — not responding"
fi

# ── Nginx (public HTTPS OPAC) ────────────────────────────────────────────────
if curl -sk "https://localhost:${HTTPS_P}/" -o /dev/null 2>/dev/null; then
    ok "Nginx OPAC (https://localhost:${HTTPS_P}) — responding"
else
    fail "Nginx OPAC (https://localhost:${HTTPS_P}) — not responding"
fi

# ── Nginx (public HTTPS Staff) ───────────────────────────────────────────────
if curl -sk "https://localhost:${HTTPS_SP}/cgi-bin/koha/mainpage.pl" \
    -o /dev/null 2>/dev/null; then
    ok "Nginx Staff (https://localhost:${HTTPS_SP}) — responding"
else
    fail "Nginx Staff (https://localhost:${HTTPS_SP}) — not responding"
fi

echo ""
echo "  Public URLs"
echo "  ────────────────────────────────────"
echo "  OPAC  : https://${SERVER_IP}:${HTTPS_P}/"
echo "  Staff : https://${SERVER_IP}:${HTTPS_SP}/cgi-bin/koha/mainpage.pl"
echo ""

if [ "$FAILURES" -eq 0 ]; then
    echo -e "  ${GREEN}All checks passed.${NC}"
else
    echo -e "  ${RED}${FAILURES} check(s) failed.${NC}"
    echo "  Run 'docker logs <container>' for details."
fi
echo ""

exit "$FAILURES"
