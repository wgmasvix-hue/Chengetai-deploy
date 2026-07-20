# Platform Verification Checklist

After deploying a platform on a real server, confirm it actually came up.
The quickest path is the built-in smoke test:

```bash
chengetai verify <name>            # engine present? containers up? web serving?
chengetai verify <name> --timeout 600   # wait longer for slow first boots
```

`verify` exits non-zero if any check fails, so it also works in scripts/CI.
Below is what "good" looks like per platform, plus the manual checks and the
common gotchas when a first boot doesn't come up.

General, for every platform:

1. `chengetai status <name>` — containers listed, health line green.
2. `chengetai verify <name>` — all checks pass.
3. Open the URL in a browser and log in with the admin account (the password
   is in `deployments/<name>/engine/.env`).
4. `chengetai backup <name>` then check a dated folder appears under
   `deployments/<name>/backups/`.

Requirements before you start: 4+ GB RAM (8+ for several at once), 40+ GB
disk, and outbound access to Docker Hub. First boots download images and can
take several minutes — be patient and watch `chengetai logs <name>`.

---

## DSpace

- **Health path:** `/` (UI) and `/server/api` (REST).
- **Ports:** UI `UI_PORT` (4000), REST `REST_PORT` (8080).
- **Admin:** created during deploy, or `chengetai admin <name>`.
- **Boot time:** up to ~6 min (healthcheck `start_period` 360s).
- **Check:** UI loads; `curl -sf http://<ip>:8080/server/api` returns JSON.
- **Gotchas:** "passwords do not match" at deploy → use `chengetai admin
  <name> --generate`. UI loads but search fails on a domain → repoint REST
  (`chengetai domain`), see `docs/DEPLOY-DSPACE.md`.

## Koha

- **Health path:** `/` on OPAC and Staff ports.
- **Ports:** OPAC `UI_PORT` (8080), Staff `REST_PORT` (8081).
- **Admin:** `KOHA_ADMIN_*` in the engine `.env`.
- **Setup:** **one-time web installer** — open the Staff URL and complete the
  wizard before the site is usable.
- **Check:** OPAC and Staff URLs both load; the web installer completes.
- **Gotchas:** a native `koha-common` install on the host will conflict — use
  the containerized deploy only.

## Moodle

- **Health path:** `/login/index.php`.
- **Port:** `UI_PORT` (8080).
- **Admin:** `MOODLE_ADMIN_*` in the engine `.env` (created on first boot —
  no web installer).
- **Boot time:** 5–10 min on first boot (site install).
- **Check:** login page loads; sign in as the admin.
- **Gotchas:** admin password must meet Moodle's policy — the generated one
  does; if you set `ADMIN_PASS`, make it strong.

## OJS

- **Health path:** `/`.
- **Port:** `UI_PORT` (8081).
- **Setup:** **one-time web installer** — open the URL and enter the DB
  details the deploy printed (host `ojs-db`, user `ojs`, the generated
  password, db `ojs`), then create the admin.
- **Check:** installer completes; the journal front page loads afterwards.
- **Gotchas:** config/uploads persist under `engine/volumes/` — don't delete
  them.

## Nextcloud

- **Health path:** `/status.php` (returns JSON with `installed:true`).
- **Port:** `UI_PORT` (80).
- **Admin:** `NC_ADMIN_*` in the engine `.env` (auto-installs on first boot).
- **Check:** `curl -sf http://<ip>:<port>/status.php` shows `installed:true`;
  log in as the admin.
- **Gotchas:** "Access through untrusted domain" → add the host/domain to
  `NC_TRUSTED_DOMAINS` via `chengetai edit config <name>`.

## WordPress

- **Health path:** `/wp-login.php`.
- **Port:** `UI_PORT` (8080).
- **Admin:** `WP_ADMIN_*` in the engine `.env` (created on first boot).
- **Check:** `/wp-login.php` loads; sign in and reach `/wp-admin`.
- **Gotchas:** if you front it with a domain, set the site/home URL in
  wp-admin → Settings, or WordPress may redirect to the old host.

---

## If verify fails

- **Containers not running:** `chengetai logs <name>` — look for a crashed
  DB or an image that failed to pull. `chengetai start <name>` to retry.
- **Web not responding within the timeout:** first boot may just be slow —
  re-run `chengetai verify <name> --timeout 600`.
- **Port already in use:** re-deploy with a different `UI_PORT`/`REST_PORT`.
- **Out of disk / RAM:** `free -h && df -h /`; each stack wants a few GB.
