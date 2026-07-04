#!/usr/bin/env bash
# Creates a community/collection structure in DSpace 8 via its REST API.
# Generic and data-driven: reads the structure from a text file.
#
# Usage:
#   DSPACE_URL=http://localhost:8080/server \
#   ADMIN_EMAIL=... ADMIN_PASS=... \
#   bash setup-communities.sh communities.txt
#
# File format (see communities.txt.example):
#   Community Name|Description          top-level community
#   > Sub-community Name|Description    sub-community of the last community
#   >> Collection Name|Description      collection in the last sub-community

set -euo pipefail

STRUCTURE_FILE="${1:-communities.txt}"
DSPACE_URL="${DSPACE_URL:-http://localhost:8080/server}"

[ -f "$STRUCTURE_FILE" ] || { echo "Structure file not found: $STRUCTURE_FILE"; exit 1; }
[ -n "${ADMIN_EMAIL:-}" ] || { echo "ADMIN_EMAIL is required."; exit 1; }
[ -n "${ADMIN_PASS:-}"  ] || { echo "ADMIN_PASS is required.";  exit 1; }

COOKIE_JAR=$(mktemp)
trap 'rm -f "$COOKIE_JAR"' EXIT

get_csrf() {
  curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" -D - \
    "${DSPACE_URL}/api/authn/status" -o /dev/null \
    | grep -i "dspace-xsrf-token:" | awk '{print $2}' | tr -d '\r'
}

login() {
  local csrf="$1"
  curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    -X POST "${DSPACE_URL}/api/authn/login" \
    -H "X-XSRF-Token: ${csrf}" \
    --data-urlencode "user=${ADMIN_EMAIL}" \
    --data-urlencode "password=${ADMIN_PASS}" \
    -D - -o /dev/null | grep -i "authorization:" | awk '{print $2}' | tr -d '\r'
}

json_payload() {
  local name="$1" description="$2"
  python3 - "$name" "$description" <<'PY'
import json, sys
name, desc = sys.argv[1], sys.argv[2]
print(json.dumps({
    "name": name,
    "metadata": {
        "dc.title":       [{"value": name, "language": "en_US"}],
        "dc.description": [{"value": desc, "language": "en_US"}],
    },
}))
PY
}

create_dso() {
  # create_dso <endpoint> <parent-uuid-or-empty> <name> <description>
  local endpoint="$1" parent="$2" name="$3" description="$4" url
  url="${DSPACE_URL}/api/core/${endpoint}"
  [ -n "$parent" ] && url="${url}?parent=${parent}"
  curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    -X POST "$url" \
    -H "Content-Type: application/json" \
    -H "X-XSRF-Token: ${CSRF}" \
    -H "Authorization: ${TOKEN}" \
    -d "$(json_payload "$name" "$description")" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('uuid','ERROR: '+str(d)))"
}

echo "Connecting to ${DSPACE_URL} ..."
CSRF=$(get_csrf)
TOKEN=$(login "$CSRF")

if [ -z "$TOKEN" ]; then
  echo "ERROR: Login failed. Check ADMIN_EMAIL and ADMIN_PASS."
  exit 1
fi
echo "Logged in as ${ADMIN_EMAIL}"

# Re-fetch CSRF after login (cookie is refreshed)
CSRF=$(grep -i dspace-xsrf-token "$COOKIE_JAR" | awk '{print $NF}')

COMMUNITY_UUID=""
SUBCOMMUNITY_UUID=""

while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    ''|'#'*) continue ;;
  esac

  name="${line#>> }"; name="${name#> }"
  desc="${name#*|}"; name="${name%%|*}"
  [ "$desc" = "$name" ] && desc=""

  case "$line" in
    '>> '*)
      [ -n "$SUBCOMMUNITY_UUID" ] || { echo "  Skipping collection '$name' (no parent sub-community)"; continue; }
      echo -n "      Collection: $name ... "
      create_dso collections "$SUBCOMMUNITY_UUID" "$name" "$desc"
      ;;
    '> '*)
      [ -n "$COMMUNITY_UUID" ] || { echo "  Skipping '$name' (no parent community)"; continue; }
      echo -n "    Sub-community: $name ... "
      SUBCOMMUNITY_UUID=$(create_dso communities "$COMMUNITY_UUID" "$name" "$desc")
      echo "$SUBCOMMUNITY_UUID"
      ;;
    *)
      echo -n "  Community: $name ... "
      COMMUNITY_UUID=$(create_dso communities "" "$name" "$desc")
      SUBCOMMUNITY_UUID=""
      echo "$COMMUNITY_UUID"
      ;;
  esac
done < "$STRUCTURE_FILE"

echo ""
echo "Community structure created."
