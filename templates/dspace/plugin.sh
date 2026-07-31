#!/usr/bin/env bash
# DSpace 9 platform plugin for ChengetAi Deploy.
# Sourced by lib/utils.sh:load_plugin — requires DEPLOY_DIR, DEPLOY_NAME and
# the profile variables (INSTITUTION, ADMIN_EMAIL, ...) to be set.
#
# ChengetAi Deploy is an ORCHESTRATOR. The canonical DSpace deployment
# lives in the DSpace 9 engine repository, which is itself a generic,
# institution-neutral deployment kit (own install.sh, .env contract,
# scripts/ for admin/config/backup/restore/update). This plugin never
# duplicates that logic — it namespaces a deployment (ports, Compose
# project name, its own branding/ + admin credentials) and drives the
# engine's own scripts. Per deployment:
#
#   clone      the reference repository into deployments/<name>/engine/
#   configure  institution identity, ports, admin account — passed straight
#              through to the engine's own install.sh --non-interactive
#   brand      copy deployments/<name>/branding/ over the engine's branding/,
#              write institution/colour values into the engine's own .env,
#              let its generate-config.sh render local.cfg/config.yml/theme.css
#   deploy     run the reference repository's install.sh
#   verify     the installer waits for the backend health endpoint
#   maintain   start/stop/status/logs/backup/restore/update/remove below
#
# Upgraded in place from DSpace 8 (previously pointed at
# bulawayo-polytechnic-dspace-), then again when the engine itself was
# restructured from a single-purpose stack into a generic,
# institution-neutral deployment kit — see CHANGELOG.md.

# shellcheck disable=SC2034  # PLUGIN_* consumed by the CLI after sourcing
PLUGIN_NAME="dspace"
PLUGIN_DESCRIPTION="DSpace 9 institutional repository"
PLUGIN_STATUS="available"

# The canonical DSpace deployment implementation.
ENGINE_REPO="https://github.com/wgmasvix-hue/dare-dspace-9-installation-package.git"
ENGINE_BRANCH="main"

# Database credentials inside the postgres service (the engine's own
# defaults — see its .env.example). The password is generated once by the
# engine's installer and lives in the engine's .env, chmod 600.
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

require_engine() {
    if [ ! -d "$(engine_dir)/.git" ]; then
        error "Deployment '$DEPLOY_NAME' has not been deployed yet. Run: chengetai deploy $DEPLOY_NAME"
    fi
}

# All compose operations run against the engine's stack, namespaced per
# deployment (COMPOSE_PROJECT_NAME) so both containers and volumes never
# collide even when several DSpace 9 deployments run on one server. The
# engine sets no fixed container_name: on any service — resolve containers
# by SERVICE NAME via `pcompose exec <service> ...` / `pcompose ps -q
# <service>`, never by an assumed literal container name.
pcompose() {
    docker compose -p "chengetai-$DEPLOY_NAME" \
        -f "$(engine_dir)/docker-compose.yml" \
        --project-directory "$(engine_dir)" "$@"
}

# Is <service> (by compose service name, e.g. "dspace", "postgres") up and
# running? Replaces a plain `container_running <name>` (lib/utils.sh),
# which assumes a fixed container name the engine no longer sets.
service_running() {
    local cid
    cid=$(pcompose ps -q "$1" 2>/dev/null)
    [ -n "$cid" ] && [ "$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null)" = "true" ]
}

plugin_server_ip() {
    local ip
    ip=$(grep -s '^SERVER_IP=' "$(engine_dir)/.env" | cut -d= -f2)
    echo "${ip:-localhost}"
}

# The engine computes and persists these in its own .env at install/update
# time (see scripts/generate-config.sh) — covers both plain IP:port mode
# and domain+HTTPS mode, so this plugin never has to re-derive them.
_engine_env() {
    grep -s "^${1}=" "$(engine_dir)/.env" | tail -1 | cut -d= -f2-
}

plugin_urls() {
    local ui rest
    ui=$(_engine_env UI_URL)
    rest=$(_engine_env REST_URL)
    echo "  UI (browser):  ${ui:-http://$(plugin_server_ip):$(ui_port)}"
    echo "  REST API:      ${rest:-http://$(plugin_server_ip):$(rest_port)/server}"
}

# Create or reset the DSpace administrator against the already-running
# backend — no redeploy needed. Delegates to the engine's own script,
# which is non-interactive when ADMIN_EMAIL/ADMIN_PASS are set and prompts
# otherwise. This is what recovers from the "passwords do not match" case
# cleanly.
plugin_admin() {
    require_engine
    if ! service_running dspace; then
        error "The backend (dspace) is not running. Start it first: chengetai start $DEPLOY_NAME"
    fi
    local email="${1:-${ADMIN_EMAIL:-}}"
    ( cd "$(engine_dir)" && \
      ADMIN_EMAIL="${email}" \
      ADMIN_FIRST_NAME="${ADMIN_FIRST_NAME:-Repository}" \
      ADMIN_LAST_NAME="${ADMIN_LAST_NAME:-Admin}" \
      ADMIN_PASS="${ADMIN_PASS:-}" \
        scripts/create-admin.sh )
    echo "  Sign in at: $(_engine_env UI_URL)"
}

# ── Institutional branding ──────────────────────────────────────────────────
# Make the repository read as the institution's own, not "DSpace". Values
# are persisted in this deployment's own branding/brand.env (so `chengetai
# brand --status` and re-applies survive engine updates), then written into
# the engine's own .env and rendered by the engine's own
# scripts/generate-config.sh — this plugin no longer edits local.cfg
# directly, since the engine templatizes it itself now.

plugin_brand() {
    require_engine
    local brand
    brand="$(branding_dir)"

    local action="set" repo_name="" institution="" shortname=""
    local logo="" favicon="" primary="" accent="" do_apply=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --name|--repository) repo_name="$2"; shift 2 ;;
            --institution)       institution="$2"; shift 2 ;;
            --shortname)         shortname="$2"; shift 2 ;;
            --logo)              logo="$2"; shift 2 ;;
            --favicon)           favicon="$2"; shift 2 ;;
            --primary)           primary="$2"; shift 2 ;;
            --accent|--secondary) accent="$2"; shift 2 ;;
            --apply)             do_apply=1; shift ;;
            --status)            action="status"; shift ;;
            *) error "Unknown option for brand: $1" ;;
        esac
    done

    mkdir -p "$brand"
    local envf="$brand/brand.env"

    if [ "$action" = "status" ]; then
        if [ -f "$envf" ]; then
            echo -e "${GREEN}✓${NC} Branding for '$DEPLOY_NAME':"
            sed 's/^/    /' "$envf"
        else
            echo -e "${YELLOW}○${NC} No branding profile yet for '$DEPLOY_NAME'."
            echo "    Set it: chengetai brand $DEPLOY_NAME --institution \"DARE Digital Repository\" --shortname DARE"
        fi
        [ -f "$brand/logo.png" ]    && echo "    logo    : $brand/logo.png"
        [ -f "$brand/favicon.png" ] && echo "    favicon : $brand/favicon.png"
        return 0
    fi

    # Merge previous values with flags (flags win), then persist.
    # shellcheck disable=SC1090
    [ -f "$envf" ] && source "$envf"
    [ -n "$repo_name" ]   && REPOSITORY_NAME="$repo_name"
    [ -n "$institution" ] && INSTITUTION_NAME="$institution"
    [ -n "$shortname" ]   && SHORT_NAME="$shortname"
    if [ -n "$primary" ]; then
        [[ "$primary" =~ ^#[0-9A-Fa-f]{6}$ ]] || error "--primary must be a hex colour like #0E5C4A"
        PRIMARY_COLOR="$primary"
    fi
    if [ -n "$accent" ]; then
        [[ "$accent" =~ ^#[0-9A-Fa-f]{6}$ ]] || error "--accent must be a hex colour like #C8A24B"
        ACCENT_COLOR="$accent"
    fi

    : "${INSTITUTION_NAME:=${REPOSITORY_NAME:-Institutional Repository}}"
    : "${REPOSITORY_NAME:=$INSTITUTION_NAME}"
    if [ -z "${SHORT_NAME:-}" ]; then
        # Multi-word names → initials (Digital Archive Research Exchange → DARE);
        # a single word is kept whole (DARE → DARE, not "D").
        if [ "$(printf '%s' "$INSTITUTION_NAME" | wc -w)" -le 1 ]; then
            SHORT_NAME="$INSTITUTION_NAME"
        else
            SHORT_NAME="$(printf '%s' "$INSTITUTION_NAME" | awk '{for(i=1;i<=NF;i++) printf toupper(substr($i,1,1))}')"
        fi
    fi

    {
        echo "INSTITUTION_NAME=$(printf '%q' "$INSTITUTION_NAME")"
        echo "REPOSITORY_NAME=$(printf '%q' "$REPOSITORY_NAME")"
        echo "SHORT_NAME=$(printf '%q' "$SHORT_NAME")"
        echo "PRIMARY_COLOR=$(printf '%q' "${PRIMARY_COLOR:-}")"
        echo "ACCENT_COLOR=$(printf '%q' "${ACCENT_COLOR:-}")"
    } > "$envf"

    [ -n "$logo" ]    && { [ -f "$logo" ] || error "Logo not found: $logo"; cp "$logo" "$brand/logo.png"; info "Logo staged."; }
    [ -n "$favicon" ] && { [ -f "$favicon" ] || error "Favicon not found: $favicon"; cp "$favicon" "$brand/favicon.png"; info "Favicon staged."; }

    echo ""
    info "Branding set for '$DEPLOY_NAME':"
    echo "    Repository : $REPOSITORY_NAME   (site name + browser tab title)"
    echo "    Institution: $INSTITUTION_NAME  ($SHORT_NAME)"
    echo ""

    if [ "$do_apply" = 1 ]; then
        info "Applying branding..."
        apply_branding
        if service_running dspace; then
            info "Rebuilding the frontend image (logo/favicon) and restarting..."
            pcompose up -d --build angular
            pcompose restart dspace
        fi
        info "Applied. The repository now presents as $REPOSITORY_NAME."
    else
        echo "  Apply with: chengetai brand $DEPLOY_NAME --apply   (restarts backend; rebuilds UI if logo/favicon changed)"
    fi
}

# ── ORCID integration ───────────────────────────────────────────────────────
# Enable "Sign in with ORCID" + researcher-identity linking on a running
# DSpace, or report/disable it. The engine renders local.cfg from a
# template at install/update time (scripts/generate-config.sh) — this
# plugin edits the RENDERED file directly (dspace-config/local.cfg) since
# ORCID settings are deployment-specific secrets, not something the
# generic template should carry. A `restart dspace` applies it; re-running
# generate-config.sh (e.g. via `chengetai update`) does NOT wipe this
# block, since it only touches dspace-config/local.cfg, not the template.
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
    cfg="$(engine_dir)/dspace-config/local.cfg"
    [ -f "$cfg" ] || error "Rendered local.cfg not found for '$DEPLOY_NAME' ($cfg). Deploy first (it's generated by the engine's install.sh)."

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

    # The redirect URI DSpace advertises; it MUST be registered with the ORCID
    # app or the OAuth handshake is rejected.
    local server_url redirect
    server_url="$(grep -sE '^dspace\.server\.url[[:space:]]*=' "$cfg" | head -1 | cut -d= -f2- | tr -d ' ')"
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
        if [ "$restart" = 1 ] && service_running dspace; then
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
        if service_running dspace; then
            info "Restarting the backend to apply (first boot after a config change can take a few minutes)..."
            pcompose restart dspace
            echo ""
            info "Done. Users will see 'Sign in with ORCID' at $(_engine_env UI_URL)"
        else
            warn "Backend not running — start it to apply: chengetai start $DEPLOY_NAME"
        fi
    else
        info "Config written. Apply with: chengetai restart $DEPLOY_NAME"
    fi
}

# Copy this deployment's branding into the engine's own branding/default/,
# write institution identity + colours into the engine's own .env, then let
# the engine's own scripts/generate-config.sh render local.cfg/config.yml/
# theme.css from them (avoids duplicating that rendering logic here — the
# engine already does it, and does it consistently with a bare `./update.sh`).
apply_branding() {
    local engine brand envf
    engine=$(engine_dir)
    brand=$(branding_dir)

    if [ ! -d "$brand" ]; then
        mkdir -p "$brand"
        cp "$TEMPLATES_DIR/dspace/branding/"* "$brand/" 2>/dev/null || true
    fi

    # shellcheck disable=SC1090
    [ -f "$brand/brand.env" ] && source "$brand/brand.env"

    mkdir -p "$engine/branding/default"
    [ -f "$brand/logo.png" ]    && cp "$brand/logo.png"    "$engine/branding/default/logo.png"
    [ -f "$brand/favicon.png" ] && cp "$brand/favicon.png" "$engine/branding/default/favicon.png"

    [ -f "$engine/.env" ] || return 0   # first deploy: install.sh writes .env itself
    envf="$engine/.env"
    _apply_env_set() {
        local key="$1" val="$2"
        [ -n "$val" ] || return 0
        if grep -q "^${key}=" "$envf" 2>/dev/null; then
            sed -i "s#^${key}=.*#${key}=${val}#" "$envf"
        else
            echo "${key}=${val}" >> "$envf"
        fi
    }
    _apply_env_set INSTITUTION_NAME "${INSTITUTION_NAME:-}"
    _apply_env_set INSTITUTION_SHORT_NAME "${SHORT_NAME:-}"
    _apply_env_set DSPACE_NAME "${REPOSITORY_NAME:-}"
    _apply_env_set PRIMARY_COLOR "${PRIMARY_COLOR:-}"
    _apply_env_set SECONDARY_COLOR "${ACCENT_COLOR:-}"

    ( cd "$engine" && scripts/generate-config.sh )
}

plugin_deploy() {
    local engine
    engine=$(engine_dir)

    # 1. Clone (or reuse) the canonical repository. Its installer handles
    #    its own updates on re-runs.
    if [ ! -d "$engine/.git" ]; then
        if [ -e "$engine" ]; then
            error "Deployment '$DEPLOY_NAME' has a legacy engine directory. Back up its data, then: chengetai remove $DEPLOY_NAME && chengetai deploy $DEPLOY_NAME"
        fi
        info "Downloading deployment engine (canonical DSpace repository)..."
        git clone --depth 1 -b "$ENGINE_BRANCH" "$ENGINE_REPO" "$engine"
    fi

    # 2. Configure & deploy: the engine's own installer does the real work,
    #    through its own env-var contract. COMPOSE_PROJECT_NAME namespaces
    #    containers/volumes per deployment. --non-interactive requires the
    #    profile to already supply INSTITUTION/ADMIN_EMAIL/ADMIN_PASS (the
    #    `chengetai deploy` wizard collects these before plugin_deploy runs).
    local short_name
    short_name="${SHORT_NAME:-$(printf '%s' "${INSTITUTION:-$DEPLOY_NAME}" | awk '{for(i=1;i<=NF;i++) printf toupper(substr($i,1,1))}')}"

    ( cd "$engine" && \
      INSTITUTION_NAME="${INSTITUTION:-$DEPLOY_NAME}" \
      INSTITUTION_SHORT_NAME="$short_name" \
      DSPACE_NAME="${REPOSITORY:-${INSTITUTION:-$DEPLOY_NAME}}" \
      DOMAIN="${DOMAIN:-}" \
      UI_PORT="$(ui_port)" \
      REST_PORT="$(rest_port)" \
      ADMIN_EMAIL="${ADMIN_EMAIL:-}" \
      ADMIN_FIRST_NAME="${ADMIN_FIRST_NAME:-Repository}" \
      ADMIN_LAST_NAME="${ADMIN_LAST_NAME:-Admin}" \
      ADMIN_PASS="${ADMIN_PASS:-}" \
      COMPOSE_PROJECT_NAME="chengetai-$DEPLOY_NAME" \
        bash install.sh --non-interactive )

    # 3. Layer this deployment's saved branding (if any) on top.
    if [ -f "$(branding_dir)/brand.env" ]; then
        apply_branding
        if service_running dspace; then
            pcompose up -d --build angular
            pcompose restart dspace
        fi
    fi
}

# Point the deployment's public URL at an HTTPS domain — used by
# `chengetai domain`, which puts Caddy in front. The engine natively
# supports domain+HTTPS mode (see its README) — this just sets DOMAIN in
# the engine's own .env and lets its generate-config.sh + a redeploy do
# the rest, instead of hand-editing config.yml/docker-compose env with awk.
plugin_domain() {
    require_engine
    local domain="${1:-}"
    [ -n "$domain" ] || error "plugin_domain: a domain is required"

    local engine envf
    engine="$(engine_dir)"
    envf="$engine/.env"
    [ -f "$envf" ] || error ".env not found for '$DEPLOY_NAME' ($envf). Deploy first."

    cp -f "$envf" "$envf.bak"
    if grep -q '^DOMAIN=' "$envf"; then
        sed -i "s#^DOMAIN=.*#DOMAIN=${domain}#" "$envf"
    else
        echo "DOMAIN=${domain}" >> "$envf"
    fi
    info "DOMAIN set to $domain (backup: .env.bak)"

    info "Regenerating config and redeploying (can take a few minutes)..."
    ( cd "$engine" && scripts/generate-config.sh )
    pcompose up -d --build

    echo ""
    info "DSpace is now served at https://$domain"
    echo "  If a reverse proxy isn't already in front of this deployment,"
    echo "  see $engine/config/proxy/Caddyfile.template (rendered to"
    echo "  $engine/Caddyfile) for a ready-to-use starting point."
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

    local ip rest_url ui_url
    ip=$(plugin_server_ip)
    rest_url=$(_engine_env REST_URL)
    ui_url=$(_engine_env UI_URL)

    echo ""
    if curl -sf "http://localhost:$(rest_port)/server/api" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} REST API       : ${rest_url:-http://${ip}:$(rest_port)/server}"
    else
        echo -e "${RED}✗${NC} REST API       : not responding (${rest_url:-http://${ip}:$(rest_port)/server})"
    fi

    if curl -sf "http://localhost:$(ui_port)" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} User Interface : ${ui_url:-http://${ip}:$(ui_port)}"
    else
        echo -e "${RED}✗${NC} User Interface : not responding (${ui_url:-http://${ip}:$(ui_port)})"
    fi
    echo ""
}

plugin_logs() {
    require_engine
    # Follows the whole stack, or only the services named as arguments.
    pcompose logs --tail=200 -f "$@"
}

# Delegates to the engine's own backup.sh/restore.sh (which resolve
# containers by compose service name already — see docker-compose.yml),
# just pointed at this deployment's project name and given a
# chengetai-managed destination directory under deployments/<name>/backups/.
plugin_backup() {
    require_engine
    local engine dest
    engine="$(engine_dir)"
    if ! service_running postgres; then
        error "The database service is not running. Start the repository first: chengetai start $DEPLOY_NAME"
    fi
    if ! service_running dspace; then
        error "The backend service is not running. Start the repository first: chengetai start $DEPLOY_NAME"
    fi

    dest="$DEPLOY_DIR/backups/chengetai-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$dest"

    info "Backing up database..."
    pcompose exec -T postgres pg_dump -U "$DB_USER" "$DB_NAME" | gzip > "$dest/dspace-db.sql.gz"

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

    if ! service_running postgres; then
        error "The database service is not running. Start the repository first: chengetai start $DEPLOY_NAME"
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
    pcompose stop dspace angular

    info "Restoring database..."
    pcompose exec -T postgres psql -U "$DB_USER" -d postgres \
        -c "DROP DATABASE IF EXISTS $DB_NAME WITH (FORCE);"
    pcompose exec -T postgres psql -U "$DB_USER" -d postgres \
        -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
    pcompose exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" \
        -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
    gunzip -c "$db_dump" | pcompose exec -T postgres psql -q -U "$DB_USER" -d "$DB_NAME"

    info "Restoring assetstore (uploaded files)..."
    # dspace is stopped, so unpack into its assetstore volume from a
    # throwaway container that shares its volumes. The backend image is
    # already present locally, so nothing needs to be pulled.
    local dspace_cid image
    dspace_cid=$(pcompose ps -a -q dspace)
    image=$(docker inspect "$dspace_cid" --format '{{.Config.Image}}')
    docker run --rm -i --volumes-from "$dspace_cid" --entrypoint bash "$image" \
        -c "rm -rf /dspace/assetstore/* && tar xzf - -C /dspace" < "$assets"

    info "Starting services..."
    pcompose start dspace angular

    echo ""
    info "Restore complete."
    echo "The backend can take 3-5 minutes to come up. Check with: chengetai status $DEPLOY_NAME"
    echo ""
}

plugin_update() {
    require_engine
    local engine
    engine=$(engine_dir)

    apply_branding

    info "Pulling latest canonical repository (branch: $ENGINE_BRANCH) and redeploying..."
    ( cd "$engine" && ./update.sh "$ENGINE_BRANCH" )
}

# plugin_edit <component>
# Branding lives in deployments/<name>/branding/ and is applied over the
# engine on deploy/update, so canonical updates never conflict with it.
plugin_edit() {
    local component="$1" file

    case "$component" in
        logo)
            file="$(branding_dir)/logo.png"
            echo "The navbar logo is a PNG image (320x80 recommended):"
            echo ""
            echo "  $file"
            echo ""
            echo "Replace that file with your own PNG, then rebuild below."
            ;;
        favicon)
            file="$(branding_dir)/favicon.png"
            echo "The browser-tab icon is a PNG image (64x64 recommended):"
            echo ""
            echo "  $file"
            echo ""
            echo "Replace that file with your own PNG, then rebuild below."
            ;;
        config)
            require_engine
            file="$(engine_dir)/.env"
            [ -f "$file" ] || error "File not found: $file"
            echo "Opening: $file"
            echo "(institution name/domain/ports/etc — local.cfg and config.yml are"
            echo " regenerated FROM this on the next start/update, so edit this, not"
            echo " the rendered dspace-config/local.cfg or angular-config/config.yml)"
            echo ""
            "${EDITOR:-nano}" "$file"
            echo ""
            if confirm "Regenerate config and restart now?"; then
                ( cd "$(engine_dir)" && scripts/generate-config.sh )
                pcompose up -d
            fi
            return 0
            ;;
        communities)
            require_engine
            file="$(engine_dir)/data/communities.csv"
            [ -f "$file" ] || error "File not found: $file"
            echo "Opening: $file (community,collection,description — leave collection"
            echo "blank to create a community with no collections under it yet)"
            echo ""
            "${EDITOR:-nano}" "$file"
            echo ""
            if confirm "Run scripts/setup-communities.sh now to apply?"; then
                ( cd "$(engine_dir)" && scripts/setup-communities.sh )
            fi
            return 0
            ;;
        homepage|footer|news|css)
            error "'$component' cannot be edited: the frontend is a prebuilt image and only branding (logo, favicon, config) is replaceable. Editing page content requires a source build of dspace-angular — see the separate theme-engine/ in the DSpace 9 engine repo."
            ;;
        *)
            error "Unknown component '$component'. Editable components: logo favicon config communities"
            ;;
    esac

    mkdir -p "$(branding_dir)"

    echo ""
    if confirm "Rebuild the frontend now so the change goes live?"; then
        require_docker
        require_engine
        apply_branding
        info "Rebuilding frontend..."
        pcompose up -d --build angular
        echo ""
        info "Frontend rebuilt and restarted."
    else
        echo "Apply later with: chengetai update $DEPLOY_NAME"
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
