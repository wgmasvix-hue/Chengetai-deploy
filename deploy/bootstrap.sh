#!/usr/bin/env bash
# =============================================================================
#  ChengetAi Deploy — one-shot platform bootstrap (internal use).
#  Installs the CLI, API and dashboard, wires nginx + systemd, prints login.
#
#  Run from a clone, as root, on Ubuntu 22.04/24.04:
#    sudo bash deploy/bootstrap.sh
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
say()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

WITH_DSPACE=0
[ "${1:-}" = "--with-dspace" ] && WITH_DSPACE=1

[ "$(id -u)" = 0 ] || { echo "Run with sudo."; exit 1; }

SRC="$(cd "$(dirname "$0")/.." && pwd)"
DEST=/opt/chengetai-deploy

# 1. Dependencies -------------------------------------------------------------
say "Installing dependencies (node, nginx, git)..."
apt-get update -qq
command -v node  >/dev/null || { curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null; apt-get install -y nodejs >/dev/null; }
command -v nginx >/dev/null || apt-get install -y nginx >/dev/null
command -v git   >/dev/null || apt-get install -y git >/dev/null

# 2. Copy into place ----------------------------------------------------------
say "Installing to $DEST..."
[ "$SRC" = "$DEST" ] || { mkdir -p "$DEST"; cp -a "$SRC/." "$DEST/"; }
ln -sf "$DEST/chengetai" /usr/local/bin/chengetai
chmod +x "$DEST/chengetai"

# 3. API ----------------------------------------------------------------------
say "Setting up API..."
cd "$DEST/api"
npm install --omit=dev --no-audit --no-fund >/dev/null
if [ ! -f .env ]; then
  ADMIN_PASS=$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 16)
  cat > .env <<EOF
PORT=3000
ADMIN_EMAIL=admin@chengetai.local
ADMIN_PASSWORD=${ADMIN_PASS}
EOF
  chmod 600 .env
fi
cp "$DEST/deploy/chengetai-api.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now chengetai-api >/dev/null

# 4. Dashboard ----------------------------------------------------------------
say "Building dashboard (~1 min)..."
cd "$DEST/dashboard"
npm install --no-audit --no-fund >/dev/null
npm run build >/dev/null

# 5. Nginx --------------------------------------------------------------------
say "Configuring nginx..."
cp "$DEST/deploy/nginx.conf" /etc/nginx/sites-available/chengetai
ln -sf /etc/nginx/sites-available/chengetai /etc/nginx/sites-enabled/chengetai
rm -f /etc/nginx/sites-enabled/default
nginx -t >/dev/null 2>&1 && systemctl reload nginx

# 6. Optional: deploy DSpace straight away ------------------------------------
if [ "$WITH_DSPACE" = 1 ]; then
  say "Deploying a DSpace repository (installs Docker, ~15 min on first run)..."
  chengetai doctor
  chengetai deploy dspace || warn "DSpace deploy did not finish — run 'chengetai deploy dspace' to retry."
fi

# 7. Done ---------------------------------------------------------------------
IP=$(hostname -I | awk '{print $1}')
echo ""
say "ChengetAi Deploy is running."
echo "    Dashboard : http://${IP}/"
echo "    API       : http://${IP}/api/health"
echo "    Login     : admin@chengetai.local"
grep -q '^ADMIN_PASSWORD=' "$DEST/api/.env" && \
  echo "    Password  : $(grep '^ADMIN_PASSWORD=' "$DEST/api/.env" | cut -d= -f2)"
echo ""
warn "Internal tool — firewall port 80 to your campus/VPN subnet:"
echo "    sudo ufw allow from <subnet> to any port 80 proto tcp && sudo ufw enable"
