# ORCID integration

Turn a deployed repository into part of the global research ecosystem: let
researchers **sign in with ORCID** and link their ORCID iD to their profile.
ORCID is DSpace-native — ChengetAi wires it up against the already-running
backend, so there is no redeploy.

## One-time: register an ORCID application

ORCID issues the client credentials. This is the only step ChengetAi cannot do
for you (it needs your ORCID account).

1. Sign in at **https://orcid.org** (or **https://sandbox.orcid.org** for
   testing) → **Your name → Developer Tools**.
2. Register an application. You'll get a **Client ID** (`APP-XXXXXXXX`) and a
   **Client secret**.
3. Add the **redirect URI** ChengetAi prints when you enable ORCID (see below).
   It is your repository's server URL + `/api/authn/orcid`, for example:
   - `https://repo.dare.co.zw/server/api/authn/orcid` (behind a domain), or
   - `http://144.91.125.128:8080/server/api/authn/orcid` (bare IP, testing).

> Use **sandbox** first. Sandbox and production are separate ORCID systems with
> separate apps and credentials.

## Enable it

```bash
# Sandbox (default) — safe for first setup:
chengetai orcid dare --client-id APP-XXXXXXXX --client-secret THE_SECRET

# Production, once you've tested:
chengetai orcid dare --client-id APP-XXXXXXXX --client-secret THE_SECRET --production
```

Keep the secret out of your shell history by exporting it instead:

```bash
export ORCID_CLIENT_SECRET='THE_SECRET'
chengetai orcid dare --client-id APP-XXXXXXXX --production
```

ChengetAi writes the settings into the deployment's `local.cfg`, adds
`OrcidAuthentication` to the login stack (password login stays enabled too),
restarts the backend, and prints the exact redirect URI to register. Once the
backend is back up, users see **"Sign in with ORCID"** on the login screen —
the frontend advertises it automatically, no UI rebuild needed.

## Check or turn off

```bash
chengetai orcid dare --status     # enabled? which environment? client id? redirect URI?
chengetai orcid dare --disable    # remove ORCID; password login remains
```

## What gets written

A single managed block in `deployments/<name>/engine/dspace/config/local.cfg`
(the only config file the campus stack bind-mounts into the backend, so a
restart applies it):

```properties
# >>> ChengetAi ORCID (managed — do not edit between these markers) >>>
orcid.application-client-id = APP-XXXXXXXX
orcid.application-client-secret = ...
orcid.domain-url = https://orcid.org            # or sandbox.orcid.org
orcid.api-url = https://api.orcid.org/v3.0
orcid.public-url = https://pub.orcid.org/v3.0
orcid.synchronization-enabled = true
plugin.sequence.org.dspace.authenticate.AuthenticationMethod = \
    org.dspace.authenticate.PasswordAuthentication, org.dspace.authenticate.OrcidAuthentication
# <<< ChengetAi ORCID (managed) <<<
```

Re-running `chengetai orcid` replaces this block in place (idempotent) — it
never duplicates or disturbs the rest of `local.cfg`.

## Options

| Option | Meaning |
|---|---|
| `--client-id APP-XXXX` | ORCID application client ID (required to enable) |
| `--client-secret SECRET` | ORCID client secret (or export `ORCID_CLIENT_SECRET`) |
| `--sandbox` | Use ORCID sandbox (default) |
| `--production` / `--live` | Use production ORCID |
| `--status` | Report current ORCID configuration |
| `--disable` | Remove ORCID; keep password login |
| `--no-restart` | Write config but don't restart the backend |

## Troubleshooting

- **"redirect_uri_mismatch" on ORCID's site** — the redirect URI registered in
  your ORCID app must match exactly what `--status` prints (scheme, host, port,
  path). Put the repository behind a domain first (`chengetai domain`) if you
  want a clean `https://…` URI, then re-run `chengetai orcid … --production`.
- **No ORCID button appears** — confirm the backend restarted and is healthy
  (`chengetai status <name>`); the config only takes effect after the backend
  reboots.

## Roadmap

ORCID is the first research-ecosystem integration. Planned follow-ons: Crossref,
DataCite, OpenAlex, OpenAIRE, Sherpa Romeo and ROR.
