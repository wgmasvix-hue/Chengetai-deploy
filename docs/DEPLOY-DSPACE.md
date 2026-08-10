# Deploying DSpace with ChengetAi Deploy

The exact, field-tested flow for standing up DSpace 10 on a fresh Ubuntu
server — the path validated in production. Two parts:

1. [Deploy DSpace](#part-1--deploy-dspace) — get it running on an IP.
2. [Custom domain + HTTPS](#part-2--custom-domain--https) — put a real
   URL in front of it with TLS.

---

## Requirements

- Ubuntu 22.04 or 24.04
- 2+ CPU cores, **4+ GB RAM**, **40+ GB free disk**
- Outbound internet (Docker Hub for images, GitHub for the engine)

Check before you start:

```bash
free -h && df -h /
```

---

## Part 1 — Deploy DSpace

### 1. Open a resilient session

Always deploy inside `tmux` so a dropped SSH connection can't interrupt it.

```bash
sudo -i
tmux new -s dspace          # reconnect later with: tmux attach -t dspace
```

### 2. Install ChengetAi Deploy

```bash
curl -fsSL https://raw.githubusercontent.com/wgmasvix-hue/Chengetai-deploy/main/install-online.sh | sudo bash
```

Safe to re-run — it updates in place and never touches existing deployments.

### 3. Check the system (auto-installs Docker etc.)

```bash
chengetai doctor
```

Installs anything missing: Docker, Docker Compose, git, curl.

### 4. Deploy

```bash
chengetai deploy dspace
```

It asks for the institution name, admin account (email / first / last /
password) and UI/REST ports (defaults `4000` / `8080`), then clones the
canonical DSpace engine, generates a random DB password, applies branding,
starts the containers and **waits out the healthcheck (up to ~6 minutes —
this is normal)**.

> **If the admin step fails with "Passwords do not match"** — the backend is
> already up; don't redeploy. Create the admin directly against the running
> container:
>
> ```bash
> docker exec -it $(docker ps --format '{{.Names}}' | grep -i dspace \
>   | grep -iv 'solr\|db\|postgres\|ui\|frontend\|angular' | head -1) \
>   /dspace/bin/dspace create-administrator
> ```
>
> Type the password slowly — it doesn't echo.

### 5. Open the firewall

The UI runs on `4000`, the REST API on `8080`. If UFW is enabled, allow them;
also open them in your cloud provider's security group.

```bash
sudo ufw allow 22/tcp
sudo ufw allow 4000/tcp
sudo ufw allow 8080/tcp
```

### 6. Access it

- **UI:**  `http://<server-ip>:4000`
- **REST:** `http://<server-ip>:8080/server`

Log in with the admin email/password from step 4.

### Day-2 operations

```bash
chengetai status     # service + URL health
chengetai logs       # follow logs (add a service name to filter)
chengetai backup     # back up database + assetstore
chengetai restore    # restore the most recent backup
chengetai restart    # restart services
chengetai update     # update the tool + deployment
```

The deployment name can be omitted whenever only one deployment exists.

---

## Part 2 — Custom domain + HTTPS

Serve DSpace on a real domain with TLS — e.g.
`https://unifiedrepo.chengerailabs.co.zw` — instead of `:4000`.

### `chengetai domain` (the only supported path)

One command sets up **Caddy** (automatic Let's Encrypt HTTPS), reverse-proxies
the UI and REST under one domain, and repoints DSpace at the HTTPS URL:

```bash
# DNS first: an A record for your domain → the server's public IP.
sudo chengetai domain <name> your-domain.example --email you@example
```

It installs Caddy if needed, writes the site to `/etc/caddy/conf.d/<name>.caddy`,
reloads Caddy, and repoints the deployment (`plugin_domain`): it rewrites
`DSPACE_HOSTNAME`, `DSPACE_UI_URL` and `DSPACE_REST_URL` in the deployment's
`deployments/<name>/engine/.env` to `https://your-domain.example`, then
recreates the stack so the DSpace backend and Angular SSR both advertise (and
CORS-allow) the new HTTPS origin. Watch certificate issuance with
`journalctl -u caddy -f`.

```bash
chengetai domain <name> your-domain.example --caddy-only   # proxy only, skip the repoint
```

If you need to repoint it by hand instead (e.g. a proxy Caddy doesn't manage),
edit those same three variables directly and recreate:

```bash
nano /opt/chengetai-deploy/deployments/<name>/engine/.env
#   DSPACE_HOSTNAME=your-domain.example
#   DSPACE_UI_URL=https://your-domain.example
#   DSPACE_REST_URL=https://your-domain.example/server
chengetai start <name>      # 'start' runs 'up -d', which recreates the
                             # containers with the new environment
```

### Verify

- Open **https://your-domain.example** — the UI loads over TLS.
- REST: **https://your-domain.example/server** returns the DSpace REST root
  document.
- Log in as admin and confirm you can browse and submit.

> **If the UI loads but searches/logins fail**, the browser is still trying to
> reach the REST API on the old IP/port — DSpace's CORS check rejects requests
> from an origin that doesn't match `DSPACE_UI_URL`/`DSPACE_REST_URL`. Recheck
> those two variables in `engine/.env`, then `chengetai start <name>` to
> recreate the containers (a `restart` alone does **not** pick up `.env`
> changes — only `up -d` does).

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Deploy interrupted by SSH drop | `tmux attach -t dspace`, re-run `chengetai deploy dspace` — it resumes. |
| "Passwords do not match" at admin step | Use the `create-administrator` container command above; don't redeploy. |
| UI slow to appear after "deployed" | First boot takes several minutes; watch `chengetai logs`. |
| Healthcheck seems slow (~6 min) | Expected — DSpace `start_period` is 360s by design. |
| Port already in use | Re-run `chengetai deploy dspace` and choose different UI/REST ports. |
| Out of disk | DSpace needs 40+ GB; free space or resize the volume. |
| Domain loads but REST calls fail | REST URL not repointed — recheck Part 2, step 2. |
