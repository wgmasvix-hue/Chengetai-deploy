#!/usr/bin/env bash

set -e

clear

echo "========================================================"
echo "        ChengetAi Deploy : DSpace 8.3"
echo "========================================================"
echo ""
echo "Deployment Wizard"
echo ""

read -rp "Institution Name       : " INSTITUTION
read -rp "Repository Name        : " REPOSITORY
read -rp "Administrator Email    : " ADMIN_EMAIL
read -rp "Administrator Name     : " ADMIN_NAME

read -rsp "Administrator Password : " ADMIN_PASS
echo
read -rsp "Confirm Password       : " ADMIN_PASS2
echo

if [ "$ADMIN_PASS" != "$ADMIN_PASS2" ]; then
    echo ""
    echo "ERROR: Passwords do not match."
    exit 1
fi

echo ""
echo "========================================="
echo "Deployment Summary"
echo "========================================="
echo "Institution : $INSTITUTION"
echo "Repository  : $REPOSITORY"
echo "Admin Email : $ADMIN_EMAIL"
echo ""

read -rp "Proceed with deployment? (Y/N): " ANSWER

if [[ ! "$ANSWER" =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 0
fi

export INSTITUTION
export REPOSITORY
export ADMIN_EMAIL
export ADMIN_NAME
export ADMIN_PASS

echo ""
echo "Running Deployment Readiness Check..."
bash "$(dirname "$0")/doctor.sh"

echo ""
echo "Preparing Deployment Engine..."

REPO_URL="https://github.com/wgmasvix-hue/bulawayo-polytechnic-dspace-.git"
BRANCH="claude/dspace-deployment-review-48qeth"
WORKDIR="/opt/chengetai-engine"

if [ -d "$WORKDIR/.git" ]; then
    echo "Updating deployment engine..."
    git -C "$WORKDIR" fetch origin
    git -C "$WORKDIR" checkout "$BRANCH"
    git -C "$WORKDIR" pull origin "$BRANCH"
else
    echo "Downloading deployment engine..."
    git clone -b "$BRANCH" "$REPO_URL" "$WORKDIR"
fi

echo ""
echo "Starting ChengetAi Deployment..."
bash "$WORKDIR/install.sh"

echo ""
echo "============================================================"
echo "DSpace deployment completed successfully!"
echo "============================================================"

echo ""
echo "Frontend : http://$SERVER_IP:4000"
echo "Backend  : http://$SERVER_IP:8080/server/api"

echo ""
read -rp "Create the DSpace administrator now? (Y/N): " CREATE_ADMIN

if [[ "$CREATE_ADMIN" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Launching DSpace administrator setup..."
    docker exec -it dspace /dspace/bin/dspace create-administrator
fi

echo ""
echo "============================================================"
echo "ChengetAi Deploy Finished Successfully"
echo "============================================================"

