#!/bin/bash
# Koha container entrypoint. Configures a single Koha instance against the
# external MariaDB, creates it on first boot, and runs Apache + Zebra in the
# foreground. Idempotent: on restart it detects the existing instance and
# just starts the services.
set -e

INSTANCE="${KOHA_INSTANCE:-library}"
OPAC_PORT="${OPAC_PORT:-8080}"
STAFF_PORT="${STAFF_PORT:-8081}"

echo "[koha] Waiting for database $DB_HOST:$DB_PORT ..."
until mariadb -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -e 'SELECT 1' >/dev/null 2>&1; do
  sleep 2
done
echo "[koha] Database is up."

# Point koha-common at the external MariaDB and set the web ports.
cat > /etc/koha/koha-sites.conf <<EOF
INTRAPORT="$STAFF_PORT"
INTRAPREFIX=""
INTRASUFFIX=""
OPACPORT="$OPAC_PORT"
OPACPREFIX=""
OPACSUFFIX=""
DEFAULTSQL=""
ZEBRA_MARC_FORMAT="marc21"
ZEBRA_LANGUAGE="en"
KOHA_CONF_DIR="/etc/koha/sites"
BIB_INDEXING_MODE="dom"
AUTH_INDEXING_MODE="dom"
USE_MEMCACHED="no"
DB_HOST="$DB_HOST"
DB_PORT="$DB_PORT"
DOMAIN=""
EOF

start_services() {
  echo "[koha] Starting Zebra + Apache..."
  service koha-common start 2>/dev/null || koha-zebra --start "$INSTANCE" 2>/dev/null || true
  # Run Apache in the foreground so the container stays alive.
  . /etc/apache2/envvars
  exec apache2 -D FOREGROUND
}

if koha-list 2>/dev/null | grep -qx "$INSTANCE"; then
  echo "[koha] Instance '$INSTANCE' already exists — starting services."
  start_services
fi

echo "[koha] Creating instance '$INSTANCE' against $DB_NAME ..."
# Use the pre-created external database rather than a local one.
koha-create --use-db \
  --database "$DB_NAME" \
  --adminuser 1 \
  --defaultsql "" \
  "$INSTANCE" || {
    echo "[koha] koha-create --use-db failed; the database may need to be populated by Koha's web installer." >&2
  }

# Enable the OPAC/plack config and reload apache config.
a2ensite "$INSTANCE" 2>/dev/null || true
a2enmod cgi rewrite headers 2>/dev/null || true

echo ""
echo "=================================================================="
echo " Koha instance '$INSTANCE' is starting."
echo " Finish setup in the browser (Koha's one-time web installer):"
echo "   Staff : http://<server>:${STAFF_PORT}   (log in with the Koha"
echo "           admin user shown by 'chengetai status') "
echo " The installer creates the schema and initial library settings."
echo "=================================================================="
echo ""

start_services
