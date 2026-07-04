#!/usr/bin/env bash
# =============================================================================
#  ChengetAi Deploy — build the dashboard into a WebZim/cPanel-ready zip.
#
#  Usage (from a clone):
#    bash deploy/build-frontend.sh [API_URL] [OUTPUT_ZIP]
#
#  Examples:
#    bash deploy/build-frontend.sh https://api.mydomain.co.zw/api
#    bash deploy/build-frontend.sh http://57.173.127.168:3000/api ~/dash.zip
#
#  API_URL     backend URL ending in /api (baked into config.js; editable
#              later on the host). Default: http://57.173.127.168:3000/api
#  OUTPUT_ZIP  where to write the zip. Default: ./chengetai-dashboard-webzim.zip
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
say()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DASH="$ROOT/dashboard"
API_URL="${1:-http://57.173.127.168:3000/api}"
OUT="${2:-$ROOT/chengetai-dashboard-webzim.zip}"

command -v node >/dev/null || { echo "node is required."; exit 1; }
command -v zip  >/dev/null || { echo "zip is required (apt-get install -y zip)."; exit 1; }

# 1. Build ---------------------------------------------------------------------
say "Building dashboard (production)..."
cd "$DASH"
[ -d node_modules ] || npm install --no-audit --no-fund
npx ng build --configuration production

DIST="$DASH/dist/chengetai-dashboard/browser"
[ -f "$DIST/index.html" ] || { echo "Build output not found at $DIST"; exit 1; }

# 2. Point config.js at the chosen backend ------------------------------------
say "Setting backend API to: $API_URL"
cat > "$DIST/config.js" <<EOF
// ChengetAi Deploy — runtime configuration.
// Edit apiUrl on the host to repoint the dashboard; no rebuild needed.
window.__CHENGETAI_CONFIG__ = {
  apiUrl: "${API_URL}"
};
EOF

# 3. Apache SPA routing --------------------------------------------------------
cat > "$DIST/.htaccess" <<'EOF'
Options -MultiViews
RewriteEngine On
<FilesMatch "^(config\.js|index\.html)$">
  Header set Cache-Control "no-cache, no-store, must-revalidate"
</FilesMatch>
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule ^ index.html [L]
EOF

# 4. Upload notes --------------------------------------------------------------
cat > "$DIST/README-DEPLOY.txt" <<EOF
ChengetAi Deploy — Dashboard for WebZim / cPanel
================================================
1. Upload everything here to public_html (include the hidden .htaccess).
2. Backend is set to: ${API_URL}
   Change it any time by editing config.js on the host, then refresh.
3. LOGIN NEEDS TWO THINGS TO MATCH:
   - HTTPS: an https:// site must use an https:// backend (mixed content
     is blocked). Give the backend a domain + TLS if the site is https.
   - CORS: on the VPS set CORS_ORIGIN=<this site's origin> in api/.env,
     then: sudo systemctl restart chengetai-api
4. If login fails, open the browser console (F12) — it names the cause.
EOF

# 5. Zip -----------------------------------------------------------------------
say "Packaging..."
rm -f "$OUT"
( cd "$DIST" && zip -rq "$OUT" . )

echo ""
say "Done: $OUT"
echo "    Backend : $API_URL"
echo "    Upload the zip's contents to public_html (show hidden files for .htaccess)."
case "$API_URL" in
  http://*) warn "Backend is HTTP — if WebZim serves over HTTPS, login will be blocked (mixed content). Use an HTTPS backend URL." ;;
esac
