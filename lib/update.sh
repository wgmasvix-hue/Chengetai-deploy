#!/usr/bin/env bash
# chengetai update
# Updates the CLI (and its deployments) to the latest of its branch.
#
# The CLI update FORCE-ALIGNS to the remote (fetch + checkout -f) rather than
# a fast-forward pull, so it is robust even when the branch history was
# rewritten. Untracked runtime state — deployments/, api/.env, api/data — is
# gitignored and therefore preserved. It also re-points the launcher and
# warns if a different 'chengetai' is shadowing this install on your PATH.
set -e

source "$(dirname "$0")/utils.sh"

LINK="/usr/local/bin/chengetai"

banner "Updating ChengetAi Deploy"

update_cli() {
    if [ ! -d "$CHENGETAI_HOME/.git" ]; then
        warn "This install ($CHENGETAI_HOME) is not a git checkout — can't self-update."
        warn "Re-run the installer instead:"
        warn "  curl -fsSL https://raw.githubusercontent.com/wgmasvix-hue/Chengetai-deploy/main/install-online.sh | sudo bash"
        return 0
    fi

    local branch
    branch="${CHENGETAI_BRANCH:-$(git -C "$CHENGETAI_HOME" rev-parse --abbrev-ref HEAD 2>/dev/null)}"
    if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then branch="main"; fi

    info "Updating CLI to the latest '$branch' (force-aligning to the remote)..."
    # fetch + checkout -f is history-rewrite proof; untracked runtime state
    # (deployments/, api/.env, api/data) is left in place.
    git -C "$CHENGETAI_HOME" fetch --depth 1 origin "$branch"
    git -C "$CHENGETAI_HOME" checkout -qf -B "$branch" FETCH_HEAD
    chmod +x "$CHENGETAI_HOME/chengetai" 2>/dev/null || true
    info "CLI is now at version $(cli_version)."
}

# Make sure the launcher points at THIS install (fixes a stale symlink).
relink() {
    local want
    want="$(readlink -f "$CHENGETAI_HOME/chengetai" 2>/dev/null)"
    [ -n "$want" ] || return 0
    if [ "$(readlink -f "$LINK" 2>/dev/null)" != "$want" ]; then
        if ln -sf "$CHENGETAI_HOME/chengetai" "$LINK" 2>/dev/null; then
            info "Re-pointed $LINK -> $CHENGETAI_HOME/chengetai"
        fi
    fi
}

# Warn if the 'chengetai' resolved on PATH is a DIFFERENT copy than the one
# we just updated (a stale clone shadowing the real install).
warn_if_shadowed() {
    local onpath resolved want
    onpath="$(command -v chengetai 2>/dev/null || true)"
    [ -n "$onpath" ] || return 0
    resolved="$(readlink -f "$onpath" 2>/dev/null)"
    want="$(readlink -f "$CHENGETAI_HOME/chengetai" 2>/dev/null)"
    if [ -n "$resolved" ] && [ -n "$want" ] && [ "$resolved" != "$want" ]; then
        echo ""
        warn "A different 'chengetai' is ahead on your PATH:"
        warn "  on PATH : $onpath -> $resolved"
        warn "  updated : $CHENGETAI_HOME/chengetai"
        warn "Point PATH at the updated install, then reload the shell:"
        warn "  sudo ln -sf $CHENGETAI_HOME/chengetai $LINK && hash -r"
    fi
}

update_cli
relink

for name in $(list_deployments); do
    echo ""
    info "Updating deployment '$name'..."
    (
        resolve_deployment "$name"
        require_docker
        plugin_update
    ) || warn "Update of deployment '$name' failed — check the output above."
done

echo ""
info "ChengetAi Deploy is now at version $(cli_version)."
warn_if_shadowed
echo ""
