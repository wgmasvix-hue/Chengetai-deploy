#!/usr/bin/env bash

set -e

source "$(dirname "$0")/utils.sh"

resolve_deployment "${1:-}"
require_docker

banner "Restarting : $DEPLOY_NAME"

plugin_restart
