#!/usr/bin/env bash
# DSpace 10 platform plugin for ChengetAi Deploy.
# Sourced by lib/utils.sh:load_plugin — requires DEPLOY_DIR, DEPLOY_NAME and
# the profile variables (INSTITUTION, ADMIN_EMAIL, ...) to be set.
#
# ChengetAi Deploy is an ORCHESTRATOR. The canonical DSpace deployment lives
# in the ChengetAi-DSPACE-Engine repository (the reference template — one
# Docker Compose stack per deployment, its own `bin/chengetai` CLI, DSpace
# pinned via DSPACE_VER, default `dspace-10_x`). This plugin never
# duplicates that logic. Per deployment it:
#
#   clone      the reference engine into deployments/<name>/engine/
#   configure  .env + config/local.cfg from the profile (ports, instance
#              name, admin account, a generated DB secret, DSPACE_VER)
#   brand      forward to the engine's own `bin/chengetai brand`
#   deploy     pull + start the engine's stack, wait for the backend, then
#              create the administrator (forwarded to the engine CLI)
#   maintain   start/stop/status/logs/backup/restore/update/remove below

# shellcheck disable=SC2034  # PLUGIN_* consumed by the CLI after sourcing
PLUGIN_NAME="dspace"
PLUGIN_DESCRIPTION="DSpace 10 institutional repository"
PLUGIN_STATUS="available"

# The canonical DSpace deployment implementation.
ENGINE_REPO="https://github.com/wgmasvix-hue/ChengetAi-DSPACE-Engine.git"
ENGINE_BRANCH="main"
# DSpace version deployed by default — override per deployment with
# DSPACE_VER=dspace-9_x chengetai deploy dspace <name> (older supported lines).
ENGINE_DSPACE_VER_DEFAULT="dspace-10_x"

# Database credentials inside the dspacedb service (dspace/.env.example
# defaults — the password itself is generated below and lives only in the
# engine's .env, chmod 600).
DB_USER="dspace"
DB_NAME="dspace"

engine_dir() {
    echo "$DEPLOY_DIR/engine"
}

branding_dir() {
    echo "$DEPLOY_DIR/branding"
}

ui_port() {
    echo "${UI_PORT:-4000}"
}

rest_port() {
    echo "${REST_PORT:-8080}"
}

project_name() {
    echo "chengetai-$DEPLOY_NAME"
}

require_engine() {
    if [ ! -d "$(engine_dir)/.git" ] || [ ! -f "$(engine_dir)/.env" ]; then
        error "Deployment '$DEPLOY_NAME' has not been deployed yet. Run: chengetai deploy $DEPLOY_NAME"
    fi
}

# Run the engine's own CLI against THIS deployment's clone — it computes its
# root directory from its own path, so it always operates on the right engine
# regardless of the caller's cwd.
engine_cli() {
    "$(engine_dir)/bin/chengetai" "$@"
}

# All compose operations run against the engine's own compose file, namespaced
# per deployment (-p) so several DSpace deployments never collide on one
# server. Used directly by lib/status.sh and lib/verify.sh too.
pcompose() {
    docker compose -p "$(project_name)" \
        -f "$(engine_dir)/docker-compose.yml" \
        --project-directory "$(engine_dir)" "$@"
}

plugin_service_running() {
    [ -n "$(pcompose ps --status running -q "$1" 2>/dev/null)" ]
}

gen_password() {
    head -c 64 /dev/urandom | base64 | tr -d '+/=\n' | head -c 24
}

# Best-effort public IP of this server, so a bare-IP deployment (no domain
# yet) advertises a URL browsers can actually reach — not "localhost".
detect_public_ip() {
    curl -fsS -m 8 https://api.ipify.org 2>/dev/null \
        || hostname -I 2>/dev/null | awk '{print $1}' \
        || echo "localhost"
}

# Set (or replace, in place) `KEY=value` in this deployment's engine/.env.
_env_set() {
    local key="$1" val="$2"
    sed -i "s|^${key}=.*|${key}=${val}|" "$(engine_dir)/.env"
}

_env_get() {
    grep -s "^${1}=" "$(engine_dir)/.env" | head -1 | cut -d= -f2- | sed 's/^"//; s/"$//'
}

plugin_server_ip() {
    local hostname
    hostname="$(_env_get DSPACE_HOSTNAME)"
    if [ -n "$hostname" ] && [ "$hostname" != "dspace.example.org" ]; then
        echo "$hostname"
    else
        echo "localhost"
    fi
}

plugin_urls() {
    local ip scheme
    ip=$(plugin_server_ip)
    scheme="http"
    case "$(_env_get DSPACE_UI_URL)" in https://*) scheme="https" ;; esac
    if [ "$scheme" = "https" ]; then
        echo "  UI (browser):  https://${ip}/"
        echo "  REST API:      https://${ip}/server"
    else
        echo "  UI (browser):  http://${ip}:$(ui_port)"
        echo "  REST API:      http://${ip}:$(rest_port)/server"
    fi
}

# Create or reset the DSpace administrator against the already-running
# backend — no redeploy needed. Forwards to the engine's own `chengetai
# admin`, which is non-interactive when ADMIN_EMAIL/ADMIN_PASS are set
# (writes them into the engine's .env first) and falls back to DSpace's own
# interactive prompt otherwise.
plugin_admin() {
    require_engine
    if ! plugin_service_running dspace; then
        error "The backend service (dspace) is not running. Start it first: chengetai start $DEPLOY_NAME"
    fi

    # Note: these use `if`, not `[ ... ] && cmd` — under this CLI's `set -e`,
    # a bare `&&` guard that evaluates false (e.g. no ADMIN_FIRST_NAME given)
    # would abort the whole command right here, silently.
    if [ -n "${ADMIN_EMAIL:-}" ]; then _env_set ADMIN_EMAIL "$ADMIN_EMAIL"; fi
    if [ -n "${ADMIN_FIRST_NAME:-}" ]; then _env_set ADMIN_FIRSTNAME "\"${ADMIN_FIRST_NAME}\""; fi
    if [ -n "${ADMIN_LAST_NAME:-}" ]; then _env_set ADMIN_LASTNAME "\"${ADMIN_LAST_NAME}\""; fi

    if [ -n "${ADMIN_PASS:-}" ]; then
        _env_set ADMIN_PASSWORD "$ADMIN_PASS"
        info "Creating/updating administrator $(_env_get ADMIN_EMAIL) (non-interactive)..."
        engine_cli admin
        echo ""
        info "Administrator ready: $(_env_get ADMIN_EMAIL)"
        echo "  Sign in at: $(plugin_urls | head -1 | awk '{print $NF}')"
    else
        info "Launching DSpace's interactive administrator setup..."
        echo "  Tip: set ADMIN_PASS (or pass --password) to run this without any prompts."
        echo ""
        engine_cli admin
    fi
}

# ── Institutional branding ──────────────────────────────────────────────────
# The DSpace 10 engine supports two identity knobs at runtime, no rebuild:
# the site name (DSPACE_NAME, env-driven — browser tab title + header) and
# the header logo (branding/logo.svg, bind-mounted into the frontend). Both
# are set by the engine's own `bin/chengetai brand`, which this forwards to.
plugin_brand() {
    require_engine
    local action="set" name="" logo=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --name|--repository|--institution) name="$2"; shift 2 ;;
            --logo)                            logo="$2"; shift 2 ;;
            --status)                          action="status"; shift ;;
            --shortname|--publisher|--tagline|--favicon|--primary|--accent)
                warn "chengetai brand: '$1' is not supported by the DSpace 10 engine (name + logo only) — ignored."
                shift 2 ;;
            --apply)
                shift ;;
            *) error "Unknown option for brand: $1" ;;
        esac
    done

    if [ "$action" = "status" ]; then
        local cur_name
        cur_name="$(_env_get DSPACE_NAME)"
        echo -e "${GREEN}✓${NC} Branding for '$DEPLOY_NAME':"
        echo "    Repository name : ${cur_name:-(default)}"
        if [ -f "$(engine_dir)/branding/logo.svg" ]; then
            echo "    Logo            : $(engine_dir)/branding/logo.svg"
        fi
        return 0
    fi

    [ -n "$name" ] || error "usage: chengetai brand $DEPLOY_NAME --name \"Institution Digital Repository\" [--logo logo.svg]"
    if [ -n "$logo" ]; then
        [ -f "$logo" ] || error "Logo not found: $logo"
        engine_cli brand "$name" "$logo"
    else
        engine_cli brand "$name"
    fi
    echo ""
    info "Branding applied for '$DEPLOY_NAME'. Hard-refresh the browser (Ctrl+Shift+R) — the old logo may be cached."
}

# ── ORCID integration ───────────────────────────────────────────────────────
# Enable "Sign in with ORCID" + researcher-identity linking on a running
# DSpace, or report/disable it. ORCID is DSpace-native — every setting lives
# in config/local.cfg, the engine's one mounted backend config file, so a
# `restart dspace` applies it.
ORCID_MARK_BEGIN="# >>> ChengetAi ORCID (managed — do not edit between these markers) >>>"
ORCID_MARK_END="# <<< ChengetAi ORCID (managed) <<<"

# Remove the managed ORCID block from a local.cfg (idempotent, no-op if absent).
_orcid_strip() {
    local cfg="$1" tmp
    tmp="$(mktemp)"
    awk -v b="$ORCID_MARK_BEGIN" -v e="$ORCID_MARK_END" '
        $0==b {skip=1; next}
        skip && $0==e {skip=0; next}
        !skip {print}
    ' "$cfg" > "$tmp"
    cat "$tmp" > "$cfg"
    rm -f "$tmp"
}

plugin_orcid() {
    require_engine
    local cfg
    cfg="$(engine_dir)/config/local.cfg"
    [ -f "$cfg" ] || error "local.cfg not found for '$DEPLOY_NAME' ($cfg). Deploy first."

    local action="enable" env="sandbox" client_id="" restart=1
    local client_secret="${ORCID_CLIENT_SECRET:-}"
    while [ $# -gt 0 ]; do
        case "$1" in
            --client-id)         client_id="$2"; shift 2 ;;
            --client-secret)     client_secret="$2"; shift 2 ;;
            --sandbox)           env="sandbox"; shift ;;
            --production|--live) env="production"; shift ;;
            --status)            action="status"; shift ;;
            --disable|--off)     action="disable"; shift ;;
            --no-restart)        restart=0; shift ;;
            *) error "Unknown option for orcid: $1" ;;
        esac
    done

    # The redirect URI DSpace advertises; it MUST be registered with the
    # ORCID app or the OAuth handshake is rejected. The public REST URL is
    # engine-level config (env, not local.cfg) — read it from the engine's .env.
    local server_url redirect
    server_url="$(_env_get DSPACE_REST_URL)"
    redirect="${server_url%/}/api/authn/orcid"

    case "$action" in
      status)
        if grep -qF "$ORCID_MARK_BEGIN" "$cfg"; then
            local cur_env cur_id
            if grep -sE '^orcid\.domain-url' "$cfg" | grep -q sandbox; then
                cur_env="sandbox"
            else
                cur_env="production"
            fi
            cur_id="$(grep -sE '^orcid\.application-client-id' "$cfg" | tail -1 | cut -d= -f2- | tr -d ' ')"
            echo -e "${GREEN}✓${NC} ORCID is ENABLED for '$DEPLOY_NAME'"
            echo "    Environment  : $cur_env"
            echo "    Client ID    : ${cur_id:-(unset)}"
            echo "    Redirect URI : $redirect"
        else
            echo -e "${YELLOW}○${NC} ORCID is not configured for '$DEPLOY_NAME' (password login only)."
            echo "    Enable it: chengetai orcid $DEPLOY_NAME --client-id APP-XXXX --client-secret SECRET"
        fi
        return 0 ;;
      disable)
        _orcid_strip "$cfg"
        info "ORCID disabled for '$DEPLOY_NAME' (managed block removed; password login remains)."
        if [ "$restart" = 1 ] && plugin_service_running dspace; then
            info "Restarting the backend to apply..."
            pcompose restart dspace
        fi
        return 0 ;;
    esac

    # enable
    [ -n "$client_id" ] || error "ORCID needs --client-id APP-XXXX (from ORCID → Developer Tools)."
    [ -n "$client_secret" ] || error "ORCID needs --client-secret (or export ORCID_CLIENT_SECRET to keep it out of shell history)."

    local domain api public
    if [ "$env" = "production" ]; then
        domain="https://orcid.org"
        api="https://api.orcid.org/v3.0"
        public="https://pub.orcid.org/v3.0"
    else
        domain="https://sandbox.orcid.org"
        api="https://api.sandbox.orcid.org/v3.0"
        public="https://pub.sandbox.orcid.org/v3.0"
    fi

    _orcid_strip "$cfg"   # clear any previous managed block, then write fresh
    {
        echo ""
        echo "$ORCID_MARK_BEGIN"
        echo "# ORCID sign-in + researcher identity. Environment: $env"
        echo "orcid.application-client-id = $client_id"
        echo "orcid.application-client-secret = $client_secret"
        echo "orcid.domain-url = $domain"
        echo "orcid.api-url = $api"
        echo "orcid.public-url = $public"
        echo "orcid.synchronization-enabled = true"
        echo "plugin.sequence.org.dspace.authenticate.AuthenticationMethod = org.dspace.authenticate.PasswordAuthentication, org.dspace.authenticate.OrcidAuthentication"
        echo "$ORCID_MARK_END"
    } >> "$cfg"

    echo ""
    info "ORCID ($env) configured for '$DEPLOY_NAME'."
    echo ""
    echo "  ➜ Register this EXACT redirect URI in your ORCID app"
    echo "    (ORCID → Developer Tools → your application → Redirect URIs):"
    echo ""
    echo "        $redirect"
    echo ""
    echo "    Client ID : $client_id"
    echo "    Secret    : stored in $cfg"
    echo ""
    if [ "$restart" = 1 ]; then
        if plugin_service_running dspace; then
            info "Restarting the backend to apply (first boot after a config change can take a few minutes)..."
            pcompose restart dspace
            echo ""
            info "Done. Users will see 'Sign in with ORCID' at $(plugin_urls | head -1 | awk '{print $NF}')"
        else
            warn "Backend not running — start it to apply: chengetai start $DEPLOY_NAME"
        fi
    else
        info "Config written. Apply with: chengetai restart $DEPLOY_NAME"
    fi
}

# Copy this deployment's branding over the engine's own, if any was staged
# (chengetai brand also writes the logo directly into the engine, so this is
# mostly relevant after `chengetai update` resets the clone).
apply_branding() {
    local engine brand
    engine=$(engine_dir)
    brand=$(branding_dir)
    if [ -f "$brand/logo.svg" ]; then
        mkdir -p "$engine/branding"
        cp "$brand/logo.svg" "$engine/branding/logo.svg"
    fi
}

# Write this deployment's engine/.env from .env.example, filling in the
# profile (ports, instance name, admin identity, a generated DB password,
# the default DSpace version) — everything the engine's own `chengetai init`
# would otherwise ask for interactively.
write_engine_env() {
    local engine ip
    engine=$(engine_dir)
    cp "$engine/.env.example" "$engine/.env"
    chmod 600 "$engine/.env"

    ip="$(detect_public_ip)"

    _env_set COMPOSE_PROJECT_NAME "$(project_name)"
    _env_set DEPLOY_ENV "development"
    _env_set DSPACE_HOSTNAME "$ip"
    _env_set DSPACE_VER "${DSPACE_VER:-$ENGINE_DSPACE_VER_DEFAULT}"
    _env_set DSPACE_UI_PORT "$(ui_port)"
    _env_set DSPACE_BACKEND_PORT "$(rest_port)"
    _env_set DSPACE_UI_URL "http://${ip}:$(ui_port)"
    _env_set DSPACE_REST_URL "http://${ip}:$(rest_port)/server"
    _env_set DSPACE_NAME "\"${REPOSITORY:-$INSTITUTION}\""
    _env_set POSTGRES_PASSWORD "$(gen_password)"
    # `if`, not `[ ... ] && cmd` — see the note in plugin_admin() above: a
    # false guard under `set -e` would otherwise abort the deploy silently.
    if [ -n "${ADMIN_EMAIL:-}" ]; then _env_set ADMIN_EMAIL "$ADMIN_EMAIL"; fi
    if [ -n "${ADMIN_FIRST_NAME:-}" ]; then _env_set ADMIN_FIRSTNAME "\"${ADMIN_FIRST_NAME}\""; fi
    if [ -n "${ADMIN_LAST_NAME:-}" ]; then _env_set ADMIN_LASTNAME "\"${ADMIN_LAST_NAME}\""; fi
    if [ -n "${ADMIN_PASS:-}" ]; then _env_set ADMIN_PASSWORD "$ADMIN_PASS"; fi
}

wait_for_backend() {
    info "Waiting for the DSpace backend (first start can take several minutes — this is normal)..."
    local tries=0
    until pcompose exec -T dspace bash -c \
        'if command -v curl >/dev/null; then curl -sf http://localhost:8080/server/api >/dev/null; else (echo > /dev/tcp/127.0.0.1/8080); fi' \
        >/dev/null 2>&1; do
        tries=$((tries + 1))
        if [ "$tries" -ge 120 ]; then
            warn "Backend not confirmed healthy after 10 minutes — check: chengetai logs $DEPLOY_NAME dspace"
            return 1
        fi
        sleep 5
    done
    info "Backend is responding."
}

plugin_deploy() {
    local engine
    engine=$(engine_dir)

    # 1. Clone (or reuse) the canonical engine repository.
    if [ ! -d "$engine/.git" ]; then
        if [ -e "$engine" ]; then
            error "Deployment '$DEPLOY_NAME' has a legacy engine directory. Back up its data, then: chengetai remove $DEPLOY_NAME && chengetai deploy $DEPLOY_NAME"
        fi
        info "Downloading deployment engine (canonical DSpace repository, branch: $ENGINE_BRANCH)..."
        git clone --depth 1 -b "$ENGINE_BRANCH" "$ENGINE_REPO" "$engine"
    fi

    # 2. Configure: .env + config/local.cfg from the profile. Only on first
    #    deploy — an existing .env (and its generated DB password) is never
    #    overwritten by a redeploy.
    if [ ! -f "$engine/.env" ]; then
        info "Writing deployment configuration (.env, config/local.cfg)..."
        write_engine_env
    fi
    [ -f "$engine/config/local.cfg" ] || cp "$engine/config/local.cfg.example" "$engine/config/local.cfg"
    [ -f "$engine/branding/logo.svg" ] || cp "$engine/branding/logo.default.svg" "$engine/branding/logo.svg"
    apply_branding

    # 3. Deploy: pull the pinned DSpace images and start the stack.
    require_docker
    info "Pulling DSpace images ($(_env_get DSPACE_VER))..."
    pcompose pull -q
    info "Starting the stack..."
    pcompose up -d

    wait_for_backend || true

    # 4. Create the administrator now when we have credentials to do it
    #    non-interactively (the one-click / --with-dspace path); otherwise
    #    leave it for `chengetai admin`, printed by lib/deploy.sh next.
    if [ -n "${ADMIN_PASS:-}" ]; then
        plugin_admin
    fi
}

# Point the deployment's public URL at an HTTPS domain — used by
# `chengetai domain`, which puts Caddy in front on 80/443. Rewrites the
# engine's .env (UI/REST URLs + hostname) and recreates the stack so the new
# environment takes effect. The engine's own nginx/TLS system is untouched
# (unused here — Caddy is the orchestrator's proxy).
plugin_domain() {
    require_engine
    local domain="${1:-}"
    [ -n "$domain" ] || error "plugin_domain: a domain is required"

    _env_set DSPACE_HOSTNAME "$domain"
    _env_set DSPACE_UI_URL "https://${domain}"
    _env_set DSPACE_REST_URL "https://${domain}/server"

    require_docker
    info "Recreating services with the new public URL..."
    pcompose up -d
    echo ""
    info "DSpace is now served at https://$domain"
}

plugin_start() {
    require_engine
    require_docker
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
    if ! plugin_service_running dspacedb; then
        error "The database service (dspacedb) is not running. Start the repository first: chengetai start $DEPLOY_NAME"
    fi
    if ! plugin_service_running dspace; then
        error "The backend service (dspace) is not running. Start the repository first: chengetai start $DEPLOY_NAME"
    fi

    local dest
    dest="$DEPLOY_DIR/backups/chengetai-backup-$(date +%Y%m%d-%H%M%S)"
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

    if ! plugin_service_running dspacedb; then
        error "The database service (dspacedb) is not running. Start the repository first: chengetai start $DEPLOY_NAME"
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

    info "Starting the backend to restore the assetstore..."
    pcompose start dspace

    info "Restoring assetstore (uploaded files)..."
    pcompose exec -T dspace bash -c "rm -rf /dspace/assetstore/* && tar xzf - -C /dspace" < "$assets"

    info "Starting remaining services..."
    pcompose start dspace-angular

    info "Rebuilding the search index..."
    wait_for_backend || true
    pcompose exec -T dspace /dspace/bin/dspace index-discovery -b || \
        warn "Reindex did not complete — retry once the backend is up: chengetai reindex $DEPLOY_NAME"

    echo ""
    info "Restore complete."
    echo "The backend can take 3-5 minutes to come up. Check with: chengetai status $DEPLOY_NAME"
    echo ""
}

plugin_update() {
    require_engine
    local engine
    engine=$(engine_dir)

    info "Pulling latest canonical engine (branch: $ENGINE_BRANCH)..."
    git -C "$engine" fetch origin "$ENGINE_BRANCH"
    git -C "$engine" checkout -- . 2>/dev/null || true
    git -C "$engine" pull --ff-only origin "$ENGINE_BRANCH"

    apply_branding

    info "Pulling images and applying update..."
    require_docker
    pcompose pull -q
    pcompose up -d --remove-orphans
}

# plugin_edit <component>
# Branding lives in deployments/<name>/branding/ and is applied over the
# engine on deploy/update, so canonical updates never conflict with it.
plugin_edit() {
    local component="$1" file

    case "$component" in
        logo)
            file="$(branding_dir)/logo.svg"
            echo "The navbar logo is an SVG image:"
            echo ""
            echo "  $file"
            echo ""
            echo "Replace that file with your own (or use: chengetai brand $DEPLOY_NAME --logo file.svg), then apply below."
            ;;
        config)
            require_engine
            file="$(engine_dir)/config/local.cfg"
            [ -f "$file" ] || error "File not found: $file"
            echo "Opening: $file"
            echo ""
            "${EDITOR:-nano}" "$file"
            ;;
        favicon|communities)
            error "'$component' is not supported by the DSpace 10 engine yet. Editable components: logo config"
            ;;
        *)
            error "Unknown component '$component'. Editable components: logo config"
            ;;
    esac

    mkdir -p "$(branding_dir)"

    echo ""
    if confirm "Apply the change now (restarts the affected service)?"; then
        require_docker
        require_engine
        case "$component" in
            logo)   apply_branding; pcompose up -d dspace-angular ;;
            config) pcompose restart dspace ;;
        esac
        echo ""
        info "Applied."
    else
        echo "Apply later with: chengetai restart $DEPLOY_NAME"
    fi
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
