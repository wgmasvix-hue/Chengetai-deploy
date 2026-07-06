# ChengetAi Koha Engine — Operations Guide

## Daily Operations

### Check status

```bash
bash scripts/healthcheck.sh
# or via ChengetAi CLI:
chengetai status <deployment>
```

### View logs

```bash
# All services
docker compose --env-file .env -f docker-compose.yml logs -f

# Specific service
docker compose --env-file .env -f docker-compose.yml logs -f koha
docker compose --env-file .env -f docker-compose.yml logs -f db

# via CLI
chengetai logs <deployment>
chengetai logs <deployment> koha
```

### Start / Stop

```bash
chengetai start <deployment>
chengetai stop  <deployment>
```

## Backup and Restore

### Create a backup

```bash
bash scripts/backup.sh
# Backup saved to: engines/koha-engine/backups/koha-backup-YYYYMMDD-HHMMSS/
```

Backup contents:
- `koha-db.sql.gz` — Full MariaDB dump (compressed)
- `koha-uploads.tar.gz` — Patron-uploaded files
- `koha-config.tar.gz` — Koha site configuration
- `backup.meta` — Metadata (date, instance, version)

### Restore from backup

```bash
# Restore from a specific backup:
bash scripts/restore.sh backups/koha-backup-20241215-143022

# Restore from most recent backup (no argument):
bash scripts/restore.sh
```

### Scheduled backups

Add to crontab for nightly backups:

```cron
0 2 * * * /path/to/engines/koha-engine/scripts/backup.sh >> /var/log/koha-backup.log 2>&1
```

## Updates

```bash
bash scripts/update.sh
# or:
chengetai update <deployment>
```

The update script:
1. Creates a pre-update backup
2. Pulls latest MariaDB/OpenSearch/Memcached/Nginx images
3. Rebuilds the Koha image with the latest 24.05.x packages
4. Restarts the stack
5. Runs database schema migrations automatically on next Koha start

## Reindexing OpenSearch

Full reindex (required after upgrading Koha or changing indexing settings):

```bash
docker exec <project>-koha-1 \
    koha-elasticsearch --rebuild -d -v library
```

Rebuild only bibliographic records:

```bash
docker exec <project>-koha-1 \
    koha-elasticsearch --rebuild -b -v library
```

## Adding a Koha Instance

To run multiple library instances in the same stack:

```bash
bash scripts/create-instance.sh <instance-name>
```

## Editing Configuration

Edit `koha-conf.xml` inside the running container:

```bash
docker exec -it <project>-koha-1 nano /etc/koha/sites/library/koha-conf.xml
```

Restart Koha after changes:

```bash
chengetai restart <deployment>
```

System preferences and OPAC appearance are managed through the Staff web UI:

- `https://<server>:8443/cgi-bin/koha/admin/preferences.pl`

## Container Reference

| Container | Role |
|---|---|
| `<project>-koha-1` | Koha 24.05 (Apache + Plack + Zebra) |
| `<project>-db-1` | MariaDB 11 |
| `<project>-opensearch-1` | OpenSearch 2 search index |
| `<project>-memcached-1` | Memcached session cache |
| `<project>-nginx-1` | Nginx TLS reverse proxy |

## Volumes

| Volume | Contents |
|---|---|
| `<project>_koha_db_data` | MariaDB data files |
| `<project>_koha_os_data` | OpenSearch index data |
| `<project>_koha_uploads` | Koha uploaded files |
| `<project>_koha_config` | Koha site configuration |
| `<project>_koha_ssl` | Nginx TLS certificates |

## Troubleshooting

### Koha won't start

```bash
docker logs <project>-koha-1 | tail -50
```

### Database connection errors

Verify MariaDB is healthy:

```bash
docker inspect <project>-db-1 --format '{{.State.Health.Status}}'
docker logs <project>-db-1 | tail -20
```

### OpenSearch cluster red

```bash
docker exec <project>-opensearch-1 \
    curl -s http://localhost:9200/_cluster/health | python3 -m json.tool
```

Force reindex after fixing:

```bash
docker exec <project>-koha-1 \
    koha-elasticsearch --rebuild -d -v library
```

### Nginx SSL errors (self-signed certificate)

Browsers will warn about self-signed certificates. To bypass:
- Firefox: "Advanced" → "Accept the Risk"
- Chrome: type `thisisunsafe` on the warning page
- For production, use `SSL_MODE=letsencrypt` in `.env` and re-run `install.sh`
