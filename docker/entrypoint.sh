#!/bin/bash
set -euo pipefail

APP_DIR="/var/www/kivitendo-erp"
KIVITENDO_CONFIG="${APP_DIR}/config/kivitendo.conf"
KIVITENDO_CONFIG_DEFAULT="${APP_DIR}/config/kivitendo.conf.default"
WEBSERVER_USER="www-data"
APACHE_PID_FILE="/var/run/apache2/apache2.pid"
TASK_SERVER_PID_GLOB="${APP_DIR}/users/pid/*.pid"
POSTGRES_READY_TIMEOUT_SECONDS=60

patch_ini_key_in_section() {
    local section="$1"
    local next_section="$2"
    local key="$3"
    local value="$4"
    sed -i "/^\[${section}\]$/,/^\[${next_section}\]$/ {
        s|^${key}\s*=.*|${key} = ${value}|
    }" "$KIVITENDO_CONFIG"
}

patch_ini_key_in_section_uncomment_if_needed() {
    local section="$1"
    local next_section="$2"
    local key="$3"
    local value="$4"
    sed -i "/^\[${section}\]$/,/^\[${next_section}\]$/ {
        s|^#${key}\s*=.*|${key} = ${value}|
        s|^${key}\s*=.*|${key} = ${value}|
    }" "$KIVITENDO_CONFIG"
}

generate_config_from_defaults() {
    cp "$KIVITENDO_CONFIG_DEFAULT" "$KIVITENDO_CONFIG"

    patch_ini_key_in_section \
        "authentication" "authentication/database" \
        "admin_password" "${ADMIN_PASSWORD:-admin123}"

    patch_ini_key_in_section "authentication\/database" "authentication\/ldap" "host"     "${DB_HOST:-db}"
    patch_ini_key_in_section "authentication\/database" "authentication\/ldap" "port"     "${DB_PORT:-5432}"
    patch_ini_key_in_section "authentication\/database" "authentication\/ldap" "db"       "${DB_NAME:-kivitendo_auth}"
    patch_ini_key_in_section "authentication\/database" "authentication\/ldap" "user"     "${DB_USER:-postgres}"
    patch_ini_key_in_section "authentication\/database" "authentication\/ldap" "password" "${DB_PASSWORD:-}"

    patch_ini_key_in_section "mail_delivery" "imap_client" "host" "${SMTP_HOST:-mailhog}"

    if [ -n "${SMTP_PORT:-}" ]; then
        patch_ini_key_in_section_uncomment_if_needed \
            "mail_delivery" "imap_client" \
            "port" "$SMTP_PORT"
    fi

    if [ -n "${SECRET_MASTER_KEY:-}" ]; then
        patch_ini_key_in_section \
            "secrets" "console" \
            "master_key" "$SECRET_MASTER_KEY"
    fi

    patch_ini_key_in_section \
        "task_server" "task_server\/notify_on_failure" \
        "run_as" "$WEBSERVER_USER"
}

wait_until_postgres_accepts_connections() {
    local elapsed=0
    until pg_isready -h "${DB_HOST:-db}" -p "${DB_PORT:-5432}" -U "${DB_USER:-postgres}" -q; do
        if [ "$elapsed" -ge "$POSTGRES_READY_TIMEOUT_SECONDS" ]; then
            echo "ERROR: PostgreSQL at ${DB_HOST:-db}:${DB_PORT:-5432} not ready after ${POSTGRES_READY_TIMEOUT_SECONDS}s."
            exit 1
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
}

grant_webserver_ownership_of_runtime_directories() {
    mkdir -p users/pid spool webdav
    chown -R "$WEBSERVER_USER:$WEBSERVER_USER" users spool webdav config 2>/dev/null || true
}

remove_stale_daemon_pid_files() {
    rm -f $TASK_SERVER_PID_GLOB
}

remove_stale_apache_pid_file() {
    rm -f "$APACHE_PID_FILE"
}

start_task_server_in_foreground() {
    remove_stale_daemon_pid_files
    exec perl scripts/task_server.pl -f start
}

start_apache_in_foreground() {
    remove_stale_apache_pid_file
    exec apache2ctl -D FOREGROUND
}

main() {
    cd "$APP_DIR"

    generate_config_from_defaults
    wait_until_postgres_accepts_connections
    grant_webserver_ownership_of_runtime_directories

    case "${ROLE:-app}" in
        task-server) start_task_server_in_foreground ;;
        *)           start_apache_in_foreground ;;
    esac
}

main
