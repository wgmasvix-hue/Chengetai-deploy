# ChengetAi Deploy

One Command. Complete Deployment.

ChengetAi Deploy is a command-line tool for deploying and operating
institutional platforms — starting with **DSpace 8** repositories — on any
Ubuntu server. Install it once, then manage everything with simple
commands, the same way you use `git` or `docker`.

## Install

ChengetAi Deploy is an internal tool for ChengetAi engineers. On the
target Ubuntu 22.04/24.04 server:

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
creates a deployment profile, checks the operating system, installs
missing dependencies, instantiates the built-in deployment engine,
starts the services, creates the administrator account and prints the
frontend and backend URLs. The engine (compose stack, frontend image,
branding) ships inside this repository — nothing is downloaded from
other repositories at deploy time.

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
| `koha` | Coming soon |
| `moodle` | Coming soon |
| `ojs` | Coming soon |

```bash
chengetai deploy dspace
```

## Project structure

```
chengetai            CLI entry point (dispatcher)
VERSION              Current version
install-cli.sh       installer (run from a clone of this repo)
lib/                 One script per command + utils.sh helpers
templates/           Platform plugins; templates/dspace/engine/ is the
                     built-in DSpace stack (compose, Dockerfile, branding)
deployments/         Deployment profiles and engines (created at runtime)
api/                 ChengetAi Deploy API (dashboard backend)
dashboard/           Engineer dashboard (Angular)
```

Each deployment lives in `deployments/<name>/` with a `profile.env`
(platform, institution, administrator details and ports — never the
password), its instantiated engine (including a generated `.env` with a
random database password), and its `backups/`. Deployments run as
separate compose projects, so several can share a server when their
`UI_PORT`/`REST_PORT` differ.

## Requirements

- Ubuntu 22.04 or 24.04
- 2+ CPU cores, 4+ GB RAM, 40+ GB free disk
- Internet access (Docker Hub, GitHub)

`chengetai doctor` verifies all of this and, when run with `sudo`,
installs anything that is missing (Docker, Docker Compose, git, curl).
