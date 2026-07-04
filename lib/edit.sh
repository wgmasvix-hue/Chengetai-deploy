#!/usr/bin/env bash

set -e

source "$(dirname "$0")/utils.sh"

# Usage: chengetai edit <component> [name]
# Opens the component's source file in $EDITOR (default nano) and offers
# to rebuild the frontend afterwards.
COMPONENT="${1:-}"

if [ -z "$COMPONENT" ]; then
    echo "Usage:"
    echo "  chengetai edit logo    [name]"
    echo "  chengetai edit favicon [name]"
    echo "  chengetai edit config  [name]"
    exit 1
fi

resolve_deployment "${2:-}"

banner "Repository Editor : $DEPLOY_NAME"

if ! declare -F plugin_edit >/dev/null; then
    error "The '$PLATFORM' platform does not support editing."
fi

plugin_edit "$COMPONENT"
