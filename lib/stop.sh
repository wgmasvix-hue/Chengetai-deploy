#!/usr/bin/env bash

set -e

source "$(dirname "$0")/utils.sh"

resolve_deployment "${1:-}"
require_docker

banner "Stopping : $DEPLOY_NAME"

plugin_stop
