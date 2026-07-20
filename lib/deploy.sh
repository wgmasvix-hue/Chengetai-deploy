#!/usr/bin/env bash

set -e

source "$(dirname "$0")/utils.sh"

clear 2>/dev/null || true

echo "========================================================"
echo "        ChengetAi Deploy v$(cli_version)"
echo "========================================================"

# ── Enrollment gate ─────────────────────────────────────────────────────────
# A managed server may only deploy when it is enrolled with the ChengetAi
# control plane. A server is "managed" when a control plane is configured
# (agent config or CHENGETAI_CONTROL_PLANE) or enrollment is explicitly
# required. Standalone servers with no control plane are unaffected, so
# existing deployments keep working (backward compatible).
enforce_enrollment_gate() {
    # shellcheck source=/dev/null
    . "$CHENGETAI_HOME/lib/agent-common.sh"
    load_agent_config
    if [ -n "${CONTROL_PLANE_URL:-}" ] || [ "${CHENGETAI_REQUIRE_ENROLLMENT:-0}" = "1" ]; then
        if [ -z "${AGENT_TOKEN:-}" ]; then
            error "This server must be enrolled with ChengetAi before deploying.
  Run: sudo chengetai enroll <enrollment-token> --control-plane <url>
  Ask your ChengetAi administrator for an enrollment token."
        fi
        info "Server is enrolled with ChengetAi (managed deployment)."
    fi
}
enforce_enrollment_gate

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

# Post-deploy summary. plugin_urls is defined by every platform plugin;
# guard in case a plugin omits it.
echo ""
banner "Deployment '$DEPLOY_NAME' is up"
if declare -F plugin_urls >/dev/null; then
    plugin_urls
    echo ""
fi
if declare -F plugin_admin >/dev/null; then
    echo "  Manage the administrator account any time (no redeploy):"
    echo "    chengetai admin $DEPLOY_NAME              # interactive"
    echo "    chengetai admin $DEPLOY_NAME --generate   # reset with a new random password"
    echo ""
fi
info "Check service + URL health with: chengetai status $DEPLOY_NAME"
