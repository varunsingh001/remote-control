#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Building python-sandbox image..."
docker build -t python-sandbox "$SCRIPT_DIR"

echo "Removing old container if exists..."
docker rm -f python-sandbox 2>/dev/null || true

echo "Starting sandbox container..."
docker run -d \
    --name python-sandbox \
    --restart unless-stopped \
    --read-only \
    --tmpfs /tmp:size=50m \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    --memory 512m \
    --cpus 1 \
    --pids-limit 50 \
    -p 8050:8050 \
    python-sandbox

echo "Waiting for sandbox to be ready..."
for i in $(seq 1 30); do
    if curl -s http://localhost:8050/health >/dev/null 2>&1; then
        echo "Sandbox ready on http://localhost:8050"
        exit 0
    fi
    sleep 1
done

echo "Sandbox failed to start. Check: docker logs python-sandbox"
exit 1
