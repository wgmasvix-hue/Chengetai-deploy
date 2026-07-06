# ChengetAi Deploy

One Command. Complete Deployment.

ChengetAi Deploy is an **orchestration platform** for deploying and
operating institutional platforms — starting with **DSpace 8** — on any
Ubuntu server. It clones, configures, brands, deploys, verifies, monitors
and maintains canonical open-source repositories (DSpace via the Bulawayo
Polytechnic reference repository); it never reimplements the deployment
logic it drives.

It ships three tiers — an Angular dashboard, a Node/Express REST API, and a
Bash CLI + plugin engine. See `docs/ARCHITECTURE.md` for the full design,
`docs/API.md` for the REST API, and `docs/PLUGIN-GUIDE.md` to add a platform.

## Install (one command)

On a fresh Ubuntu 22.04/24.04 server:

```bash
curl -fsSL https://raw.githubusercontent.com/wgmasvix-hue/Chengetai-deploy/main/install-online.sh | sudo bash
```

Add a DSpace repository in the same run:

```bash
curl -fsSL https://raw.githubusercontent.com/wgmasvix-hue/Chengetai-deploy/main/install-online.sh | sudo bash -s -- --with-dspace
```

It installs the CLI, API and dashboard, wires nginx, and prints your
dashboard URL and admin login. **Safe to re-run** — it updates in place
and never touches your existing deployments or admin password. If an SSH
drop interrupts it, run the same command again and it resumes. (Tip: run
inside `tmux` so a dropped connection can't interrupt it at all.)

### CLI only (from a clone)

To install just the `chengetai` CLI (no dashboard/API) from a checkout:

```bash
git clone https://github.com/wgmasvix-hue/Chengetai-deploy.git
cd Chengetai-deploy
sudo bash install-cli.sh
```

Then:

```bash
chengetai doctor    # check the system, install missing dependencies
chengetai deploy    # deploy a repository
```

`chengetai deploy` on a fresh server walks you through everything: it
creates a deployment profile, checks the system, installs missing
dependencies, clones and configures the canonical DSpace repository,
brands it, starts the services, creates the administrator account and
prints the frontend and backend URLs.

## Commands

| Command | Purpose |
|---|---|
| `chengetai install` | Install or update ChengetAi Deploy on the server. |
| `chengetai doctor` | Check the system and install missing dependencies. |
| `chengetai create [platform] [name]` | Create a new deployment profile. |
| `chengetai deploy [platform\|name]` | Deploy a repository. |
| `chengetai start [name]` | Start a deployment. |
| `chengetai stop [name]` | Stop a deployment (data is preserved). |
| `chengetai restart [name]` | Restart services. |
| `chengetai status [name]` | Show service status and URL health. |
| `chengetai logs [name] [service...]` | Follow logs. |
| `chengetai backup [name]` | Back up the database and uploaded files. |
| `chengetai restore [name] [dir]` | Restore a backup (most recent by default). |
| `chengetai edit <component> [name]` | Edit the logo, favicon, UI config or communities, then rebuild. |
| `chengetai update` | Update ChengetAi Deploy and its deployments. |
| `chengetai remove [name]` | Remove a deployment. |
| `chengetai version` | Show version information. |
| `chengetai help` | Display all commands. |

The deployment name can be omitted whenever only one deployment exists.

## Platforms

Platforms are plugins under `templates/`. Each platform provides a
`plugin.sh` implementing the deploy/start/stop/backup/... operations, so
new platforms can be added without touching the CLI itself.

| Platform | Status |
|---|---|
| `dspace` | Available — DSpace 8 institutional repository |
| `koha` | Available — Koha library management system |
| `moodle` | Coming soon |
| `ojs` | Coming soon |

```bash
chengetai deploy dspace
```

## Project structure

```
chengetai            CLI entry point (dispatcher)
VERSION              Current version
install-online.sh    one-command installer (curl | sudo bash)
install-cli.sh       CLI-only installer (run from a clone)
deploy/              bootstrap.sh, systemd unit, nginx recipe
lib/                 One script per command + utils.sh helpers
templates/           Platform plugins (plugin.sh + plugin.json);
                     templates/dspace/branding/ holds the default assets
deployments/         Deployment profiles and engines (created at runtime)
api/                 ChengetAi Deploy API (dashboard backend)
dashboard/           Engineer dashboard (Angular)
```

Each deployment lives in `deployments/<name>/` with a `profile.env`
(platform, institution, administrator details and ports — never the
password), a clone of the canonical engine (with a generated `.env`
holding a random database password), local `branding/`, and its
`backups/`. Deployments run as separate compose projects, so several can
share a server when their `UI_PORT`/`REST_PORT` differ.

## Requirements

- Ubuntu 22.04 or 24.04
- 2+ CPU cores, 4+ GB RAM, 40+ GB free disk
- Internet access (Docker Hub, GitHub)

`chengetai doctor` verifies all of this and, when run with `sudo`,
installs anything that is missing (Docker, Docker Compose, git, curl).
