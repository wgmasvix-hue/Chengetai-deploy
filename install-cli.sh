#!/usr/bin/env bash

set -e

echo "========================================="
echo " Installing ChengetAi Deploy"
echo "========================================="

INSTALL_DIR="/opt/chengetai-deploy"

echo "Creating installation directory..."
mkdir -p "$INSTALL_DIR"

echo "Copying files..."
cp -r ./* "$INSTALL_DIR"

echo "Installing launcher..."
chmod +x "$INSTALL_DIR/chengetai"

ln -sf "$INSTALL_DIR/chengetai" /usr/local/bin/chengetai

echo ""
echo "========================================="
echo "ChengetAi Deploy Installed Successfully!"
echo "========================================="
echo ""
echo "Try:"
echo ""
echo "  chengetai doctor"
echo "  chengetai deploy"
echo ""
