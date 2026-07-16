#!/bin/bash
PLATFORM=$1

echo "Checking $PLATFORM services..."

# Get all containers for this platform
CONTAINERS=$(docker ps --filter "name=${PLATFORM}" --format "{{.Names}}")

for container in $CONTAINERS; do
    STATUS=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null)
    HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null)
    
    if [ "$STATUS" = "running" ]; then
        if [ "$HEALTH" = "healthy" ]; then
            echo "  ✅ $container: Running (Healthy)"
        elif [ "$HEALTH" = "starting" ]; then
            echo "  ⏳ $container: Starting up..."
        else
            echo "  ✅ $container: Running"
        fi
    else
        echo "  ❌ $container: $STATUS"
    fi
done

# Check common ports
echo ""
echo "Port checks:"
for port in 8080 8983 5432 3000 80 443; do
    if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
        echo "  ✅ Port $port: In use"
    fi
done
