#!/usr/bin/env bash

set -e

source "$(dirname "$0")/utils.sh"

banner "Installing ChengetAi Deploy"

INSTALL_DIR="${CHENGETAI_INSTALL_DIR:-/opt/chengetai-deploy}"

if [ "$(id -u)" != "0" ]; then
    error "Installation needs root. Run: sudo chengetai install"
fi

if [ "$CHENGETAI_HOME" = "$INSTALL_DIR" ]; then
    # Already running from the installed location — update it in place.
    if [ -d "$INSTALL_DIR/.git" ]; then
        BRANCH=$(git -C "$INSTALL_DIR" rev-parse --abbrev-ref HEAD)
        info "Updating installation (branch: $BRANCH)..."
        git -C "$INSTALL_DIR" fetch origin "$BRANCH"
        git -C "$INSTALL_DIR" pull --ff-only origin "$BRANCH"
    else
        warn "Installation is not a git checkout — re-run the online installer to update."
    fi
else
    info "Installing from $CHENGETAI_HOME to $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"
    cp -a "$CHENGETAI_HOME/." "$INSTALL_DIR/"
fi

chmod +x "$INSTALL_DIR/chengetai"
ln -sf "$INSTALL_DIR/chengetai" /usr/local/bin/chengetai

echo ""
info "ChengetAi Deploy $(cat "$INSTALL_DIR/VERSION" 2>/dev/null || echo unknown) installed at $INSTALL_DIR"
echo ""
echo "Next steps:"
echo ""
echo "  chengetai doctor"
echo "  chengetai deploy"
echo ""
