#!/usr/bin/env bash

set -e

source "$(dirname "$0")/common.sh"

require_engine

banner "Service Status"

compose ps

SERVER_IP=$(server_ip)

echo ""
if curl -sf "http://localhost:8080/server/api" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} REST API       : http://${SERVER_IP}:8080/server"
else
    echo -e "${RED}✗${NC} REST API       : not responding (http://${SERVER_IP}:8080/server)"
fi

if curl -sf "http://localhost:4000" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} User Interface : http://${SERVER_IP}:4000"
else
    echo -e "${RED}✗${NC} User Interface : not responding (http://${SERVER_IP}:4000)"
fi
echo ""
