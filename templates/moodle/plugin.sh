#!/usr/bin/env bash
# Moodle platform plugin for ChengetAi Deploy.
# Sourced by lib/utils.sh:load_plugin — requires DEPLOY_DIR, DEPLOY_NAME and
# the profile variables (INSTITUTION, ADMIN_EMAIL, UI_PORT, ...).
#
# Moodle ships as the official Bitnami images (no external deployment repo),
# so the stack lives in this template (templates/moodle/engine/) and is
# instantiated per deployment into deployments/<name>/engine/ with a
# generated .env. Bitnami creates the administrator on first boot from the
# environment, so there is no web installer to run. Moodle uses a single web
# port (UI_PORT -> container 8080).

# shellcheck disable=SC2034  # PLUGIN_* consumed by the CLI after sourcing
PLUGIN_NAME="moodle"
PLUGIN_DESCRIPTION="Moodle learning management system"
PLUGIN_STATUS="available"

ENGINE_TEMPLATE="$TEMPLATES_DIR/moodle/engine"

engine_dir() {
    echo "$DEPLOY_DIR/engine"
}

ui_port() {
    echo "${UI_PORT:-8080}"
}

require_engine() {
    if [ ! -f "$(engine_dir)/docker-compose.yml" ]; then
        error "Deployment '$DEPLOY_NAME' has not been deployed yet. Run: chengetai deploy $DEPLOY_NAME"
    fi
}

pcompose() {
    docker compose -p "chengetai-$DEPLOY_NAME" \
        -f "$(engine_dir)/docker-compose.yml" \
        --project-directory "$(engine_dir)" "$@"
}

plugin_server_ip() {
    local ip
    ip=$(grep -s '^SERVER_IP=' "$(engine_dir)/.env" | cut -d= -f2)
    [ -n "$ip" ] || ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
    echo "${ip:-localhost}"
}

plugin_urls() {
    local ip
    ip=$(plugin_server_ip)
    echo "  Moodle (web):  http://${ip}:$(ui_port)"
}

plugin_deploy() {
    local engine
    engine=$(engine_dir)

    # 1. Instantiate the engine from the template (idempotent).
    mkdir -p "$engine"
    cp -a "$ENGINE_TEMPLATE/." "$engine/"

    # 2. Generate .env once (preserved across re-deploys), chmod 600.
    if [ ! -f "$engine/.env" ]; then
        local db_pass db_root admin_pass
        db_pass=$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)
        db_root=$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)
        # Moodle's password policy needs upper/lower/digit/special — the
        # suffix guarantees it when we generate one.
        admin_pass="${ADMIN_PASS:-$(head -c 16 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 10)Aa1@}"
        {
            echo "SERVER_IP=$(plugin_server_ip)"
            echo "UI_PORT=$(ui_port)"
            echo "DB_PASSWORD=${db_pass}"
            echo "DB_ROOT_PASSWORD=${db_root}"
            echo "MOODLE_ADMIN_USER=${MOODLE_ADMIN_USER:-admin}"
            echo "MOODLE_ADMIN_PASS=${admin_pass}"
            echo "MOODLE_ADMIN_EMAIL=${ADMIN_EMAIL:-admin@example.org}"
            echo "MOODLE_SITE_NAME=${REPOSITORY:-${INSTITUTION:-Moodle}}"
        } > "$engine/.env"
        chmod 600 "$engine/.env"
    fi

    info "Pulling Moodle images (first run downloads a few hundred MB)..."
    pcompose pull

    info "Starting Moodle..."
    pcompose up -d

    echo ""
    info "Moodle is starting. First boot installs the site and can take 5-10 minutes."
    echo ""
    plugin_urls
    local admin
    admin=$(grep -s '^MOODLE_ADMIN_USER=' "$engine/.env" | cut -d= -f2)
    echo ""
    echo "  Admin login: ${admin:-admin} (password in $engine/.env — MOODLE_ADMIN_PASS)"
    echo "  Watch progress with: chengetai status $DEPLOY_NAME"
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
    echo "  The site can take a few minutes to come up. Check: chengetai status $DEPLOY_NAME"
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

    local ip admin
    ip=$(plugin_server_ip)
    admin=$(grep -s '^MOODLE_ADMIN_USER=' "$(engine_dir)/.env" | cut -d= -f2)

    echo ""
    if curl -sf "http://localhost:$(ui_port)/login/index.php" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Moodle : http://${ip}:$(ui_port)"
    else
        echo -e "${RED}✗${NC} Moodle : not responding yet (http://${ip}:$(ui_port))"
    fi
    echo -e "  Admin login: ${admin:-admin} (password in $(engine_dir)/.env)"
    echo ""
}

plugin_logs() {
    require_engine
    pcompose logs --tail=200 -f "$@"
}

plugin_backup() {
    require_engine
    if ! pcompose ps --status running 2>/dev/null | grep -q moodle-db; then
        error "The database container is not running. Start it first: chengetai start $DEPLOY_NAME"
    fi

    local dest root
    dest="$DEPLOY_DIR/backups/chengetai-backup-$(date +%Y%m%d-%H%M%S)"
    root=$(grep -s '^DB_ROOT_PASSWORD=' "$(engine_dir)/.env" | cut -d= -f2)
    mkdir -p "$dest"

    info "Backing up database..."
    pcompose exec -T moodle-db sh -c "exec mariadb-dump -uroot -p'$root' bitnami_moodle" | gzip > "$dest/moodle-db.sql.gz"

    info "Backing up Moodle data (uploads, config)..."
    pcompose exec -T moodle tar czf - -C /bitnami moodledata > "$dest/moodledata.tar.gz" 2>/dev/null || \
        warn "Moodle data backup skipped (container not running)."

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

    local db_dump="$backup/moodle-db.sql.gz"
    [ -f "$db_dump" ] || error "Database dump not found: $db_dump"

    echo "This will REPLACE the current Moodle database with:"
    echo "  $backup"
    echo ""
    if ! confirm "Proceed with restore?"; then
        echo "Restore cancelled."
        exit 0
    fi

    local root
    root=$(grep -s '^DB_ROOT_PASSWORD=' "$(engine_dir)/.env" | cut -d= -f2)

    info "Restoring database..."
    gunzip -c "$db_dump" | pcompose exec -T moodle-db sh -c "exec mariadb -uroot -p'$root' bitnami_moodle"

    info "Restarting Moodle..."
    pcompose restart moodle

    echo ""
    info "Restore complete. Moodle may purge its caches on the next request."
    echo ""
}

plugin_update() {
    require_engine
    info "Pulling the latest Moodle images..."
    pcompose pull
    pcompose up -d
}

plugin_edit() {
    local component="$1"
    case "$component" in
        config)
            require_engine
            local file
            file="$(engine_dir)/.env"
            echo "Opening: $file"
            "${EDITOR:-nano}" "$file"
            echo ""
            if confirm "Restart Moodle to apply?"; then
                require_docker
                pcompose up -d
            fi
            ;;
        *)
            error "Moodle supports: chengetai edit config $DEPLOY_NAME (port, site name, image tags, admin email). Themes and branding are configured inside Moodle's own admin UI."
            ;;
    esac
}

# plugin_remove [purge]
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
