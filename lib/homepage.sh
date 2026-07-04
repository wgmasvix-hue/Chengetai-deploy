#!/usr/bin/env bash

set -e

echo "========================================="
echo " ChengetAi Homepage Editor"
echo "========================================="
echo ""

read -rp "Deployment name: " DEPLOYMENT

DEPLOY_DIR="/opt/chengetai/deployments/$DEPLOYMENT"

if [ ! -d "$DEPLOY_DIR" ]; then
    echo "Deployment '$DEPLOYMENT' not found."
    exit 1
fi

PAGE=$(find "$DEPLOY_DIR" -name "home-page.component.html" | head -1)

if [ -z "$PAGE" ]; then
    echo "Homepage file not found."
    exit 1
fi

echo ""
echo "Opening:"
echo "$PAGE"
echo ""

nano "$PAGE"

echo ""
read -rp "Rebuild Angular frontend now? (Y/N): " REBUILD

if [[ "$REBUILD" =~ ^[Yy]$ ]]; then
    cd "$DEPLOY_DIR"
    docker compose -f docker-compose-campus.yml build dspace-angular
    docker compose -f docker-compose-campus.yml up -d dspace-angular

    echo ""
    echo "Homepage updated successfully."
fi
