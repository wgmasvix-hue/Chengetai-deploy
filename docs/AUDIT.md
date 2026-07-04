# ChengetAi Deploy — Project Audit

Date: 2026-07-04 · Auditor: Lead Architecture Review · Scope: full repository
plus the reference DSpace repository (`wgmasvix-hue/Bulawayo-polytechnic-DSPACE-`).

## 1. Architecture overview (as audited)

Three loosely-coupled tiers, one shared server filesystem:

| Tier | Tech | State |
|---|---|---|
| CLI (`chengetai`, `lib/`, `templates/`) | Bash | Functional, plugin-based, 15 commands |
| REST API (`api/`) | Node/Express 5 | Skeleton: 3 endpoints, in-memory data, no auth |
| Dashboard (`dashboard/`) | Angular 22 | Boots and builds; dashboard page live, other pages scaffolds |

The CLI is the mature tier: deployment profiles under `deployments/<name>/`,
platform plugins under `templates/<platform>/plugin.sh` exposing
`plugin_deploy/start/stop/restart/status/logs/backup/restore/update/remove/edit`,
a doctor that installs missing dependencies, and installers for internal use.

## 2. Material design conflict (resolved by this audit)

Two competing directions existed in-tree:

- **Branch commit “v2.0.0 built-in engine”**: the DSpace compose stack,
  Dockerfile and branding copied into `templates/dspace/engine/` — the CLI
  repo becomes self-contained but **duplicates** the deployment logic that
  the Bulawayo Polytechnic DSpace repository already maintains.
- **Platform principle (this brief)**: ChengetAi Deploy is an
  *orchestration* platform. The reference repository is the canonical
  DSpace implementation; ChengetAi clones → configures → brands → deploys
  → verifies → maintains. It must never fork that logic.

**Decision: orchestration wins.** The dspace plugin is reworked to drive
the reference repository. The *good parts* of the built-in engine —
generated per-deployment database passwords, port parametrisation,
configurable instance name — are not lost: they are contributed **to the
reference repository**, which is where deployment logic belongs.

Trade-offs accepted: deploys require network access to GitHub (mitigated:
the clone is cached per deployment and re-used), and multi-instance-per-
server remains constrained by the reference stack's fixed container names
(roadmap item for the reference repo, not for ChengetAi).

## 3. Findings by area

### CLI (good shape)
- ✅ Clean dispatcher → command scripts → shared utils → plugin functions.
- ✅ Non-interactive operation via env-guarded prompts throughout.
- ⚠️ `require_engine`/`pcompose` were rewritten for the built-in engine —
  must be re-pointed at the reference stack (fixed in this cycle).
- ⚠️ No shellcheck/CI gate (fixed: CI added).

### REST API (needs the most work)
- ❌ No authentication or authorization of any kind; `cors()` wide open.
- ❌ `/api/dashboard` returns hardcoded fake numbers.
- ❌ Server inventory in memory (lost on restart), exposes host/username.
- ❌ No start script, no validation, no logging strategy, no health route.
- ✅ Express 5 + helmet + morgan foundation and a routes/controllers split
  had been started — kept and extended.

### Angular dashboard
- ✅ Modern standalone-component app; builds after the routing/DI fixes.
- ⚠️ No login flow; API consumed anonymously.
- ⚠️ Pages beyond Dashboard are empty scaffolds (Servers, Deployments,
  Backups, Settings, New Deployment).
- ⚠️ `any` used for API models; no typed interfaces.

### Templates / plugin framework
- ✅ Plugin contract exists and is uniform (bash functions).
- ⚠️ No machine-readable metadata (fixed: `plugin.json` per platform, and
  an API endpoint that lists them).
- ⚠️ koha/moodle/ojs are stubs (correct for now; roadmap).

### Security (cross-cutting)
- ❌ Reference repo carried a **committed database password** in `.env`
  and a second hardcoded password in `install.sh` (fixed at source:
  generated secrets, `.env` untracked).
- ❌ API on a public IP with no auth (fixed: JWT + RBAC + rate limit).
- ⚠️ No audit trail (fixed: audit log middleware + store).
- ⚠️ Secrets policy now: per-deployment generated, chmod 600, never in git.

### Docker
- ✅ Healthcheck-gated startup ordering; named volumes for state.
- ⚠️ Fixed container names in the reference stack limit one DSpace
  instance per server (documented; canonical-repo roadmap item).

### Performance & scalability
- CLI operations are I/O-bound and fine at fleet sizes in the hundreds.
- API dashboard stats are computed on demand from `/proc`, `os` and
  `docker` — cheap; caching unnecessary at internal-tool scale.
- The Angular bundle is 259 kB initial — healthy.
- Real bottleneck when fleets grow: per-server SSH fan-out (roadmap).

### Maintainability
- ⚠️ API needed layering (fixed: config/middleware/controllers/services/
  repositories/routes).
- ⚠️ No tests anywhere (fixed: API smoke tests via `node --test`; CI runs
  them plus `bash -n` over every shell script and the Angular build).
- ⚠️ Docs were a single README (fixed: `docs/` set).

## 4. What this cycle changes

1. dspace plugin → pure orchestrator of the reference repository.
2. Reference repository → parametrised (generated password, ports,
   instance name) with backward-compatible defaults; `.env` untracked.
3. API → layered architecture, JWT auth + RBAC, persisted repositories
   (JSON store by default, PostgreSQL driver when `DATABASE_URL` is set),
   real system stats, health endpoint, audit logging, rate limiting.
4. Dashboard → login + token interceptor + guards; Servers page CRUD;
   typed API models; real data end to end.
5. Plugin metadata (`plugin.json`) + `/api/plugins`; nextcloud/wordpress/
   roserag registered as planned platforms.
6. GitHub Actions CI: shell checks, API tests, dashboard build.
7. Documentation set + formal reviews and roadmaps under `docs/`.

Deferred with rationale (see `docs/reports/PLATFORM-REVIEW.md`): SSH
engine, WebSocket monitoring, browser terminal, AI assistant — each needs
native/runtime dependencies (ssh2, node-pty, xterm.js, model access) that
must be developed against real target servers; shipping untestable
scaffolding would violate the clean-code rules of this brief.
