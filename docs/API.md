# API Reference

Base URL: `http://<server>:3000`. All `/api/*` routes except `/api/health`
and `/api/auth/login` require `Authorization: Bearer <token>`.

## Auth

| Method | Path | Role | Body | Notes |
|---|---|---|---|---|
| POST | `/api/auth/login` | public | `{ email, password }` | Rate-limited. Returns `{ token, user }`. |
| GET | `/api/auth/me` | any | — | Current token's user. |
| POST | `/api/auth/change-password` | any | `{ currentPassword, newPassword }` | |

## Platform

| Method | Path | Role | Description |
|---|---|---|---|
| GET | `/api/health` | public | Liveness: `{ status, version, uptime }`. |
| GET | `/api/dashboard` | any | Live stats: cpu, memory, disk, containers, repositories, uptime, server, hostname. |
| GET | `/api/plugins` | any | Platform catalogue from `plugin.json` files. |
| GET | `/api/deployments` | any | Deployments on this server (from the CLI's `deployments/`). |

## Servers (Task 6)

| Method | Path | Role | Description |
|---|---|---|---|
| GET | `/api/servers` | any | List servers. |
| POST | `/api/servers` | engineer | Add a server. `{ name, host, port?, username, authMethod?, os?, group? }`. |
| PATCH | `/api/servers/:id` | engineer | Update fields. |
| DELETE | `/api/servers/:id` | admin | Remove a server. |

## Roles

`admin > engineer > viewer`. Viewers read; engineers mutate; admins also
delete servers and manage users.

## Configuration

See `api/.env.example`. Key variables: `PORT`, `JWT_SECRET`,
`JWT_EXPIRES_IN`, `ADMIN_EMAIL`, `ADMIN_PASSWORD`, `CORS_ORIGIN`,
`DATABASE_URL`, `CHENGETAI_DEPLOYMENTS_DIR`.

## Errors

JSON `{ "error": "message" }`; validation failures add
`{ "details": [ ... ] }`. Status codes: 400 validation, 401
unauthenticated, 403 role denied, 404 not found, 429 rate limited.
