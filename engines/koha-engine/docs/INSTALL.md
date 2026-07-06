# ChengetAi Koha Engine — Installation Guide

## Prerequisites

| Requirement | Minimum |
|---|---|
| OS | Ubuntu 22.04 or 24.04 |
| RAM | 4 GB (8 GB recommended) |
| Disk | 20 GB free |
| Docker | 24.0+ |
| Docker Compose | 2.20+ (v2 plugin) |
| Open ports | 80, 443, 8443 |

Install Docker if not already present:

```bash
curl -fsSL https://get.docker.com | sudo bash
sudo usermod -aG docker $USER
```

## Quick Start

```bash
# 1. Configure the environment
cp .env.example .env
nano .env          # set SERVER_NAME, OPAC_DOMAIN, STAFF_DOMAIN at minimum

# 2. Run the installer
sudo bash scripts/install.sh
```

The installer:
- Validates Docker and Docker Compose
- Generates cryptographically random secrets for any blank credentials
- Creates a self-signed TLS certificate (or runs certbot for Let's Encrypt)
- Generates the Nginx reverse-proxy configuration
- Pulls and builds all Docker images
- Starts the full stack (Koha, MariaDB, OpenSearch, Memcached, Nginx)
- Waits for all services to become healthy
- Prints the OPAC URL, Staff URL, and admin credentials

## Domain Configuration

### IP-based access (default)

Leave `OPAC_DOMAIN` and `STAFF_DOMAIN` set to your server's IP address or
`localhost`. Access the interfaces at:

- OPAC:  `https://<SERVER_IP>:443/`
- Staff: `https://<SERVER_IP>:8443/cgi-bin/koha/mainpage.pl`

### Named domains

Set real FQDNs in `.env`:

```env
SERVER_NAME=koha.example.com
OPAC_DOMAIN=catalog.example.com
STAFF_DOMAIN=staff.example.com
```

For Let's Encrypt certificates, also set:

```env
SSL_MODE=letsencrypt
CERTBOT_EMAIL=admin@example.com
```

Ports 80 and 443 must be reachable from the internet for ACME validation.

## Post-Install Steps

### Confirm health

```bash
bash scripts/healthcheck.sh
```

### Initial Koha configuration

Log into the Staff interface and complete:

1. **Administration → System Preferences** — set library timezone, currency, etc.
2. **Administration → Libraries** — verify or add library branches.
3. **Cataloguing → Marc Frameworks** — import a MARC 21 or UNIMARC framework.
4. **Administration → Search Engine Configuration (Elasticsearch)** — set the
   index to `koha_<instance>` and run a full reindex:

```bash
docker exec <project>-koha-1 \
    koha-elasticsearch --rebuild -d -v library
```

## Uninstallation

Remove containers (preserve data):

```bash
bash scripts/uninstall.sh
```

Remove everything including data volumes:

```bash
bash scripts/uninstall.sh --purge
```
