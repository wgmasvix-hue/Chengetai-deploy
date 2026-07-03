#!/usr/bin/env bash

set -e

source "$(dirname "$0")/utils.sh"

# First argument may be a deployment name; anything after it (or everything,
# when no name is given) selects services, e.g.:
#   chengetai logs                  all services of the only deployment
#   chengetai logs dspace           logs of the 'dspace' deployment
#   chengetai logs library dspacedb only the database of 'library'
if is_deployment "${1:-}"; then
    resolve_deployment "$1"
    shift
else
    resolve_deployment ""
fi
require_docker

# Press Ctrl+C to stop following.
plugin_logs "$@"
