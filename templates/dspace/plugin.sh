#!/usr/bin/env bash
# DSpace 8 platform plugin for ChengetAi Deploy.
# Sourced by lib/utils.sh:load_plugin — requires DEPLOY_DIR and the
# profile variables (INSTITUTION, ADMIN_EMAIL, ...) to be set.

PLUGIN_NAME="dspace"
PLUGIN_DESCRIPTION="DSpace 8 institutional repository"
PLUGIN_STATUS="available"

# The deployment engine: a DSpace tree with install.sh, the campus compose
# file and branding assets.
ENGINE_REPO="https://github.com/wgmasvix-hue/bulawayo-polytechnic-dspace-.git"
ENGINE_BRANCH="claude/dspace-deployment-review-48qeth"

# Database credentials inside the dspacedb container
# (dspace/dspace-postgres-pgcrypto defaults).
DB_USER="dspace"
DB_NAME="dspace"

engine_dir() {
    echo "$DEPLOY_DIR/engine"
}

require_engine() {
    if [ ! -f "$(engine_dir)/docker-compose-campus.yml" ]; then
        error "Deployment '$DEPLOY_NAME' has not been deployed yet. Run: chengetai deploy $DEPLOY_NAME"
    fi
}

pcompose() {
    docker compose -f "$(engine_dir)/docker-compose-campus.yml" \
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
    echo "  UI (browser):  http://${ip}:4000"
    echo "  REST API:      http://${ip}:8080/server"
}

plugin_deploy() {
    local engine
    engine=$(engine_dir)

    if [ ! -d "$engine/.git" ]; then
        info "Downloading deployment engine..."
        git clone --depth 1 -b "$ENGINE_BRANCH" "$ENGINE_REPO" "$engine"
    fi

    # The engine's install.sh handles everything else: dependency install,
    # engine update, image build, stack startup, admin creation and the
    # community setup. The admin details from the profile flow in through
    # the environment; it only prompts for whatever is missing.
    INSTALL_DIR="$engine" bash "$engine/install.sh"
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
    echo "  Check progress with: chengetai status"
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
    echo "The backend can take 3-5 minutes to come up. Check with: chengetai status"
    echo ""
}

plugin_status() {
    require_engine
    pcompose ps

    local ip
    ip=$(plugin_server_ip)

    echo ""
    if curl -sf "http://localhost:8080/server/api" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} REST API       : http://${ip}:8080/server"
    else
        echo -e "${RED}✗${NC} REST API       : not responding (http://${ip}:8080/server)"
    fi

    if curl -sf "http://localhost:4000" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} User Interface : http://${ip}:4000"
    else
        echo -e "${RED}✗${NC} User Interface : not responding (http://${ip}:4000)"
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
    if ! container_running dspacedb; then
        error "The database container (dspacedb) is not running. Start the repository first: chengetai start $DEPLOY_NAME"
    fi
    if ! container_running dspace; then
        error "The backend container (dspace) is not running. Start the repository first: chengetai start $DEPLOY_NAME"
    fi

    local dest="$DEPLOY_DIR/backups/chengetai-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$dest"

    info "Backing up database..."
    docker exec dspacedb pg_dump -U "$DB_USER" "$DB_NAME" | gzip > "$dest/dspace-db.sql.gz"

    info "Backing up assetstore (uploaded files)..."
    docker exec dspace tar czf - -C /dspace assetstore > "$dest/assetstore.tar.gz"

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

    if ! container_running dspacedb; then
        error "The database container (dspacedb) is not running. Start the repository first: chengetai start $DEPLOY_NAME"
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
    docker exec dspacedb psql -U "$DB_USER" -d postgres \
        -c "DROP DATABASE IF EXISTS $DB_NAME WITH (FORCE);"
    docker exec dspacedb psql -U "$DB_USER" -d postgres \
        -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
    docker exec dspacedb psql -U "$DB_USER" -d "$DB_NAME" \
        -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
    gunzip -c "$db_dump" | docker exec -i dspacedb psql -q -U "$DB_USER" -d "$DB_NAME"

    info "Restoring assetstore (uploaded files)..."
    # The dspace container is stopped, so unpack into its assetstore volume
    # from a throwaway container that shares its volumes. The backend image
    # is already present locally, so nothing needs to be pulled.
    local image
    image=$(docker inspect dspace --format '{{.Config.Image}}')
    docker run --rm -i --volumes-from dspace --entrypoint bash "$image" \
        -c "rm -rf /dspace/assetstore/* && tar xzf - -C /dspace" < "$assets"

    info "Starting services..."
    pcompose start dspace dspace-angular

    echo ""
    info "Restore complete."
    echo "The backend can take 3-5 minutes to come up. Check with: chengetai status"
    echo ""
}

# plugin_edit <component>
# Opens the file behind a UI component for editing, then offers to rebuild
# and restart the frontend so the change goes live.
#
# The frontend runs from the prebuilt dspace-angular image with branding
# files layered on top (see Dockerfile.angular), so only those files are
# editable. Editing page templates (homepage, footer, news, css) would
# require building the UI from source, which this engine does not do.
plugin_edit() {
    require_engine
    local component="$1" file

    case "$component" in
        logo)    file="$(engine_dir)/assets/bpoly-logo.svg" ;;
        favicon) file="$(engine_dir)/assets/favicon.svg" ;;
        config)  file="$(engine_dir)/config.yml" ;;
        homepage|footer|news|css)
            error "'$component' cannot be edited: the frontend is a prebuilt image and only its branding files (logo, favicon, config) are replaceable. Editing page content requires a source build of dspace-angular."
            ;;
        *)
            error "Unknown component '$component'. Editable components: logo favicon config"
            ;;
    esac

    [ -f "$file" ] || error "File not found: $file"

    echo "Opening: $file"
    echo ""
    "${EDITOR:-nano}" "$file"

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
    local engine
    engine=$(engine_dir)
    [ -d "$engine/.git" ] || error "Deployment engine not found at $engine. Run: chengetai deploy $DEPLOY_NAME"

    info "Pulling latest deployment engine (branch: $ENGINE_BRANCH)..."
    git -C "$engine" fetch origin "$ENGINE_BRANCH"
    git -C "$engine" pull --ff-only origin "$ENGINE_BRANCH"

    info "Rebuilding branded Angular image..."
    docker build -f "$engine/Dockerfile.angular" -t bpoly-dspace-angular:latest "$engine"

    info "Applying update..."
    pcompose up -d --remove-orphans
}

# plugin_remove [purge]
# Stops and removes the containers; with purge=1 the data volumes
# (database, assetstore, Solr index) are deleted as well.
plugin_remove() {
    local purge="${1:-0}"
    if [ -f "$(engine_dir)/docker-compose-campus.yml" ]; then
        if [ "$purge" = "1" ]; then
            pcompose down --remove-orphans --volumes
        else
            pcompose down --remove-orphans
        fi
    fi
}
