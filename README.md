# ChengetAi Deploy

One Command. Complete Deployment.

ChengetAi Deploy is a command-line tool for deploying and operating
institutional platforms — starting with **DSpace 8** repositories — on any
Ubuntu server. Install it once, then manage everything with simple
commands, the same way you use `git` or `docker`.

## Install

On a fresh Ubuntu 22.04/24.04 server:

```bash
curl -fsSL https://raw.githubusercontent.com/wgmasvix-hue/Chengetai-deploy/claude/dspace-deployment-review-98kzqb/install-online.sh | sudo bash
```

Then:

```bash
chengetai doctor    # check the system, install missing dependencies
chengetai deploy    # deploy a repository
```

`chengetai deploy` on a fresh server walks you through everything: it
creates a deployment profile, checks the operating system, installs
missing dependencies, downloads the deployment engine, deploys the
platform, starts the services, creates the administrator account and
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
install-online.sh    curl-able installer for fresh servers
install-cli.sh       installer for local/offline checkouts
lib/                 One script per command + utils.sh helpers
templates/           Platform plugins (dspace, koha, moodle, ojs)
deployments/         Deployment profiles and engines (created at runtime)
```

Each deployment lives in `deployments/<name>/` with a `profile.env`
(platform, institution and administrator details — never the password),
the platform engine, and its `backups/`.

## Requirements

- Ubuntu 22.04 or 24.04
- 2+ CPU cores, 4+ GB RAM, 40+ GB free disk
- Internet access (Docker Hub, GitHub)

`chengetai doctor` verifies all of this and, when run with `sudo`,
installs anything that is missing (Docker, Docker Compose, git, curl).
