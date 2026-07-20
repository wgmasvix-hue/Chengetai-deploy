#!/usr/bin/env bash
# Generated health check for {{DEPLOY_ID}} ({{DOMAIN}}).
set -u
URL="{{PUBLIC_URL}}"
fail=0
check() { if curl -skf -m 10 "$1" >/dev/null; then echo "[SUCCESS] $2"; else echo "[ERROR] $2 ($1)"; fail=1; fi; }
check "$URL"             "Repository homepage"
check "$URL/server/api"  "REST API"
body="$(curl -skf -m 10 "$URL/server/api" 2>/dev/null || true)"
if echo "$body" | grep -q "{{PUBLIC_URL}}"; then
    echo "[SUCCESS] REST advertises {{PUBLIC_URL}} (no internal IP)"
else
    echo "[WARNING] REST did not advertise {{PUBLIC_URL}} yet"
fi
exit $fail
