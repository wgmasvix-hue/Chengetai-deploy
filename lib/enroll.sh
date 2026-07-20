#!/usr/bin/env bash
# chengetai enroll <enrollment-token> [--control-plane URL] [--name NAME]
#
# Registers this server with the ChengetAi control plane so its deployments
# become centrally managed. Stores the returned agent token in the root-only
# agent config, then (when run as root) installs and starts the heartbeat
# service.
set -e

# shellcheck source=/dev/null
. "$CHENGETAI_HOME/lib/agent-common.sh"

ENROLL_TOKEN=""
CONTROL_PLANE_URL="${CHENGETAI_CONTROL_PLANE:-}"
AGENT_NAME=""

while [ $# -gt 0 ]; do
    case "$1" in
        --control-plane|--url) CONTROL_PLANE_URL="$2"; shift 2 ;;
        --name)                AGENT_NAME="$2"; shift 2 ;;
        -*)                    error "Unknown option: $1" ;;
        *)                     ENROLL_TOKEN="$1"; shift ;;
    esac
done

banner "Enroll with control plane"

[ -n "$ENROLL_TOKEN" ] || error "Usage: chengetai enroll <enrollment-token> [--control-plane URL]"
[ -n "$CONTROL_PLANE_URL" ] || error "No control plane URL. Pass --control-plane https://control.example, or set CHENGETAI_CONTROL_PLANE."

require_json_tool

# Best-effort facts about this server.
HOSTNAME_VAL="$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo unknown)"
PUBLIC_IP="$(curl -fsS -m 8 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')"
VERSION_VAL="$(cli_version)"
# Name defaults to the sole deployment, else the hostname.
if [ -z "$AGENT_NAME" ]; then
    if [ -d "$DEPLOYMENTS_DIR" ]; then
        AGENT_NAME="$(find "$DEPLOYMENTS_DIR" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | head -1)"
    fi
    AGENT_NAME="${AGENT_NAME:-$HOSTNAME_VAL}"
fi

info "Control plane : $CONTROL_PLANE_URL"
info "Server name   : $AGENT_NAME"

BODY="$(json_object \
    "enrollmentToken=$ENROLL_TOKEN" \
    "name=$AGENT_NAME" \
    "platform=dspace" \
    "hostname=$HOSTNAME_VAL" \
    "publicIp=$PUBLIC_IP" \
    "version=$VERSION_VAL")"

cp_post "/api/fleet/enroll" "$BODY"
if [ "${CP_STATUS:-000}" != "201" ]; then
    MSG="$(printf '%s' "$CP_BODY" | json_get error)"
    error "Enrollment failed (HTTP ${CP_STATUS:-000}): ${MSG:-no response from control plane}"
fi

AGENT_TOKEN="$(printf '%s' "$CP_BODY" | json_get agentToken)"
AGENT_ID="$(printf '%s' "$CP_BODY" | json_get agentId)"
[ -n "$AGENT_TOKEN" ] || error "Control plane did not return an agent token."

save_agent_config
info "Enrolled. Agent ID: $AGENT_ID"
info "Credentials saved to: $(agent_config_file)"

# Install the heartbeat service when we have the privileges to.
if [ "$(id -u)" = "0" ]; then
    bash "$CHENGETAI_HOME/lib/agent.sh" install || warn "Could not install the agent service automatically. Run: sudo chengetai agent install"
else
    echo ""
    warn "Run 'sudo chengetai agent install' to start the heartbeat service."
fi

echo ""
info "This server is now managed by ChengetAi. Check in from the dashboard."
