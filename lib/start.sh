#!/usr/bin/env bash

set -e

source "$(dirname "$0")/common.sh"

require_engine

banner "Starting Repository"

compose up -d

SERVER_IP=$(server_ip)

echo ""
info "Services started."
echo ""
echo "  UI (browser):  http://${SERVER_IP}:4000"
echo "  REST API:      http://${SERVER_IP}:8080/server"
echo ""
echo "  The backend can take 3-5 minutes to come up."
echo "  Check progress with: chengetai status"
echo ""
