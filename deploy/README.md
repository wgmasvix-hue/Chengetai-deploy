# Deploying ChengetAi Deploy (the platform itself)

An internal tool for ChengetAi engineers. Install it on a control server;
reach it over the campus network or VPN, never the public internet.

## 1. Install

```bash
sudo git clone <this repo> /opt/chengetai-deploy
cd /opt/chengetai-deploy
sudo bash install-cli.sh        # links the `chengetai` CLI
```

## 2. API

```bash
cd /opt/chengetai-deploy/api
cp .env.example .env            # set ADMIN_EMAIL, ADMIN_PASSWORD, JWT_SECRET, CORS_ORIGIN
chmod 600 .env
npm ci --omit=dev
# optional PostgreSQL:
#   set DATABASE_URL in .env, then: psql "$DATABASE_URL" -f db/schema.sql
sudo cp ../deploy/chengetai-api.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now chengetai-api
```

The API binds to `127.0.0.1:3000`. It is reached only through the reverse
proxy.

## 3. Dashboard

```bash
cd /opt/chengetai-deploy/dashboard
npm ci && npm run build         # emits dist/chengetai-dashboard/browser
```

## 4. Reverse proxy + TLS

```bash
sudo cp deploy/nginx.conf /etc/nginx/sites-available/chengetai
sudo ln -s /etc/nginx/sites-available/chengetai /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d chengetai.<your-domain>   # if internet-facing over VPN
```

Dashboard and API now share one origin (no CORS); only the proxy port is
exposed. Firewall the rest:

```bash
sudo ufw allow from <campus-or-vpn-subnet> to any port 80,443 proto tcp
sudo ufw enable
```

## Security checklist

- [ ] `.env` files are chmod 600 and untracked (they are git-ignored).
- [ ] `ADMIN_PASSWORD` set, or the generated one recorded then rotated.
- [ ] `CORS_ORIGIN` set to the dashboard origin (not `*`) if not same-origin.
- [ ] API bound to localhost; only the proxy is network-exposed.
- [ ] TLS terminated at the proxy for anything beyond the LAN.
- [ ] Deployment database passwords are generated per deployment (they are).
