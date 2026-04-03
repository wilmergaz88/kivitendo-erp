FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    APACHE_RUN_USER=www-data \
    APACHE_RUN_GROUP=www-data \
    APACHE_LOG_DIR=/var/log/apache2

# Ubuntu 22.04 needs "universe" for several Perl packages (per official docs)
RUN apt-get update \
    && apt-get install -y --no-install-recommends software-properties-common \
    && add-apt-repository universe \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    # Web server
    apache2 \
    libapache2-mod-fcgid \
    curl \
    # PostgreSQL client (pg_isready used in entrypoint)
    postgresql-client \
    # ── Perl modules from CI workflow (.github/workflows/main.yml) ──────────
    libtest-deep-perl \
    libtest-exception-perl \
    libtest-output-perl \
    libwww-perl \
    liburi-find-perl \
    libsys-cpu-perl \
    libthread-pool-simple-perl \
    libdbi-perl \
    liblist-moreutils-perl \
    libyaml-perl \
    libregexp-ipv6-perl \
    libpbkdf2-tiny-perl \
    librose-object-perl \
    librose-db-perl \
    librose-db-object-perl \
    libdigest-perl-md5-perl \
    liblist-utilsby-perl \
    libalgorithm-checkdigits-perl \
    libhtml-restrict-perl \
    libfile-slurp-perl \
    libsort-naturally-perl \
    libmath-round-perl \
    libtext-csv-xs-perl \
    libtemplate-perl \
    libcam-pdf-perl \
    libxml-libxml-perl \
    libxml-writer-perl \
    libemail-address-perl \
    libemail-mime-perl \
    libarchive-zip-perl \
    libimager-perl \
    libimager-qrcode-perl \
    libstring-shellquote-perl \
    libgd-gd2-perl \
    libimage-info-perl \
    libconfig-std-perl \
    libdbd-pg-perl \
    libdatetime-event-cron-perl \
    libfile-copy-recursive-perl \
    librest-client-perl \
    libipc-run-perl \
    libfile-mimeinfo-perl \
    libencode-imaputf7-perl \
    libmail-imapclient-perl \
    libhttp-dav-perl \
    libpdf-api2-perl \
    libppi-perl \
    libuuid-tiny-perl \
    libcryptx-perl \
    cpanminus \
    # ── Required for web/FCGI operation (not in CI test list) ───────────────
    libfcgi-perl \
    libdaemon-generic-perl \
    # ── Additional modules from official installation docs ───────────────────
    libclone-perl \
    libdatetime-perl \
    libparams-validate-perl \
    liburi-perl \
    libnet-smtp-ssl-perl \
    libnet-sslglue-perl \
    libjson-perl \
    libcgi-pm-perl \
    libtry-tiny-perl \
    libfile-flock-perl \
    libexception-class-perl \
    # ── LaTeX for PDF generation ─────────────────────────────────────────────
    texlive-latex-recommended \
    texlive-fonts-recommended \
    texlive-latex-extra \
    texlive-lang-german \
    latexmk \
    # ── LibreOffice for OpenDocument conversion ───────────────────────────────
    libreoffice-writer \
    python3-uno \
    # ── GhostScript and html2ps ───────────────────────────────────────────────
    ghostscript \
    html2ps \
    && rm -rf /var/lib/apt/lists/*

# Install CPAN modules not available as Debian packages
RUN cpanm --notest HTML::Query

# Configure Apache: enable required modules, install vhost
COPY docker/apache/kivitendo.conf /etc/apache2/sites-available/kivitendo.conf
RUN a2enmod fcgid rewrite \
    && a2ensite kivitendo \
    && a2dissite 000-default

# Copy application code
WORKDIR /var/www/kivitendo-erp
COPY . .

# Create writable runtime directories (users/pid/ needed by task server)
RUN mkdir -p users/pid spool webdav \
    && chown -R www-data:www-data users spool webdav \
    && chmod +x dispatcher.pl dispatcher.fpl dispatcher.fcgi scripts/task_server.pl

# Entrypoint
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -fs http://localhost/ > /dev/null || exit 1

ENTRYPOINT ["/entrypoint.sh"]
