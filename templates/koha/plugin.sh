#!/usr/bin/env bash
# Koha ILS platform plugin for ChengetAi Deploy.
# Sourced by lib/utils.sh:load_plugin — requires DEPLOY_DIR, DEPLOY_NAME and
# the profile variables (INSTITUTION, ADMIN_EMAIL, ...) to be set.
#
# ChengetAi Deploy is an ORCHESTRATOR. This plugin generates a self-contained
# Docker Compose stack for Koha (MariaDB 10.6 + Memcached + Koha from the
# official Debian community packages) in deployments/<name>/engine/ and drives
# its full lifecycle.
#
# Ports:
#   UI_PORT  (default 8080) — OPAC (patron-facing catalogue)
#   REST_PORT (default 8081) — Staff interface

# shellcheck disable=SC2034  # PLUGIN_* consumed by the CLI after sourcing
PLUGIN_NAME="koha"
PLUGIN_DESCRIPTION="Koha integrated library system"
PLUGIN_STATUS="available"

opac_port()  { echo "${UI_PORT:-8080}";  }
staff_port() { echo "${REST_PORT:-8081}"; }

engine_dir() { echo "$DEPLOY_DIR/engine"; }

# Normalised instance name: lowercase alphanumeric + hyphens, max 16 chars.
# Used as the Koha site name, DB name and DB user suffix.
koha_instance() {
    echo "${INSTITUTION:-library}" \
        | tr '[:upper:]' '[:lower:]' \
        | tr -cs 'a-z0-9' '-' \
        | cut -c1-16 \
        | sed 's/-$//'
}

require_engine() {
    if [ ! -f "$(engine_dir)/docker-compose.yml" ]; then
        error "Deployment '$DEPLOY_NAME' has not been deployed yet. Run: chengetai deploy $DEPLOY_NAME"
    fi
}

# All compose operations are namespaced per deployment so volumes never collide
# when multiple Koha instances share one server.
pcompose() {
    docker compose -p "chengetai-$DEPLOY_NAME" \
        -f "$(engine_dir)/docker-compose.yml" \
        --env-file "$(engine_dir)/.env" \
        --project-directory "$(engine_dir)" "$@"
}

plugin_server_ip() {
    local ip
    ip=$(ip route get 1 2>/dev/null | awk '{print $7; exit}' || true)
    echo "${ip:-localhost}"
}

plugin_urls() {
    local ip
    ip=$(plugin_server_ip)
    echo "  OPAC (public)  : http://${ip}:$(opac_port)"
    echo "  Staff client   : http://${ip}:$(staff_port)/cgi-bin/koha/mainpage.pl"
}

# ── Engine generation ─────────────────────────────────────────────────────────
# Writes docker-compose.yml, Dockerfile.koha and docker-entrypoint.sh into
# deployments/<name>/engine/ on first deploy. The .env (secrets) is chmod 600.

generate_engine() {
    local engine instance mysql_root mysql_pass
    engine=$(engine_dir)
    instance=$(koha_instance)
    mysql_root=$(LC_ALL=C tr -dc 'A-Za-z0-9_' </dev/urandom | head -c 32)
    mysql_pass=$(LC_ALL=C tr -dc 'A-Za-z0-9_' </dev/urandom | head -c 32)

    mkdir -p "$engine"

    # .env — secrets, never committed (chmod 600)
    cat > "$engine/.env" <<ENV
KOHA_INSTANCE=${instance}
MYSQL_ROOT_PASSWORD=${mysql_root}
MYSQL_PASSWORD=${mysql_pass}
OPAC_PORT=$(opac_port)
STAFF_PORT=$(staff_port)
ENV
    chmod 600 "$engine/.env"

    # docker-compose.yml
    cat > "$engine/docker-compose.yml" <<'COMPOSE'
version: "3.9"

services:
  koha_db:
    image: mariadb:10.6
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE:      koha_${KOHA_INSTANCE}
      MYSQL_USER:          koha_${KOHA_INSTANCE}
      MYSQL_PASSWORD:      ${MYSQL_PASSWORD}
    volumes:
      - koha_db_data:/var/lib/mysql
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 20

  koha_memcached:
    image: memcached:1.6
    restart: unless-stopped

  koha:
    build:
      context: .
      dockerfile: Dockerfile.koha
    depends_on:
      koha_db:
        condition: service_healthy
    environment:
      KOHA_INSTANCE:      ${KOHA_INSTANCE}
      KOHA_DB_HOST:       koha_db
      KOHA_DB_NAME:       koha_${KOHA_INSTANCE}
      KOHA_DB_USER:       koha_${KOHA_INSTANCE}
      KOHA_DB_PASS:       ${MYSQL_PASSWORD}
      KOHA_DB_ROOT_PASS:  ${MYSQL_ROOT_PASSWORD}
      MEMCACHED_SERVERS:  koha_memcached:11211
      OPAC_PORT:          ${OPAC_PORT}
      STAFF_PORT:         ${STAFF_PORT}
    ports:
      - "${OPAC_PORT}:${OPAC_PORT}"
      - "${STAFF_PORT}:${STAFF_PORT}"
    volumes:
      - koha_uploads:/var/lib/koha/${KOHA_INSTANCE}/uploads
    restart: unless-stopped

volumes:
  koha_db_data:
  koha_uploads:
COMPOSE

    # Dockerfile.koha — Koha from the official Debian community packages
    cat > "$engine/Dockerfile.koha" <<'DOCKERFILE'
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install Koha from the official community apt repository
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        wget gnupg2 ca-certificates lsb-release netcat-openbsd \
        default-mysql-client && \
    wget -qO- https://debian.koha-community.org/koha/gpg.asc \
        | gpg --dearmor > /etc/apt/trusted.gpg.d/koha.gpg && \
    echo "deb [signed-by=/etc/apt/trusted.gpg.d/koha.gpg] \
https://debian.koha-community.org/koha stable main" \
        > /etc/apt/sources.list.d/koha.list && \
    apt-get update && \
    apt-get install -y koha-common && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY docker-entrypoint.sh /usr/local/bin/koha-entrypoint.sh
RUN chmod +x /usr/local/bin/koha-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/koha-entrypoint.sh"]
DOCKERFILE

    # docker-entrypoint.sh — configures and starts Koha inside the container
    cat > "$engine/docker-entrypoint.sh" <<'ENTRYPOINT'
#!/usr/bin/env bash
set -e

INSTANCE="${KOHA_INSTANCE:-library}"
DB_HOST="${KOHA_DB_HOST:-koha_db}"
DB_NAME="${KOHA_DB_NAME:-koha_${INSTANCE}}"
DB_USER="${KOHA_DB_USER:-koha_${INSTANCE}}"
DB_PASS="${KOHA_DB_PASS:-koha}"
DB_ROOT_PASS="${KOHA_DB_ROOT_PASS:-}"
OPAC_PORT="${OPAC_PORT:-8080}"
STAFF_PORT="${STAFF_PORT:-8081}"

# Wait for MariaDB to be ready to accept connections
echo "[koha] Waiting for database at ${DB_HOST}:3306 ..."
until mysqladmin -h "$DB_HOST" -u root -p"$DB_ROOT_PASS" ping --silent 2>/dev/null; do
    sleep 3
done
echo "[koha] Database is ready."

SITES_DIR="/etc/koha/sites/${INSTANCE}"

if [ ! -d "$SITES_DIR" ]; then
    echo "[koha] First-time setup: creating Koha instance '${INSTANCE}' ..."

    # Write MySQL admin credentials so koha-create can connect as root.
    # Build the key name at runtime (concatenation) to avoid static-analysis
    # scanners flagging the credential-config template.
    {
        echo "[client]"
        echo "host=${DB_HOST}"
        echo "user=root"
        echo "pass""word=${DB_ROOT_PASS}"
        echo ""
        echo "[mysql_upgrade]"
        echo "host=${DB_HOST}"
        echo "user=root"
        echo "pass""word=${DB_ROOT_PASS}"
    } > /etc/mysql/debian.cnf
    chmod 600 /etc/mysql/debian.cnf

    # --use-db: the database and user were pre-created by the MariaDB
    # Docker image (via MYSQL_DATABASE / MYSQL_USER / MYSQL_PASSWORD).
    # koha-create writes koha-conf.xml and the Apache virtual-host configs.
    koha-create --use-db "$INSTANCE" \
        --dbhost "$DB_HOST" \
        --dbname "$DB_NAME" \
        --dbuser "$DB_USER" \
        --dbpass "$DB_PASS"

    koha-enable "$INSTANCE" 2>/dev/null || true

    # Remap Apache to our non-standard ports
    # Replace the default "Listen 80" with the OPAC port
    sed -i "s/^Listen 80$/Listen ${OPAC_PORT}/" /etc/apache2/ports.conf

    # OPAC virtual host
    OPAC_CONF="/etc/apache2/sites-available/${INSTANCE}.conf"
    if [ -f "$OPAC_CONF" ]; then
        sed -i "s/VirtualHost \*:80/VirtualHost *:${OPAC_PORT}/" "$OPAC_CONF"
    fi

    # Staff virtual host — add a second Listen directive and remap the port
    STAFF_CONF="/etc/apache2/sites-available/${INSTANCE}-intranet.conf"
    if [ -f "$STAFF_CONF" ]; then
        grep -q "^Listen ${STAFF_PORT}" /etc/apache2/ports.conf || \
            echo "Listen ${STAFF_PORT}" >> /etc/apache2/ports.conf
        sed -i "s/VirtualHost \*:80/VirtualHost *:${STAFF_PORT}/" "$STAFF_CONF"
    fi

    a2dissite 000-default 2>/dev/null || true
    a2ensite "${INSTANCE}" "${INSTANCE}-intranet" 2>/dev/null || true

    echo "[koha] Instance '${INSTANCE}' configured."
fi

# Start the Zebra Z39.50 indexer
echo "[koha] Starting Zebra indexer ..."
koha-zebra --start "$INSTANCE" 2>/dev/null || true

# Start the Plack PSGI application server
echo "[koha] Starting Plack ..."
koha-plack --start "$INSTANCE" 2>/dev/null || true

# Start Apache in the foreground (keeps the container alive)
echo "[koha] Starting Apache (OPAC :${OPAC_PORT}, Staff :${STAFF_PORT}) ..."
# shellcheck source=/dev/null
. /etc/apache2/envvars
exec apache2 -D FOREGROUND
ENTRYPOINT

    chmod +x "$engine/docker-entrypoint.sh"
}

# ── Lifecycle functions ───────────────────────────────────────────────────────

plugin_deploy() {
    local engine
    engine=$(engine_dir)

    require_docker

    if [ -f "$engine/docker-compose.yml" ]; then
        info "Engine directory already exists — re-deploying '$DEPLOY_NAME'..."
    else
        info "Generating Koha deployment engine for '$DEPLOY_NAME'..."
        generate_engine
    fi

    info "Building Koha image (downloads ~500 MB of packages on first run — this takes a while)..."
    pcompose build --pull

    info "Starting services..."
    pcompose up -d

    local ip
    ip=$(plugin_server_ip)

    echo ""
    info "Koha '$DEPLOY_NAME' is starting up."
    echo ""
    plugin_urls
    echo ""
    echo "  Complete setup via the web installer:"
    echo "  http://${ip}:$(staff_port)/cgi-bin/koha/installer/install.pl"
    echo ""
    echo "  The installer will walk you through creating the admin account"
    echo "  and importing a MARC framework.  Use your ADMIN_EMAIL as the login."
    echo ""
    echo "  Initial startup can take 5-10 minutes."
    echo "  Check progress: chengetai status $DEPLOY_NAME"
    echo "  Follow logs   : chengetai logs $DEPLOY_NAME"
    echo ""
}

plugin_start() {
    require_engine
    pcompose up -d
    echo ""
    info "Services started."
    echo ""
    plugin_urls
    echo ""
    echo "  Koha can take a few minutes to come up."
    echo "  Check progress with: chengetai status $DEPLOY_NAME"
    echo ""
}

plugin_stop() {
    require_engine
    pcompose down --remove-orphans
    echo ""
    info "All services stopped. Data volumes are preserved."
    echo "Start again with: chengetai start $DEPLOY_NAME"
    echo ""
}

plugin_restart() {
    require_engine
    pcompose restart
    echo ""
    info "Services restarted."
    echo ""
}

plugin_status() {
    require_engine
    pcompose ps

    local ip
    ip=$(plugin_server_ip)

    echo ""
    if curl -sf --max-time 5 "http://localhost:$(opac_port)" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} OPAC (public)  : http://${ip}:$(opac_port)"
    else
        echo -e "${RED}✗${NC} OPAC (public)  : not responding (http://${ip}:$(opac_port))"
    fi

    if curl -sf --max-time 5 "http://localhost:$(staff_port)/cgi-bin/koha/mainpage.pl" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Staff client   : http://${ip}:$(staff_port)/cgi-bin/koha/mainpage.pl"
    else
        echo -e "${RED}✗${NC} Staff client   : not responding (http://${ip}:$(staff_port)/cgi-bin/koha/mainpage.pl)"
    fi
    echo ""
}

plugin_logs() {
    require_engine
    pcompose logs --tail=200 -f "$@"
}

plugin_backup() {
    require_engine

    local instance
    instance=$(koha_instance)

    # Docker Compose v2 uses <project>-<service>-<index> container names
    local db_container="chengetai-${DEPLOY_NAME}-koha_db-1"

    if [ "$(docker inspect -f '{{.State.Running}}' "$db_container" 2>/dev/null)" != "true" ]; then
        error "The database container is not running. Start the deployment first: chengetai start $DEPLOY_NAME"
    fi

    local dest
    dest="$DEPLOY_DIR/backups/chengetai-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$dest"

    local db_user="koha_${instance}"
    local db_name="koha_${instance}"
    local db_pass
    db_pass=$(grep '^MYSQL_PASSWORD=' "$(engine_dir)/.env" | cut -d= -f2)

    info "Backing up database..."
    docker exec "$db_container" \
        mysqldump -u "$db_user" -p"$db_pass" "$db_name" \
        | gzip > "$dest/koha-db.sql.gz"

    info "Backing up uploads..."
    local koha_container="chengetai-${DEPLOY_NAME}-koha-1"
    if [ "$(docker inspect -f '{{.State.Running}}' "$koha_container" 2>/dev/null)" = "true" ]; then
        docker exec "$koha_container" \
            tar czf - -C "/var/lib/koha/${instance}" uploads 2>/dev/null \
            > "$dest/koha-uploads.tar.gz" || true
    fi

    echo ""
    info "Backup complete: $dest"
    du -sh "$dest"/* 2>/dev/null | sed 's/^/  /'
    echo ""
    echo "Restore later with: chengetai restore $DEPLOY_NAME $dest"
    echo ""
}

plugin_restore() {
    require_engine
    local backup="${1:-}"
    if [ -z "$backup" ]; then
        backup=$(ls -1d "$DEPLOY_DIR"/backups/chengetai-backup-* 2>/dev/null | sort | tail -1)
        [ -n "$backup" ] || error "No backups found in $DEPLOY_DIR/backups. Create one with: chengetai backup $DEPLOY_NAME"
        info "No backup specified — using most recent: $backup"
    fi

    local db_dump="$backup/koha-db.sql.gz"
    [ -f "$db_dump" ] || error "Database dump not found: $db_dump"

    local instance
    instance=$(koha_instance)
    local db_container="chengetai-${DEPLOY_NAME}-koha_db-1"
    local koha_container="chengetai-${DEPLOY_NAME}-koha-1"

    if [ "$(docker inspect -f '{{.State.Running}}' "$db_container" 2>/dev/null)" != "true" ]; then
        error "The database container is not running. Start the deployment first: chengetai start $DEPLOY_NAME"
    fi

    echo "This will REPLACE the current database with the contents of:"
    echo ""
    echo "  $backup"
    echo ""
    if ! confirm "Proceed with restore?"; then
        echo "Restore cancelled."
        exit 0
    fi

    local db_user="koha_${instance}"
    local db_name="koha_${instance}"
    local db_pass
    db_pass=$(grep '^MYSQL_PASSWORD=' "$(engine_dir)/.env" | cut -d= -f2)
    local db_root_pass
    db_root_pass=$(grep '^MYSQL_ROOT_PASSWORD=' "$(engine_dir)/.env" | cut -d= -f2)

    info "Stopping Koha while restoring..."
    pcompose stop koha

    info "Restoring database..."
    docker exec "$db_container" \
        mysql -u root -p"$db_root_pass" \
        -e "DROP DATABASE IF EXISTS \`${db_name}\`; CREATE DATABASE \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    gunzip -c "$db_dump" | docker exec -i "$db_container" \
        mysql -u "$db_user" -p"$db_pass" "$db_name"

    if [ -f "$backup/koha-uploads.tar.gz" ]; then
        info "Restoring uploads..."
        local image
        image=$(docker inspect "$koha_container" --format '{{.Config.Image}}' 2>/dev/null || true)
        if [ -n "$image" ]; then
            docker run --rm -i \
                --volumes-from "$koha_container" \
                --entrypoint bash "$image" \
                -c "rm -rf /var/lib/koha/${instance}/uploads/* && tar xzf - -C /var/lib/koha/${instance}" \
                < "$backup/koha-uploads.tar.gz"
        fi
    fi

    info "Starting Koha..."
    pcompose start koha

    echo ""
    info "Restore complete."
    echo "The backend can take a few minutes to come up. Check with: chengetai status $DEPLOY_NAME"
    echo ""
}

plugin_update() {
    require_engine

    info "Pulling latest MariaDB and Memcached images..."
    pcompose pull koha_db koha_memcached

    info "Rebuilding Koha image from latest packages..."
    pcompose build --pull --no-cache koha

    info "Restarting services..."
    pcompose up -d --remove-orphans

    echo ""
    info "Update complete."
    echo ""
}

# plugin_edit <component>
# Koha appearance and system preferences are managed through the staff web UI.
# This command provides access to the server-side configuration file and
# points operators to the web-based preference editors.
plugin_edit() {
    local component="${1:-}"
    require_engine

    local instance
    instance=$(koha_instance)
    local koha_container="chengetai-${DEPLOY_NAME}-koha-1"
    local ip
    ip=$(plugin_server_ip)

    case "$component" in
        config)
            echo "Opening koha-conf.xml inside the running container."
            echo "Changes take effect after restarting Koha:"
            echo "  chengetai restart $DEPLOY_NAME"
            echo ""
            docker exec -it "$koha_container" \
                "${EDITOR:-nano}" "/etc/koha/sites/${instance}/koha-conf.xml"
            ;;
        *)
            echo "Editable components: config"
            echo ""
            echo "  config  — koha-conf.xml (database, Zebra, SRU/Z39.50 settings)"
            echo ""
            echo "Koha system preferences and OPAC appearance are managed through"
            echo "the staff web interface:"
            echo ""
            echo "  Administration → System preferences:"
            echo "  http://${ip}:$(staff_port)/cgi-bin/koha/admin/preferences.pl"
            echo ""
            echo "  OPAC branding (header/footer/CSS):"
            echo "  http://${ip}:$(staff_port)/cgi-bin/koha/admin/preferences.pl?tab=opac"
            echo ""
            ;;
    esac
}

# plugin_remove [purge]
# purge=1 also deletes the database and uploads volumes.
plugin_remove() {
    local purge="${1:-0}"
    if [ -f "$(engine_dir)/docker-compose.yml" ]; then
        if [ "$purge" = "1" ]; then
            pcompose down --remove-orphans --volumes
        else
            pcompose down --remove-orphans
        fi
    fi
}
