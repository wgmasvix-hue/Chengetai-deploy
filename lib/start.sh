#!/usr/bin/env bash

set -e

echo "========================================="
echo " Starting ChengetAi DSpace Services"
echo "========================================="

DEPLOY_DIR="$HOME/bpoly-dspace"

if [ ! -d "$DEPLOY_DIR" ]; then
    echo "ERROR: DSpace deployment not found."
    exit 1
fi

cd "$DEPLOY_DIR"

echo "Starting Docker containers..."
docker compose -f docker-compose-campus.yml up -d

echo ""
echo "Waiting for DSpace backend..."

until curl -sf http://localhost:8080/server/api >/dev/null; do
    sleep 5
    echo -n "."
done

echo ""
echo ""
echo "========================================="
echo " DSpace Started Successfully"
echo "========================================="

docker ps

IP=$(hostname -I | awk '{print $1}')

echo ""
echo "Frontend : http://$IP:4000"
echo "Backend  : http://$IP:8080/server/api"

