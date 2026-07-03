#!/usr/bin/env bash

set -e

source "$(dirname "$0")/utils.sh"

banner "New Deployment Profile"

# Platform: first argument, PLATFORM env var, or prompt.
PLATFORM="${1:-${PLATFORM:-}}"
if [ -z "$PLATFORM" ]; then
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

load_plugin "$PLATFORM"
if [ "$PLUGIN_STATUS" != "available" ]; then
    error "The '$PLATFORM' template is not available yet. Currently available: dspace"
fi

# Deployment name: second argument, DEPLOYMENT_NAME env var, or prompt.
NAME="${2:-${DEPLOYMENT_NAME:-}}"
if [ -z "$NAME" ]; then
    read -rp "Deployment name [$PLATFORM] : " NAME
    NAME="${NAME:-$PLATFORM}"
fi

if ! [[ "$NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    error "Deployment name must be lowercase letters, digits and hyphens."
fi
if is_deployment "$NAME"; then
    error "Deployment '$NAME' already exists. Deploy it with: chengetai deploy $NAME"
fi

prompt_if_empty INSTITUTION      "Institution Name      "
prompt_if_empty REPOSITORY       "Repository Name       "
prompt_if_empty ADMIN_EMAIL      "Administrator Email   "
prompt_if_empty ADMIN_FIRST_NAME "Admin First Name      "
prompt_if_empty ADMIN_LAST_NAME  "Admin Last Name       "

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
    printf 'CREATED_AT=%q\n'        "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$DEPLOY_DIR/profile.env"

echo ""
info "Profile created: $DEPLOY_DIR/profile.env"
echo ""
echo "  Platform    : $PLATFORM"
echo "  Institution : $INSTITUTION"
echo "  Repository  : $REPOSITORY"
echo "  Admin       : $ADMIN_FIRST_NAME $ADMIN_LAST_NAME <$ADMIN_EMAIL>"
echo ""
echo "Deploy it with: chengetai deploy $NAME"
echo ""
