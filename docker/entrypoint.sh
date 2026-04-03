#!/bin/bash
set -euo pipefail

APP_DIR="/var/www/kivitendo-erp"
CONFIG_FILE="${APP_DIR}/config/kivitendo.conf"
CONFIG_DEFAULT="${APP_DIR}/config/kivitendo.conf.default"

cd "$APP_DIR"

# ---------------------------------------------------------------------------
# 1. Generate kivitendo.conf from defaults, patching with environment vars
#
# IMPORTANT: Keys like 'host', 'port', 'user', 'password' appear in multiple
# INI sections. All sed substitutions are scoped to their specific section
# using address ranges (/\[section\]/,/\[next-section\]/) to avoid
# corrupting other sections (LDAP, IMAP, testing, etc.).
# ---------------------------------------------------------------------------
echo ">>> Generating config/kivitendo.conf ..."
cp "$CONFIG_DEFAULT" "$CONFIG_FILE"

# [authentication] – admin password
sed -i '/^\[authentication\]$/,/^\[authentication\/database\]$/ {
    s|^admin_password = .*|admin_password = '"${ADMIN_PASSWORD:-admin123}"'|
}' "$CONFIG_FILE"

# [authentication/database] – PostgreSQL connection for auth DB
sed -i '/^\[authentication\/database\]$/,/^\[authentication\/ldap\]$/ {
    s|^host\s*=.*|host     = '"${DB_HOST:-db}"'|
    s|^port\s*=.*|port     = '"${DB_PORT:-5432}"'|
    s|^db\s*=.*|db       = '"${DB_NAME:-kivitendo_auth}"'|
    s|^user\s*=.*|user     = '"${DB_USER:-postgres}"'|
    s|^password\s*=.*|password = '"${DB_PASSWORD:-}"'|
}' "$CONFIG_FILE"

# [mail_delivery] – SMTP host and port (MailHog by default)
sed -i '/^\[mail_delivery\]$/,/^\[imap_client\]$/ {
    s|^host = .*|host = '"${SMTP_HOST:-mailhog}"'|
}' "$CONFIG_FILE"

if [ -n "${SMTP_PORT:-}" ]; then
    sed -i '/^\[mail_delivery\]$/,/^\[imap_client\]$/ {
        s|^#port = .*|port = '"$SMTP_PORT"'|
        s|^port = .*|port = '"$SMTP_PORT"'|
    }' "$CONFIG_FILE"
fi

# [secrets] – master encryption key
if [ -n "${SECRET_MASTER_KEY:-}" ]; then
    sed -i '/^\[secrets\]$/,/^\[console\]$/ {
        s|^master_key = .*|master_key = '"$SECRET_MASTER_KEY"'|
    }' "$CONFIG_FILE"
fi

# [task_server] – drop privileges to www-data (task server's own setuid support)
sed -i '/^\[task_server\]$/,/^\[task_server\/notify_on_failure\]$/ {
    s|^run_as = .*|run_as = www-data|
}' "$CONFIG_FILE"

echo ">>> config/kivitendo.conf written."

# ---------------------------------------------------------------------------
# 2. Wait for PostgreSQL to be ready
# ---------------------------------------------------------------------------
echo ">>> Waiting for PostgreSQL at ${DB_HOST:-db}:${DB_PORT:-5432} ..."
MAX_WAIT=60
WAITED=0
until pg_isready -h "${DB_HOST:-db}" -p "${DB_PORT:-5432}" -U "${DB_USER:-postgres}" -q; do
    if [ "$WAITED" -ge "$MAX_WAIT" ]; then
        echo "ERROR: PostgreSQL not ready after ${MAX_WAIT}s. Aborting."
        exit 1
    fi
    sleep 2
    WAITED=$((WAITED + 2))
done
echo ">>> PostgreSQL is ready."

# ---------------------------------------------------------------------------
# 3. Fix permissions on volume-mounted runtime directories
#    (volumes are initially owned by root; app runs as www-data)
# ---------------------------------------------------------------------------
mkdir -p users/pid spool webdav
chown -R www-data:www-data users spool webdav config 2>/dev/null || true

# ---------------------------------------------------------------------------
# 4. Start the requested service
# ---------------------------------------------------------------------------
ROLE="${ROLE:-app}"

if [ "$ROLE" = "task-server" ]; then
    # Remove stale PID file left over from a previous container run.
    # Daemon::Generic refuses to start if the PID file already exists.
    rm -f users/pid/*.pid

    echo ">>> Starting kivitendo task server (foreground mode) ..."
    # The task server drops privileges to 'run_as' user via its own setuid()
    exec perl scripts/task_server.pl -f start
else
    # Remove stale Apache PID to prevent "Address already in use" on restart
    rm -f /var/run/apache2/apache2.pid

    echo ">>> Starting Apache2 ..."
    exec apache2ctl -D FOREGROUND
fi
