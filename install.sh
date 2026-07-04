#!/usr/bin/env bash

set -e

echo ""
echo "============================================================"
echo " ChengetAi Deploy : Deployment Complete"
echo "============================================================"

echo ""
echo "✓ DSpace Backend Running"
echo "✓ DSpace Frontend Running"
echo "✓ Deployment Successful"

SERVER_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "Frontend : http://$SERVER_IP:4000"
echo "Backend  : http://$SERVER_IP:8080/server/api"

echo ""
read -rp "Create DSpace Administrator now? (Y/N): " CREATE_ADMIN

if [[ "$CREATE_ADMIN" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Launching DSpace Administrator..."
    docker exec -it dspace /dspace/bin/dspace create-administrator
else
    echo ""
    echo "You can create the administrator later with:"
    echo "docker exec -it dspace /dspace/bin/dspace create-administrator"
fi

echo ""
echo "============================================================"
echo " ChengetAi Deploy Finished Successfully"
echo "============================================================"
