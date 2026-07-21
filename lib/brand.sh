#!/usr/bin/env bash
# chengetai brand [name] --name "DARE Digital Repository" --institution DARE \
#                        [--shortname DARE] [--publisher DARE] [--tagline "..."] \
#                        [--logo FILE] [--favicon FILE] [--apply]
# chengetai brand [name] --status
#
# Make a deployed repository present as the institution's own — name, short
# name, publisher, preview brand and browser-tab title — plus stage the
# institution logo/favicon. Identity is applied to the running backend's
# config (no rebuild); logo/favicon are baked into the frontend image on
# --apply. Colours/footer/login styling need a themed source build (docs).
set -e

source "$(dirname "$0")/utils.sh"

# Optional first positional is the deployment name; the rest goes to the plugin.
NAME=""
if [ $# -gt 0 ] && [[ "$1" != -* ]]; then
    NAME="$1"; shift
fi

resolve_deployment "$NAME"

if ! declare -F plugin_brand >/dev/null; then
    error "The '$PLATFORM' platform does not support 'chengetai brand'."
fi

banner "Institutional branding — $DEPLOY_NAME ($PLATFORM)"
plugin_brand "$@"
