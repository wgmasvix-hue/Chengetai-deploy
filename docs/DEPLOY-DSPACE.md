# Deploying DSpace with ChengetAi Deploy

## DSpace 10 deployment

Run the following on a supported Ubuntu server. ChengetAi Deploy validates the
host and Docker/Compose, pins DSpace images to a stable release, creates a
deployment profile and persistent volumes, generates database and administrator
credentials, starts the backend/Angular/Solr/PostgreSQL services, waits for
database migrations and checks the REST API and UI.

```bash
sudo chengetai deploy dspace --version 10.1
```

For HTTPS with the bundled Caddy reverse proxy, point DNS at this server first:
ensure inbound ports 80/tcp and 443/tcp (optionally 443/udp for HTTP/3) are
allowed by the cloud firewall. ChengetAi Deploy opens these ports in UFW when
UFW is active and it has permission.

```bash
sudo chengetai deploy dspace \
  --version 10.1 \
  --domain repository.example.org \
  --production
```

Interactive mode is the default. To deploy without prompts, provide an admin
email:

```bash
sudo chengetai deploy dspace \
  --version 10.1 \
  --domain repository.example.org \
  --admin-email admin@example.org \
  --non-interactive
```

The deployment prints the UI/REST URLs, administrator email, and initial
administrator password. The password is also saved in
`deployments/dspace/admin-credentials` with mode `0600`; database credentials
are in the mode-`0600` `deployments/dspace/engine/.env`. Persistent data is held
in per-deployment Docker volumes; backups and DSpace configuration are stored
under the deployment directory. Use a different deployment name when managing
multiple repositories on one host.

Day-two commands:

```bash
chengetai status dspace
chengetai logs dspace
chengetai backup dspace
chengetai restore dspace
chengetai restart dspace
chengetai update dspace
chengetai verify dspace
```

> **Upstream image limitation:** The official DSpace 10.1 Docker documentation
> labels the published Compose images/resources as development/testing images
> and advises against using them as-is in production. ChengetAi Deploy pins
> versioned images and configures persistent storage, private database/Solr
> networking, health checks, and HTTPS, but that does not remove the upstream
> image limitation. Institutions requiring supported production images should
> build and audit their own images using the official DSpace Dockerfiles.

## Legacy DSpace 8 deployment

These instructions document the older DSpace 8 reference-engine path for
existing installations. New DSpace deployments use DSpace 10 by default. Two
parts:

1. [Legacy DSpace 8 deployment](#part-1--deploy-legacy-dspace-8) — get it running on an IP.
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

## Part 1 — Deploy legacy DSpace 8

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

### Automated (recommended) — `chengetai domain`

One command sets up **Caddy** (automatic Let's Encrypt HTTPS), reverse-proxies
the UI and REST under one domain, and repoints DSpace at the HTTPS URL:

```bash
# DNS first: an A record for your domain → the server's public IP.
sudo chengetai domain <name> your-domain.example --email you@example
```

It installs Caddy if needed, writes the site to `/etc/caddy/conf.d/<name>.caddy`,
reloads Caddy, rewrites the frontend `config.yml` and the backend public URL
(backups kept as `.bak`), and rebuilds/restarts the stack. Watch certificate
issuance with `journalctl -u caddy -f`. That's it — skip the manual steps below.

The rest of this section documents the equivalent **manual nginx + certbot**
setup if you prefer to run it by hand. Replace `unifiedrepo.chengerailabs.co.zw`
with your domain throughout, and `<name>` with your deployment name.

### 1. Point DNS at the server

Create an **A record** for your domain → the server's **public** IP:

```
unifiedrepo.chengerailabs.co.zw.   A   <server-public-ip>
```

Wait for it to resolve (`dig +short unifiedrepo.chengerailabs.co.zw`).

### 2. Tell DSpace its public URL

**Backend** — edit the deployment's engine compose file and set the public
HTTPS URLs:

```bash
nano /opt/chengetai-deploy/deployments/<name>/engine/docker-compose.yml
```

Change the `dspace` service environment to:

```yaml
      dspace__P__server__P__url: https://unifiedrepo.chengerailabs.co.zw/server
      dspace__P__ui__P__url: https://unifiedrepo.chengerailabs.co.zw
```

**Frontend** — point the browser-side REST config at the domain over TLS:

```bash
chengetai edit config <name>
```

Set:

```yaml
ui:
  ssl: true
  host: unifiedrepo.chengerailabs.co.zw
  port: 443
rest:
  ssl: true
  host: unifiedrepo.chengerailabs.co.zw
  port: 443
  namespace: /server
```

Answer **yes** to rebuild the frontend, then recreate the backend so the new
compose env takes effect:

```bash
chengetai start <name>      # 'start' runs 'up -d', which applies the changes
```

### 3. Install nginx and add the reverse proxy

```bash
sudo apt-get update && sudo apt-get install -y nginx
sudo tee /etc/nginx/sites-available/unifiedrepo.chengerailabs.co.zw >/dev/null <<'NGINX'
server {
    listen 80;
    server_name unifiedrepo.chengerailabs.co.zw;

    client_max_body_size 1024m;   # allow large bitstream uploads

    # DSpace REST API
    location /server {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # DSpace Angular UI (server-side rendered)
    location / {
        proxy_pass http://127.0.0.1:4000;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade           $http_upgrade;
        proxy_set_header Connection        "upgrade";
    }
}
NGINX
sudo ln -sf /etc/nginx/sites-available/unifiedrepo.chengerailabs.co.zw \
            /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

### 4. Get a TLS certificate

```bash
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d unifiedrepo.chengerailabs.co.zw \
     --redirect --agree-tos -m admin@chengerailabs.co.zw
```

certbot rewrites the nginx site to serve HTTPS on 443 and redirect HTTP → HTTPS,
and auto-renews via a systemd timer.

### 5. Open web ports, close the raw app ports

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

Optional hardening: once nginx is proxying, you no longer need `4000`/`8080`
exposed publicly. You can `sudo ufw deny 4000/tcp` and `sudo ufw deny 8080/tcp`
(nginx reaches them on `127.0.0.1`).

### 6. Verify

- Open **https://unifiedrepo.chengerailabs.co.zw** — the UI loads over TLS.
- REST: **https://unifiedrepo.chengerailabs.co.zw/server** returns the DSpace
  REST root document.
- Log in as admin and confirm you can browse and submit.

> **If the UI loads but searches/logins fail**, the browser is still trying to
> reach the REST API on the old IP/port. Recheck step 2 (`config.yml` `rest`
> block **and** `dspace__P__server__P__url`), rebuild the frontend, and
> `chengetai start <name>`.

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
