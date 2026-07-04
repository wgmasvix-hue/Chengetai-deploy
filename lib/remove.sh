#!/usr/bin/env bash

set -e

source "$(dirname "$0")/utils.sh"

resolve_deployment "${1:-}"

banner "Remove Deployment : $DEPLOY_NAME"

echo "This will stop and remove the '$DEPLOY_NAME' deployment"
echo "($PLUGIN_DESCRIPTION)."
echo ""

if ! confirm "Remove deployment '$DEPLOY_NAME'?"; then
    echo "Removal cancelled."
    exit 0
fi

PURGE=0
if confirm "Also DELETE stored data (database, uploaded files, search index)?"; then
    PURGE=1
fi

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    plugin_remove "$PURGE"
else
    warn "Docker is not available — containers were not touched, only the deployment profile is removed."
fi

rm -rf "$DEPLOY_DIR"

echo ""
info "Deployment '$DEPLOY_NAME' removed."
if [ "$PURGE" = "0" ]; then
    echo "Data volumes were preserved and will be reused if you deploy '$DEPLOY_NAME' again."
fi
echo ""
