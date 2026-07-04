#!/usr/bin/env bash

set -e

source "$(dirname "$0")/utils.sh"

clear 2>/dev/null || true

echo "========================================================"
echo "        ChengetAi Deploy v$(cli_version)"
echo "========================================================"

# 'chengetai deploy' accepts an existing deployment name, a platform for a
# new deployment, or nothing (uses the only deployment, or starts the
# creation wizard on a fresh server).
ARG="${1:-}"

if is_deployment "$ARG"; then
    resolve_deployment "$ARG"
elif [ -n "$ARG" ] && [ -f "$TEMPLATES_DIR/$ARG/plugin.sh" ]; then
    source "$CHENGETAI_HOME/lib/create.sh" "$ARG" "${2:-}"
    resolve_deployment "$NAME"
elif [ -n "$ARG" ]; then
    error "'$ARG' is neither a deployment nor a platform. Platforms: $(list_platforms | tr '\n' ' ')"
elif [ -z "$(list_deployments)" ]; then
    source "$CHENGETAI_HOME/lib/create.sh" "" ""
    resolve_deployment "$NAME"
else
    resolve_deployment ""
fi

echo ""
info "Running Deployment Readiness Check..."
bash "$CHENGETAI_HOME/lib/doctor.sh" \
    || error "Required dependencies are missing and could not be installed — resolve the issues above and re-run: chengetai deploy $DEPLOY_NAME"

banner "Deploying '$DEPLOY_NAME' ($PLATFORM)"

plugin_deploy
