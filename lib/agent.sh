#!/usr/bin/env bash
# chengetai agent <run|once|install|uninstall|status>
#
# The fleet agent. Once enrolled (see `chengetai enroll`), it heartbeats to
# the control plane and executes the commands handed back — the mechanism
# that makes a deployment remotely managed. Model A: it keeps serving through
# control-plane outages and only acts on explicit commands (e.g. the `stop`
# queued when a licence is revoked).
set -e

# shellcheck source=/dev/null
. "$CHENGETAI_HOME/lib/agent-common.sh"

SERVICE_NAME="chengetai-agent"

collect_health() {
    local cpu mem disk
    cpu="$(awk '/^cpu /{u=$2+$4; t=$2+$4+$5; if(t>0) printf "%.0f", (u/t)*100}' /proc/stat 2>/dev/null || echo 0)"
    mem="$(free -m 2>/dev/null | awk '/^Mem:/{printf "%d/%dMB", $3, $2}')"
    disk="$(df -h / 2>/dev/null | awk 'NR==2{print $4" free"}')"
    json_object "cpu=${cpu:-0}" "memory=${mem:-unknown}" "disk=${disk:-unknown}"
}

collect_deployments() {
    # A compact JSON array of deployment names + running state.
    local names=() d name running
    if [ -d "$DEPLOYMENTS_DIR" ]; then
        while IFS= read -r d; do
            name="$(basename "$d")"
            running=false
            if command -v docker >/dev/null 2>&1 &&
               docker ps --filter "name=chengetai-$name" --format '{{.Names}}' 2>/dev/null | grep -q .; then
                running=true
            fi
            names+=("$name:$running")
        done < <(find "$DEPLOYMENTS_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import sys,json
out=[]
for a in sys.argv[1:]:
    n,_,r=a.partition(":")
    out.append({"name":n,"status":"running" if r=="true" else "stopped"})
print(json.dumps(out))' "${names[@]}"
    else
        printf '[]'
    fi
}

# Emit one line per queued command: "id<TAB>command<TAB>arg arg ...".
parse_commands() {
    if [ "$JSON_TOOL" = "jq" ]; then
        jq -r '.commands[]? | .id + "\t" + .command + "\t" + ((.args // []) | join(" "))'
    else
        python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
except Exception:
    sys.exit(0)
for c in d.get("commands",[]):
    print(c["id"]+"\t"+c["command"]+"\t"+" ".join(c.get("args",[])))'
    fi
}

execute_command() {
    local id="$1" command="$2"; shift 2
    local timeout_s=900
    [ "$command" = "logs" ] && timeout_s=25
    info "Running command from control plane: $command $*"
    local output status
    if output="$(timeout "$timeout_s" bash "$(cli_entry)" "$command" "$@" 2>&1)"; then
        status="done"
    else
        status="failed"
    fi
    local body
    body="$(json_object "status=$status" "output=$output")"
    cp_post "/api/fleet/commands/$id/result" "$body" "$AGENT_TOKEN" >/dev/null
    info "Command $command → $status"
}

do_heartbeat() {
    local health deployments body license
    health="$(collect_health)"
    deployments="$(collect_deployments)"
    # Compose the heartbeat body (health + deployments are raw JSON).
    body="$(printf '{"health":%s,"deployments":%s}' "$health" "$deployments")"

    cp_post "/api/fleet/heartbeat" "$body" "$AGENT_TOKEN"
    if [ "${CP_STATUS:-000}" != "200" ]; then
        warn "Heartbeat failed (HTTP ${CP_STATUS:-000}) — will retry. Deployments keep running."
        return 0
    fi

    license="$(printf '%s' "$CP_BODY" | json_get license)"
    [ "$license" = "revoked" ] && warn "This deployment's licence is REVOKED. Executing control-plane instructions."

    # Execute each queued command, then report its result.
    local id command args
    while IFS=$'\t' read -r id command args; do
        [ -n "$id" ] || continue
        # shellcheck disable=SC2086
        execute_command "$id" "$command" $args
    done < <(printf '%s' "$CP_BODY" | parse_commands)
}

cmd_run() {
    load_agent_config
    require_json_tool
    [ -n "${AGENT_TOKEN:-}" ] || error "Not enrolled. Run: chengetai enroll <token> --control-plane <url>"
    [ -n "${CONTROL_PLANE_URL:-}" ] || error "No control plane URL in agent config."
    local interval="${CHENGETAI_HEARTBEAT_SECONDS:-60}"
    info "Agent started. Heartbeat every ${interval}s to $CONTROL_PLANE_URL"
    while true; do
        do_heartbeat || true
        sleep "$interval"
    done
}

cmd_once() {
    load_agent_config
    require_json_tool
    [ -n "${AGENT_TOKEN:-}" ] || error "Not enrolled. Run: chengetai enroll <token> --control-plane <url>"
    do_heartbeat
    info "Single heartbeat complete."
}

cmd_status() {
    load_agent_config
    banner "Fleet agent status"
    if [ -z "${AGENT_TOKEN:-}" ]; then
        warn "This server is NOT enrolled (standalone)."
        echo "Enroll with: chengetai enroll <token> --control-plane <url>"
        return 0
    fi
    echo "  Control plane : ${CONTROL_PLANE_URL:-unknown}"
    echo "  Server name   : ${AGENT_NAME:-unknown}"
    echo "  Agent ID      : ${AGENT_ID:-unknown}"
    echo "  Config        : $(agent_config_file)"
    if command -v systemctl >/dev/null 2>&1; then
        echo "  Service       : $(systemctl is-active "$SERVICE_NAME" 2>/dev/null || echo 'not installed')"
    fi
}

cmd_install() {
    [ "$(id -u)" = "0" ] || error "Installing the agent service requires root: sudo chengetai agent install"
    command -v systemctl >/dev/null 2>&1 || error "systemd is required to run the agent as a service."
    load_agent_config
    [ -n "${AGENT_TOKEN:-}" ] || error "Enroll first: chengetai enroll <token> --control-plane <url>"

    local unit="/etc/systemd/system/${SERVICE_NAME}.service"
    cat > "$unit" <<EOF
[Unit]
Description=ChengetAi Deploy fleet agent
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
Environment=CHENGETAI_HOME=$CHENGETAI_HOME
ExecStart=/usr/bin/env bash $(cli_entry) agent run
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" >/dev/null 2>&1 || true
    systemctl restart "$SERVICE_NAME"
    info "Agent service installed and started ($SERVICE_NAME)."
    echo "  Logs: journalctl -u $SERVICE_NAME -f"
}

cmd_uninstall() {
    [ "$(id -u)" = "0" ] || error "Requires root: sudo chengetai agent uninstall"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        systemctl disable "$SERVICE_NAME" 2>/dev/null || true
        rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
        systemctl daemon-reload
    fi
    info "Agent service removed. This server stops heartbeating (deployments keep running)."
}

case "${1:-status}" in
    run)       cmd_run ;;
    once)      cmd_once ;;
    install)   cmd_install ;;
    uninstall) cmd_uninstall ;;
    status)    cmd_status ;;
    *)         error "Usage: chengetai agent <run|once|install|uninstall|status>" ;;
esac
