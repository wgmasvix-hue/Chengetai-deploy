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
ARG="" DEPLOY_VERSION="" DEPLOY_DOMAIN="" DEPLOY_ADMIN_EMAIL=""
NON_INTERACTIVE=0 INTERACTIVE=0 PRODUCTION=0 DSPACE_CADDY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --version)       [ $# -ge 2 ] || error "--version requires a value"; DEPLOY_VERSION="$2"; shift 2 ;;
        --domain)        [ $# -ge 2 ] || error "--domain requires a value"; DEPLOY_DOMAIN="$2"; DSPACE_CADDY=1; shift 2 ;;
        --admin-email)   [ $# -ge 2 ] || error "--admin-email requires a value"; DEPLOY_ADMIN_EMAIL="$2"; shift 2 ;;
        --production)    PRODUCTION=1; DSPACE_CADDY=1; shift ;;
        --caddy)         DSPACE_CADDY=1; shift ;;
        --no-caddy)      DSPACE_CADDY=0; shift ;;
        --non-interactive) NON_INTERACTIVE=1; shift ;;
        --interactive)   INTERACTIVE=1; shift ;;
        -*)              error "Unknown deploy option: $1" ;;
        *)               [ -z "$ARG" ] || error "Only one deployment name or platform may be specified."; ARG="$1"; shift ;;
    esac
done

if [ "$INTERACTIVE" = "1" ] && [ "$NON_INTERACTIVE" = "1" ]; then
    error "Choose either --interactive or --non-interactive."
fi
if [ "$PRODUCTION" = "1" ] && [ -z "$DEPLOY_DOMAIN" ]; then
    error "--production requires --domain so DSpace is served through HTTPS."
fi
if [ -n "$DEPLOY_VERSION" ] && [ -n "$ARG" ] && [ "$ARG" != "dspace" ] && ! is_deployment "$ARG"; then
    error "--version is currently supported for the dspace platform only."
fi

if is_deployment "$ARG"; then
    resolve_deployment "$ARG"
    if [ -n "$DEPLOY_VERSION" ] && [ "$DEPLOY_VERSION" != "${DSPACE_VERSION:-}" ]; then
        error "This deployment uses DSpace ${DSPACE_VERSION:-8 legacy}. Use a new deployment for another DSpace version."
    fi
    if [ -n "$DEPLOY_DOMAIN" ] && [ "$DEPLOY_DOMAIN" != "${PUBLIC_DOMAIN:-}" ]; then
        error "This deployment already has different domain metadata. Use: chengetai domain $DEPLOY_NAME $DEPLOY_DOMAIN"
    fi
    if [ -n "$DEPLOY_ADMIN_EMAIL" ] && [ "$DEPLOY_ADMIN_EMAIL" != "${ADMIN_EMAIL:-}" ]; then
        error "This deployment already has a different administrator email. Use: chengetai admin $DEPLOY_NAME --email $DEPLOY_ADMIN_EMAIL"
    fi
    if [ "$PRODUCTION" = "1" ] && [ "${DSPACE_PRODUCTION:-0}" != "1" ]; then
        error "Production mode is set when creating a deployment. Use a new deployment or configure this deployment explicitly."
    fi
elif [ -n "$ARG" ] && [ -f "$TEMPLATES_DIR/$ARG/plugin.sh" ]; then
    if [ "$ARG" = "dspace" ]; then
        export DSPACE_VERSION="${DEPLOY_VERSION:-10.1}"
        export PUBLIC_DOMAIN="$DEPLOY_DOMAIN"
        export ADMIN_EMAIL="$DEPLOY_ADMIN_EMAIL"
        export DSPACE_CADDY="${DSPACE_CADDY:-0}"
        export DSPACE_PRODUCTION="$PRODUCTION"
    fi
    export NON_INTERACTIVE INTERACTIVE
    source "$CHENGETAI_HOME/lib/create.sh" "$ARG" "$ARG"
    resolve_deployment "$NAME"
elif [ -n "$ARG" ]; then
    error "'$ARG' is neither a deployment nor a platform. Platforms: $(list_platforms | tr '\n' ' ')"
elif [ -z "$(list_deployments)" ]; then
    export DSPACE_VERSION="${DEPLOY_VERSION:-10.1}"
    export PUBLIC_DOMAIN="$DEPLOY_DOMAIN"
    export ADMIN_EMAIL="$DEPLOY_ADMIN_EMAIL"
    export DSPACE_CADDY="${DSPACE_CADDY:-0}"
    export DSPACE_PRODUCTION="$PRODUCTION"
    export NON_INTERACTIVE INTERACTIVE
    source "$CHENGETAI_HOME/lib/create.sh" "" ""
    resolve_deployment "$NAME"
else
    if [ -n "$DEPLOY_VERSION" ] || [ -n "$DEPLOY_DOMAIN" ] || [ -n "$DEPLOY_ADMIN_EMAIL" ] || [ "$PRODUCTION" = "1" ]; then
        error "Specify a deployment name when using deployment options."
    fi
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
