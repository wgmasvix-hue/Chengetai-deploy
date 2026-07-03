#!/usr/bin/env bash

set -e

source "$(dirname "$0")/common.sh"

require_engine

banner "Stopping Repository"

# Containers are removed; the assetstore, database and Solr volumes are kept.
compose down --remove-orphans

echo ""
info "All services stopped. Data volumes are preserved."
echo "Start again with: chengetai start"
echo ""
