# ChengetAi Deploy — Platform Review & Roadmap

Prepared as the Lead Architect deliverables. Companion to `docs/AUDIT.md`.

---

## 1. Architecture review

ChengetAi Deploy is now a three-tier orchestration platform with a clean
separation of concerns:

- **CLI (Bash)** — mature. Dispatcher → command scripts → shared utils →
  platform plugins. Source of truth for on-disk deployment state.
- **REST API (Express 5)** — rebuilt into config / middleware /
  repositories / services / controllers / routes. Stateless request
  handling; storage abstracted behind a repository interface.
- **Dashboard (Angular 22)** — standalone components, auth guard +
  interceptor, typed models, live pages.

The defining decision: **ChengetAi orchestrates canonical reference
repositories; it does not reimplement deployment logic.** The DSpace
plugin clones and drives the Bulawayo Polytechnic repository. Parametrising
that repository (ports, instance name, generated secret) was done *in the
reference repository*, upstream of ChengetAi.

**Verdict:** the foundation is enterprise-grade and extensible. The plugin
contract makes new platforms additive. The API layering supports growth
without rewrites.

## 2. Repository improvement report

Delivered this cycle:

- Orchestration refactor of the dspace plugin; per-deployment branding.
- Reference repo: generated DB password, `.env` untracked, ports/name
  parametrised (backward compatible).
- API: JWT auth, RBAC, validation, audit logging, rate limiting, real
  system stats, health, plugins and deployments endpoints, persisted
  server inventory, JSON/PostgreSQL repository drivers, 10 integration
  tests.
- Dashboard: login flow, guard, interceptor, typed models, live Dashboard
  / Servers (CRUD) / Deployments pages, working sign-out.
- CI: shell checks, API tests, dashboard build, dependency audit.
- Docs: audit, architecture, plugin guide, API reference, this review.

Still open (tracked below): SSH engine, WebSocket monitoring, terminal, AI
assistant, remaining dashboard pages (Docker, Logs, Terminal, Monitoring,
Users, Settings, AI, New-Deployment wizard), and merging the API-driven
`deploy` action so the dashboard can trigger deployments (today the CLI
performs them).

## 3. Security review

**Fixed**

- Committed database password removed from the reference repo; secrets
  now generated per deployment (chmod 600) and untracked.
- API moved from zero-auth to JWT + RBAC; mutations audited; login and
  global rate limits; helmet; body-size cap; input validation.
- JWT secret is env-provided or generated once into `DATA_DIR`, never in
  git.

**Outstanding (priority order)**

1. **Network exposure** — the target server appears to expose the API on a
   public IP. Bind to localhost/VPN or put it behind a TLS reverse proxy;
   never expose `/api` to the internet. *(Operational, do now.)*
2. **TLS** — no HTTPS termination in-repo; add via reverse proxy.
3. **Server credentials at rest** — when SSH lands, private keys/passwords
   must be encrypted at rest (libsodium sealed boxes), not stored plain.
4. **Token storage** — dashboard keeps the JWT in localStorage (XSS-
   reachable). Acceptable for an internal tool; consider httpOnly cookies
   if exposure widens.
5. **Secret scanning** — add gitleaks to CI to prevent regressions.

## 4. Performance review

- CLI operations are I/O-bound and fine into the hundreds of servers.
- API dashboard stats are computed on demand from `/proc`, `df` and
  `docker` (~250 ms CPU sample); negligible load, no caching needed at
  internal scale.
- Dashboard initial bundle 330 kB / ~84 kB transfer — healthy; lazy-load
  routes when the page count grows.
- Anticipated bottleneck: SSH fan-out across a large fleet — solve with a
  bounded worker pool and per-server status caching when SSH lands.

## 5. Technical debt report

| Item | Severity | Note |
|---|---|---|
| `dashboard` was a broken gitlink | resolved | Source now committed. |
| Empty dashboard pages (Docker/Logs/Terminal/Monitoring/Users/AI) | medium | Scaffolds present; wire as backends land. |
| New-Deployment page is static | medium | Needs a deploy API + wizard. |
| API deploy/lifecycle not exposed | medium | Dashboard reads state; can't yet act. CLI is the actuator. |
| No E2E test across all three tiers | low | Unit/integration exist per tier. |
| shellcheck advisory-only in CI | low | Tighten to enforced once findings cleared. |
| koha/moodle/ojs/nextcloud/wordpress/roserag stubs | expected | Additive; implement per demand. |

## 6. Version 1.0 roadmap

Goal: a dependable internal tool for ChengetAi engineers.

1. **Deploy API** — `POST /api/deployments` and lifecycle actions that
   shell out to the CLI, so the dashboard can create/start/stop/backup.
2. **New-Deployment wizard** — dashboard form → deploy API.
3. **Users page + user CRUD API** — admin manages engineers/viewers.
4. **Settings page** — change password, API/CORS config surface.
5. **Harden deployment** — reverse proxy + TLS recipe, systemd units for
   API and dashboard, gitleaks in CI.
6. **One real end-to-end DSpace deploy** driven from the dashboard on a
   campus server (the environment here blocks Docker Hub, so this must be
   validated on real infrastructure).

## 7. Version 2.0 vision

A universal, multi-server deployment control plane:

- **SSH engine** (`ssh2`): manage unlimited remote servers; run the CLI
  remotely; upload/download files; encrypted credential vault.
- **Real-time monitoring** (WebSockets): CPU/RAM/disk/containers/certs
  streamed to the dashboard.
- **Browser terminal** (`xterm.js` + `node-pty`): multi-tab SSH in the UI.
- **AI Assistant** (ChengetAi): deployment advisor, log analysis, health
  diagnosis, config validation — built on the Claude API, grounded in the
  platform's own telemetry, evolving toward natural-language deployment.
- **More platforms**: Koha, Moodle, OJS, Nextcloud, WordPress, ROSERAG,
  each orchestrating its canonical repository.
- **Server groups & multi-tenancy**: fleet views, per-group RBAC.

## 8. Recommended next milestones

1. Deploy API + New-Deployment wizard (unlocks the dashboard's core value).
2. Users/Settings pages + user management API (completes RBAC surface).
3. Deployment hardening: TLS reverse proxy, systemd, gitleaks.
4. SSH engine (opens multi-server; prerequisite for terminal & remote
   monitoring).
5. WebSocket monitoring, then browser terminal.
6. AI assistant (advisory first, actions later).

## Design decisions & trade-offs recorded

- **Orchestrate vs. bundle the engine.** Chose orchestration per the
  platform principle; accepted a GitHub dependency at deploy time
  (mitigated by per-deployment caching).
- **JSON store default, PostgreSQL optional.** Zero-setup for the common
  single-node case; same interface scales to PostgreSQL via `DATABASE_URL`.
- **API reads the CLI's state** instead of owning its own deployment
  records — one source of truth, at the cost of the API not yet being able
  to *act*. The v1.0 deploy API closes that gap deliberately, with the CLI
  remaining the actuator.
- **Deferred untestable subsystems** (SSH/monitoring/terminal/AI) rather
  than commit scaffolding that can't be exercised here — consistent with
  the brief's clean-code rule. Each is specified in the roadmap with its
  required dependency.
