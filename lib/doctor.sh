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

# When run as root, doctor installs missing dependencies itself;
# otherwise it reports what is missing and how to fix it.
AUTO_FIX=0
[ "$(id -u)" = "0" ] && AUTO_FIX=1
FIX_HINT="run 'sudo chengetai doctor' to install it automatically"

APT_UPDATED=0
apt_install() {
    if [ "$APT_UPDATED" = "0" ]; then
        apt-get update -qq || true
        APT_UPDATED=1
    fi
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" >/dev/null
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
        fi
    else
        note "$cmd missing — $FIX_HINT"
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

# Internet
if ping -c 1 github.com >/dev/null 2>&1 || curl -sfI https://github.com >/dev/null 2>&1; then
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
    if curl -fsSL https://get.docker.com | sh >/dev/null && command -v docker >/dev/null 2>&1; then
        pass "Docker Installed"
    else
        fail "Docker could not be installed"
    fi
else
    note "Docker Not Installed — $FIX_HINT"
fi

# Docker Compose plugin
if docker compose version >/dev/null 2>&1; then
    pass "Docker Compose Installed"
elif [ "$AUTO_FIX" = "1" ] && command -v docker >/dev/null 2>&1; then
    echo -e "${YELLOW}!${NC} Docker Compose missing — installing..."
    if apt_install docker-compose-plugin 2>/dev/null && docker compose version >/dev/null 2>&1; then
        pass "Docker Compose Installed"
    else
        mkdir -p /usr/local/lib/docker/cli-plugins
        curl -fsSL https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64 \
            -o /usr/local/lib/docker/cli-plugins/docker-compose \
            && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
        if docker compose version >/dev/null 2>&1; then
            pass "Docker Compose Installed"
        else
            fail "Docker Compose could not be installed"
        fi
    fi
else
    note "Docker Compose Missing — $FIX_HINT"
fi

echo ""
echo "========================================="
echo " Ready for Deployment Check Complete"
echo "========================================="
