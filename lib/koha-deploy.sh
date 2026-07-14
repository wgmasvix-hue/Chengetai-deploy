#!/usr/bin/env bash
set -e

NAME="${1:-library}"
DEPLOY_DIR="/opt/chengetai-deploy/deployments/$NAME"

# Detect docker compose command
if docker compose version &>/dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    DOCKER_COMPOSE="docker-compose"
fi

echo "╔════════════════════════════════════════════════╗"
echo "║     ChengetAI Koha Deployment                 ║"
echo "╚════════════════════════════════════════════════╝"
echo ""
echo "Instance: $NAME"
echo "Compose:  $DOCKER_COMPOSE"
echo ""

# Create directories
echo "📁 Creating directories..."
mkdir -p "$DEPLOY_DIR"/{mysql,elasticsearch,memcached,logs,backups}

# Create docker-compose.yml
echo "🐳 Creating Docker Compose file..."
cat > "$DEPLOY_DIR/docker-compose.yml" << COMPOSE
version: '3.8'

services:
  db:
    image: mysql:8.0
    container_name: ${NAME}-db
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: koha123
      MYSQL_DATABASE: koha_${NAME}
      MYSQL_USER: koha
      MYSQL_PASSWORD: koha123
    volumes:
      - ./mysql:/var/lib/mysql
    ports:
      - "3307:3306"
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5

  elasticsearch:
    image: elasticsearch:7.17.0
    container_name: ${NAME}-elasticsearch
    restart: unless-stopped
    environment:
      - discovery.type=single-node
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
    volumes:
      - ./elasticsearch:/usr/share/elasticsearch/data

  memcached:
    image: memcached:alpine
    container_name: ${NAME}-memcached
    restart: unless-stopped

  app:
    image: debian:bookworm-slim
    container_name: ${NAME}-app
    restart: unless-stopped
    command: >
      bash -c "
        apt-get update -qq &&
        apt-get install -y -qq wget gnupg2 apache2 mysql-client &&
        wget -qO- https://debian.koha-community.org/koha/gpg.asc | gpg --dearmor > /usr/share/keyrings/koha-keyring.gpg &&
        echo 'deb [signed-by=/usr/share/keyrings/koha-keyring.gpg] http://debian.koha-community.org/koha stable main' > /etc/apt/sources.list.d/koha.list &&
        apt-get update -qq &&
        apt-get install -y -qq koha-common &&
        a2enmod rewrite cgi &&
        service apache2 start &&
        echo 'Koha installed. Run web installer at http://localhost:8081' &&
        tail -f /dev/null
      "
    ports:
      - "8081:80"
      - "8082:8080"
    depends_on:
      db:
        condition: service_healthy
    volumes:
      - ./logs:/var/log/koha
COMPOSE

echo "🚀 Starting containers..."
cd "$DEPLOY_DIR"
$DOCKER_COMPOSE up -d

echo ""
echo "⏳ Waiting for services to initialize..."
sleep 20

echo ""
echo "📊 Container Status:"
$DOCKER_COMPOSE ps

echo ""
echo "╔════════════════════════════════════════════════╗"
echo "║     Koha Deployment Complete!                  ║"
echo "╚════════════════════════════════════════════════╝"
echo ""
echo "Access URLs (after web installer completes):"
echo "  Staff: http://144.91.125.128:8081"
echo "  OPAC:  http://144.91.125.128:8082"
echo ""
echo "Default login after web installer:"
echo "  Username: admin"
echo "  Password: admin123"
echo ""
echo "Check logs: $DOCKER_COMPOSE logs app"

# Create marker
mkdir -p "$DEPLOY_DIR/.chengetai"
cat > "$DEPLOY_DIR/.chengetai/deployment.yaml" << MARKER
id: ${NAME}
plugin: koha
version: "24.05"
created: "$(date +%Y-%m-%d)"
MARKER

echo ""
echo "✅ Deployment marker created"
echo "Run './chengetai' to manage your Koha instance"
