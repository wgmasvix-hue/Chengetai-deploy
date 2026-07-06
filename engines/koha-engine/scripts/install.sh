#!/usr/bin/env bash
# ChengetAi Koha Engine — install.sh
# One-command installer: validates prerequisites, generates secrets,
# provisions SSL certificates, builds images, and starts the full stack.
# Idempotent — safe to run more than once.
set -euo pipefail

# ── Resolve script / engine root ─────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ENGINE_DIR"

# ── Colours and logging ──────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()  { echo -e "\n${CYAN}══ $* ══${NC}"; }
die()       { log_error "$*"; exit 1; }

# ── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║       ChengetAi Koha Engine  v1.0.0                 ║"
echo "  ║  Koha 24.05 · MariaDB 11 · OpenSearch 2 · Nginx     ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo ""

# ── Step 1: Validate Docker ──────────────────────────────────────────────────
log_step "Validating prerequisites"

if ! command -v docker >/dev/null 2>&1; then
    die "Docker is not installed. Install it from https://docs.docker.com/engine/install/"
fi
if ! docker info >/dev/null 2>&1; then
    die "Docker daemon is not running. Start it with: sudo systemctl start docker"
fi
log_info "Docker $(docker --version | grep -oP '[\d.]+' | head -1) — OK"

if ! docker compose version >/dev/null 2>&1; then
    die "Docker Compose v2 is not installed. See https://docs.docker.com/compose/install/"
fi
log_info "Docker Compose $(docker compose version --short 2>/dev/null || echo 'v2') — OK"

# ── Step 2: Load / create .env ───────────────────────────────────────────────
log_step "Environment configuration"

if [ ! -f "$ENGINE_DIR/.env" ]; then
    if [ -f "$ENGINE_DIR/.env.example" ]; then
        cp "$ENGINE_DIR/.env.example" "$ENGINE_DIR/.env"
        log_warn ".env not found — created from .env.example. Review and re-run if needed."
    else
        die ".env file is missing. Copy .env.example to .env and fill in the values."
    fi
fi

# shellcheck source=../.env
set -a
# shellcheck disable=SC1091
source "$ENGINE_DIR/.env"
set +a

# ── Step 3: Generate secrets for any blank credentials ───────────────────────
log_step "Generating secrets"

gen_secret() { LC_ALL=C tr -dc 'A-Za-z0-9_' </dev/urandom | head -c 32; }

CHANGED=0

if [ -z "${MYSQL_ROOT_PASSWORD:-}" ]; then
    MYSQL_ROOT_PASSWORD=$(gen_secret)
    sed -i "s/^MYSQL_ROOT_PASSWORD=$/MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}/" "$ENGINE_DIR/.env"
    CHANGED=1
fi

if [ -z "${MYSQL_PASSWORD:-}" ]; then
    MYSQL_PASSWORD=$(gen_secret)
    sed -i "s/^MYSQL_PASSWORD=$/MYSQL_PASSWORD=${MYSQL_PASSWORD}/" "$ENGINE_DIR/.env"
    CHANGED=1
fi

if [ -z "${ADMIN_PASS:-}" ]; then
    ADMIN_PASS=$(gen_secret)
    sed -i "s/^ADMIN_PASS=$/ADMIN_PASS=${ADMIN_PASS}/" "$ENGINE_DIR/.env"
    CHANGED=1
    log_warn "Generated admin password — save it from the summary printed at the end."
fi

[ "$CHANGED" -eq 1 ] && log_info "Secrets written to .env (chmod 600)"
chmod 600 "$ENGINE_DIR/.env"

# Re-export updated values
# shellcheck disable=SC1091
set -a; source "$ENGINE_DIR/.env"; set +a

# ── Step 4: SSL certificates ─────────────────────────────────────────────────
log_step "SSL certificates (mode: ${SSL_MODE:-self-signed})"

SSL_DIR="$ENGINE_DIR/config/ssl"
mkdir -p "$SSL_DIR"

case "${SSL_MODE:-self-signed}" in
    self-signed)
        if [ ! -f "$SSL_DIR/koha.crt" ] || [ ! -f "$SSL_DIR/koha.key" ]; then
            log_info "Generating self-signed TLS certificate ..."
            openssl req -x509 -nodes -days 3650 \
                -newkey rsa:2048 \
                -keyout "$SSL_DIR/koha.key" \
                -out    "$SSL_DIR/koha.crt" \
                -subj   "/CN=${SERVER_NAME:-localhost}/O=Koha/OU=ChengetAi" \
                -addext "subjectAltName=DNS:${SERVER_NAME:-localhost},IP:${SERVER_NAME:-127.0.0.1}" \
                2>/dev/null
            chmod 600 "$SSL_DIR/koha.key"
            log_info "Self-signed cert created: $SSL_DIR/koha.crt"
        else
            log_info "SSL certificate already exists — skipping."
        fi
        ;;
    letsencrypt)
        if ! command -v certbot >/dev/null 2>&1; then
            log_warn "certbot not installed — installing ..."
            apt-get install -y certbot 2>/dev/null || die "certbot installation failed. Install it manually."
        fi
        certbot certonly --standalone \
            -d "${OPAC_DOMAIN}" -d "${STAFF_DOMAIN}" \
            --email "${CERTBOT_EMAIL:-admin@example.com}" \
            --agree-tos --non-interactive 2>/dev/null || true
        SRC_DIR="/etc/letsencrypt/live/${OPAC_DOMAIN}"
        [ -f "$SRC_DIR/fullchain.pem" ] || die "Let's Encrypt certificate not found in $SRC_DIR"
        cp "$SRC_DIR/fullchain.pem" "$SSL_DIR/koha.crt"
        cp "$SRC_DIR/privkey.pem"   "$SSL_DIR/koha.key"
        chmod 600 "$SSL_DIR/koha.key"
        log_info "Let's Encrypt certificate installed."
        ;;
    manual)
        [ -f "$SSL_DIR/koha.crt" ] || die "SSL_MODE=manual but $SSL_DIR/koha.crt not found."
        [ -f "$SSL_DIR/koha.key" ] || die "SSL_MODE=manual but $SSL_DIR/koha.key not found."
        log_info "Using manually provided SSL certificate."
        ;;
    *)
        die "Unknown SSL_MODE: ${SSL_MODE}. Valid options: self-signed, letsencrypt, manual"
        ;;
esac

# ── Step 5: Generate Nginx config from template ──────────────────────────────
log_step "Nginx configuration"

NGINX_CONF="$ENGINE_DIR/config/nginx.conf"
NGINX_TMPL="$ENGINE_DIR/templates/nginx.conf.tmpl"

if [ -f "$NGINX_TMPL" ]; then
    export OPAC_DOMAIN STAFF_DOMAIN HTTPS_PORT HTTPS_STAFF_PORT \
           OPAC_INTERNAL_PORT STAFF_INTERNAL_PORT HTTP_PORT
    envsubst '${OPAC_DOMAIN} ${STAFF_DOMAIN} ${HTTPS_PORT} ${HTTPS_STAFF_PORT} \
              ${OPAC_INTERNAL_PORT} ${STAFF_INTERNAL_PORT} ${HTTP_PORT}' \
        < "$NGINX_TMPL" > "$NGINX_CONF"
    log_info "Nginx config generated: $NGINX_CONF"
else
    log_warn "Nginx template not found at $NGINX_TMPL — nginx will use a default config."
fi

# ── Step 6: Create persistent Docker volume for SSL certs ────────────────────
log_step "Docker volumes"

# Ensure the named volume exists and seed it with the SSL certs
PROJECT="${COMPOSE_PROJECT_NAME:-koha}"
VOL_SSL="${PROJECT}_koha_ssl"

if ! docker volume inspect "$VOL_SSL" >/dev/null 2>&1; then
    docker volume create "$VOL_SSL" >/dev/null
    log_info "Volume '$VOL_SSL' created."
fi

# Copy certs into the volume using a temporary Alpine container
docker run --rm \
    -v "$SSL_DIR":/src:ro \
    -v "${VOL_SSL}":/dst \
    alpine sh -c "cp /src/koha.crt /dst/koha.crt && cp /src/koha.key /dst/koha.key" \
    2>/dev/null
log_info "SSL certs seeded into volume '$VOL_SSL'."

# ── Step 7: Pull images ───────────────────────────────────────────────────────
log_step "Pulling Docker images"

docker compose --env-file "$ENGINE_DIR/.env" \
    -f "$ENGINE_DIR/docker-compose.yml" \
    --project-directory "$ENGINE_DIR" \
    pull --ignore-pull-failures db memcached opensearch nginx 2>&1 \
    | grep -v "^#" || true

log_info "Base images pulled."

# ── Step 8: Build Koha image ──────────────────────────────────────────────────
log_step "Building Koha 24.05 image"
log_warn "This downloads ~600 MB of packages on the first run — please be patient ..."

docker compose --env-file "$ENGINE_DIR/.env" \
    -f "$ENGINE_DIR/docker-compose.yml" \
    --project-directory "$ENGINE_DIR" \
    build --pull koha 2>&1 | tail -5

log_info "Koha image built."

# ── Step 9: Start the stack ───────────────────────────────────────────────────
log_step "Starting services"

docker compose --env-file "$ENGINE_DIR/.env" \
    -f "$ENGINE_DIR/docker-compose.yml" \
    --project-directory "$ENGINE_DIR" \
    up -d --remove-orphans

log_info "All services started."

# ── Step 10: Wait for MariaDB to be healthy ───────────────────────────────────
log_step "Waiting for MariaDB"

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-koha}"
DB_CONTAINER="${PROJECT_NAME}-db-1"

RETRIES=60
until docker inspect -f '{{.State.Health.Status}}' "$DB_CONTAINER" 2>/dev/null | grep -q "healthy"; do
    RETRIES=$((RETRIES - 1))
    if [ "$RETRIES" -le 0 ]; then
        die "MariaDB did not become healthy in time. Check logs: docker logs $DB_CONTAINER"
    fi
    printf "."
    sleep 3
done
echo ""
log_info "MariaDB is healthy."

# ── Step 11: Wait for Koha to be ready ───────────────────────────────────────
log_step "Waiting for Koha to start"
log_warn "First startup can take 5-10 minutes (Zebra indexer, Plack warm-up) ..."

KOHA_CONTAINER="${PROJECT_NAME}-koha-1"
OPAC_INTERNAL="${OPAC_INTERNAL_PORT:-8080}"

RETRIES=120
until docker exec "$KOHA_CONTAINER" \
    curl -sf "http://localhost:${OPAC_INTERNAL}/" -o /dev/null 2>/dev/null; do
    RETRIES=$((RETRIES - 1))
    if [ "$RETRIES" -le 0 ]; then
        log_warn "Koha is taking longer than expected. Check: docker logs $KOHA_CONTAINER"
        break
    fi
    printf "."
    sleep 5
done
echo ""

# ── Step 12: Health check ─────────────────────────────────────────────────────
log_step "Running health check"
bash "$SCRIPT_DIR/healthcheck.sh" 2>/dev/null || log_warn "Some services are still warming up — run healthcheck.sh later."

# ── Step 13: Print summary ────────────────────────────────────────────────────
SERVER_IP=$(ip route get 1 2>/dev/null | awk '{print $7; exit}' || echo "${SERVER_NAME:-localhost}")
HTTPS_P="${HTTPS_PORT:-443}"
HTTPS_SP="${HTTPS_STAFF_PORT:-8443}"

echo ""
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║              Koha Deployment Complete!                       ║"
echo "  ╠══════════════════════════════════════════════════════════════╣"
printf "  ║  OPAC URL   : https://%-39s║\n" "${SERVER_IP}:${HTTPS_P}/"
printf "  ║  Staff URL  : https://%-39s║\n" "${SERVER_IP}:${HTTPS_SP}/cgi-bin/koha/mainpage.pl"
echo "  ╠══════════════════════════════════════════════════════════════╣"
printf "  ║  Admin user : %-46s║\n" "${ADMIN_USER:-koha}"
printf "  ║  Admin pass : %-46s║\n" "${ADMIN_PASS}"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo ""
log_warn "Credentials are stored in .env — keep this file secure (chmod 600)."
echo ""
log_info "Manage with: chengetai status / stop / logs / backup"
echo ""
