FROM ubuntu:22.04 AS base

ENV DEBIAN_FRONTEND=noninteractive

# Layer A: fetch package lists + heavy document-generation tools
# (~1.5 GB, changes almost never).
# Package lists are kept (NOT cleaned up here) so that Layer B can call
# apt-get install without a second network round-trip.  The lists are only
# removed at the end of Layer B.
RUN apt-get update \
    && apt-get install -y --no-install-recommends software-properties-common \
    && add-apt-repository universe \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    texlive-latex-recommended \
    texlive-fonts-recommended \
    texlive-latex-extra \
    texlive-lang-german \
    latexmk \
    libreoffice-writer \
    python3-uno \
    ghostscript \
    html2ps

# ── Layer B: web server + Perl modules (~400 MB, changes when deps added) ───
# No apt-get update here – inherits the package lists from Layer A.
# Packages removed from Ubuntu 22.04 universe are omitted and installed via
# cpanm in Layer C instead.
RUN apt-get install -y --no-install-recommends \
    apache2 \
    libapache2-mod-fcgid \
    curl \
    postgresql-client \
    libtest-deep-perl \
    libtest-exception-perl \
    libtest-output-perl \
    libwww-perl \
    liburi-find-perl \
    libdbi-perl \
    liblist-moreutils-perl \
    libyaml-perl \
    librose-object-perl \
    librose-db-perl \
    librose-db-object-perl \
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
    libencode-imaputf7-perl \
    libmail-imapclient-perl \
    libhttp-dav-perl \
    libpdf-api2-perl \
    libppi-perl \
    libcryptx-perl \
    libfcgi-perl \
    libclone-perl \
    libdatetime-perl \
    libparams-validate-perl \
    liburi-perl \
    libnet-smtp-ssl-perl \
    libnet-sslglue-perl \
    libjson-perl \
    libcgi-pm-perl \
    libtry-tiny-perl \
    cpanminus \
    build-essential \
    libperl-dev \
    && rm -rf /var/lib/apt/lists/*

# ── Layer C: CPAN modules ────────────────────────────────────────────────────
# Packages removed from Ubuntu 22.04 universe (Exception::Class and others
# were absorbed into Perl itself or dropped; File::MimeInfo, UUID::Tiny,
# Regexp::IPv6, File::Flock, Daemon::Generic, Sys::CPU, PBKDF2::Tiny and
# Digest::Perl::MD5 are no longer shipped as distro packages) plus
# HTML::Query which was never packaged for Debian/Ubuntu.
RUN cpanm --notest \
    Exception::Class \
    File::MimeInfo \
    UUID::Tiny \
    Regexp::IPv6 \
    File::Flock \
    Daemon::Generic \
    Sys::CPU \
    Thread::Pool::Simple \
    PBKDF2::Tiny \
    Digest::Perl::MD5 \
    Badger \
    HTML::Query


# ── app stage: inherits all deps from base, rebuilt on code/config changes ──
FROM base AS app

ENV APACHE_RUN_USER=www-data \
    APACHE_RUN_GROUP=www-data \
    APACHE_LOG_DIR=/var/log/apache2

# Apache wiring (changes rarely — keep above COPY . .)
COPY docker/apache/kivitendo.conf /etc/apache2/sites-available/kivitendo.conf
RUN a2enmod fcgid rewrite \
    && a2ensite kivitendo \
    && a2dissite 000-default

# Application code (invalidated on every code change)
WORKDIR /var/www/kivitendo-erp
COPY . .

RUN mkdir -p users/pid spool webdav \
    && chown -R www-data:www-data users spool webdav \
    && chmod +x dispatcher.pl dispatcher.fpl dispatcher.fcgi scripts/task_server.pl

COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -fs http://localhost/ > /dev/null || exit 1

ENTRYPOINT ["/entrypoint.sh"]
