#!/usr/bin/env bash
set -e

CHENGETAI_HOME="/opt/chengetai-deploy"
DEPLOYMENTS_DIR="$CHENGETAI_HOME/deployments"

ACTION="${1:-status}"
INSTANCE="${2:-library}"
DEPLOY_DIR="$DEPLOYMENTS_DIR/$INSTANCE"

case "$ACTION" in
    start)
        echo "Starting Koha instance: $INSTANCE"
        cd "$DEPLOY_DIR"
        docker-compose up -d
        echo "✓ Koha started"
        ;;
    stop)
        echo "Stopping Koha instance: $INSTANCE"
        cd "$DEPLOY_DIR"
        docker-compose stop
        echo "✓ Koha stopped"
        ;;
    restart)
        echo "Restarting Koha instance: $INSTANCE"
        cd "$DEPLOY_DIR"
        docker-compose restart
        echo "✓ Koha restarted"
        ;;
    status)
        echo "Koha instance: $INSTANCE"
        cd "$DEPLOY_DIR" 2>/dev/null || { echo "Instance not found"; exit 1; }
        docker-compose ps
        ;;
    logs)
        cd "$DEPLOY_DIR" 2>/dev/null || { echo "Instance not found"; exit 1; }
        docker-compose logs --tail=50 "${3:-koha-app}"
        ;;
    backup)
        echo "Creating backup for: $INSTANCE"
        BACKUP_DIR="$DEPLOY_DIR/backups/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        cd "$DEPLOY_DIR"
        docker-compose exec -T koha-db mysqldump -u root -p"${DB_PASS:-}" koha_${INSTANCE} > "$BACKUP_DIR/database.sql" 2>/dev/null || true
        tar -czf "$BACKUP_DIR/koha-data.tar.gz" -C "$DEPLOY_DIR" koha-data koha-config 2>/dev/null || true
        echo "✓ Backup created: $BACKUP_DIR"
        ;;
    remove)
        echo "Removing Koha instance: $INSTANCE"
        read -p "Are you sure? This will delete all data. [y/N] " confirm
        if [ "$confirm" = "y" ]; then
            cd "$DEPLOY_DIR"
            docker-compose down -v
            rm -rf "$DEPLOY_DIR"
            echo "✓ Koha instance removed"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs|backup|remove} [instance]"
        exit 1
        ;;
esac
