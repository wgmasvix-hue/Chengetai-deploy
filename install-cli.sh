#!/usr/bin/env bash

set -e

INSTALL_DIR="/opt/chengetai-deploy"
CURRENT_DIR="$(pwd)"

echo "=========================================="
echo " Installing ChengetAi Deploy"
echo "=========================================="

echo "[1/5] Creating installation directory..."
mkdir -p "$INSTALL_DIR"

if [ "$CURRENT_DIR" != "$INSTALL_DIR" ]; then
    echo "[2/5] Copying files..."
    cp -a . "$INSTALL_DIR/"
else
    echo "[2/5] Already running from $INSTALL_DIR - skipping copy."
fi

echo "[3/5] Setting permissions..."
chmod +x "$INSTALL_DIR/chengetai"
chmod +x "$INSTALL_DIR/install-cli.sh"

echo "[4/5] Creating launcher..."
ln -sf "$INSTALL_DIR/chengetai" /usr/local/bin/chengetai

echo "[5/5] Installation complete."

echo ""
echo "=========================================="
echo " ChengetAi Deploy Installed Successfully"
echo "=========================================="
echo ""
echo "Run:"
echo "  chengetai"
echo "  chengetai doctor"
echo "  chengetai deploy"
echo ""
