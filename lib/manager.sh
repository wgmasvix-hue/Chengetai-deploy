#!/usr/bin/env bash
# chengetai manager [name] [--install|--uninstall|--status|--service] [--port N] [--bind ADDR]
#
# A small local web console for ONE deployment — status, start/stop/restart,
# backup, recent logs, and the administrator account.
#
#   chengetai manager <name>              run in the foreground (Ctrl-C to stop)
#   sudo chengetai manager <name> --install   run as an always-on systemd service
#   sudo chengetai manager <name> --uninstall remove the service
#   chengetai manager <name> --status     show the service state + URL
#
# The access token and port are persisted per deployment (manager.env,
# mode 600), so the manager URL is stable across restarts and every
# deployment gets its own port. Local by default; reach a 127.0.0.1 bind
# over an SSH tunnel.
set -e

source "$(dirname "$0")/utils.sh"

NAME="" MODE="run" PORT_FLAG="" BIND_FLAG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --install)   MODE="install"; shift ;;
        --uninstall) MODE="uninstall"; shift ;;
        --status)    MODE="status"; shift ;;
        --service)   MODE="service"; shift ;;
        --port)      PORT_FLAG="$2"; shift 2 ;;
        --bind)      BIND_FLAG="$2"; shift 2 ;;
        -*)          error "Unknown option: $1" ;;
        *)           NAME="$1"; shift ;;
    esac
done

# Loads the profile (INSTITUTION, ports) and the platform plugin.
resolve_deployment "$NAME"

SERVICE="chengetai-manager@$DEPLOY_NAME"
MGRENV="$DEPLOY_DIR/manager.env"

# Persisted settings survive restarts so the URL is stable. Precedence:
# CLI flag > persisted value > default.
# shellcheck source=/dev/null
[ -f "$MGRENV" ] && . "$MGRENV"
MANAGER_PORT="${PORT_FLAG:-${MANAGER_PORT:-$(( $(ui_port) + 1000 ))}}"
# Localhost by default: the manager is reached through the dashboard's
# authenticated proxy or an SSH tunnel, never an open port. --bind can widen
# it, but that's discouraged.
MANAGER_BIND="${BIND_FLAG:-${MANAGER_BIND:-127.0.0.1}}"
if [ -z "${MANAGER_TOKEN:-}" ]; then
    MANAGER_TOKEN="$(openssl rand -hex 8 2>/dev/null || head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')"
fi
umask 077
{
    echo "MANAGER_TOKEN=$MANAGER_TOKEN"
    echo "MANAGER_PORT=$MANAGER_PORT"
    echo "MANAGER_BIND=$MANAGER_BIND"
} > "$MGRENV"
chmod 600 "$MGRENV" 2>/dev/null || true

resolve_cli() {
    if [ -f "$CHENGETAI_HOME/chengetai" ]; then echo "$CHENGETAI_HOME/chengetai"
    elif [ -f "$CHENGETAI_HOME/chengetai-engine" ]; then echo "$CHENGETAI_HOME/chengetai-engine"
    else command -v chengetai 2>/dev/null || echo "$CHENGETAI_HOME/chengetai"; fi
}

manager_url() {
    echo "http://$MANAGER_BIND:$MANAGER_PORT/?t=$MANAGER_TOKEN"
}

# Launch the Node server (foreground). Used by `run` and by systemd (--service).
run_server() {
    command -v node >/dev/null 2>&1 || \
        error "The manager UI needs Node.js. The full installer includes it; otherwise install Node and retry."
    local ui_url="" rest_url="" ip
    if declare -F plugin_server_ip >/dev/null; then
        ip="$(plugin_server_ip)"
        ui_url="http://${ip}:$(ui_port)"
        rest_url="http://${ip}:$(rest_port)/server"
    fi
    MGR_DEPLOYMENT="$DEPLOY_NAME" \
    MGR_PLATFORM="$PLATFORM" \
    MGR_INSTITUTION="${INSTITUTION:-}" \
    MGR_UI_URL="$ui_url" \
    MGR_REST_URL="$rest_url" \
    MGR_CLI="$(resolve_cli)" \
    MGR_TOKEN="$MANAGER_TOKEN" \
    MGR_PORT="$MANAGER_PORT" \
    MGR_BIND="$MANAGER_BIND" \
        exec node "$CHENGETAI_HOME/lib/manager/server.js"
}

reachable_hint() {
    if [ "$MANAGER_BIND" = "127.0.0.1" ]; then
        echo "  From your laptop:  ssh -L $MANAGER_PORT:127.0.0.1:$MANAGER_PORT <user>@<server>"
    else
        warn "Bound to $MANAGER_BIND — restrict the port to your VPN/campus subnet, e.g.:"
        echo "    sudo ufw allow from <subnet> to any port $MANAGER_PORT proto tcp"
    fi
}

case "$MODE" in
    service)
        # Invoked by systemd. Log a concise startup line (journal), then run.
        echo "[manager] $DEPLOY_NAME on http://$MANAGER_BIND:$MANAGER_PORT (token in $MGRENV)"
        run_server
        ;;

    run)
        banner "ChengetAi Manager — $DEPLOY_NAME"
        echo "  Open:  $(manager_url)"
        echo ""
        reachable_hint
        echo "  Ctrl-C to stop.  (Install as a service: sudo chengetai manager $DEPLOY_NAME --install)"
        echo ""
        run_server
        ;;

    install)
        [ "$(id -u)" = "0" ] || error "Installing the manager service needs root: sudo chengetai manager $DEPLOY_NAME --install"
        command -v systemctl >/dev/null 2>&1 || error "systemd is required to run the manager as a service."
        # One shared template unit; each deployment is an instance (%i).
        local_unit="/etc/systemd/system/chengetai-manager@.service"
        cat > "$local_unit" <<EOF
[Unit]
Description=ChengetAi Manager for %i
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
Environment=CHENGETAI_HOME=$CHENGETAI_HOME
Environment=CHENGETAI_DEPLOYMENTS_DIR=$DEPLOYMENTS_DIR
ExecStart=/usr/bin/env bash $CHENGETAI_HOME/chengetai manager %i --service
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable --now "$SERVICE"
        banner "Manager service running — $DEPLOY_NAME"
        echo "  Service : $SERVICE ($(systemctl is-active "$SERVICE" 2>/dev/null))"
        echo "  Open    : $(manager_url)"
        echo ""
        reachable_hint
        echo "  Logs: journalctl -u $SERVICE -f"
        ;;

    uninstall)
        [ "$(id -u)" = "0" ] || error "Requires root: sudo chengetai manager $DEPLOY_NAME --uninstall"
        if command -v systemctl >/dev/null 2>&1; then
            systemctl disable --now "$SERVICE" 2>/dev/null || true
        fi
        info "Manager service removed for $DEPLOY_NAME (the deployment itself is untouched)."
        ;;

    status)
        banner "Manager — $DEPLOY_NAME"
        echo "  URL   : $(manager_url)"
        if command -v systemctl >/dev/null 2>&1; then
            echo "  Service : $SERVICE ($(systemctl is-active "$SERVICE" 2>/dev/null || echo 'not installed'))"
        fi
        ;;
esac
