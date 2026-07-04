#!/usr/bin/env bash

set -e

echo "=========================================="
echo " ChengetAi Deployment Creator"
echo "=========================================="
echo ""

read -rp "Institution Name : " INSTITUTION
read -rp "Deployment Name  : " DEPLOYMENT

DEPLOY_DIR="/opt/chengetai/deployments/$DEPLOYMENT"

if [ -d "$DEPLOY_DIR" ]; then
    echo ""
    echo "ERROR: Deployment '$DEPLOYMENT' already exists."
    exit 1
fi

mkdir -p "$DEPLOY_DIR"

cat > "$DEPLOY_DIR/deployment.conf" <<EOC
INSTITUTION="$INSTITUTION"
DEPLOYMENT="$DEPLOYMENT"
CREATED=$(date)
EOC

echo ""
echo "=========================================="
echo "Deployment Created Successfully"
echo "=========================================="

echo "Institution : $INSTITUTION"
echo "Deployment  : $DEPLOYMENT"
echo "Directory   : $DEPLOY_DIR"
