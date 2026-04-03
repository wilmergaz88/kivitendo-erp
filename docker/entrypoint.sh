#!/bin/bash
set -euo pipefail

APP_DIR="/var/www/kivitendo-erp"
cd "$APP_DIR"

# ---------------------------------------------------------------------------
# 1. Generate kivitendo.conf from defaults, patching with environment vars
# ---------------------------------------------------------------------------
echo ">>> Generating config/kivitendo.conf from defaults..."
cp config/kivitendo.conf.default config/kivitendo.conf

patch_ini() {
  local section="$1"   # e.g. "authentication/database"
  local key="$2"       # e.g. "host"
  local value="$3"

  # Escape special characters for sed replacement
  local escaped_value
  escaped_value=$(printf '%s\n' "$value" | sed 's/[\/&]/\\&/g')
  local escaped_section
  escaped_section=$(printf '%s\n' "$section" | sed 's/[\/]/\\\//g')

  # Replace key within its section (between this section header and the next)
  sed -i \
    "/^\[${escaped_section}\]/,/^\[/ s/^${key}[ ]*=.*/${key} = ${escaped_value}/" \
    config/kivitendo.conf
}

# Authentication
patch_ini "authentication"          "admin_password"  "${ADMIN_PASSWORD:-admin123}"

# Auth database connection
patch_ini "authentication/database" "host"     "${DB_HOST:-db}"
patch_ini "authentication/database" "port"     "${DB_PORT:-5432}"
patch_ini "authentication/database" "db"       "${DB_NAME:-kivitendo_auth}"
patch_ini "authentication/database" "user"     "${DB_USER:-kivitendo}"
patch_ini "authentication/database" "password" "${DB_PASSWORD:-}"

# Mail delivery
patch_ini "mail_delivery" "host" "${SMTP_HOST:-mailhog}"
if [ -n "${SMTP_PORT:-}" ]; then
  patch_ini "mail_delivery" "port" "$SMTP_PORT"
fi

# Secrets
if [ -n "${SECRET_MASTER_KEY:-}" ]; then
  patch_ini "secrets" "master_key" "$SECRET_MASTER_KEY"
fi

echo ">>> config/kivitendo.conf written."

# ---------------------------------------------------------------------------
# 2. Wait for PostgreSQL to be ready
# ---------------------------------------------------------------------------
echo ">>> Waiting for PostgreSQL at ${DB_HOST:-db}:${DB_PORT:-5432}..."
MAX_WAIT=60
WAITED=0
until pg_isready -h "${DB_HOST:-db}" -p "${DB_PORT:-5432}" -U "${DB_USER:-kivitendo}" -q; do
  if [ "$WAITED" -ge "$MAX_WAIT" ]; then
    echo "ERROR: PostgreSQL did not become ready within ${MAX_WAIT}s. Aborting."
    exit 1
  fi
  sleep 2
  WAITED=$((WAITED + 2))
done
echo ">>> PostgreSQL is ready."

# ---------------------------------------------------------------------------
# 3. Fix permissions on runtime directories
# ---------------------------------------------------------------------------
chown -R www-data:www-data users spool webdav 2>/dev/null || true

# ---------------------------------------------------------------------------
# 4. Start the appropriate service
# ---------------------------------------------------------------------------
ROLE="${ROLE:-app}"

if [ "$ROLE" = "task-server" ]; then
  echo ">>> Starting kivitendo task server..."
  exec perl scripts/task_server.pl -f start
else
  echo ">>> Starting Apache2..."
  # Remove stale PID file if present
  rm -f /var/run/apache2/apache2.pid
  exec apache2ctl -D FOREGROUND
fi
