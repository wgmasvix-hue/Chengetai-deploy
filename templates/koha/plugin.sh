#!/usr/bin/env bash
# Koha platform plugin for ChengetAi Deploy — placeholder.

# shellcheck disable=SC2034  # PLUGIN_* consumed by the CLI after sourcing
PLUGIN_NAME="koha"
PLUGIN_DESCRIPTION="Koha library management system (coming soon)"
PLUGIN_STATUS="coming-soon"

plugin_deploy() {
    error "The '$PLUGIN_NAME' template is not available yet. Currently available: dspace"
}
