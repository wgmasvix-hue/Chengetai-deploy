#!/usr/bin/env bash

set -e

source "$(dirname "$0")/utils.sh"

banner "Updating ChengetAi Deploy"

if [ -d "$CHENGETAI_HOME/.git" ]; then
    BRANCH=$(git -C "$CHENGETAI_HOME" rev-parse --abbrev-ref HEAD)
    info "Updating CLI (branch: $BRANCH)..."
    git -C "$CHENGETAI_HOME" fetch origin "$BRANCH"
    git -C "$CHENGETAI_HOME" pull --ff-only origin "$BRANCH"
else
    warn "ChengetAi Deploy was not installed from git — re-run the online installer to update the CLI."
fi

for name in $(list_deployments); do
    echo ""
    info "Updating deployment '$name'..."
    (
        resolve_deployment "$name"
        require_docker
        plugin_update
    ) || warn "Update of deployment '$name' failed — check the output above."
done

echo ""
info "ChengetAi Deploy is now at version $(cli_version)."
echo ""
