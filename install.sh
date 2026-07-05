#!/bin/bash
set -e

echo "=========================================="
echo " ChengetAi Deploy Installer"
echo "=========================================="

echo "[1/4] Installing CLI..."
chmod +x install-cli.sh
./install-cli.sh

echo "[2/4] Running system checks..."
chengetai doctor || true

echo "[3/4] Creating deployment directory..."
mkdir -p /opt/deployments

echo "[4/4] Installation complete."

echo
echo "=========================================="
echo " ChengetAi Deploy is ready!"
echo "=========================================="
echo
echo "Next:"
echo "  chengetai deploy dspace"
