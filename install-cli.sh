#!/usr/bin/env bash
# Installs ChengetAi Deploy from this checkout (for offline / development
# installs). For the one-command online install, see install-online.sh.

set -e

INSTALL_DIR="${CHENGETAI_INSTALL_DIR:-/opt/chengetai-deploy}"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=========================================="
echo " Installing ChengetAi Deploy"
echo "=========================================="

echo "[1/5] Creating installation directory..."
sudo mkdir -p "$INSTALL_DIR"

echo "[2/5] Copying files..."
# Includes .git so the installed copy can update itself with 'chengetai update'.
sudo cp -a "$SOURCE_DIR/." "$INSTALL_DIR/"

echo "[3/5] Setting permissions..."
sudo chmod +x "$INSTALL_DIR/chengetai"

echo "[4/5] Creating launcher..."
sudo ln -sf "$INSTALL_DIR/chengetai" /usr/local/bin/chengetai

echo "[5/5] Verifying installation..."

if command -v chengetai >/dev/null 2>&1; then
    echo ""
    echo "=========================================="
    echo " ChengetAi Deploy $(cat "$INSTALL_DIR/VERSION" 2>/dev/null || echo unknown) Installed Successfully"
    echo "=========================================="
    echo ""
    echo "Run:"
    echo ""
    echo "  chengetai doctor"
    echo "  chengetai deploy"
else
    echo "Installation failed."
    exit 1
fi
