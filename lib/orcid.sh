#!/usr/bin/env bash
# chengetai orcid [name] --client-id APP-XXXX --client-secret SECRET [--sandbox|--production]
# chengetai orcid [name] --status
# chengetai orcid [name] --disable
#
# Turn on "Sign in with ORCID" and researcher-identity linking for a deployed
# repository, run against the already-running backend — no redeploy. ORCID is
# DSpace-native; this writes the settings into the deployment's mounted
# local.cfg and restarts the backend so they take effect.
#
# Keep the secret out of your shell history by exporting ORCID_CLIENT_SECRET
# instead of passing --client-secret.
set -e

source "$(dirname "$0")/utils.sh"

# The deployment name is an optional first positional (anything not a flag).
# Everything else is forwarded to the platform's plugin_orcid untouched.
NAME=""
if [ $# -gt 0 ] && [[ "$1" != -* ]]; then
    NAME="$1"; shift
fi

# Loads the profile and the platform plugin (sets PLATFORM, DEPLOY_NAME, ...).
resolve_deployment "$NAME"

if ! declare -F plugin_orcid >/dev/null; then
    error "The '$PLATFORM' platform does not support ORCID (currently DSpace only)."
fi

banner "ORCID integration — $DEPLOY_NAME ($PLATFORM)"
plugin_orcid "$@"
