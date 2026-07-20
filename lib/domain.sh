#!/usr/bin/env bash
# chengetai domain [name] <domain> [--email you@org] [--caddy-only]
#
# Puts a deployment behind a real domain with automatic HTTPS using Caddy.
# Caddy provisions and renews Let's Encrypt certificates on its own, so this
# replaces the whole nginx + certbot dance with one command. It:
#
#   1. installs Caddy (once),
#   2. writes a per-deployment Caddy site that reverse-proxies the domain to
#      the deployment's UI and REST ports (served under one origin),
#   3. reloads Caddy,
#   4. repoints the platform at the HTTPS domain (plugin_domain), unless
#      --caddy-only is given.
set -e

source "$(dirname "$0")/utils.sh"

DOMAIN="" NAME="" EMAIL="" CADDY_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --email)      EMAIL="$2"; shift 2 ;;
        --caddy-only) CADDY_ONLY=1; shift ;;
        -*)           error "Unknown option: $1" ;;
        *)
            # An argument containing a dot is the domain; otherwise it's the
            # deployment name.
            if [[ "$1" == *.* ]]; then DOMAIN="$1"; else NAME="$1"; fi
            shift
            ;;
    esac
done

[ -n "$DOMAIN" ] || error "Usage: chengetai domain [name] <domain> [--email you@org]"
[ "$(id -u)" = "0" ] || error "Setting up a domain needs root: sudo chengetai domain $NAME $DOMAIN"

banner "Domain + HTTPS (Caddy)"

# Loads the profile and the platform plugin (gives us the UI/REST ports).
resolve_deployment "$NAME"

UI="$(ui_port)"
REST="$(rest_port)"
info "Deployment : $DEPLOY_NAME ($PLATFORM)"
info "Domain     : https://$DOMAIN"
info "Upstreams  : UI 127.0.0.1:$UI · REST 127.0.0.1:$REST/server"

install_caddy() {
    if command -v caddy >/dev/null 2>&1; then
        return 0
    fi
    info "Installing Caddy..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg >/dev/null
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
        | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
        > /etc/apt/sources.list.d/caddy-stable.list
    apt-get update -y >/dev/null
    apt-get install -y caddy >/dev/null
    info "Caddy installed."
}

write_caddy_site() {
    local conf_dir="/etc/caddy/conf.d"
    local caddyfile="/etc/caddy/Caddyfile"
    mkdir -p "$conf_dir"
    # Make sure the main Caddyfile imports our per-deployment sites.
    [ -f "$caddyfile" ] || echo "# Managed by ChengetAi Deploy" > "$caddyfile"
    if ! grep -q 'import /etc/caddy/conf.d/\*' "$caddyfile"; then
        echo 'import /etc/caddy/conf.d/*.caddy' >> "$caddyfile"
    fi

    local tls_line=""
    [ -n "$EMAIL" ] && tls_line=$'\n    tls '"$EMAIL"

    cat > "$conf_dir/$DEPLOY_NAME.caddy" <<CADDY
# ChengetAi Deploy — $DEPLOY_NAME. Automatic HTTPS via Let's Encrypt.
$DOMAIN {
    encode gzip$tls_line

    # REST API keeps its /server path on the backend.
    @rest path /server /server/*
    reverse_proxy @rest 127.0.0.1:$REST

    # Everything else goes to the UI.
    reverse_proxy 127.0.0.1:$UI
}
CADDY
    info "Caddy site written: $conf_dir/$DEPLOY_NAME.caddy"
}

reload_caddy() {
    if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
        systemctl reload caddy 2>/dev/null || systemctl restart caddy
        info "Caddy reloaded."
    else
        caddy validate --config /etc/caddy/Caddyfile || true
        error "Caddy config failed validation (see above). Nothing was reloaded."
    fi
}

install_caddy
write_caddy_site
systemctl enable caddy >/dev/null 2>&1 || true
reload_caddy

# Open the web ports so Caddy can serve and complete the ACME challenge.
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow 80/tcp >/dev/null 2>&1 || true
    ufw allow 443/tcp >/dev/null 2>&1 || true
    info "Opened ports 80 and 443 (ufw)."
fi

# Repoint the platform at the HTTPS domain (frontend + backend), unless the
# caller only wanted the proxy in place.
if [ "$CADDY_ONLY" != "1" ] && declare -F plugin_domain >/dev/null; then
    echo ""
    info "Repointing $PLATFORM at https://$DOMAIN ..."
    plugin_domain "$DOMAIN"
elif [ "$CADDY_ONLY" != "1" ]; then
    warn "The '$PLATFORM' plugin has no domain hook — Caddy is proxying, but"
    warn "you may need to point the app at https://$DOMAIN yourself."
fi

echo ""
banner "Done"
echo "  Your site:  https://$DOMAIN"
echo ""
echo "  Before it works, make sure:"
echo "    • DNS: an A record for $DOMAIN → this server's public IP"
echo "    • Ports 80 and 443 are reachable (firewall + cloud security group)"
echo ""
echo "  Watch certificate issuance:  journalctl -u caddy -f"
