#!/usr/bin/env bash
# Koha ILS platform plugin for ChengetAi Deploy.
# Sourced by lib/utils.sh:load_plugin — requires DEPLOY_DIR, DEPLOY_NAME and
# the profile variables (INSTITUTION, ADMIN_EMAIL, ...) to be set.
#
# ChengetAi Deploy is an ORCHESTRATOR.  This plugin provisions a
# self-contained Docker Compose stack (Koha 24.05 + MariaDB 11 +
# OpenSearch 2 + Memcached + Nginx TLS reverse proxy) in
# deployments/<name>/engine/ by copying the engine template from
# engines/koha-engine/ and driving its full lifecycle.
#
# Public URLs (via Nginx):
#   OPAC  : https://<IP>:<HTTPS_PORT:-443>/
#   Staff : https://<IP>:<HTTPS_STAFF_PORT:-8443>/cgi-bin/koha/mainpage.pl

# shellcheck disable=SC2034  # PLUGIN_* consumed by the CLI after sourcing
PLUGIN_NAME="koha"
PLUGIN_DESCRIPTION="Koha 24.05 integrated library system"
PLUGIN_STATUS="available"

# Location of the engine source template (relative to CHENGETAI_HOME)
KOHA_ENGINE_SRC="${CHENGETAI_HOME}/engines/koha-engine"

https_port()       { echo "${HTTPS_PORT:-443}"; }
https_staff_port() { echo "${HTTPS_STAFF_PORT:-8443}"; }

engine_dir() { echo "$DEPLOY_DIR/engine"; }

# Normalised instance name: lowercase alphanumeric + hyphens, max 16 chars.
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

# All compose operations are namespaced per deployment so volumes never
# collide when multiple Koha instances share one server.
pcompose() {
    docker compose \
        -p "chengetai-${DEPLOY_NAME}" \
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
    echo "  OPAC (public)  : https://${ip}:$(https_port)/"
    echo "  Staff client   : https://${ip}:$(https_staff_port)/cgi-bin/koha/mainpage.pl"
}

# ── Engine provisioning ───────────────────────────────────────────────────────
# Copies engines/koha-engine/ to deployments/<name>/engine/ and writes
# a deployment-specific .env (chmod 600).  Idempotent.

provision_engine() {
    local engine instance mysql_root mysql_pass admin_pass
    engine=$(engine_dir)
    instance=$(koha_instance)

    # Verify engine source exists
    if [ ! -d "$KOHA_ENGINE_SRC" ]; then
        error "Koha engine source not found at $KOHA_ENGINE_SRC.
Please ensure the ChengetAi Koha Engine is present in the engines/ directory."
    fi

    mkdir -p "$engine"

    # Copy engine files (skip if already present to preserve customisations)
    if [ ! -f "$engine/docker-compose.yml" ]; then
        cp -r "$KOHA_ENGINE_SRC/." "$engine/"
        info "Engine files copied to: $engine"
    fi

    # Generate .env from .env.example, then fill in deployment-specific values
    if [ ! -f "$engine/.env" ]; then
        cp "$engine/.env.example" "$engine/.env"
    fi

    # Generate secrets for any blank values
    mysql_root=$(LC_ALL=C tr -dc 'A-Za-z0-9_' </dev/urandom | head -c 32)
    mysql_pass=$(LC_ALL=C tr -dc 'A-Za-z0-9_' </dev/urandom | head -c 32)
    admin_pass=$(LC_ALL=C tr -dc 'A-Za-z0-9_' </dev/urandom | head -c 32)

    # Write deployment-specific values (overwrite .env completely)
    cat > "$engine/.env" <<ENV
# ChengetAi Deploy — Koha deployment: ${DEPLOY_NAME}
# Generated $(date -u +%Y-%m-%dT%H:%M:%SZ)

KOHA_INSTANCE=${instance}
INSTITUTION=${INSTITUTION:-My Library}
ADMIN_USER=${ADMIN_EMAIL%%@*}
ADMIN_EMAIL=${ADMIN_EMAIL:-admin@example.com}
ADMIN_PASS=${admin_pass}

SERVER_NAME=$(plugin_server_ip)
OPAC_DOMAIN=$(plugin_server_ip)
STAFF_DOMAIN=$(plugin_server_ip)

HTTP_PORT=80
HTTPS_PORT=$(https_port)
HTTPS_STAFF_PORT=$(https_staff_port)
OPAC_INTERNAL_PORT=8080
STAFF_INTERNAL_PORT=8081

MYSQL_ROOT_PASSWORD=${mysql_root}
MYSQL_PASSWORD=${mysql_pass}

OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m
MEMCACHED_MAX_MEMORY=256
SSL_MODE=self-signed
CERTBOT_EMAIL=${ADMIN_EMAIL:-admin@example.com}
TZ=Africa/Harare

COMPOSE_PROJECT_NAME=chengetai-${DEPLOY_NAME}
ENV
    chmod 600 "$engine/.env"
}

# ── Lifecycle functions ───────────────────────────────────────────────────────

plugin_deploy() {
    local engine
    engine=$(engine_dir)

    require_docker

    if [ -f "$engine/docker-compose.yml" ]; then
        info "Engine already provisioned — re-deploying '$DEPLOY_NAME'..."
    else
        info "Provisioning Koha engine for '$DEPLOY_NAME'..."
        provision_engine
    fi

    info "Running Koha engine installer..."
    COMPOSE_PROJECT_NAME="chengetai-${DEPLOY_NAME}" \
    BACKUP_DIR="$DEPLOY_DIR/backups" \
        bash "$engine/scripts/install.sh"
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
    local hp hs
    hp=$(https_port)
    hs=$(https_staff_port)

    echo ""
    if curl -sk --max-time 5 "https://localhost:${hp}/" -o /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} OPAC (public)  : https://${ip}:${hp}/"
    else
        echo -e "${RED}✗${NC} OPAC (public)  : not responding (https://${ip}:${hp}/)"
    fi

    if curl -sk --max-time 5 "https://localhost:${hs}/cgi-bin/koha/mainpage.pl" -o /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Staff client   : https://${ip}:${hs}/cgi-bin/koha/mainpage.pl"
    else
        echo -e "${RED}✗${NC} Staff client   : not responding (https://${ip}:${hs}/cgi-bin/koha/mainpage.pl)"
    fi
    echo ""
}

plugin_logs() {
    require_engine
    pcompose logs --tail=200 -f "$@"
}

plugin_backup() {
    require_engine
    COMPOSE_PROJECT_NAME="chengetai-${DEPLOY_NAME}" \
    BACKUP_DIR="$DEPLOY_DIR/backups" \
        bash "$(engine_dir)/scripts/backup.sh"
}

plugin_restore() {
    require_engine
    local backup="${1:-}"
    COMPOSE_PROJECT_NAME="chengetai-${DEPLOY_NAME}" \
    BACKUP_DIR="$DEPLOY_DIR/backups" \
        bash "$(engine_dir)/scripts/restore.sh" "$backup"
}

plugin_update() {
    require_engine
    COMPOSE_PROJECT_NAME="chengetai-${DEPLOY_NAME}" \
    BACKUP_DIR="$DEPLOY_DIR/backups" \
        bash "$(engine_dir)/scripts/update.sh"
}

# plugin_edit <component>
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
            echo "  https://${ip}:$(https_staff_port)/cgi-bin/koha/admin/preferences.pl"
            echo ""
            echo "  OPAC branding (header/footer/CSS):"
            echo "  https://${ip}:$(https_staff_port)/cgi-bin/koha/admin/preferences.pl?tab=opac"
            echo ""
            ;;
    esac
}

# plugin_remove [purge]
# purge=1 also deletes data volumes.
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
