# Changelog

## 2.0.0

- The DSpace engine is now BUILT IN (templates/dspace/engine/): compose
  stack, frontend Dockerfile, branding and community setup ship inside
  this repository. Deploys no longer clone an external engine repo.
- Each deployment gets a generated random database password (stored only
  in its engine/.env, chmod 600) — no shared secrets in git.
- Deployments run as separate compose projects (chengetai-<name>) with
  per-profile UI_PORT/REST_PORT, so several repositories can share one
  server.
- Community structure is data-driven: edit communities.txt
  (chengetai edit communities) and redeploy.
- Removed the public curl installer (install-online.sh) — ChengetAi
  Deploy is an internal tool; install from a git clone with
  install-cli.sh.
- Legacy deployments made with the external engine are detected and get
  migration instructions (backup, remove, deploy, restore).


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
