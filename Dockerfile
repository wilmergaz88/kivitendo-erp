FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    APACHE_RUN_USER=www-data \
    APACHE_RUN_GROUP=www-data \
    APACHE_LOG_DIR=/var/log/apache2

# Install system packages: web server, Perl modules (matching CI), LaTeX, LibreOffice, tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Web server
    apache2 \
    libapache2-mod-fcgid \
    curl \
    # PostgreSQL client (for pg_isready in entrypoint)
    postgresql-client \
    # Perl modules (matching .github/workflows/main.yml)
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
    # LaTeX for PDF generation
    texlive-latex-recommended \
    texlive-fonts-recommended \
    texlive-latex-extra \
    texlive-lang-german \
    latexmk \
    # LibreOffice for OpenDocument conversion
    libreoffice-writer \
    python3-uno \
    # GhostScript for PDF processing
    ghostscript \
    # html2ps
    html2ps \
    && rm -rf /var/lib/apt/lists/*

# Install CPAN modules without apt packages
RUN cpanm --notest HTML::Query

# Copy application code
WORKDIR /var/www/kivitendo-erp
COPY . .

# Create writable runtime directories and set ownership
RUN mkdir -p users spool webdav \
    && chown -R www-data:www-data users spool webdav \
    && chmod 755 users spool webdav \
    && chmod +x dispatcher.pl dispatcher.fpl scripts/task_server.pl

# Configure Apache
COPY docker/apache/kivitendo.conf /etc/apache2/sites-available/kivitendo.conf
RUN a2enmod fcgid rewrite \
    && a2ensite kivitendo \
    && a2dissite 000-default

# Entrypoint
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -fs http://localhost/ > /dev/null || exit 1

ENTRYPOINT ["/entrypoint.sh"]
