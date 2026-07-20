#!/usr/bin/env bash
# Shared helpers for the fleet agent (enroll + heartbeat daemon).
# Sourced by lib/enroll.sh and lib/agent.sh — not run directly.
#
# The agent turns a server into a *managed* deployment: it enrolls with the
# ChengetAi control plane, then heartbeats and executes the commands the
# control plane hands back (start/stop/restart/update/backup/...). Its
# credentials live in a root-only config file; the plaintext agent token is
# never printed after enrollment.

# shellcheck source=/dev/null
. "$CHENGETAI_HOME/lib/utils.sh"

# The CLI entry point differs across lineages: the plugin CLI ships a root
# `chengetai`, the v3 layout ships `chengetai-engine`. Resolve whichever
# exists so the agent can run commands on either.
cli_entry() {
    if [ -x "$CHENGETAI_HOME/chengetai" ] || [ -f "$CHENGETAI_HOME/chengetai" ]; then
        echo "$CHENGETAI_HOME/chengetai"
    elif [ -f "$CHENGETAI_HOME/chengetai-engine" ]; then
        echo "$CHENGETAI_HOME/chengetai-engine"
    elif command -v chengetai >/dev/null 2>&1; then
        command -v chengetai
    else
        echo "$CHENGETAI_HOME/chengetai-engine"
    fi
}

# Config file: system-wide when we can write there, else per-checkout.
agent_config_file() {
    if [ -n "${CHENGETAI_AGENT_CONFIG:-}" ]; then
        echo "$CHENGETAI_AGENT_CONFIG"
    elif [ -w /etc/chengetai ] || { [ ! -e /etc/chengetai ] && [ -w /etc ]; }; then
        echo "/etc/chengetai/agent.env"
    else
        echo "$CHENGETAI_HOME/.agent.env"
    fi
}

load_agent_config() {
    local f
    f="$(agent_config_file)"
    # shellcheck source=/dev/null
    [ -f "$f" ] && . "$f"
    CONTROL_PLANE_URL="${CONTROL_PLANE_URL:-${CHENGETAI_CONTROL_PLANE:-}}"
}

save_agent_config() {
    local f dir
    f="$(agent_config_file)"
    dir="$(dirname "$f")"
    mkdir -p "$dir"
    umask 077
    cat > "$f" <<EOF
# ChengetAi Deploy — fleet agent credentials. Root-only; do not share.
CONTROL_PLANE_URL="$CONTROL_PLANE_URL"
AGENT_ID="$AGENT_ID"
AGENT_TOKEN="$AGENT_TOKEN"
AGENT_NAME="$AGENT_NAME"
EOF
    chmod 600 "$f"
}

# A JSON tool is required. Prefer jq, fall back to python3.
require_json_tool() {
    if command -v jq >/dev/null 2>&1; then
        JSON_TOOL="jq"
    elif command -v python3 >/dev/null 2>&1; then
        JSON_TOOL="python3"
    else
        error "The agent needs 'jq' or 'python3' to parse JSON. Install one: sudo apt-get install -y jq"
    fi
}

# Extract a top-level string field from a JSON document on stdin.
json_get() {
    local field="$1"
    if [ "$JSON_TOOL" = "jq" ]; then
        jq -r --arg f "$field" '.[$f] // empty'
    else
        python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
except Exception:
    sys.exit(0)
v=d.get(sys.argv[1])
if v is not None:
    print(v if not isinstance(v,(dict,list)) else json.dumps(v))' "$field"
    fi
}

# Build a JSON object from KEY=VALUE pairs (string values), safely escaped.
json_object() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import sys,json
o={}
for a in sys.argv[1:]:
    k,_,v=a.partition("=")
    o[k]=v
print(json.dumps(o))' "$@"
    else
        # jq fallback
        local args=() a k v
        for a in "$@"; do
            k="${a%%=*}"; v="${a#*=}"
            args+=(--arg "$k" "$v")
        done
        jq -n "${args[@]}" '$ARGS.named'
    fi
}

# POST JSON to a control-plane path. Args: path json [agent-token]
# Sets globals CP_BODY (response body) and CP_STATUS (HTTP status). It sets
# globals rather than echoing because callers must read the status too, and
# `x="$(cp_post ...)"` would run it in a subshell where that status is lost.
cp_post() {
    local path="$1" body="$2" agent_token="${3:-}"
    local url="${CONTROL_PLANE_URL%/}$path"
    local hdr=(-H 'Content-Type: application/json')
    [ -n "$agent_token" ] && hdr+=(-H "X-Agent-Token: $agent_token")
    local out
    # No -f: we want the body AND status on 4xx/5xx, not a silent failure.
    out="$(curl -sS -m 30 -w '\n%{http_code}' "${hdr[@]}" -X POST --data "$body" "$url" 2>/dev/null || true)"
    # shellcheck disable=SC2034
    CP_STATUS="${out##*$'\n'}"
    # shellcheck disable=SC2034
    CP_BODY="${out%$'\n'*}"
}
