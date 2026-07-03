#!/usr/bin/env bash

set -e

source "$(dirname "$0")/common.sh"

require_engine

# Follows logs for the whole stack, or only the services named on the
# command line, e.g.:  chengetai logs dspace
# Press Ctrl+C to stop following.
compose logs --tail=200 -f "$@"
