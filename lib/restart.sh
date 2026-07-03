#!/usr/bin/env bash

set -e

source "$(dirname "$0")/common.sh"

require_engine

banner "Restarting Repository"

compose restart

echo ""
info "Services restarted."
echo "The backend can take 3-5 minutes to come up. Check with: chengetai status"
echo ""
