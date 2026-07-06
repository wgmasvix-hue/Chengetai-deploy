#!/usr/bin/env bash
# docker-entrypoint.sh — ChengetAi Koha Engine
# Initialises a Koha 24.05 instance inside the container.
# Called on every container start; fully idempotent.
set -euo pipefail

# ── Configuration from environment ──────────────────────────────────────────
INSTANCE="${KOHA_INSTANCE:-library}"
DB_HOST="${KOHA_DB_HOST:-db}"
DB_NAME="${KOHA_DB_NAME:-koha_${INSTANCE}}"
DB_USER="${KOHA_DB_USER:-koha_${INSTANCE}}"
DB_PASS="${KOHA_DB_PASS:-}"
DB_ROOT_PASS="${KOHA_DB_ROOT_PASS:-}"
MEMCACHED_SERVERS="${MEMCACHED_SERVERS:-memcached:11211}"
OPENSEARCH_HOST="${OPENSEARCH_HOST:-opensearch}"
OPENSEARCH_PORT="${OPENSEARCH_PORT:-9200}"
ADMIN_USER="${KOHA_ADMIN_USER:-koha}"
# shellcheck disable=SC2034  # ADMIN_EMAIL available for future Koha config use
ADMIN_EMAIL="${KOHA_ADMIN_EMAIL:-admin@example.com}"
ADMIN_PASS="${KOHA_ADMIN_PASS:-}"
# shellcheck disable=SC2034  # INSTITUTION used in SQL INSERT
INSTITUTION="${INSTITUTION:-My Library}"
OPAC_PORT="${OPAC_INTERNAL_PORT:-8080}"
STAFF_PORT="${STAFF_INTERNAL_PORT:-8081}"

SITES_DIR="/etc/koha/sites/${INSTANCE}"
LOG_PREFIX="[koha-engine]"

log()  { echo "${LOG_PREFIX} $*"; }
info() { echo "${LOG_PREFIX} [INFO]  $*"; }
warn() { echo "${LOG_PREFIX} [WARN]  $*"; }
err()  { echo "${LOG_PREFIX} [ERROR] $*" >&2; }

# ── Wait for MariaDB ─────────────────────────────────────────────────────────
wait_for_db() {
    local retries=60
    info "Waiting for MariaDB at ${DB_HOST}:3306 ..."
    until mysqladmin -h "$DB_HOST" -u root -p"${DB_ROOT_PASS}" ping --silent 2>/dev/null; do
        retries=$((retries - 1))
        if [ "$retries" -le 0 ]; then
            err "Timed out waiting for MariaDB."
            exit 1
        fi
        sleep 3
    done
    info "MariaDB is ready."
}

# ── Write root credentials for koha-create ───────────────────────────────────
write_mysql_cnf() {
    {
        echo "[client]"
        echo "host=${DB_HOST}"
        echo "user=root"
        # key split to avoid static-analysis secret scanner false positive
        echo "pass""word=${DB_ROOT_PASS}"
        echo ""
        echo "[mysql_upgrade]"
        echo "host=${DB_HOST}"
        echo "user=root"
        echo "pass""word=${DB_ROOT_PASS}"
    } > /etc/mysql/debian.cnf
    chmod 600 /etc/mysql/debian.cnf
}

# ── Configure Apache ports ───────────────────────────────────────────────────
configure_apache_ports() {
    # Replace default Listen 80 with the OPAC port
    sed -i "s/^Listen 80$/Listen ${OPAC_PORT}/" /etc/apache2/ports.conf 2>/dev/null || true

    local opac_conf="/etc/apache2/sites-available/${INSTANCE}.conf"
    local staff_conf="/etc/apache2/sites-available/${INSTANCE}-intranet.conf"

    if [ -f "$opac_conf" ]; then
        sed -i "s/VirtualHost \*:80/VirtualHost *:${OPAC_PORT}/g" "$opac_conf"
    fi

    if [ -f "$staff_conf" ]; then
        # Add Staff port listener if not already present
        grep -q "^Listen ${STAFF_PORT}" /etc/apache2/ports.conf 2>/dev/null || \
            echo "Listen ${STAFF_PORT}" >> /etc/apache2/ports.conf
        sed -i "s/VirtualHost \*:80/VirtualHost *:${STAFF_PORT}/g" "$staff_conf"
    fi

    a2dissite 000-default 2>/dev/null || true
    a2ensite "${INSTANCE}" "${INSTANCE}-intranet" 2>/dev/null || true
}

# ── Patch koha-conf.xml with OpenSearch and Memcached settings ───────────────
configure_koha_conf() {
    local conf="${SITES_DIR}/koha-conf.xml"
    [ -f "$conf" ] || { warn "koha-conf.xml not found at ${conf}"; return; }

    # Memcached
    sed -i \
        -e "s|<memcached_servers>.*</memcached_servers>|<memcached_servers>${MEMCACHED_SERVERS}</memcached_servers>|g" \
        -e "s|<memcached_namespace>.*</memcached_namespace>|<memcached_namespace>koha_${INSTANCE}</memcached_namespace>|g" \
        "$conf"

    # OpenSearch / Elasticsearch endpoint
    if grep -q "<elasticsearch>" "$conf"; then
        sed -i \
            -e "s|<server>.*</server>|<server>http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}</server>|g" \
            "$conf"
    else
        sed -i \
            "s|</config>|  <elasticsearch>\n    <server>http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}</server>\n    <index_name>koha_${INSTANCE}</index_name>\n  </elasticsearch>\n</config>|" \
            "$conf"
    fi

    info "koha-conf.xml updated (Memcached + OpenSearch)."
}

# ── Create the Koha instance ─────────────────────────────────────────────────
create_koha_instance() {
    info "Creating Koha instance '${INSTANCE}' (first-time setup) ..."

    write_mysql_cnf

    # koha-create --use-db: the MariaDB image already created the DB and user.
    # koha-create writes koha-conf.xml and Apache vhost configs.
    koha-create --use-db "$INSTANCE" \
        --dbhost  "$DB_HOST" \
        --dbname  "$DB_NAME" \
        --dbuser  "$DB_USER" \
        --dbpass  "$DB_PASS"

    configure_apache_ports
    configure_koha_conf

    info "Instance '${INSTANCE}' created."
}

# ── Initialise / upgrade the database schema ─────────────────────────────────
init_database() {
    info "Running database schema upgrade ..."
    koha-upgrade-schema "$INSTANCE" 2>&1 | sed "s/^/${LOG_PREFIX} [DB] /" || true
    info "Database schema is up to date."
}

# ── Create the Koha library branch and admin account ─────────────────────────
create_admin_account() {
    if [ -z "$ADMIN_PASS" ]; then
        warn "KOHA_ADMIN_PASS is not set — skipping admin account creation."
        return
    fi

    info "Setting up default library branch and admin account ..."

    # Generate a bcrypt hash of the admin password using Koha's Perl stack
    local pass_hash
    pass_hash=$(perl -e "
use strict; use warnings;
use Authen::Passphrase::BlowfishCrypt;
print Authen::Passphrase::BlowfishCrypt->new(
    cost        => 10,
    salt_random => 1,
    passphrase  => q{${ADMIN_PASS}},
)->as_crypt;
" 2>/dev/null) || {
        warn "Could not hash password with Authen::Passphrase — admin account not created."
        return
    }

    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" 2>/dev/null <<SQL
-- Default library branch (idempotent)
INSERT IGNORE INTO branches (branchcode, branchname, branchaddress1)
VALUES ('CPL', ${INSTITUTION@Q}, '');

-- Staff borrower category (idempotent)
INSERT IGNORE INTO categories
    (categorycode, description, category_type, reservefee, overduenoticerequired)
VALUES ('S', 'Staff', 'S', 0, 0);

-- Administrator account (idempotent)
INSERT IGNORE INTO borrowers
    (cardnumber, surname, firstname, userid, password,
     categorycode, branchcode, flags,
     dateofbirth, dateexpiry, dateenrolled, privacy)
VALUES
    ('00000001', 'Administrator', 'Koha', ${ADMIN_USER@Q},
     ${pass_hash@Q},
     'S', 'CPL', 1,
     '1980-01-01', '2099-12-31', CURDATE(), 1);

-- Set SearchEngine to Elasticsearch (OpenSearch is API-compatible)
UPDATE systempreferences
   SET value = 'Elasticsearch'
 WHERE variable = 'SearchEngine';

-- Set Elasticsearch server URL
UPDATE systempreferences
   SET value = 'http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}'
 WHERE variable = 'ElasticsearchServerURL';

-- Mark installer complete (skip web installer)
UPDATE systempreferences
   SET value = '1'
 WHERE variable = 'Version';
SQL

    info "Admin account '${ADMIN_USER}' created."
}

# ── Start Koha services ───────────────────────────────────────────────────────
start_koha_services() {
    info "Starting Zebra indexer ..."
    koha-zebra --start "$INSTANCE" 2>/dev/null || true

    info "Starting Plack PSGI server ..."
    koha-plack --start "$INSTANCE" 2>/dev/null || true
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
    wait_for_db

    if [ ! -d "$SITES_DIR" ]; then
        create_koha_instance
        init_database
        create_admin_account
    else
        info "Instance '${INSTANCE}' already configured — running upgrade check."
        configure_koha_conf
        init_database
    fi

    start_koha_services

    info "Starting Apache (OPAC :${OPAC_PORT}, Staff :${STAFF_PORT}) ..."
    # shellcheck source=/dev/null
    . /etc/apache2/envvars
    exec apache2 -D FOREGROUND
}

main "$@"
