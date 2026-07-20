#!/usr/bin/env bash
# chengetai manager [name] [--port N] [--bind ADDR]
#
# Launch a small local web UI to manage ONE deployment — status, start/stop/
# restart, backup, recent logs, and the administrator account. Every
# deployment can have its own manager: the default port is derived from the
# deployment's UI port, so they never collide.
#
# Local by default (127.0.0.1). To reach it from your laptop, tunnel over
# SSH rather than exposing the port:
#   ssh -L 9000:127.0.0.1:9000 user@server   # then open the printed URL
set -e

source "$(dirname "$0")/utils.sh"

NAME="" PORT="" BIND="127.0.0.1"
while [ $# -gt 0 ]; do
    case "$1" in
        --port) PORT="$2"; shift 2 ;;
        --bind) BIND="$2"; shift 2 ;;
        -*)     error "Unknown option: $1" ;;
        *)      NAME="$1"; shift ;;
    esac
done

# Loads the profile (INSTITUTION, ports) and the platform plugin.
resolve_deployment "$NAME"

command -v node >/dev/null 2>&1 || \
    error "The manager UI needs Node.js. The full installer includes it; otherwise install Node and retry."

# Resolve the CLI entry point (works on either lineage).
if [ -f "$CHENGETAI_HOME/chengetai" ]; then
    CLI="$CHENGETAI_HOME/chengetai"
elif [ -f "$CHENGETAI_HOME/chengetai-engine" ]; then
    CLI="$CHENGETAI_HOME/chengetai-engine"
else
    CLI="$(command -v chengetai || echo "$CHENGETAI_HOME/chengetai")"
fi

# Default the manager port off the UI port so each deployment differs.
[ -n "$PORT" ] || PORT=$(( $(ui_port) + 1000 ))

TOKEN="$(openssl rand -hex 8 2>/dev/null || head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')"

# URLs for the "open" links (best-effort; the plugin knows the server IP).
UI_URL="" REST_URL=""
if declare -F plugin_server_ip >/dev/null; then
    ip="$(plugin_server_ip)"
    UI_URL="http://${ip}:$(ui_port)"
    REST_URL="http://${ip}:$(rest_port)/server"
fi

banner "ChengetAi Manager — $DEPLOY_NAME"
echo "  Open:  http://$BIND:$PORT/?t=$TOKEN"
echo ""
if [ "$BIND" != "127.0.0.1" ]; then
    warn "Bound to $BIND — anyone who can reach this port AND the token can"
    warn "control this deployment. Prefer the default (127.0.0.1) + an SSH tunnel."
else
    echo "  From your laptop:  ssh -L $PORT:127.0.0.1:$PORT <user>@<server>"
    echo "  then open the URL above."
fi
echo "  Ctrl-C to stop."
echo ""

MGR_DEPLOYMENT="$DEPLOY_NAME" \
MGR_PLATFORM="$PLATFORM" \
MGR_INSTITUTION="${INSTITUTION:-}" \
MGR_UI_URL="$UI_URL" \
MGR_REST_URL="$REST_URL" \
MGR_CLI="$CLI" \
MGR_TOKEN="$TOKEN" \
MGR_PORT="$PORT" \
MGR_BIND="$BIND" \
    exec node "$CHENGETAI_HOME/lib/manager/server.js"
