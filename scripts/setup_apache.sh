#!/bin/bash
##############################################################################
# Apache Setup for Kiviex - Dynamic Path Configuration
##############################################################################
set -euo pipefail

APP_DIR="${APP_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
APACHE_CONF_DIR="/etc/apache2"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && log_error "Must run as root: sudo $0"
[ ! -d "$APP_DIR" ] && log_error "App directory not found: $APP_DIR"

log_info "Configuring Apache for Kiviex ERP at: $APP_DIR"

# Install dependencies
echo ""
echo "Step 1: Installing Perl dependencies..."
PKGS="libalgorithm-checkdigits-perl libarchive-zip-perl libauthen-sasl-perl libcam-pdf-perl libcgi-pm-perl libclone-perl libconfig-std-perl libcryptx-perl libdaemon-generic-perl libdatetime-perl libdatetime-event-cron-perl libdatetime-format-strptime-perl libdatetime-set-perl libdbi-perl libdbd-pg-perl libencode-imaputf7-perl libemail-address-perl libemail-mime-perl libexception-class-perl libfcgi-perl libfile-copy-recursive-perl libfile-flock-perl libfile-mimeinfo-perl libfile-slurp-perl libgd-gd2-perl libhtml-parser-perl libhtml-restrict-perl libhttp-dav-perl libimage-info-perl libimager-perl libimager-qrcode-perl libipc-run-perl libjson-perl liblist-moreutils-perl liblist-utilsby-perl libmail-imapclient-perl libmath-round-perl libnet-smtp-ssl-perl libnet-sslglue-perl libparams-validate-perl libpbkdf2-tiny-perl libpdf-api2-perl libregexp-ipv6-perl librest-client-perl librose-object-perl librose-db-perl librose-db-object-perl libset-infinite-perl libsort-naturally-perl libstring-shellquote-perl libtemplate-perl libtext-csv-xs-perl libtext-iconv-perl libtext-unidecode-perl libtry-tiny-perl libuuid-tiny-perl liburi-perl libwww-perl libxml-libxml-perl libxml-writer-perl libyaml-perl tzdata apache2 libapache2-mod-cgi libapache2-mod-fcgid"
apt-get update -qq && apt-get install -y --no-install-recommends $PKGS >/dev/null 2>&1 && log_info "Dependencies installed"

# Enable modules
echo ""
echo "Step 2: Enabling Apache modules..."
for mod in fcgid rewrite cgi cgid; do
    a2enmod "$mod" >/dev/null 2>&1 && log_info "Module enabled: $mod" || log_info "Module already enabled: $mod"
done

# Create config
echo ""
echo "Step 3: Creating Apache configuration..."
cat > "$APACHE_CONF_DIR/conf-available/kivitendo-app.conf" << CONFIG
# Kiviex Configuration (auto-generated)
Define KIVITENDO_ROOT $APP_DIR

<VirtualHost *:80>
    ServerName localhost
    DocumentRoot \${KIVITENDO_ROOT}
    
    RedirectMatch ^/\$ /login.pl
    
    ScriptAlias /dispatcher.fcgi \${KIVITENDO_ROOT}/dispatcher.fcgi
    AliasMatch ^/[^/]+\\.pl\$       \${KIVITENDO_ROOT}/dispatcher.fcgi
    Alias       /                  \${KIVITENDO_ROOT}/

    <Directory \${KIVITENDO_ROOT}>
        AllowOverride All
        Options +ExecCGI +Includes +FollowSymLinks
        Require all granted
        AddHandler cgi-script .pl .fcgi
    </Directory>

    <DirectoryMatch "^\${KIVITENDO_ROOT}/(users|spool|webdav)(/|$)">
        Require all denied
    </DirectoryMatch>

    ErrorLog \${APACHE_LOG_DIR}/kivitendo-error.log
    CustomLog \${APACHE_LOG_DIR}/kivitendo-access.log combined
</VirtualHost>
CONFIG
log_info "Created: $APACHE_CONF_DIR/conf-available/kivitendo-app.conf"

# Disable conflicting
echo ""
echo "Step 4: Disabling conflicting configuration..."
apache2ctl -M 2>/dev/null | grep -q "php" && a2dismod php* 2>/dev/null && log_warn "Disabled PHP module"
a2dissite 000-default 2>/dev/null && log_info "Disabled default site"

# Enable config
echo ""
echo "Step 5: Enabling Kiviex configuration..."
a2enconf kivitendo-app >/dev/null 2>&1 && log_info "Configuration enabled: kivitendo-app"

# Verify
echo ""
echo "Step 6: Verifying Apache configuration..."
apache2ctl configtest 2>&1 | grep -q "Syntax OK" && log_info "Apache syntax valid" || log_error "Apache config error"

# Permissions
echo ""
echo "Step 7: Setting permissions..."
mkdir -p "$APP_DIR/users/pid" "$APP_DIR/spool" "$APP_DIR/webdav"
chown -R www-data:www-data "$APP_DIR/users" "$APP_DIR/spool" "$APP_DIR/webdav" 2>/dev/null
chmod -R 750 "$APP_DIR/users" "$APP_DIR/spool" "$APP_DIR/webdav" 2>/dev/null
log_info "Permissions configured for www-data"

# Restart
echo ""
echo "Step 8: Restarting Apache..."
systemctl restart apache2 && log_info "Apache restarted" || log_error "Failed to restart Apache"
sleep 2
systemctl is-active --quiet apache2 && log_info "Apache is running" || log_error "Apache failed to start"

# Summary
echo ""
echo "=========================================="
log_info "Setup completed successfully!"
echo "=========================================="
echo "App:        $APP_DIR"
echo "Access:     http://localhost/login.pl"
echo "Error log:  tail -f /var/log/apache2/kivitendo-error.log"
echo ""
