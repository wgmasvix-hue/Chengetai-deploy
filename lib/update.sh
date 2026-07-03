#!/usr/bin/env bash

set -e

source "$(dirname "$0")/common.sh"

require_engine

banner "Updating Repository"

BRANCH=$(git -C "$ENGINE_DIR" rev-parse --abbrev-ref HEAD)

info "Pulling latest deployment engine (branch: $BRANCH)..."
git -C "$ENGINE_DIR" fetch origin "$BRANCH"
git -C "$ENGINE_DIR" pull --ff-only origin "$BRANCH"

info "Rebuilding branded Angular image..."
docker build -f "$ENGINE_DIR/Dockerfile.angular" -t bpoly-dspace-angular:latest "$ENGINE_DIR"

info "Applying update..."
compose up -d --remove-orphans

echo ""
info "Update complete."
echo "The backend can take 3-5 minutes to come up. Check with: chengetai status"
echo ""
