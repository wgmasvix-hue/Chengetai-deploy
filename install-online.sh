#!/usr/bin/env bash
# =============================================================================
#  ChengetAi Deploy — one-command installer.
#
#  Install (or update) the whole platform on a fresh Ubuntu server:
#
#    curl -fsSL https://raw.githubusercontent.com/wgmasvix-hue/Chengetai-deploy/claude/dspace-deployment-review-98kzqb/install-online.sh | sudo bash
#
#  Add DSpace in the same run:
#    ... | sudo bash -s -- --with-dspace
#
#  Safe to re-run: it updates in place and never touches your existing
#  deployments, admin password, or API data (all kept out of git). If an
#  SSH drop interrupts it, just run the same command again — it resumes.
# =============================================================================
set -euo pipefail

REPO_URL="https://github.com/wgmasvix-hue/Chengetai-deploy.git"
BRANCH="${CHENGETAI_BRANCH:-claude/dspace-deployment-review-98kzqb}"
DEST="/opt/chengetai-deploy"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
say()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

if [ "$(id -u)" != 0 ]; then
  echo "This installer needs root. Re-run:"
  echo "  curl -fsSL <url> | sudo bash"
  exit 1
fi

# 1. Prerequisites for fetching the code -------------------------------------
if ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  say "Installing git and curl..."
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y git curl >/dev/null
fi
# tmux so long installs survive a dropped SSH session.
command -v tmux >/dev/null 2>&1 || apt-get install -y tmux >/dev/null 2>&1 || true

# 2. Fetch or update the code, preserving runtime state ----------------------
# Using init+fetch+checkout works whether $DEST is absent, a fresh dir, an
# older non-git install, or an existing checkout — and leaves untracked
# runtime state (deployments/, api/.env, api/data) in place.
say "Fetching ChengetAi Deploy ($BRANCH) into $DEST..."
mkdir -p "$DEST"
cd "$DEST"
if [ ! -d .git ]; then
  git init -q
  git remote add origin "$REPO_URL" 2>/dev/null || true
fi
git remote set-url origin "$REPO_URL"
git fetch --depth 1 origin "$BRANCH"
git checkout -qf -B "$BRANCH" FETCH_HEAD
say "Code ready."

# 3. Hand off to the platform bootstrap (node, nginx, API, dashboard) ---------
exec bash "$DEST/deploy/bootstrap.sh" "$@"
