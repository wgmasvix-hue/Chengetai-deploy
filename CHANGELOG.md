# Changelog

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
