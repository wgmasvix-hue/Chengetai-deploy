# ChengetAi Deploy — Architecture Guide

ChengetAi Deploy is an **orchestration platform** for deploying and
operating enterprise open-source software on Linux servers. It does not
reimplement the software it deploys; it clones, configures, brands,
deploys, verifies, monitors and maintains canonical reference
implementations.

## Tiers

```
┌─────────────────────────────────────────────────────────────┐
│  Angular Dashboard (dashboard/)                              │
│  Login · Dashboard · Servers · Deployments · Plugins · …     │
│  JWT in localStorage, HTTP interceptor, route guard          │
└───────────────┬─────────────────────────────────────────────┘
                │ REST + Bearer token
┌───────────────▼─────────────────────────────────────────────┐
│  REST API (api/)  — Express 5                                │
│  routes → controllers → services → repositories              │
│  middleware: auth (JWT+RBAC), validate, audit, rate-limit    │
│  repositories: JSON-file store  |  PostgreSQL (DATABASE_URL) │
└───────────────┬─────────────────────────────────────────────┘
                │ reads the same on-disk state
┌───────────────▼─────────────────────────────────────────────┐
│  CLI (chengetai, lib/, templates/)  — Bash                   │
│  dispatcher → lib/<command>.sh → lib/utils.sh → plugin fns   │
│  deployments/<name>/{profile.env, engine/, branding/, …}     │
└───────────────┬─────────────────────────────────────────────┘
                │ clone + configure + docker compose
┌───────────────▼─────────────────────────────────────────────┐
│  Canonical reference repositories (e.g. your DSpace repo)   │
│  — the actual deployment logic, per platform                 │
└─────────────────────────────────────────────────────────────┘
```

The CLI is the source of truth for what is deployed on a server. The API
**reads** the CLI's `deployments/` directory rather than keeping its own
copy, so the two never drift.

## Plugin model

A platform is a directory under `templates/<name>/`:

- `plugin.json` — machine-readable metadata (name, status, category,
  operations, reference repository). Consumed by `/api/plugins` and the
  dashboard.
- `plugin.sh` — bash functions the CLI dispatches to:
  `plugin_deploy/start/stop/restart/status/logs/backup/restore/update/remove/edit`.

`dspace` is fully implemented as an orchestrator of the reference
repository. `koha`, `moodle`, `ojs`, `nextcloud`, `wordpress` and
`roserag` are registered as planned platforms.

## Deployment lifecycle (dspace)

```
create   → deployments/<name>/profile.env  (institution, admin, ports)
deploy   → clone reference repo → deployments/<name>/engine/
           → apply branding from deployments/<name>/branding/
           → run reference installer with UI_PORT/REST_PORT/DSPACE_NAME,
             generated DB secret, admin env vars, per-deployment
             COMPOSE_PROJECT_NAME
           → installer waits on the backend health endpoint (verify)
start/stop/restart/status/logs/backup/restore/update/remove/edit
           → docker compose against deployments/<name>/engine/
```

## Security model

- **Auth**: JWT bearer tokens; `/api/auth/login` issues them.
- **RBAC**: `admin > engineer > viewer`; mutations require at least
  `engineer`, destructive server ops require `admin`.
- **Secrets**: never in git. Database passwords are generated per
  deployment (chmod 600); the API's JWT secret is env-provided or
  generated once into `DATA_DIR`.
- **Audit**: every mutating request is recorded (user, method, path,
  status, ip).
- **Transport**: run the API and dashboard behind the campus network /
  VPN or a reverse proxy with TLS; do not expose the API to the public
  internet.

## Persistence

The repository layer abstracts storage. Default is a JSON-file store
(single-node, zero-setup). Set `DATABASE_URL` to switch every repository
to PostgreSQL; apply `api/db/schema.sql` first.

## Deferred subsystems

SSH engine, WebSocket monitoring, browser terminal and the AI assistant
are designed but not yet implemented — they require native/runtime
dependencies (`ssh2`, `node-pty`, `xterm.js`, model access) and real
target servers to build against. See `docs/reports/ROADMAP.md`.
