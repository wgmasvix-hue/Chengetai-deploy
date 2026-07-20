# ChengetAi Deploy v3 — DSpace Deployment Engine (prototype)

A template-driven DSpace engine that generates every configuration file from
a **single source of truth** (`deployment.yml`). It eliminates the hardcoded
IP addresses and duplicated config of the old approach: nothing but the master
config feeds the templates, so no generated file contains a domain, IP or
secret you have to edit by hand.

This is the **prototype** that establishes the architecture. It renders and
validates the full config today; a real launch needs a server with Docker
Hub access (and DNS pointing at it for HTTPS).

## The single source of truth

Everything comes from one file (see `platforms/dspace/deployment.example.yml`):

```yaml
deployment: { id: dare, platform: dspace }
institution: { name: Dare Digital Repository }
domain:   { public: repo.dare.co.zw, ssl: true, dns_provider: manual }
ports:    { ui: 4000, api: 8080 }
database: { engine: postgres }
admin:    { email: admin@dare.co.zw }
```

## Run it

```bash
# 1. Generate + validate (no containers) — renders every file, checks the
#    compose is valid and contains NO hardcoded IPs.
chengetai generate platforms/dspace/deployment.example.yml --out ./dare

# 2. Launch (on a server with Docker + DNS pointed at the domain).
chengetai generate platforms/dspace/deployment.example.yml --out ./dare --up
```

Override secrets non-interactively with `ADMIN_PASSWORD=... POSTGRES_PASSWORD=...`
in the environment; otherwise they're generated and written to `./dare/.env`
(mode 600).

## What it generates

From `platforms/dspace/templates/*.tpl`, into the output dir:

| File | Purpose |
|---|---|
| `docker-compose.yml` | Postgres, Solr, DSpace backend, Angular UI, **Caddy** — default networking (Docker picks the subnet), named volumes, no exposed app ports |
| `Caddyfile` | Reverse proxy + **automatic Let's Encrypt HTTPS**; `/` → UI, `/server` → REST |
| `local.cfg` | DSpace backend config — `dspace.server.url`/`dspace.ui.url` from the domain |
| `config.yml` | Angular UI REST config from the domain |
| `.env` | Single runtime value file (secrets, mode 600) |
| `healthcheck.sh` | Verifies the homepage + REST, and that REST advertises the public URL (no internal IP) |

## The pipeline (structured logging, `[INFO]/[SUCCESS]/[WARNING]/[ERROR]`)

1. **Validate** — config present, `deployment.id` set, Docker/Compose (for `--up`).
2. **Generate** — render all templates; fail hard on any unfilled `{{PLACEHOLDER}}`.
3. **Guard** — assert no hardcoded IPs; `docker compose config` validates.
4. **Launch** (`--up`) — create volumes/network, start the stack behind Caddy.
5. **Health-check** — run the generated `healthcheck.sh`.

On failure during launch the stack is torn down, so a partial deployment is
never left behind.

## URL verification (the definition of success)

Once up with DNS + HTTPS:

```bash
curl https://repo.dare.co.zw/server/api
# expect: "dspaceUI": "https://repo.dare.co.zw"
#         "dspaceServer": "https://repo.dare.co.zw/server"
# and NO internal IP addresses anywhere.
```

## How this maps to the v3 spec

- **No hardcoded IPs** — templates contain only `{{PLACEHOLDERS}}`; a CI-style
  guard fails the build if an IP appears in the output.
- **Single source of truth** — `deployment.yml`; the repository URL/domain
  lives in exactly one place and flows to compose, Caddy, backend and UI.
- **Docker networking** — a per-deployment network with a Docker-assigned
  subnet (no fixed `172.x`), so deployments never collide.
- **Caddy** — native reverse proxy + SSL; no nginx/certbot steps.
- **DNS-agnostic** — `dns_provider: manual` by default; API providers
  (cloudflare/route53) are opt-in and never enforced.
- **Extensible** — the same render → validate → launch pipeline will drive
  Koha, Moodle, OJS and others by adding a `platforms/<name>/templates/` set.

## Upgrading a deployment (with automatic rollback)

Once a deployment is generated and running, upgrade it in place — safely:

```bash
# Upgrade DSpace backend + Angular UI to a specific tag (e.g. 8.1),
# with a snapshot taken first and automatic rollback if it goes wrong.
chengetai upgrade ./dare --to 8.1

# Non-interactive (no confirmation prompt):
chengetai upgrade ./dare --to 8.1 --yes

# Restore an earlier snapshot directly (disaster recovery):
chengetai upgrade ./dare --rollback 20260720-183314
```

What `upgrade` does, with structured `[INFO]/[SUCCESS]/[WARNING]/[ERROR]`
logging:

1. **Snapshot** — copies `docker-compose.yml`, `Caddyfile`, `.env`,
   `local.cfg`, `config.yml`, `healthcheck.sh` **and a `pg_dump` of the
   database** into `./dare/upgrades/<timestamp>/`.
2. **Retag** — rewrites the `dspace/dspace` and `dspace/dspace-angular` image
   tags to the target in `docker-compose.yml`.
3. **Pull + recreate** — `docker compose pull` then `up -d`.
4. **Health-check** — runs the generated `healthcheck.sh` with retries
   (DSpace runs DB migrations on first boot, which is slow).
5. **Roll back on any failure** — restores the snapshot files **and the
   database**, brings the previous version back up, and re-verifies. A bad
   upgrade never leaves the repository down or loses data: the database,
   assetstore, Caddyfile/SSL, branding and `.env` are all preserved.

On success the snapshot is kept as a rollback point, and the exact command to
roll back is printed.

## Status

- ✅ Prototype: `deployment.yml` parsing, template rendering, no-IP guard,
  `docker compose config` validation, structured logging, `--up` pipeline with
  teardown-on-failure — all verified. Confirmed rendering live on a server for
  `repo.dare.co.zw`.
- ✅ Upgrade engine: `chengetai upgrade` with snapshot (config + database),
  image retag, health-check and **automatic rollback** — snapshot/retag/restore
  mechanics verified with a mocked Docker; real end-to-end boot needs a server
  with Docker Hub access.
- ⏳ Next: DNS provider plugins and wiring the generated engine into the
  dashboard.
