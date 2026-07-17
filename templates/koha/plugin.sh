#!/usr/bin/env bash
# Koha platform plugin for ChengetAi Deploy.
# Sourced by lib/utils.sh:load_plugin — requires DEPLOY_DIR, DEPLOY_NAME and
# the profile variables (INSTITUTION, ADMIN_EMAIL, UI_PORT, REST_PORT, ...).
#
# Koha has no external canonical deployment repository, so the stack ships
# in this template (templates/koha/engine/) and is instantiated per
# deployment into deployments/<name>/engine/ with a generated .env. It is
# built from Koha's official koha-common Debian package. Ports:
#   UI_PORT   -> OPAC (public catalogue)   container 8080
#   REST_PORT -> Staff (librarian client)  container 8081

# shellcheck disable=SC2034  # PLUGIN_* consumed by the CLI after sourcing
PLUGIN_NAME="koha"
PLUGIN_DESCRIPTION="Koha library management system"
PLUGIN_STATUS="available"

ENGINE_TEMPLATE="$TEMPLATES_DIR/koha/engine"

engine_dir() {
    echo "$DEPLOY_DIR/engine"
}

opac_port() {
    echo "${UI_PORT:-8080}"
}

staff_port() {
    echo "${REST_PORT:-8081}"
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
    echo "  OPAC (public):   http://${ip}:$(opac_port)"
    echo "  Staff (admin):   http://${ip}:$(staff_port)"
}

plugin_deploy() {
    local engine
    engine=$(engine_dir)

    # 1. Instantiate the engine from the template (idempotent).
    mkdir -p "$engine"
    cp -a "$ENGINE_TEMPLATE/." "$engine/"

    # 2. Generate .env once (preserved across re-deploys), chmod 600.
    if [ ! -f "$engine/.env" ]; then
        local instance db_pass db_root admin_pass
        instance=$(echo "$DEPLOY_NAME" | tr -cd 'a-z0-9')
        db_pass=$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)
        db_root=$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)
        admin_pass="${ADMIN_PASS:-$(head -c 16 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 12)}"
        {
            echo "SERVER_IP=$(plugin_server_ip)"
            echo "INSTANCE=${instance:-library}"
            echo "OPAC_PORT=$(opac_port)"
            echo "STAFF_PORT=$(staff_port)"
            echo "DB_PASSWORD=${db_pass}"
            echo "DB_ROOT_PASSWORD=${db_root}"
            echo "KOHA_ADMIN_USER=${ADMIN_EMAIL:-kohaadmin}"
            echo "KOHA_ADMIN_PASS=${admin_pass}"
            echo "LIBRARY_NAME=${REPOSITORY:-${INSTITUTION:-Library}}"
        } > "$engine/.env"
        chmod 600 "$engine/.env"
    fi

    info "Building Koha image (first run downloads koha-common, ~5 minutes)..."
    pcompose build

    info "Starting Koha services..."
    pcompose up -d

    echo ""
    info "Koha is starting. It can take several minutes on first boot."
    echo ""
    plugin_urls
    echo ""
    echo "  IMPORTANT — Koha needs a one-time web installer to finish setup:"
    echo "    open the Staff URL above and follow the installer wizard."
    echo "    The admin login is stored in $engine/.env (KOHA_ADMIN_*)."
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

    local ip admin
    ip=$(plugin_server_ip)
    admin=$(grep -s '^KOHA_ADMIN_USER=' "$(engine_dir)/.env" | cut -d= -f2)

    echo ""
    if curl -sf "http://localhost:$(opac_port)" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} OPAC   : http://${ip}:$(opac_port)"
    else
        echo -e "${RED}✗${NC} OPAC   : not responding (http://${ip}:$(opac_port))"
    fi
    if curl -sf "http://localhost:$(staff_port)" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Staff  : http://${ip}:$(staff_port)"
    else
        echo -e "${RED}✗${NC} Staff  : not responding (http://${ip}:$(staff_port))"
    fi
    echo -e "  Admin login: ${admin:-kohaadmin} (password in $(engine_dir)/.env)"
    echo ""
}

plugin_logs() {
    require_engine
    pcompose logs --tail=200 -f "$@"
}

plugin_backup() {
    require_engine
    if ! pcompose ps --status running 2>/dev/null | grep -q koha-db; then
        error "The database container is not running. Start it first: chengetai start $DEPLOY_NAME"
    fi

    local dest instance root
    dest="$DEPLOY_DIR/backups/chengetai-backup-$(date +%Y%m%d-%H%M%S)"
    instance=$(grep -s '^INSTANCE=' "$(engine_dir)/.env" | cut -d= -f2)
    root=$(grep -s '^DB_ROOT_PASSWORD=' "$(engine_dir)/.env" | cut -d= -f2)
    mkdir -p "$dest"

    info "Backing up database..."
    pcompose exec -T koha-db sh -c "exec mariadb-dump -uroot -p'$root' koha_${instance}" | gzip > "$dest/koha-db.sql.gz"

    info "Backing up Koha files (config, uploads)..."
    pcompose exec -T koha tar czf - -C /var/lib koha > "$dest/koha-lib.tar.gz" 2>/dev/null || \
        warn "Koha file backup skipped (container not running)."

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

    echo "This will REPLACE the current Koha database with:"
    echo "  $backup"
    echo ""
    if ! confirm "Proceed with restore?"; then
        echo "Restore cancelled."
        exit 0
    fi

    local instance root
    instance=$(grep -s '^INSTANCE=' "$(engine_dir)/.env" | cut -d= -f2)
    root=$(grep -s '^DB_ROOT_PASSWORD=' "$(engine_dir)/.env" | cut -d= -f2)

    info "Restoring database..."
    gunzip -c "$db_dump" | pcompose exec -T koha-db sh -c "exec mariadb -uroot -p'$root' koha_${instance}"

    info "Restarting Koha..."
    pcompose restart koha

    echo ""
    info "Restore complete."
    echo ""
}

plugin_update() {
    require_engine
    info "Rebuilding Koha image with the latest koha-common..."
    pcompose build --pull koha
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
            if confirm "Restart Koha to apply?"; then
                require_docker
                pcompose up -d
            fi
            ;;
        *)
            error "Koha supports: chengetai edit config $DEPLOY_NAME (ports, library name, admin). Branding is configured in Koha's own staff interface."
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
