#!/usr/bin/env bash

set -e

INSTALL_DIR="/opt/chengetai-deploy"

echo "=========================================="
echo " Installing ChengetAi Deploy"
echo "=========================================="

echo "[1/5] Creating installation directory..."
sudo mkdir -p "$INSTALL_DIR"

echo "[2/5] Copying files..."
sudo cp -r ./* "$INSTALL_DIR"

echo "[3/5] Setting permissions..."
sudo chmod +x "$INSTALL_DIR/chengetai"

echo "[4/5] Creating launcher..."
sudo ln -sf "$INSTALL_DIR/chengetai" /usr/local/bin/chengetai

echo "[5/5] Verifying installation..."

if command -v chengetai >/dev/null 2>&1; then
    echo ""
    echo "=========================================="
    echo " ChengetAi Deploy Installed Successfully"
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
