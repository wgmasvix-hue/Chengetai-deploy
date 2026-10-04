#!/usr/bin/env bash

set -e

source "$(dirname "$0")/utils.sh"

banner "New Deployment Profile"

# Platform: first argument, PLATFORM env var, or prompt.
PLATFORM="${1:-${PLATFORM:-}}"
if [ -z "$PLATFORM" ]; then
    if [ "${NON_INTERACTIVE:-0}" = "1" ]; then
        PLATFORM="dspace"
    else
    echo "Available platforms:"
    echo ""
    for p in $(list_platforms); do
        load_plugin "$p"
        echo "  $p - $PLUGIN_DESCRIPTION"
    done
    echo ""
    read -rp "Platform [dspace] : " PLATFORM
    PLATFORM="${PLATFORM:-dspace}"
    fi
fi

load_plugin "$PLATFORM"
if [ "$PLUGIN_STATUS" != "available" ]; then
    error "The '$PLATFORM' template is not available yet. Currently available: dspace"
fi

# Deployment name: second argument, DEPLOYMENT_NAME env var, or prompt.
NAME="${2:-${DEPLOYMENT_NAME:-}}"
if [ -z "$NAME" ]; then
    if [ "${NON_INTERACTIVE:-0}" = "1" ]; then
        NAME="$PLATFORM"
    else
        read -rp "Deployment name [$PLATFORM] : " NAME
        NAME="${NAME:-$PLATFORM}"
    fi
fi

if ! [[ "$NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    error "Deployment name must be lowercase letters, digits and hyphens."
fi
if is_deployment "$NAME"; then
    error "Deployment '$NAME' already exists. Deploy it with: chengetai deploy $NAME"
fi

if [ "$PLATFORM" = "dspace" ]; then
    DSPACE_VERSION="${DSPACE_VERSION:-10.1}"
    [[ "$DSPACE_VERSION" =~ ^10\.[0-9]+$ ]] \
        || error "Unsupported DSpace version '$DSPACE_VERSION'. Use a stable 10.x version such as 10.1."
    if [ -n "${PUBLIC_DOMAIN:-}" ] && ! [[ "$PUBLIC_DOMAIN" =~ ^([[:alnum:]]([[:alnum:]-]{0,61}[[:alnum:]])?\.)+[[:alpha:]]{2,63}$ ]]; then
        error "Invalid domain '$PUBLIC_DOMAIN'. Supply a DNS hostname such as repository.example.org."
    fi
    if [ "${DSPACE_CADDY:-0}" = "1" ] && [ -z "${PUBLIC_DOMAIN:-}" ]; then
        error "Caddy integration requires --domain."
    fi
    if [ "${NON_INTERACTIVE:-0}" = "1" ] && [ -z "${ADMIN_EMAIL:-}" ]; then
        error "Non-interactive DSpace deployment requires --admin-email."
    fi
fi

if [ "${NON_INTERACTIVE:-0}" = "1" ]; then
    INSTITUTION="${INSTITUTION:-DSpace Repository}"
    REPOSITORY="${REPOSITORY:-$INSTITUTION}"
    ADMIN_FIRST_NAME="${ADMIN_FIRST_NAME:-Repository}"
    ADMIN_LAST_NAME="${ADMIN_LAST_NAME:-Admin}"
else
    prompt_if_empty INSTITUTION      "Institution Name      "
    prompt_if_empty REPOSITORY       "Repository Name       "
    prompt_if_empty ADMIN_EMAIL      "Administrator Email   "
    prompt_if_empty ADMIN_FIRST_NAME "Admin First Name      "
    prompt_if_empty ADMIN_LAST_NAME  "Admin Last Name       "
fi

[ -n "${ADMIN_EMAIL:-}" ] || error "Administrator Email is required."
[[ "$ADMIN_EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] \
    || error "Invalid administrator email address: $ADMIN_EMAIL"

# Ports are env-overridable (UI_PORT=4100 REST_PORT=8180 chengetai create ...)
# so several deployments can share one server.
UI_PORT="${UI_PORT:-4000}"
REST_PORT="${REST_PORT:-8080}"

DEPLOY_DIR="$DEPLOYMENTS_DIR/$NAME"
mkdir -p "$DEPLOY_DIR"

# The admin password is deliberately NOT stored — it is asked for (or read
# from ADMIN_PASS in the environment) at deploy time.
{
    printf 'PLATFORM=%q\n'          "$PLATFORM"
    printf 'INSTITUTION=%q\n'       "$INSTITUTION"
    printf 'REPOSITORY=%q\n'        "$REPOSITORY"
    printf 'ADMIN_EMAIL=%q\n'       "$ADMIN_EMAIL"
    printf 'ADMIN_FIRST_NAME=%q\n'  "$ADMIN_FIRST_NAME"
    printf 'ADMIN_LAST_NAME=%q\n'   "$ADMIN_LAST_NAME"
    printf 'UI_PORT=%q\n'           "$UI_PORT"
    printf 'REST_PORT=%q\n'         "$REST_PORT"
    if [ "$PLATFORM" = "dspace" ]; then
        printf 'DSPACE_VERSION=%q\n' "$DSPACE_VERSION"
        printf 'PUBLIC_DOMAIN=%q\n' "${PUBLIC_DOMAIN:-}"
        printf 'DSPACE_CADDY=%q\n' "${DSPACE_CADDY:-0}"
        printf 'DSPACE_PRODUCTION=%q\n' "${DSPACE_PRODUCTION:-0}"
    fi
    printf 'CREATED_AT=%q\n'        "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$DEPLOY_DIR/profile.env"
chmod 600 "$DEPLOY_DIR/profile.env"

echo ""
info "Profile created: $DEPLOY_DIR/profile.env"
echo ""
echo "  Platform    : $PLATFORM"
echo "  Institution : $INSTITUTION"
echo "  Repository  : $REPOSITORY"
echo "  Admin       : $ADMIN_FIRST_NAME $ADMIN_LAST_NAME <$ADMIN_EMAIL>"
echo "  Ports       : UI $UI_PORT, REST $REST_PORT"
if [ "$PLATFORM" = "dspace" ]; then
    echo "  DSpace      : $DSPACE_VERSION"
    [ -n "${PUBLIC_DOMAIN:-}" ] && echo "  Domain      : $PUBLIC_DOMAIN"
fi
echo ""
echo "Deploy it with: chengetai deploy $NAME"
echo ""
