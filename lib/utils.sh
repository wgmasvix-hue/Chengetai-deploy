#!/usr/bin/env bash
# Shared helpers for ChengetAi Deploy commands.
# Sourced by the lib/*.sh command scripts — not run directly.

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[INFO]${NC}  $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC}  $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
    exit 1
}

banner() {
    echo ""
    echo "========================================="
    echo " ChengetAi Deploy : $1"
    echo "========================================="
    echo ""
}

# CHENGETAI_HOME is exported by the chengetai launcher; fall back to the
# directory above lib/ so the scripts also work when run directly.
CHENGETAI_HOME="${CHENGETAI_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TEMPLATES_DIR="$CHENGETAI_HOME/templates"
DEPLOYMENTS_DIR="${CHENGETAI_DEPLOYMENTS_DIR:-$CHENGETAI_HOME/deployments}"

cli_version() {
    cat "$CHENGETAI_HOME/VERSION" 2>/dev/null || echo "unknown"
}

require_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        error "Docker is not installed. Run: chengetai doctor"
    fi
    if ! docker info >/dev/null 2>&1; then
        error "Docker daemon is not running. Start Docker and try again."
    fi
}

container_running() {
    [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]
}

# ── Platform templates (plugins) ─────────────────────────────────────────────

list_platforms() {
    local dir
    for dir in "$TEMPLATES_DIR"/*/; do
        [ -f "$dir/plugin.sh" ] && basename "$dir"
    done
}

# Sources templates/<platform>/plugin.sh, which must define PLUGIN_STATUS
# and the plugin_* functions the commands dispatch to.
load_plugin() {
    local platform="$1"
    local plugin_file="$TEMPLATES_DIR/$platform/plugin.sh"
    if [ ! -f "$plugin_file" ]; then
        error "Unknown platform '$platform'. Available: $(list_platforms | tr '\n' ' ')"
    fi
    # shellcheck source=/dev/null
    source "$plugin_file"
}

# ── Deployments ───────────────────────────────────────────────────────────────

list_deployments() {
    local dir
    for dir in "$DEPLOYMENTS_DIR"/*/; do
        [ -f "$dir/profile.env" ] && basename "$dir"
    done
}

is_deployment() {
    [ -n "${1:-}" ] && [ -f "$DEPLOYMENTS_DIR/$1/profile.env" ]
}

# resolve_deployment [name]
# Sets DEPLOY_NAME and DEPLOY_DIR, exports the profile variables and loads
# the deployment's platform plugin. With no name, uses the only deployment
# if exactly one exists.
resolve_deployment() {
    local name="${1:-}"
    if [ -z "$name" ]; then
        local all count
        all=$(list_deployments)
        count=$(echo -n "$all" | grep -c . || true)
        if [ "$count" -eq 0 ]; then
            error "No deployments found. Create one with: chengetai deploy"
        elif [ "$count" -gt 1 ]; then
            error "Multiple deployments exist — specify one: $(echo "$all" | tr '\n' ' ')"
        fi
        name="$all"
    fi

    DEPLOY_NAME="$name"
    DEPLOY_DIR="$DEPLOYMENTS_DIR/$name"
    if [ ! -f "$DEPLOY_DIR/profile.env" ]; then
        error "Deployment '$name' not found. Existing: $(list_deployments | tr '\n' ' ')"
    fi

    set -a
    # shellcheck source=/dev/null
    source "$DEPLOY_DIR/profile.env"
    set +a

    load_plugin "$PLATFORM"
}

# ── Prompting ─────────────────────────────────────────────────────────────────

# prompt_if_empty VAR "Label" — asks only when VAR is empty, so values can
# be supplied via the environment for non-interactive use.
prompt_if_empty() {
    local var="$1" label="$2"
    if [ -z "${!var:-}" ]; then
        read -rp "$label : " "$var"
    fi
    [ -n "${!var:-}" ] || error "$label is required."
}

confirm() {
    local answer
    read -rp "$1 (Y/N): " answer
    [[ "$answer" =~ ^[Yy]$ ]]
}
