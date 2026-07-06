# ChengetAi Koha Engine

**Production-ready Koha ILS deployment engine for ChengetAi Deploy.**

One command deploys a fully configured Koha 24.05 integrated library system on
Ubuntu 24.04 — complete with MariaDB 11, OpenSearch 2, Memcached, and an Nginx
TLS reverse proxy.

```bash
chengetai deploy koha
```

---

## Stack

| Service | Version | Role |
|---|---|---|
| **Koha** | 24.05 | ILS — Apache + Plack + Zebra |
| **MariaDB** | 11 | Relational database |
| **OpenSearch** | 2 | Catalogue search index |
| **Memcached** | 1.6 | Session and query cache |
| **Nginx** | stable | TLS reverse proxy |

## Architecture

```
                Internet
                    │
            ┌───────▼────────┐
            │  Nginx (TLS)   │  Port 443 → OPAC
            │  Port 8443     │  Port 8443 → Staff
            └───────┬────────┘
                    │ Docker internal network (koha-net)
          ┌─────────▼──────────┐
          │  Koha (Apache)     │
          │  :8080  :8081      │
          └──┬──────┬──────────┘
             │      │
    ┌─────────▼┐  ┌──▼────────┐  ┌────────────┐
    │ MariaDB  │  │ OpenSearch│  │ Memcached  │
    │   :3306  │  │   :9200   │  │   :11211   │
    └──────────┘  └───────────┘  └────────────┘
```

## Quick Start

```bash
# Clone or navigate to the engine
cd engines/koha-engine

# Configure
cp .env.example .env
nano .env        # set SERVER_NAME and domain names at minimum

# Deploy
sudo bash scripts/install.sh
```

Output example:

```
  ╔══════════════════════════════════════════════════════════════╗
  ║              Koha Deployment Complete!                       ║
  ╠══════════════════════════════════════════════════════════════╣
  ║  OPAC URL   : https://192.168.1.10/                         ║
  ║  Staff URL  : https://192.168.1.10:8443/cgi-bin/koha/...    ║
  ╠══════════════════════════════════════════════════════════════╣
  ║  Admin user : koha                                          ║
  ║  Admin pass : Xk7mQr9pLn2vWb4s...                          ║
  ╚══════════════════════════════════════════════════════════════╝
```

## Via ChengetAi Deploy CLI

```bash
chengetai deploy koha          # create profile and deploy
chengetai status  <name>       # check service health
chengetai logs    <name>       # follow logs
chengetai backup  <name>       # create backup
chengetai restore <name>       # restore latest backup
chengetai update  <name>       # update to latest 24.05.x
chengetai stop    <name>       # stop the stack
chengetai start   <name>       # restart the stack
chengetai remove  <name>       # remove containers (keep data)
```

## Directory Layout

```
engines/koha-engine/
├── docker-compose.yml          Full Docker Compose stack
├── engine.yml                  Engine metadata and requirements
├── .env.example                Environment variable template
├── README.md                   This file
├── docker/
│   ├── Dockerfile              Koha 24.05 image (Debian packages)
│   └── docker-entrypoint.sh    Container init + Koha configuration
├── scripts/
│   ├── install.sh              Main installer (idempotent)
│   ├── create-instance.sh      Add a Koha instance to a running stack
│   ├── backup.sh               Database + uploads backup
│   ├── restore.sh              Restore from backup
│   ├── update.sh               Update Koha packages + base images
│   ├── uninstall.sh            Remove stack (--purge to delete data)
│   └── healthcheck.sh          Full stack health check
├── templates/
│   └── nginx.conf.tmpl         Nginx config template (envsubst)
├── config/
│   └── opensearch.yml          OpenSearch single-node configuration
└── docs/
    ├── INSTALL.md              Detailed installation guide
    └── OPERATIONS.md           Day-to-day operations reference
```

## Requirements

- Ubuntu 22.04 or 24.04
- 4 GB RAM minimum (8 GB recommended for production)
- 20 GB free disk
- Docker 24.0+ and Docker Compose v2
- Open ports: 80, 443, 8443

## Configuration

Copy `.env.example` to `.env` and set at minimum:

```env
SERVER_NAME=koha.example.com
OPAC_DOMAIN=catalog.example.com
STAFF_DOMAIN=staff.example.com
```

For HTTPS with Let's Encrypt (requires a real domain):

```env
SSL_MODE=letsencrypt
CERTBOT_EMAIL=admin@example.com
```

All secrets (database passwords, admin password) are generated automatically
if left blank.

## Idempotency

`scripts/install.sh` is fully idempotent — running it a second time will:
- Skip secret generation (existing values in `.env` are preserved)
- Skip SSL cert generation (existing cert is reused)
- Regenerate the Nginx config from the template
- Pull updated base images
- Restart any stopped containers
- Run `koha-upgrade-schema` (a no-op when schema is current)

Existing database and uploaded files are never touched on re-runs.

## Backup and Restore

```bash
# Create a backup
bash scripts/backup.sh

# Restore the most recent backup
bash scripts/restore.sh

# Restore a specific backup
bash scripts/restore.sh backups/koha-backup-20241215-143022
```

## Licence

Released under the [GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0.html),
consistent with Koha's own licence.

## Related

- [Koha Community](https://koha-community.org/)
- [ChengetAi Deploy](https://github.com/wgmasvix-hue/Chengetai-deploy)
- [Koha Docker (official)](https://gitlab.com/koha-community/koha-docker)
