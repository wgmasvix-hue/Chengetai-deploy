#!/usr/bin/env bash
set -e

echo "🌾 Setting up farmOS..."
echo ""

# Wait for containers to be ready
echo "Waiting for farmOS to be ready..."
for i in {1..30}; do
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:8081 | grep -q "200\|302"; then
        echo "✓ farmOS is responding"
        break
    fi
    sleep 2
done

# Check if farmOS is already installed
if docker exec farm-www test -f /opt/drupal/web/sites/default/settings.php 2>/dev/null; then
    echo "✓ farmOS already installed"
else
    echo "Installing farmOS..."
    docker exec farm-www drush site:install farm --db-url=pgsql://farm:farmpass123@db/farm --site-name="My Farm" --account-name=admin --account-pass=admin123 --account-mail=admin@farm.local -y 2>/dev/null || {
        echo "Drush install skipped - use web installer at http://144.91.125.128:8081"
    }
fi

echo ""
echo "🌾 farmOS Setup Complete!"
echo "Access: http://144.91.125.128:8081"
echo "Username: admin"
echo "Password: admin123"
