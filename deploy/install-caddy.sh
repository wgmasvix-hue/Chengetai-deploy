#!/usr/bin/env bash
# ChengetAi Deploy — shared Caddy installer.
# Idempotent: does nothing if Caddy is already installed. Used by both
# deploy/bootstrap.sh (the dashboard's own reverse proxy) and lib/domain.sh
# (per-repository domains) so there is exactly one install recipe.
#
#   sudo bash deploy/install-caddy.sh
set -euo pipefail

command -v caddy >/dev/null 2>&1 && exit 0

export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg >/dev/null
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    > /etc/apt/sources.list.d/caddy-stable.list
apt-get update -y >/dev/null
apt-get install -y caddy >/dev/null
