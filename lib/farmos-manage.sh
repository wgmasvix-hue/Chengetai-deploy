#!/usr/bin/env bash
set -e

ACTION="${1:-status}"
NAME="${2:-farmOs}"
DEPLOY_DIR="/opt/chengetai-deploy/deployments/$NAME"

case "$ACTION" in
    start)
        echo "🌾 Starting farmOS: $NAME"
        cd "$DEPLOY_DIR" 2>/dev/null && docker compose up -d || {
            docker start docker-db-1 docker-www-1
        }
        echo "✓ farmOS started"
        ;;
    stop)
        echo "🌾 Stopping farmOS: $NAME"
        cd "$DEPLOY_DIR" 2>/dev/null && docker compose stop || {
            docker stop docker-www-1 docker-db-1
        }
        echo "✓ farmOS stopped"
        ;;
    restart)
        echo "🌾 Restarting farmOS: $NAME"
        cd "$DEPLOY_DIR" 2>/dev/null && docker compose restart || {
            docker restart docker-db-1 docker-www-1
        }
        echo "✓ farmOS restarted"
        ;;
    status)
        echo "🌾 farmOS Status:"
        docker ps --filter "name=docker-www-1" --filter "name=docker-db-1" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        ;;
    logs)
        docker logs --tail=50 docker-www-1
        ;;
    backup)
        BACKUP_DIR="$DEPLOY_DIR/backups/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        echo "🌾 Creating farmOS backup..."
        docker exec docker-db-1 pg_dump -U farm farm > "$BACKUP_DIR/database.sql" 2>/dev/null || true
        tar -czf "$BACKUP_DIR/www.tar.gz" -C "$DEPLOY_DIR" www 2>/dev/null || true
        echo "✓ Backup created: $BACKUP_DIR"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs|backup} [name]"
        exit 1
        ;;
esac
