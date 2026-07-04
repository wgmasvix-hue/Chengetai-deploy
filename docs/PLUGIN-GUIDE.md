# Plugin Development Guide

A ChengetAi Deploy platform lives in `templates/<name>/` and consists of
two files.

## 1. `plugin.json` — metadata

```json
{
  "name": "koha",
  "displayName": "Koha",
  "description": "Koha library management system",
  "status": "available",
  "category": "library",
  "operations": ["deploy","start","stop","restart","status","logs",
                 "backup","restore","update","remove","edit"],
  "reference": "https://github.com/org/koha-deploy"
}
```

- `status`: `available` or `coming-soon`.
- `reference`: the canonical deployment repository this plugin
  orchestrates. **Do not reimplement deployment logic in the plugin** —
  clone and drive the reference repository.

## 2. `plugin.sh` — operations

Sourced by `lib/utils.sh` with `DEPLOY_DIR`, `DEPLOY_NAME`, `TEMPLATES_DIR`
and the deployment's profile variables in scope. Define these functions:

| Function | Contract |
|---|---|
| `plugin_deploy` | Clone/configure/brand/deploy the reference repo into `$DEPLOY_DIR/engine`. Idempotent. |
| `plugin_start` / `plugin_stop` / `plugin_restart` | Lifecycle via `docker compose`. |
| `plugin_status` | Print service state and health. |
| `plugin_logs` | Follow logs (`"$@"` selects services). |
| `plugin_backup` / `plugin_restore` | Dump/restore data + uploads under `$DEPLOY_DIR/backups`. |
| `plugin_update` | Pull the reference repo and re-apply. |
| `plugin_edit` | Edit branding/config, then rebuild. |
| `plugin_remove [purge]` | Tear down; `purge=1` also deletes data volumes. |

Metadata-only variables: `PLUGIN_NAME`, `PLUGIN_DESCRIPTION`,
`PLUGIN_STATUS`.

### Conventions

- Namespace compose projects per deployment: `-p "chengetai-$DEPLOY_NAME"`.
- Generate secrets; never commit them. Write to the engine `.env`
  (chmod 600).
- Keep branding in `$DEPLOY_DIR/branding/` and copy it over the engine on
  deploy/update so upstream changes never conflict.
- Fail with the shared `error` helper and tell the user the exact command
  to recover.

### Minimum viable stub

```bash
#!/usr/bin/env bash
PLUGIN_NAME="koha"
PLUGIN_DESCRIPTION="Koha library management system"
PLUGIN_STATUS="coming-soon"

plugin_deploy() {
    error "The 'koha' template is not available yet. Currently available: dspace"
}
```

Once you implement the operations against a reference repository, flip
`PLUGIN_STATUS` to `available` and populate `operations` in `plugin.json`.
