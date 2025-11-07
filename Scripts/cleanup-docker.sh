#!/bin/bash

# Script to completely clean up all Docker resources for the distributed Fuzzilli setup
# Usage: ./Scripts/cleanup-docker.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

MASTER_COMPOSE="docker-compose.master.yml"
WORKERS_COMPOSE="docker-compose.workers.yml"

echo "=========================================="
echo "  Cleaning up Docker resources"
echo "=========================================="
echo ""

# Stop and remove containers, networks, and volumes
echo "Stopping and removing containers..."
docker compose -f "$MASTER_COMPOSE" -f "$WORKERS_COMPOSE" down --volumes --remove-orphans 2>/dev/null || true

# Remove any remaining volumes
echo "Removing volumes..."
docker volume ls -q | grep -E "(fuzzillai_|postgres_|fuzzer_)" | xargs -r docker volume rm 2>/dev/null || true

# Remove any orphaned containers
echo "Removing orphaned containers..."
docker ps -a --filter "name=fuzzilli\|fuzzer-worker\|postgres-local\|postgres-master" --format "{{.ID}}" | xargs -r docker rm -f 2>/dev/null || true

# Remove any orphaned networks
echo "Removing orphaned networks..."
docker network ls --filter "name=fuzzing" --format "{{.ID}}" | xargs -r docker network rm 2>/dev/null || true

# Clean up any dangling images
echo "Removing dangling images..."
docker image prune -f 2>/dev/null || true

echo ""
echo "=========================================="
echo "  Cleanup complete!"
echo "=========================================="

