#!/usr/bin/env bash
# DSpace 8 platform plugin for ChengetAi Deploy.
# Sourced by lib/utils.sh:load_plugin — requires DEPLOY_DIR, DEPLOY_NAME and
# the profile variables (INSTITUTION, ADMIN_EMAIL, ...) to be set.
#
# The engine is BUILT IN: templates/dspace/engine/ holds the compose stack,
# Dockerfile and default branding. plugin_deploy instantiates it into
# deployments/<name>/engine/ with a generated .env (random database
# password, this server's LAN IP, the deployment's ports). Each deployment
# runs as its own compose project (chengetai-<name>), so several can
# coexist on one server as long as their ports differ.

PLUGIN_NAME="dspace"
PLUGIN_DESCRIPTION="DSpace 8 institutional repository"
PLUGIN_STATUS="available"

ENGINE_TEMPLATE="$TEMPLATES_DIR/dspace/engine"

# Database credentials inside the dspacedb container
# (dspace/dspace-postgres-pgcrypto defaults).
DB_USER="dspace"
DB_NAME="dspace"

engine_dir() {
    echo "$DEPLOY_DIR/engine"
}

# Ports come from the profile; older profiles fall back to the defaults.
ui_port() {
    echo "${UI_PORT:-4000}"
}

rest_port() {
    echo "${REST_PORT:-8080}"
}

require_engine() {
    if [ -d "$(engine_dir)/.git" ]; then
        error "Deployment '$DEPLOY_NAME' uses the old external engine. Back it up, then run: chengetai remove $DEPLOY_NAME && chengetai deploy $DEPLOY_NAME"
    fi
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
    echo "${ip:-localhost}"
}

plugin_urls() {
    local ip
    ip=$(plugin_server_ip)
    echo "  UI (browser):  http://${ip}:$(ui_port)"
    echo "  REST API:      http://${ip}:$(rest_port)/server"
}

detect_server_ip() {
    local ip
    ip=$(ip route get 1.1.1.1 2>/dev/null \
        | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
    [ -n "$ip" ] || ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -n "$ip" ] || error "Cannot detect this server's IP address."
    echo "$ip"
}

random_password() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 24
    else
        tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24
    fi
}

# Copy/refresh the engine files from the template. The generated .env,
# the branding assets and an activated communities.txt are preserved so
# per-deployment customisations survive updates.
sync_engine_files() {
    local engine
    engine=$(engine_dir)
    mkdir -p "$engine/assets"

    cp "$ENGINE_TEMPLATE/docker-compose.yml"       "$engine/docker-compose.yml"
    cp "$ENGINE_TEMPLATE/Dockerfile.angular"       "$engine/Dockerfile.angular"
    cp "$ENGINE_TEMPLATE/setup-communities.sh"     "$engine/setup-communities.sh"
    cp "$ENGINE_TEMPLATE/communities.txt.example"  "$engine/communities.txt.example"

    local f
    for f in logo.png favicon.png logo.svg favicon.svg; do
        [ -f "$engine/assets/$f" ] || cp "$ENGINE_TEMPLATE/assets/$f" "$engine/assets/$f"
    done
}

# Write .env and config.yml. The database password is generated once and
# preserved on redeploys; everything else is recomputed.
write_engine_config() {
    local engine server_ip db_pass
    engine=$(engine_dir)
    server_ip=$(detect_server_ip)

    db_pass=$(grep -s '^POSTGRES_PASSWORD=' "$engine/.env" | cut -d= -f2-)
    [ -n "$db_pass" ] || db_pass=$(random_password)

    cat > "$engine/.env" << EOF
SERVER_IP=${server_ip}
UI_PORT=$(ui_port)
REST_PORT=$(rest_port)
POSTGRES_PASSWORD=${db_pass}
DSPACE_NAME=${INSTITUTION:-ChengetAi} ${REPOSITORY:-Repository}
EOF
    chmod 600 "$engine/.env"

    cat > "$engine/config.yml" << EOF
ui:
  ssl: false
  host: 0.0.0.0
  port: 4000
  namespace: /

rest:
  ssl: false
  host: ${server_ip}
  port: $(rest_port)
  namespace: /server
EOF

    info "Configured for http://${server_ip}:$(ui_port) (database password stored in $engine/.env)"
}

wait_for_backend() {
    info "Waiting for the DSpace backend to start (takes 3-5 minutes on first run)..."
    local waited=0
    until curl -sf "http://localhost:$(rest_port)/server/api" >/dev/null 2>&1; do
        sleep 10
        waited=$((waited + 10))
        if [ "$waited" -ge 600 ]; then
            error "The backend did not start within 10 minutes. Check: chengetai logs $DEPLOY_NAME dspace"
        fi
        echo -n "."
    done
    echo ""
    info "DSpace backend is running."
}

create_admin_account() {
    if [ -z "${ADMIN_PASS:-}" ]; then
        echo ""
        read -rsp "  Administrator password for $ADMIN_EMAIL : " ADMIN_PASS
        echo ""
        read -rsp "  Confirm password                        : " ADMIN_PASS2
        echo ""
        if [ "$ADMIN_PASS" != "$ADMIN_PASS2" ]; then
            error "Passwords do not match."
        fi
    fi

    if pcompose exec -T dspace /dspace/bin/dspace user --list 2>/dev/null | grep -q "$ADMIN_EMAIL"; then
        pcompose exec -T dspace /dspace/bin/dspace user --modify \
            --email "$ADMIN_EMAIL" --newPassword "$ADMIN_PASS"
        info "Admin password updated for $ADMIN_EMAIL"
    else
        pcompose exec -T dspace /dspace/bin/dspace create-administrator << EOF
$ADMIN_EMAIL
$ADMIN_FIRST_NAME
$ADMIN_LAST_NAME
y
$ADMIN_PASS
$ADMIN_PASS
EOF
        info "Admin account created: $ADMIN_EMAIL"
    fi
}

setup_communities() {
    local engine
    engine=$(engine_dir)
    if [ -f "$engine/communities.txt" ]; then
        info "Setting up community structure from communities.txt..."
        DSPACE_URL="http://localhost:$(rest_port)/server" \
            ADMIN_EMAIL="$ADMIN_EMAIL" \
            ADMIN_PASS="$ADMIN_PASS" \
            bash "$engine/setup-communities.sh" "$engine/communities.txt" \
            || warn "Community setup had errors — check manually."
    else
        echo ""
        echo "No community structure configured. To add faculties/departments:"
        echo "  cp $engine/communities.txt.example $engine/communities.txt"
        echo "  (edit it, then re-run: chengetai deploy $DEPLOY_NAME)"
    fi
}

plugin_deploy() {
    local engine
    engine=$(engine_dir)

    if [ -d "$engine/.git" ]; then
        error "Deployment '$DEPLOY_NAME' was created with the old external engine. Migrate it: chengetai backup $DEPLOY_NAME, then chengetai remove $DEPLOY_NAME, chengetai deploy $DEPLOY_NAME and chengetai restore $DEPLOY_NAME."
    fi

    info "Preparing deployment engine..."
    sync_engine_files
    write_engine_config

    info "Building the frontend image..."
    pcompose build dspace-angular

    info "Starting services..."
    pcompose up -d

    wait_for_backend
    create_admin_account
    setup_communities

    echo ""
    echo "============================================================"
    echo -e "  ${GREEN}'$DEPLOY_NAME' is READY${NC}"
    echo "============================================================"
    echo ""
    plugin_urls
    echo ""
    echo "  Admin login:   $ADMIN_EMAIL"
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
    echo "  The backend can take 3-5 minutes to come up."
    echo "  Check progress with: chengetai status $DEPLOY_NAME"
    echo ""
}

plugin_stop() {
    require_engine
    # Containers are removed; the assetstore, database and Solr volumes are kept.
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
    echo "The backend can take 3-5 minutes to come up. Check with: chengetai status $DEPLOY_NAME"
    echo ""
}

plugin_status() {
    require_engine
    pcompose ps

    local ip
    ip=$(plugin_server_ip)

    echo ""
    if curl -sf "http://localhost:$(rest_port)/server/api" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} REST API       : http://${ip}:$(rest_port)/server"
    else
        echo -e "${RED}✗${NC} REST API       : not responding (http://${ip}:$(rest_port)/server)"
    fi

    if curl -sf "http://localhost:$(ui_port)" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} User Interface : http://${ip}:$(ui_port)"
    else
        echo -e "${RED}✗${NC} User Interface : not responding (http://${ip}:$(ui_port))"
    fi
    echo ""
}

plugin_logs() {
    require_engine
    # Follows the whole stack, or only the services named as arguments.
    pcompose logs --tail=200 -f "$@"
}

plugin_backup() {
    require_engine
    if ! pcompose ps --services --status running 2>/dev/null | grep -qx dspacedb; then
        error "The database is not running. Start the repository first: chengetai start $DEPLOY_NAME"
    fi
    if ! pcompose ps --services --status running 2>/dev/null | grep -qx dspace; then
        error "The backend is not running. Start the repository first: chengetai start $DEPLOY_NAME"
    fi

    local dest="$DEPLOY_DIR/backups/chengetai-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$dest"

    info "Backing up database..."
    pcompose exec -T dspacedb pg_dump -U "$DB_USER" "$DB_NAME" | gzip > "$dest/dspace-db.sql.gz"

    info "Backing up assetstore (uploaded files)..."
    pcompose exec -T dspace tar czf - -C /dspace assetstore > "$dest/assetstore.tar.gz"

    echo ""
    info "Backup complete: $dest"
    du -sh "$dest"/* | sed 's/^/  /'
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

    local db_dump="$backup/dspace-db.sql.gz"
    local assets="$backup/assetstore.tar.gz"
    [ -f "$db_dump" ] || error "Database dump not found: $db_dump"
    [ -f "$assets" ] || error "Assetstore archive not found: $assets"

    if ! pcompose ps --services --status running 2>/dev/null | grep -qx dspacedb; then
        error "The database is not running. Start the repository first: chengetai start $DEPLOY_NAME"
    fi

    echo "This will REPLACE the current database and all uploaded files"
    echo "with the contents of:"
    echo ""
    echo "  $backup"
    echo ""
    if ! confirm "Proceed with restore?"; then
        echo "Restore cancelled."
        exit 0
    fi

    info "Stopping backend and UI while restoring..."
    pcompose stop dspace dspace-angular

    info "Restoring database..."
    pcompose exec -T dspacedb psql -U "$DB_USER" -d postgres \
        -c "DROP DATABASE IF EXISTS $DB_NAME WITH (FORCE);"
    pcompose exec -T dspacedb psql -U "$DB_USER" -d postgres \
        -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
    pcompose exec -T dspacedb psql -U "$DB_USER" -d "$DB_NAME" \
        -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
    gunzip -c "$db_dump" | pcompose exec -T dspacedb psql -q -U "$DB_USER" -d "$DB_NAME"

    info "Restoring assetstore (uploaded files)..."
    # The dspace container is stopped, so unpack into its volume from a
    # one-off container that shares the service's volumes. The image is
    # already local, nothing needs to be pulled.
    pcompose run -T --rm --no-deps --entrypoint bash dspace \
        -c "rm -rf /dspace/assetstore/* && tar xzf - -C /dspace" < "$assets"

    info "Starting services..."
    pcompose start dspace dspace-angular

    echo ""
    info "Restore complete."
    echo "The backend can take 3-5 minutes to come up. Check with: chengetai status $DEPLOY_NAME"
    echo ""
}

# plugin_edit <component>
# The frontend runs from the prebuilt dspace-angular image with branding
# files layered on top, so only those files are customisable. Editing page
# templates (homepage, footer, news, css) would require building the UI
# from source, which this engine does not do.
plugin_edit() {
    require_engine
    local component="$1" file

    case "$component" in
        logo)
            file="$(engine_dir)/assets/logo.png"
            echo "The navbar logo is a PNG image (320x80 recommended):"
            echo ""
            echo "  $file"
            echo ""
            echo "Replace that file with your own PNG, then rebuild below."
            ;;
        favicon)
            file="$(engine_dir)/assets/favicon.png"
            echo "The browser-tab icon is a PNG image (64x64 recommended):"
            echo ""
            echo "  $file"
            echo ""
            echo "Replace that file with your own PNG, then rebuild below."
            ;;
        config)
            file="$(engine_dir)/config.yml"
            [ -f "$file" ] || error "File not found: $file"
            echo "Opening: $file"
            echo ""
            "${EDITOR:-nano}" "$file"
            ;;
        communities)
            file="$(engine_dir)/communities.txt"
            [ -f "$file" ] || cp "$(engine_dir)/communities.txt.example" "$file"
            echo "Opening: $file"
            echo ""
            "${EDITOR:-nano}" "$file"
            echo ""
            echo "Apply the structure with: chengetai deploy $DEPLOY_NAME"
            return 0
            ;;
        homepage|footer|news|css)
            error "'$component' cannot be edited: the frontend is a prebuilt image and only its branding files (logo, favicon, config) are replaceable. Editing page content requires a source build of dspace-angular."
            ;;
        *)
            error "Unknown component '$component'. Editable components: logo favicon config communities"
            ;;
    esac

    echo ""
    if confirm "Rebuild the frontend now so the change goes live?"; then
        require_docker
        info "Rebuilding frontend..."
        pcompose build dspace-angular
        pcompose up -d dspace-angular
        echo ""
        info "Frontend rebuilt and restarted."
    else
        echo "Apply later with: chengetai update $DEPLOY_NAME"
    fi
}

plugin_update() {
    require_engine
    info "Refreshing engine files from the built-in template..."
    sync_engine_files
    write_engine_config

    info "Rebuilding frontend image..."
    pcompose build dspace-angular

    info "Applying update..."
    pcompose up -d --remove-orphans
}

# plugin_remove [purge]
# Stops and removes the containers; with purge=1 the data volumes
# (database, assetstore, Solr index) are deleted as well.
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
