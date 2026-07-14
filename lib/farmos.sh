#!/usr/bin/env bash
set -e

ACTION="${1:-status}"
NAME="${2:-farmos}"
DEPLOY_DIR="/opt/chengetai-deploy/deployments/$NAME"

case "$ACTION" in
    deploy)
        echo "🌾 Deploying farmOS..."
        mkdir -p "$DEPLOY_DIR"/{www,db,backups}
        
        if [ ! -f "$DEPLOY_DIR/docker-compose.yml" ]; then
            cp /opt/chengetai-deploy/lib/farmos-compose.yml "$DEPLOY_DIR/docker-compose.yml" 2>/dev/null || true
        fi
        
        cd "$DEPLOY_DIR"
        docker compose up -d
        
        # Setup
        sleep 15
        bash /opt/chengetai-deploy/lib/farmos-setup.sh
        
        # Create marker
        mkdir -p "$DEPLOY_DIR/.chengetai"
        cat > "$DEPLOY_DIR/.chengetai/deployment.yaml" << MARKER
id: ${NAME}
plugin: farmOs
version: "4.x"
created: "$(date +%Y-%m-%d)"
MARKER
        ;;
    start)
        cd "$DEPLOY_DIR" 2>/dev/null && docker compose start || {
            docker start farm-db farm-www 2>/dev/null || docker start docker-db-1 docker-www-1
        }
        ;;
    stop)
        cd "$DEPLOY_DIR" 2>/dev/null && docker compose stop || {
            docker stop farm-www farm-db 2>/dev/null || docker stop docker-www-1 docker-db-1
        }
        ;;
    restart)
        cd "$DEPLOY_DIR" 2>/dev/null && docker compose restart || {
            docker restart farm-db farm-www 2>/dev/null || docker restart docker-db-1 docker-www-1
        }
        ;;
    status)
        docker ps --filter "name=farm" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
        ;;
    logs)
        docker logs --tail=50 farm-www 2>/dev/null || docker logs --tail=50 docker-www-1
        ;;
    backup)
        BACKUP_DIR="$DEPLOY_DIR/backups/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        echo "🌾 Backing up farmOS..."
        docker exec farm-db pg_dump -U farm farm > "$BACKUP_DIR/database.sql" 2>/dev/null || \
            docker exec docker-db-1 pg_dump -U farm farm > "$BACKUP_DIR/database.sql"
        echo "✓ Backup: $BACKUP_DIR/database.sql"
        ;;
    remove)
        echo "⚠ This will delete all farmOS data!"
        read -p "Are you sure? [y/N] " confirm
        if [ "$confirm" = "y" ]; then
            cd "$DEPLOY_DIR" 2>/dev/null && docker compose down -v || true
            rm -rf "$DEPLOY_DIR"
            echo "✓ farmOS removed"
        fi
        ;;
    *)
        echo "🌾 farmOS Management"
        echo "Usage: $0 {deploy|start|stop|restart|status|logs|backup|remove} [name]"
        ;;
esac
