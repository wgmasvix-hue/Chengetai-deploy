#!/usr/bin/env bash
# chengetai admin [name] [--email E] [--first F] [--last L] [--password P] [--generate]
#
# Create or reset the administrator account for a deployment, run against the
# already-running backend — no redeploy. This is the clean recovery for the
# "passwords do not match" case, and a way to reset a forgotten admin
# password at any time.
#
# Values come from (in order) the deployment profile, then the environment,
# then CLI flags (flags win). The password is never stored in the profile;
# supply it with --password, ADMIN_PASS, or --generate.
set -e

source "$(dirname "$0")/utils.sh"

NAME=""
GEN=0
OPT_EMAIL="" OPT_FIRST="" OPT_LAST="" OPT_PASS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --email)          OPT_EMAIL="$2"; shift 2 ;;
        --first)          OPT_FIRST="$2"; shift 2 ;;
        --last)           OPT_LAST="$2"; shift 2 ;;
        --password|--pass) OPT_PASS="$2"; shift 2 ;;
        --generate)       GEN=1; shift ;;
        -*)               error "Unknown option: $1" ;;
        *)                NAME="$1"; shift ;;
    esac
done

# Loads the profile (ADMIN_EMAIL/FIRST/LAST) and the platform plugin.
resolve_deployment "$NAME"

# CLI flags override whatever the profile/environment provided.
[ -n "$OPT_EMAIL" ] && export ADMIN_EMAIL="$OPT_EMAIL"
[ -n "$OPT_FIRST" ] && export ADMIN_FIRST_NAME="$OPT_FIRST"
[ -n "$OPT_LAST" ]  && export ADMIN_LAST_NAME="$OPT_LAST"
[ -n "$OPT_PASS" ]  && export ADMIN_PASS="$OPT_PASS"

if [ "$GEN" = "1" ] && [ -z "${ADMIN_PASS:-}" ]; then
    ADMIN_PASS="$(openssl rand -base64 18 2>/dev/null || head -c 18 /dev/urandom | base64)"
    export ADMIN_PASS
    warn "Generated administrator password — save it now:"
    echo "  $ADMIN_PASS"
    echo ""
fi

if ! declare -F plugin_admin >/dev/null; then
    error "The '$PLATFORM' platform does not support 'chengetai admin'."
fi

banner "Administrator account — $DEPLOY_NAME ($PLATFORM)"
plugin_admin
