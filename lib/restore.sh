#!/usr/bin/env bash

set -e

source "$(dirname "$0")/utils.sh"

# Usage: chengetai restore [name] [backup-dir]
# With no backup directory, the deployment's most recent backup is used.
if is_deployment "${1:-}"; then
    resolve_deployment "$1"
    shift
else
    resolve_deployment ""
fi
require_docker

banner "Restoring : $DEPLOY_NAME"

plugin_restore "${1:-}"
