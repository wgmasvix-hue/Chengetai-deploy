#!/usr/bin/env bash

set -e

echo "========================================="
echo " ChengetAi Deployment Readiness Report"
echo "========================================="
echo ""

install_package() {
    PKG="$1"
    echo "[INFO] Installing $PKG..."
    apt-get update -qq
    apt-get install -y "$PKG"
}

echo "Checking Ubuntu..."
grep -q Ubuntu /etc/os-release && echo "✓ Ubuntu Version"

echo "✓ CPU Cores: $(nproc)"
echo "✓ Memory: $(free -h | awk '/Mem:/ {print $2}')"
echo "✓ Disk Space: $(df -h / | awk 'NR==2 {print $4}') Free"

echo ""
echo "Checking Internet..."
if ping -c1 github.com >/dev/null 2>&1; then
    echo "✓ Internet Connectivity"
else
    echo "✗ No Internet Connection"
    exit 1
fi

echo ""
echo "Checking Git..."
if ! command -v git >/dev/null 2>&1; then
    install_package git
fi
echo "✓ Git Installed"

echo ""
echo "Checking Curl..."
if ! command -v curl >/dev/null 2>&1; then
    install_package curl
fi
echo "✓ Curl Installed"

echo ""
echo "Checking Docker..."
if ! command -v docker >/dev/null 2>&1; then
    echo "[INFO] Installing Docker..."
    curl -fsSL https://get.docker.com | sh
fi
echo "✓ Docker Installed"

echo ""
echo "Checking Docker Compose..."
if ! docker compose version >/dev/null 2>&1; then
    install_package docker-compose-plugin
fi
echo "✓ Docker Compose Installed"

echo ""
echo "Checking Java..."
if ! command -v java >/dev/null 2>&1; then
    install_package openjdk-21-jdk
fi
echo "✓ Java Installed"

echo ""
echo "========================================="
echo " System Ready For Deployment"
echo "========================================="
