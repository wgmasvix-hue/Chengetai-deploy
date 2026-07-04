#!/usr/bin/env bash

set -e

source "$(dirname "$0")/utils.sh"

resolve_deployment "${1:-}"
require_docker

banner "Backing Up : $DEPLOY_NAME"

plugin_backup
