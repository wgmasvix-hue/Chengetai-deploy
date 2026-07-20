#!/usr/bin/env bash

source "$(dirname "$0")/utils.sh"

pass() {
    echo -e "${GREEN}✓${NC} $1"
}

fail() {
    echo -e "${RED}✗${NC} $1"
}

note() {
    echo -e "${YELLOW}!${NC} $1"
}

# Doctor installs missing dependencies itself — directly when root,
# through sudo otherwise. Only when neither is possible does it just
# report what is missing.
SUDO=""
AUTO_FIX=1
if [ "$(id -u)" != "0" ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        AUTO_FIX=0
    fi
fi
FIX_HINT="re-run as root (or install sudo) so it can be installed automatically"
MISSING=0

APT_UPDATED=0
apt_install() {
    if [ "$APT_UPDATED" = "0" ]; then
        $SUDO apt-get update -qq || true
        APT_UPDATED=1
    fi
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" >/dev/null
}

ensure_cmd() {
    local cmd="$1" pkg="$2"
    if command -v "$cmd" >/dev/null 2>&1; then
        pass "$cmd Installed"
    elif [ "$AUTO_FIX" = "1" ]; then
        echo -e "${YELLOW}!${NC} $cmd missing — installing..."
        if apt_install "$pkg" && command -v "$cmd" >/dev/null 2>&1; then
            pass "$cmd Installed"
        else
            fail "$cmd could not be installed"
            MISSING=$((MISSING + 1))
        fi
    else
        note "$cmd missing — $FIX_HINT"
        MISSING=$((MISSING + 1))
    fi
}

echo ""
echo "========================================="
echo " ChengetAi Deployment Readiness Report"
echo "========================================="
echo ""

# Ubuntu Version
if grep -q "Ubuntu 24" /etc/os-release || grep -q "Ubuntu 22" /etc/os-release; then
    pass "Ubuntu Version"
else
    fail "Unsupported Ubuntu Version"
fi

# CPU
CPU=$(nproc)
if [ "$CPU" -ge 2 ]; then
    pass "CPU Cores: $CPU"
else
    fail "Minimum 2 CPU cores required"
fi

# RAM
RAM=$(free -g | awk '/Mem:/ {print $2}')
if [ "$RAM" -ge 4 ]; then
    pass "Memory: ${RAM}GB"
else
    fail "Minimum 4GB RAM required"
fi

# Disk
DISK=$(df -BG / | awk 'NR==2 {gsub("G","",$4); print $4}')
if [ "$DISK" -ge 40 ]; then
    pass "Disk Space: ${DISK}GB Free"
else
    fail "Minimum 40GB free space required"
fi

# Internet — ICMP is often blocked, so fall back to HTTPS probes.
if ping -c 1 -W 2 github.com >/dev/null 2>&1 \
    || curl -sf -m 10 -o /dev/null https://github.com \
    || curl -sf -m 10 -o /dev/null https://api.github.com; then
    pass "Internet Connectivity"
else
    fail "No Internet Connection"
fi

# Basic tools
ensure_cmd curl curl
ensure_cmd git git
ensure_cmd ip iproute2

# Docker
if command -v docker >/dev/null 2>&1; then
    pass "Docker Installed"
elif [ "$AUTO_FIX" = "1" ]; then
    echo -e "${YELLOW}!${NC} Docker missing — installing..."
    if curl -fsSL https://get.docker.com | $SUDO sh >/dev/null && command -v docker >/dev/null 2>&1; then
        [ -n "$SUDO" ] && $SUDO usermod -aG docker "$USER" 2>/dev/null
        pass "Docker Installed"
    else
        fail "Docker could not be installed"
        MISSING=$((MISSING + 1))
    fi
else
    note "Docker Not Installed — $FIX_HINT"
    MISSING=$((MISSING + 1))
fi

# Docker Compose plugin
if docker compose version >/dev/null 2>&1; then
    pass "Docker Compose Installed"
elif [ "$AUTO_FIX" = "1" ] && command -v docker >/dev/null 2>&1; then
    echo -e "${YELLOW}!${NC} Docker Compose missing — installing..."
    if apt_install docker-compose-plugin 2>/dev/null && docker compose version >/dev/null 2>&1; then
        pass "Docker Compose Installed"
    else
        $SUDO mkdir -p /usr/local/lib/docker/cli-plugins
        $SUDO curl -fsSL https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64 \
            -o /usr/local/lib/docker/cli-plugins/docker-compose \
            && $SUDO chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
        if docker compose version >/dev/null 2>&1; then
            pass "Docker Compose Installed"
        else
            fail "Docker Compose could not be installed"
            MISSING=$((MISSING + 1))
        fi
    fi
else
    note "Docker Compose Missing — $FIX_HINT"
    MISSING=$((MISSING + 1))
fi

# ── Manager services (per-deployment always-on UI) ──────────────────────────
# Flags managers that were installed as a service but aren't running. This is
# a warning only — it never counts as a missing dependency, so it can't block
# a deploy.
if command -v systemctl >/dev/null 2>&1; then
    for _name in $(list_deployments); do
        _svc="chengetai-manager@$_name"
        _active="$(systemctl is-active "$_svc" 2>/dev/null || true)"
        _enabled="$(systemctl is-enabled "$_svc" 2>/dev/null || true)"
        if [ "$_active" = "active" ]; then
            pass "Manager service ($_name) running"
        elif [ "$_enabled" = "enabled" ]; then
            note "Manager service ($_name) installed but not running — sudo systemctl restart $_svc"
        fi
    done
fi

echo ""
echo "========================================="
echo " Ready for Deployment Check Complete"
echo "========================================="

if [ "$MISSING" -gt 0 ]; then
    echo ""
    note "$MISSING dependency issue(s) remain — resolve them before deploying."
    exit 1
fi
