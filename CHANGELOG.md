# Changelog

## 2.15.0

- **Scheduled backups, retention, and off-site.** `chengetai backup <name>`
  gains `--schedule daily|weekly|monthly` (installs a per-deployment systemd
  timer), `--keep N` (prune to the N most recent backups — defaults to 7 for
  scheduled ones), and `--offsite 'CMD'` (run a command such as an `rsync` or
  `aws s3 sync` after each backup, with `$BACKUP_DIR` set, to push the backup
  off the server). Settings are remembered in the deployment's `backup.env`;
  `--unschedule` removes the timer. A plain `chengetai backup` is still a
  one-off, now applying retention/off-site if configured.

## 2.14.0

- **Hardened the manager UI.** It now binds to **127.0.0.1** by default
  instead of `0.0.0.0`, so it is never on an open port. The dashboard reaches
  it through a new **API reverse proxy**
  (`/api/deployments/:name/manager/proxy`) that forwards to the
  localhost-bound manager and is gated by the manager token — so manager
  traffic rides the dashboard's channel (HTTPS when fronted by nginx/Caddy)
  rather than a separate plaintext port. `--bind` can still widen it for
  advanced use, but it's discouraged.

## 2.13.1

- **Robust `chengetai update`.** The CLI update now FORCE-ALIGNS to the
  remote (`fetch` + `checkout -f`) instead of a fast-forward pull, so it
  works even after the branch history was rewritten (a plain pull would fail
  with "Not possible to fast-forward"). Untracked runtime state
  (deployments/, api/.env, api/data) is preserved. Update also re-points the
  `/usr/local/bin/chengetai` launcher at this install and warns if a
  different, stale `chengetai` is shadowing it on your PATH; `install-cli.sh`
  gained the same shadow check.

## 2.13.0

- **`chengetai verify [name]` — per-platform smoke test.** Checks the engine
  is present, the containers are running, and the web endpoint is actually
  serving (probing each platform's health path, with retries for slow first
  boots). Exits non-zero on failure, so it doubles as a health gate in
  scripts/CI. Plugins declare their health path via `PLUGIN_HEALTH_PATH`
  (Moodle `/login/index.php`, Nextcloud `/status.php`, WordPress
  `/wp-login.php`; others default to `/`). New `docs/VERIFICATION.md` is a
  per-platform checklist with expected results and common gotchas.

## 2.12.0

- **New platforms: Nextcloud and WordPress.** `chengetai deploy nextcloud`
  (official Nextcloud + MariaDB, auto-installs from the profile) and
  `chengetai deploy wordpress` (official Bitnami WordPress + MariaDB, admin
  created on first boot). Both ship the full lifecycle, per-deployment
  generated passwords (`.env`, mode 600) and a single web port, and appear
  automatically in the dashboard's New Deployment picker (it lists every
  available plugin). Six platforms are now available: DSpace, Koha, Moodle,
  OJS, Nextcloud, WordPress.

## 2.11.0

- **New platform: OJS (Open Journal Systems).** `chengetai deploy ojs`
  stands up OJS from PKP's official `pkpofficial/ojs` image with MariaDB,
  with per-deployment generated passwords and port, and the full lifecycle
  (start/stop/status/logs/backup/restore/update/edit/remove). Setup finishes
  in OJS's one-time web installer (the deploy prints the database details).
  Config, uploads and public files are persisted on the host so they survive
  container recreation.

## 2.10.0

- **New platform: Moodle.** `chengetai deploy moodle` stands up Moodle from
  the official Bitnami images (Moodle + MariaDB), with per-deployment
  generated passwords and port, and the full lifecycle
  (start/stop/status/logs/backup/restore/update/edit/remove). The
  administrator is created on first boot from the profile — no web
  installer — and the admin password is stored in the engine `.env`
  (mode 600). A single web port (UI_PORT).

## 2.9.0

- **`chengetai status` overview.** With no name and several deployments it
  now prints an at-a-glance table — name, platform, whether it's deployed,
  whether it's running, the URL, and (if installed) the manager service
  state — instead of erroring "specify one". A single deployment still shows
  the detailed view, and `chengetai status <name>` is the detailed view for
  a named one.

## 2.8.1

- **`doctor` checks manager services.** The readiness report now lists each
  deployment's manager service: a running one passes, and one that was
  installed but isn't running is flagged (with the `systemctl restart`
  command to fix it). It's a warning only — never a missing dependency, so
  it can't block a deploy.

## 2.8.0

- **Always-on manager service.** `chengetai manager <name> --install`
  registers a per-deployment systemd service (a `chengetai-manager@<name>`
  instance) that keeps the manager UI running and restarts it on boot;
  `--uninstall` removes it, `--status` shows state + URL. The access token
  and port are now **persisted** per deployment (`manager.env`, mode 600),
  so the URL is stable across restarts. The dashboard's Manager button and
  API return the running service's URL directly (liveness-checked) and only
  cold-start a manager when none is running.

## 2.7.0

- **Dashboard: "Manager" button.** Each deployment on the dashboard now has
  a Manager button that starts (or reuses) that deployment's local manager
  UI and opens it in a new tab. New API endpoint
  `POST /deployments/:name/manager` spawns the manager detached, parses the
  URL + token it prints, tracks it (idempotent — an already-running manager
  is reused), and returns a link on the same host the dashboard was reached
  on. Engineer role required.

## 2.6.0

- **`chengetai manager [name]`** — a small, local, per-deployment web
  console. Serves a single self-contained page (zero npm dependencies,
  Node built-ins only) bound to `127.0.0.1` and gated by a per-session
  token: check status, start/stop/restart, back up, view recent logs, and
  create/reset the administrator. Every action shells out to the same
  `chengetai` CLI (one code path); actions are allow-listed. The default
  port derives from the deployment's UI port so multiple managers never
  collide. Reach it via an SSH tunnel.

## 2.5.0

- **`chengetai domain [name] <domain>`** — one command puts a deployment
  behind a real domain with **automatic HTTPS via Caddy** (Let's Encrypt,
  self-renewing). It installs Caddy, writes a per-deployment site that
  reverse-proxies the UI and REST under one origin, reloads Caddy, and
  repoints DSpace at the HTTPS URL (frontend `config.yml` + backend public
  URL, with `.bak` backups), then rebuilds/restarts. Replaces the manual
  nginx + certbot setup. `--caddy-only` sets up just the proxy;
  `--email` sets the ACME contact.

## 2.4.0

- **Managed deployments (fleet control plane).** Servers enrol with a
  central control plane (the API), heartbeat, and execute commands pushed
  from the dashboard. Operators can start/stop/restart/update/backup any
  deployment remotely, and **revoke/reactivate** a deployment's licence —
  a kill switch that stops services but never deletes data. `chengetai
  deploy` refuses on a managed-but-unenrolled server; standalone servers
  are unaffected (backward compatible). New: `chengetai enroll`,
  `chengetai agent`; see `docs/FLEET.md`.
- **`chengetai admin`** — create or reset a deployment's administrator
  against the already-running backend, no redeploy. Fixes the "passwords
  do not match" dead-end; `--generate` mints a random password. Deploy now
  prints a tidy summary (URLs + how to manage the admin).
- This release consolidates ChengetAi Deploy onto the plugin architecture
  as the single canonical line (the version proven in production).

## 2.3.0

- New platform: **Koha** library management system. `chengetai deploy koha`
  builds Koha from its official koha-common Debian package with MariaDB,
  per-deployment generated passwords and ports (OPAC on UI_PORT, Staff on
  REST_PORT), and the full lifecycle (start/stop/backup/restore/update/
  remove). Koha's one-time web installer completes setup in the browser.

## 2.2.0

- One-command installer (install-online.sh): curl | sudo bash installs
  or updates the whole platform. Idempotent and resumable — safe to
  re-run after an SSH drop; preserves existing deployments, admin
  password and API data (all kept out of git). Optional --with-dspace
  deploys a repository in the same run. Installs tmux so long runs
  survive dropped connections.

## 2.1.0

- The dashboard can now DEPLOY, not just observe: POST /api/deployments
  creates a profile and runs the deploy as a tracked background job; the
  New Deployment wizard streams the live job log. Every action shells out
  to the CLI, keeping one code path for deployment logic.
- Deployment lifecycle over REST: start/stop/restart/backup/update as
  jobs, synchronous status, delete (with purge). Jobs API tails output
  incrementally.
- User management (admin): list/create/update/delete with role
  validation and a last-admin guard. Users and Settings dashboard pages.
- Hardening: systemd unit (API bound to localhost), nginx reverse-proxy
  + TLS recipe, firewall guidance (deploy/), and gitleaks secret scan in
  CI. See deploy/README.md.

## 2.0.0

- ChengetAi Deploy is formally an ORCHESTRATION platform: the dspace
  plugin clones, configures, brands, deploys and maintains the canonical
  Bulawayo Polytechnic DSpace repository instead of duplicating its
  deployment logic. The parametrisation this needs (generated database
  password, UI_PORT/REST_PORT, DSPACE_NAME) was contributed upstream to
  the reference repository with backward-compatible defaults.
- Per-deployment branding lives in deployments/<name>/branding/ and is
  applied over the engine on deploy/update, so canonical updates never
  conflict with local branding.
- Deployment volumes are namespaced per deployment
  (COMPOSE_PROJECT_NAME=chengetai-<name>); profiles carry UI_PORT and
  REST_PORT.
- Every platform template now ships machine-readable metadata
  (templates/<name>/plugin.json); nextcloud, wordpress and roserag are
  registered as planned platforms alongside koha, moodle and ojs.
- Removed the public curl installer (install-online.sh) — ChengetAi
  Deploy is an internal tool; install from a git clone with
  install-cli.sh.


## 1.2.0

- New `chengetai edit <component> [name]` command: edit a deployment's
  logo, favicon or UI config and rebuild the frontend so the change
  goes live.
- Merged the Angular dashboard integration work from `main`.

## 1.1.0

- Restructured as a multi-platform deployment tool with a plugin system:
  platforms live in `templates/<name>/plugin.sh` (dspace available;
  koha, moodle and ojs coming soon).
- Full command set: install, doctor, create, deploy, start, stop,
  restart, status, logs, backup, restore, update, remove, version, help.
- Deployment profiles under `deployments/<name>/` with per-deployment
  engine and backups.
- `doctor` installs missing dependencies (curl, git, iproute2, Docker,
  Docker Compose) directly as root or through sudo otherwise, and
  `deploy` aborts when dependencies remain missing.
- One-command online installer (`install-online.sh`) plus local
  installer (`install-cli.sh`) and in-place updates via
  `chengetai install` / `chengetai update`.
- Admin credentials flow through the environment to the DSpace engine
  installer without re-prompting; admin first/last name configurable.

## 1.0.0

- Initial ChengetAi Deploy CLI with deploy wizard and doctor readiness
  check for DSpace 8 campus deployments.
