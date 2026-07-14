#!/usr/bin/env bash
set -e

NAME="${1:-myfarm}"
DEPLOY_DIR="/opt/chengetai-deploy/deployments/$NAME"
DB_PASS=$(openssl rand -base64 16 2>/dev/null || echo "farmpass123")

# Detect docker compose
if docker compose version &>/dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    DOCKER_COMPOSE="docker-compose"
fi

echo "╔════════════════════════════════════════════════╗"
echo "║     ChengetAI farmOS Deployment               ║"
echo "╚════════════════════════════════════════════════╝"
echo ""
echo "🌾 Deploying farmOS: $NAME"
echo ""

# Create directories
echo "📁 Creating directories..."
mkdir -p "$DEPLOY_DIR"/{www,db,backups}

# Create docker-compose.yml
echo "🐳 Creating Docker Compose..."
cat > "$DEPLOY_DIR/docker-compose.yml" << COMPOSE
services:
  db:
    image: postgres:17
    container_name: ${NAME}-db
    restart: unless-stopped
    environment:
      POSTGRES_DB: farm
      POSTGRES_USER: farm
      POSTGRES_PASSWORD: ${DB_PASS}
    volumes:
      - ./db:/var/lib/postgresql/data
    ports:
      - "5433:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U farm"]
      interval: 10s
      timeout: 5s
      retries: 5

  www:
    image: farmos/farmos:4.x-dev
    container_name: ${NAME}-www
    restart: unless-stopped
    ports:
      - "8081:80"
    volumes:
      - ./www:/opt/drupal
    environment:
      FARMOS_DB_HOST: db
      FARMOS_DB_NAME: farm
      FARMOS_DB_USER: farm
      FARMOS_DB_PASSWORD: ${DB_PASS}
    depends_on:
      db:
        condition: service_healthy
COMPOSE

echo "🚀 Starting containers..."
cd "$DEPLOY_DIR"
$DOCKER_COMPOSE up -d

echo ""
echo "⏳ Waiting for farmOS to initialize..."
sleep 10

echo ""
echo "📊 Container Status:"
$DOCKER_COMPOSE ps

# Create marker
mkdir -p "$DEPLOY_DIR/.chengetai"
cat > "$DEPLOY_DIR/.chengetai/deployment.yaml" << MARKER
id: ${NAME}
plugin: farmOs
version: "4.x"
created: "$(date +%Y-%m-%d)"
MARKER

# Save deployment info
cat > "$DEPLOY_DIR/deployment-info.txt" << INFO
============================================
farmOS Deployment Information
============================================

Name:         ${NAME}
Version:      4.x

Access URL:   http://localhost:8081

Database:
  Host:       localhost:5433
  Name:       farm
  User:       farm
  Password:   ${DB_PASS}

Directories:
  Web:        ${DEPLOY_DIR}/www
  Database:   ${DEPLOY_DIR}/db
  Backups:    ${DEPLOY_DIR}/backups

============================================
INFO

echo ""
echo "╔════════════════════════════════════════════════╗"
echo "║     farmOS Deployment Complete!                ║"
echo "╚════════════════════════════════════════════════╝"
echo ""
echo "🌾 Access: http://144.91.125.128:8081"
echo ""
echo "Deployment info: $DEPLOY_DIR/deployment-info.txt"
