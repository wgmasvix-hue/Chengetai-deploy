# Managed Deployments — Fleet Control Plane

ChengetAi Deploy can run every deployment as a **managed** deployment:
each server enrols with a central **control plane** (the ChengetAi Deploy
API), checks in continuously, and executes the commands operators push to
it. Nobody runs a deployment "off the grid" — a server must be enrolled and
licensed to deploy, and any deployment can be driven or disabled centrally.

This is the **Model A** design: remote-managed with a kill switch. A running
site keeps serving through short control-plane outages; only an explicit
revoke stops it, and **a revoke never deletes data** — services stop, the
institution's repository is preserved, and it can be reactivated intact.

## Architecture

```
        ChengetAi Control Plane  (the API — hosted by ChengetAi)
        - registry of every enrolled deployment (the fleet)
        - issues enrollment tokens + agent tokens
        - queues commands, tracks health + licence
                 ▲                      │
      heartbeat  │ (agent token)        │ commands + licence
      + health   │                      ▼
   ┌─────────────┴───────────────────────────────────┐
   │  chengetai-agent  (systemd service on each box)  │
   │   • enrols once, stores a root-only agent token  │
   │   • heartbeats every 60s with health + status    │
   │   • runs queued commands via the local CLI       │
   │   • on revoke: stops services (data preserved)   │
   └──────────────────────────────────────────────────┘
```

The control plane is the existing API — the same JWT auth, RBAC and
repository layer. It adds three collections: `fleetAgents` (enrolled
deployments), `enrollmentTokens`, and `fleetCommands` (the command queue).

## Security model

- **Enrollment tokens** admit a new server. Issued by an operator, shown
  once, single-use by default, and stored only as a SHA-256 hash.
- **Agent tokens** authenticate a server thereafter (header `X-Agent-Token`).
  Issued at enrollment, shown once, stored only as a hash. Servers are not
  people — they never carry a user JWT.
- Agent credentials live in a root-only file (`/etc/chengetai/agent.env`,
  mode 600).

## Operator workflow (control plane)

All operator endpoints require a user JWT; roles: `viewer < engineer < admin`.

```
POST   /api/fleet/enrollment-tokens      issue a token (engineer+)   → { token }
GET    /api/fleet/enrollment-tokens      list tokens (engineer+)
GET    /api/fleet/agents                 list the fleet (health, licence, connectivity)
GET    /api/fleet/agents/:id             one deployment
GET    /api/fleet/agents/:id/commands    command history
POST   /api/fleet/agents/:id/commands    queue a command (engineer+)
POST   /api/fleet/agents/:id/revoke      kill switch — stop + revoke licence (admin)
POST   /api/fleet/agents/:id/reactivate  restore licence + start (admin)
DELETE /api/fleet/agents/:id             deregister (admin; does not touch the server)
```

**Remote commands** (allow-list): `start`, `stop`, `restart`, `update`,
`backup`, `restore`, `status`, `logs`. `remove` is deliberately **not**
remotely queueable — a kill switch must never destroy an institution's data,
so deregistration is a separate, explicit action.

## Agent workflow (each server)

Agent endpoints authenticate with the agent token, not a JWT:

```
POST /api/fleet/enroll                   { enrollmentToken, name, ... } → { agentToken, agentId }
POST /api/fleet/heartbeat                report health, receive licence + commands
POST /api/fleet/commands/:id/result      report a command's result
```

CLI:

```bash
# Enrol this server (asks the control plane for an agent token, then
# installs the heartbeat service when run as root).
sudo chengetai enroll <enrollment-token> --control-plane https://control.chengerailabs.co.zw

# The heartbeat service (installed automatically by enroll):
chengetai agent status        # show enrolment + service state
chengetai agent once          # one heartbeat now (useful for testing)
sudo chengetai agent install  # (re)install the systemd service
sudo chengetai agent uninstall

# Service logs:
journalctl -u chengetai-agent -f
```

## The enrollment gate ("no independent deployments")

`chengetai deploy` refuses to run on a **managed** server that isn't
enrolled. A server is managed when a control plane is configured (its agent
config has a `CONTROL_PLANE_URL`, or `CHENGETAI_CONTROL_PLANE` is set) or when
`CHENGETAI_REQUIRE_ENROLLMENT=1`. In that case:

```
[ERROR] This server must be enrolled with ChengetAi before deploying.
  Run: sudo chengetai enroll <enrollment-token> --control-plane <url>
```

Standalone servers with no control plane configured are unaffected, so
existing deployments keep working — the gate is backward compatible. To make
a fleet mandatory, ship servers with the control plane pre-configured (or set
`CHENGETAI_REQUIRE_ENROLLMENT=1`) and hand out enrollment tokens.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `FLEET_HEARTBEAT_SECONDS` | `60` | how often agents check in |
| `FLEET_OFFLINE_AFTER_SECONDS` | `180` | miss window before "offline" |
| `FLEET_ENROLL_TTL_MINUTES` | `1440` | enrollment-token lifetime |
| `CHENGETAI_CONTROL_PLANE` | – | control-plane URL for the CLI/agent |
| `CHENGETAI_REQUIRE_ENROLLMENT` | `0` | force the enrollment gate |

## Data safety guarantees

- **Revoke stops, never wipes.** A revoked deployment's containers stop; its
  database, assetstore and config volumes are untouched. `reactivate`
  restores service.
- **Outage-tolerant.** If the control plane is briefly unreachable, agents
  log the miss and keep the site running — they act only on explicit
  commands, never on silence.
- **Deregister is control-plane-only.** Removing an agent from the fleet
  stops managing the server; it does not reach out and delete anything.
