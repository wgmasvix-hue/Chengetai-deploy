#!/usr/bin/env bash
# chengetai status [name]
#   with a name (or when only one deployment exists): the detailed view.
#   with no name and several deployments: an at-a-glance overview of all.
set -e

source "$(dirname "$0")/utils.sh"

ARG="${1:-}"
COUNT="$(list_deployments | wc -l | tr -d ' ')"

# ── Detailed view ────────────────────────────────────────────────────────────
if [ -n "$ARG" ] || [ "$COUNT" = "1" ]; then
    resolve_deployment "$ARG"
    require_docker
    banner "Status : $DEPLOY_NAME"
    plugin_status
    exit 0
fi

# ── Overview of every deployment ─────────────────────────────────────────────
banner "Deployments"

if [ "$COUNT" = "0" ]; then
    info "No deployments yet. Create one with: chengetai deploy"
    exit 0
fi

printf "  %-14s %-9s %-9s %-8s %s\n" "NAME" "PLATFORM" "DEPLOYED" "RUNNING" "URL"
printf "  %-14s %-9s %-9s %-8s %s\n" "----" "--------" "--------" "-------" "---"

for name in $(list_deployments); do
    (
        # Each deployment in a subshell so its profile/plugin don't leak.
        resolve_deployment "$name" >/dev/null 2>&1 || exit 0

        deployed="no"
        [ -d "$DEPLOY_DIR/engine/.git" ] && deployed="yes"

        running="?"
        if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 && declare -F pcompose >/dev/null; then
            if [ -n "$(pcompose ps -q 2>/dev/null)" ]; then running="up"; else running="down"; fi
        fi

        url=""
        declare -F plugin_server_ip >/dev/null && url="http://$(plugin_server_ip):$(ui_port)"

        printf "  %-14s %-9s %-9s %-8s %s\n" "$name" "${PLATFORM:-?}" "$deployed" "$running" "$url"

        if command -v systemctl >/dev/null 2>&1 &&
           [ "$(systemctl is-active "chengetai-manager@$name" 2>/dev/null)" = "active" ]; then
            printf "  %-14s %s\n" "" "↳ manager: running"
        fi
    )
done

echo ""
echo "  Details:  chengetai status <name>"
