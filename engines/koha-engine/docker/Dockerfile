FROM debian:bookworm-slim

LABEL maintainer="ChengetAi Deploy <https://github.com/wgmasvix-hue/Chengetai-deploy>"
LABEL description="Koha 24.05 ILS — official Debian packages"
LABEL org.opencontainers.image.version="24.05"

ENV DEBIAN_FRONTEND=noninteractive \
    KOHA_CONF=/etc/koha/sites/library/koha-conf.xml \
    PERL5LIB=/usr/share/koha/lib

# ── System packages ───────────────────────────────────────────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        wget \
        gnupg2 \
        ca-certificates \
        lsb-release \
        curl \
        netcat-openbsd \
        default-mysql-client \
        gettext-base \
        openssl \
        libapache2-mod-perl2 \
    && rm -rf /var/lib/apt/lists/*

# ── Koha 24.05 official apt repository ──────────────────────────────────────
RUN wget -qO- https://debian.koha-community.org/koha/gpg.asc \
        | gpg --dearmor > /etc/apt/trusted.gpg.d/koha.gpg && \
    echo "deb [signed-by=/etc/apt/trusted.gpg.d/koha.gpg] \
https://debian.koha-community.org/koha 24.05 main" \
        > /etc/apt/sources.list.d/koha.list && \
    apt-get update && \
    apt-get install -y koha-common && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ── Apache modules required by Koha ─────────────────────────────────────────
RUN a2enmod rewrite headers proxy_http cgi && \
    a2dissite 000-default 2>/dev/null || true

# ── Entrypoint ────────────────────────────────────────────────────────────────
COPY docker-entrypoint.sh /usr/local/bin/koha-entrypoint.sh
RUN chmod +x /usr/local/bin/koha-entrypoint.sh

EXPOSE 8080 8081

ENTRYPOINT ["/usr/local/bin/koha-entrypoint.sh"]
