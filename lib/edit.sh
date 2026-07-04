#!/usr/bin/env bash

set -e

echo "========================================="
echo " ChengetAi Repository Editor"
echo "========================================="
echo ""

COMPONENT="$1"

if [ -z "$COMPONENT" ]; then
    echo "Usage:"
    echo "  chengetai edit homepage"
    echo "  chengetai edit logo"
    echo "  chengetai edit footer"
    echo "  chengetai edit news"
    echo "  chengetai edit favicon"
    echo "  chengetai edit css"
    exit 1
fi

read -rp "Deployment Name: " DEPLOYMENT

DEPLOY_DIR="/opt/chengetai/deployments/$DEPLOYMENT"

if [ ! -d "$DEPLOY_DIR" ]; then
    echo "ERROR: Deployment '$DEPLOYMENT' not found."
    exit 1
fi

case "$COMPONENT" in
    homepage)
        FILE=$(find "$DEPLOY_DIR" -name "home-page.component.html" | head -1)
        ;;
    logo)
        FILE=$(find "$DEPLOY_DIR" -name "dspace-logo*" | head -1)
        ;;
    footer)
        FILE=$(find "$DEPLOY_DIR" -name "footer.component.html" | head -1)
        ;;
    news)
        FILE=$(find "$DEPLOY_DIR" -name "news.component.html" | head -1)
        ;;
    favicon)
        FILE=$(find "$DEPLOY_DIR" -name "favicon.ico" | head -1)
        ;;
    css)
        FILE=$(find "$DEPLOY_DIR" -name "styles.scss" | head -1)
        ;;
    *)
        echo "Unknown component: $COMPONENT"
        exit 1
        ;;
esac

if [ -z "$FILE" ]; then
    echo "Component file not found."
    exit 1
fi

echo ""
echo "Opening:"
echo "$FILE"
echo ""

nano "$FILE"

echo ""
read -rp "Rebuild Angular frontend now? (Y/N): " REBUILD

if [[ "$REBUILD" =~ ^[Yy]$ ]]; then
    cd "$DEPLOY_DIR"

    docker compose -f docker-compose-campus.yml build dspace-angular
    docker compose -f docker-compose-campus.yml up -d dspace-angular

    echo ""
    echo "Frontend rebuilt successfully."
fi

echo ""
echo "Done."
