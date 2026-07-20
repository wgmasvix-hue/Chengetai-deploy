#!/usr/bin/env bash
# OJS (Open Journal Systems) platform plugin for ChengetAi Deploy.
# Sourced by lib/utils.sh:load_plugin — requires DEPLOY_DIR, DEPLOY_NAME and
# the profile variables (INSTITUTION, ADMIN_EMAIL, UI_PORT, ...).
#
# OJS ships as PKP's official pkpofficial/ojs image plus MariaDB. The stack
# lives in this template (templates/ojs/engine/) and is instantiated per
# deployment into deployments/<name>/engine/ with a generated .env. Setup is
# finished in OJS's one-time web installer. OJS uses a single web port
# (UI_PORT -> container 8081).

# shellcheck disable=SC2034  # PLUGIN_* consumed by the CLI after sourcing
PLUGIN_NAME="ojs"
PLUGIN_DESCRIPTION="Open Journal Systems (scholarly publishing)"
PLUGIN_STATUS="available"

ENGINE_TEMPLATE="$TEMPLATES_DIR/ojs/engine"

engine_dir() {
    echo "$DEPLOY_DIR/engine"
}

ui_port() {
    echo "${UI_PORT:-8081}"
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
    echo "  OJS (web):  http://${ip}:$(ui_port)"
}

plugin_deploy() {
    local engine
    engine=$(engine_dir)

    # 1. Instantiate the engine from the template (idempotent).
    mkdir -p "$engine"
    cp -a "$ENGINE_TEMPLATE/." "$engine/"

    # 2. Create the host-side volume targets the compose bind-mounts. The
    #    empty config file is populated by OJS on first boot / install.
    mkdir -p "$engine/volumes/config" "$engine/volumes/public" "$engine/volumes/private"
    [ -e "$engine/volumes/config/ojs.config.inc.php" ] || : > "$engine/volumes/config/ojs.config.inc.php"
    chmod -R 0777 "$engine/volumes" 2>/dev/null || true

    # 3. Generate .env once (preserved across re-deploys), chmod 600.
    if [ ! -f "$engine/.env" ]; then
        local db_pass db_root
        db_pass=$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)
        db_root=$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)
        {
            echo "SERVER_IP=$(plugin_server_ip)"
            echo "SERVERNAME=$(plugin_server_ip)"
            echo "UI_PORT=$(ui_port)"
            echo "DB_PASSWORD=${db_pass}"
            echo "DB_ROOT_PASSWORD=${db_root}"
            echo "OJS_ADMIN_EMAIL=${ADMIN_EMAIL:-admin@example.org}"
            echo "JOURNAL_NAME=${REPOSITORY:-${INSTITUTION:-Journal}}"
        } > "$engine/.env"
        chmod 600 "$engine/.env"
    fi

    info "Pulling OJS images (first run downloads a few hundred MB)..."
    pcompose pull

    info "Starting OJS..."
    pcompose up -d

    local ip pass
    ip=$(plugin_server_ip)
    pass=$(grep -s '^DB_PASSWORD=' "$engine/.env" | cut -d= -f2)

    echo ""
    info "OJS is starting. First boot can take a few minutes."
    echo ""
    plugin_urls
    echo ""
    echo "  Finish setup in OJS's one-time web installer (open the URL above)."
    echo "  When it asks for the database, use:"
    echo "    Driver           : MySQLi"
    echo "    Host             : ojs-db"
    echo "    Username         : ojs"
    echo "    Password         : ${pass}"
    echo "    Database name    : ojs"
    echo "  (These are also in $engine/.env.) Create your admin account in the"
    echo "  same wizard; the administrator email suggested is ${ADMIN_EMAIL:-admin@example.org}."
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
    if curl -sf "http://localhost:$(ui_port)" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} OJS : http://${ip}:$(ui_port)"
    else
        echo -e "${RED}✗${NC} OJS : not responding yet (http://${ip}:$(ui_port))"
    fi
    echo ""
}

plugin_logs() {
    require_engine
    pcompose logs --tail=200 -f "$@"
}

plugin_backup() {
    require_engine
    if ! pcompose ps --status running 2>/dev/null | grep -q ojs-db; then
        error "The database container is not running. Start it first: chengetai start $DEPLOY_NAME"
    fi

    local dest root engine
    engine=$(engine_dir)
    dest="$DEPLOY_DIR/backups/chengetai-backup-$(date +%Y%m%d-%H%M%S)"
    root=$(grep -s '^DB_ROOT_PASSWORD=' "$engine/.env" | cut -d= -f2)
    mkdir -p "$dest"

    info "Backing up database..."
    pcompose exec -T ojs-db sh -c "exec mariadb-dump -uroot -p'$root' ojs" | gzip > "$dest/ojs-db.sql.gz"

    info "Backing up OJS files (config, uploads, public)..."
    tar czf "$dest/ojs-files.tar.gz" -C "$engine" volumes 2>/dev/null || \
        warn "OJS file backup skipped."

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

    local db_dump="$backup/ojs-db.sql.gz"
    [ -f "$db_dump" ] || error "Database dump not found: $db_dump"

    echo "This will REPLACE the current OJS database and files with:"
    echo "  $backup"
    echo ""
    if ! confirm "Proceed with restore?"; then
        echo "Restore cancelled."
        exit 0
    fi

    local root engine
    engine=$(engine_dir)
    root=$(grep -s '^DB_ROOT_PASSWORD=' "$engine/.env" | cut -d= -f2)

    info "Restoring database..."
    gunzip -c "$db_dump" | pcompose exec -T ojs-db sh -c "exec mariadb -uroot -p'$root' ojs"

    if [ -f "$backup/ojs-files.tar.gz" ]; then
        info "Restoring OJS files..."
        tar xzf "$backup/ojs-files.tar.gz" -C "$engine"
    fi

    info "Restarting OJS..."
    pcompose restart ojs

    echo ""
    info "Restore complete."
    echo ""
}

plugin_update() {
    require_engine
    info "Pulling the latest OJS images..."
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
            if confirm "Restart OJS to apply?"; then
                require_docker
                pcompose up -d
            fi
            ;;
        *)
            error "OJS supports: chengetai edit config $DEPLOY_NAME (port, journal name, image tag). Journal branding is configured inside OJS's own admin UI."
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
