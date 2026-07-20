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

echo "[5/5] Verifying the launcher..."
hash -r 2>/dev/null || true
ONPATH="$(command -v chengetai 2>/dev/null || true)"
RESOLVED="$(readlink -f "$ONPATH" 2>/dev/null)"
WANT="$(readlink -f "$INSTALL_DIR/chengetai" 2>/dev/null)"
if [ -n "$ONPATH" ] && [ "$RESOLVED" != "$WANT" ]; then
    echo ""
    echo "  WARNING: a different 'chengetai' is ahead on your PATH:"
    echo "    on PATH : $ONPATH -> $RESOLVED"
    echo "    this one: $INSTALL_DIR/chengetai"
    echo "  Remove or shadow it so PATH uses this install, e.g.:"
    echo "    sudo ln -sf $INSTALL_DIR/chengetai /usr/local/bin/chengetai && hash -r"
fi

echo "Installation complete."

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
