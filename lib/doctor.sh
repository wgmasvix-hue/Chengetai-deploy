#!/usr/bin/env bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() {
    echo -e "${GREEN}✓${NC} $1"
}

fail() {
    echo -e "${RED}✗${NC} $1"
}

warn() {
    echo -e "${YELLOW}!${NC} $1"
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
if ping -c 1 github.com >/dev/null 2>&1; then
    pass "Internet Connectivity"
else
    fail "No Internet Connection"
fi

# Docker
if command -v docker >/dev/null 2>&1; then
    pass "Docker Installed"
else
    warn "Docker Not Installed"
fi

# Docker Compose
if docker compose version >/dev/null 2>&1; then
    pass "Docker Compose Installed"
else
    warn "Docker Compose Missing"
fi

# Git
if command -v git >/dev/null 2>&1; then
    pass "Git Installed"
else
    warn "Git Missing"
fi

# Curl
if command -v curl >/dev/null 2>&1; then
    pass "Curl Installed"
else
    warn "Curl Missing"
fi

echo ""
echo "========================================="
echo " Ready for Deployment Check Complete"
echo "========================================="
