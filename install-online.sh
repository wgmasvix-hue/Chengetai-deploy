#!/usr/bin/env bash
# =============================================================================
#  ChengetAi Deploy — Online Installer
#
#  Install with one command on a fresh Ubuntu server:
#    curl -fsSL https://raw.githubusercontent.com/wgmasvix-hue/Chengetai-deploy/claude/dspace-deployment-review-98kzqb/install-online.sh | sudo bash
#
#  Then:
#    chengetai doctor
#    chengetai deploy
# =============================================================================
set -euo pipefail

REPO_URL="https://github.com/wgmasvix-hue/Chengetai-deploy.git"
# TODO: switch to 'main' once the review branch is merged.
BRANCH="${CHENGETAI_BRANCH:-claude/dspace-deployment-review-98kzqb}"
INSTALL_DIR="${CHENGETAI_INSTALL_DIR:-/opt/chengetai-deploy}"

echo ""
echo "=========================================================="
echo "        ChengetAi Deploy — Installer"
echo "=========================================================="
echo ""

if [ "$(id -u)" != "0" ]; then
    echo "This installer needs root. Re-run it as:"
    echo ""
    echo "  curl -fsSL <this-url> | sudo bash"
    echo ""
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    echo "[1/4] Installing git..."
    apt-get update -qq || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y git >/dev/null
else
    echo "[1/4] git already installed."
fi

if [ -d "$INSTALL_DIR/.git" ]; then
    echo "[2/4] Updating existing installation at $INSTALL_DIR..."
    git -C "$INSTALL_DIR" fetch origin "$BRANCH"
    git -C "$INSTALL_DIR" checkout "$BRANCH"
    git -C "$INSTALL_DIR" pull --ff-only origin "$BRANCH"
else
    echo "[2/4] Downloading ChengetAi Deploy to $INSTALL_DIR..."
    git clone -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
fi

echo "[3/4] Creating launcher..."
chmod +x "$INSTALL_DIR/chengetai"
ln -sf "$INSTALL_DIR/chengetai" /usr/local/bin/chengetai

echo "[4/4] Verifying installation..."
if ! command -v chengetai >/dev/null 2>&1; then
    echo "Installation failed: 'chengetai' is not on the PATH."
    exit 1
fi

VERSION=$(cat "$INSTALL_DIR/VERSION" 2>/dev/null || echo unknown)

echo ""
echo "=========================================================="
echo " ChengetAi Deploy v$VERSION Installed Successfully"
echo "=========================================================="
echo ""
echo "Get started:"
echo ""
echo "  chengetai doctor    # check the system, install dependencies"
echo "  chengetai deploy    # deploy a repository"
echo ""
