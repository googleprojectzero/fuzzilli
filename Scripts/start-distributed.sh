#!/bin/bash

# start-distributed.sh - Start distributed fuzzing with X workers
# Usage: ./Scripts/start-distributed.sh <X>
#   where X is the number of fuzzer workers to create
#
# Creates:
#   - 1 master postgres database
#   - X fuzzer worker containers
#   - X local postgres containers (one per fuzzer)
#
# Environment variables:
#   - V8_BUILD_PATH: Path to V8 build directory on host (default: /home/tropic/vrig/fuzzilli-vrig-proj/fuzzbuild)
#   - POSTGRES_PASSWORD: PostgreSQL password (default: fuzzilli123)
#   - SYNC_INTERVAL: Sync interval in seconds (default: 60)
#   - TIMEOUT: Execution timeout in ms (default: 2500)
#   - MIN_MUTATIONS_PER_SAMPLE: Minimum mutations per sample (default: 25)
#   - DEBUG_LOGGING: Enable debug logging (default: false)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MASTER_COMPOSE="${PROJECT_ROOT}/docker-compose.master.yml"
WORKER_COMPOSE="${PROJECT_ROOT}/docker-compose.workers.yml"

# Check if number of workers is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <X>"
    echo "  where X is the number of fuzzer workers to create"
    echo ""
    echo "Example: $0 3"
    echo "  Creates: 1 master postgres + 3 fuzzer workers + 3 local postgres"
    echo ""
    echo "Environment variables:"
    echo "  V8_BUILD_PATH - Path to V8 build on host (default: /home/tropic/vrig/fuzzilli-vrig-proj/fuzzbuild)"
    echo "  POSTGRES_PASSWORD - PostgreSQL password (default: fuzzilli123)"
    exit 1
fi

NUM_WORKERS=$1

# Validate number
if ! [[ "$NUM_WORKERS" =~ ^[0-9]+$ ]] || [ "$NUM_WORKERS" -lt 1 ]; then
    echo "Error: Number of workers must be a positive integer"
    exit 1
fi

echo "=========================================="
echo "Starting Distributed Fuzzilli"
echo "=========================================="
echo "Workers: $NUM_WORKERS"
echo "Master Postgres: 1"
echo ""

# Load environment variables
if [ -f "${PROJECT_ROOT}/.env" ]; then
    source "${PROJECT_ROOT}/.env"
elif [ -f "${PROJECT_ROOT}/env.distributed" ]; then
    source "${PROJECT_ROOT}/env.distributed"
fi

# Set defaults
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-fuzzilli123}
V8_BUILD_PATH=${V8_BUILD_PATH:-/home/tropic/vrig/fuzzilli-vrig-proj/fuzzbuild}
TIMEOUT=${TIMEOUT:-2500}
MIN_MUTATIONS_PER_SAMPLE=${MIN_MUTATIONS_PER_SAMPLE:-25}
DEBUG_LOGGING=${DEBUG_LOGGING:-false}

# Validate V8 build path
if [ ! -d "${V8_BUILD_PATH}" ]; then
    echo "Warning: V8 build path does not exist: ${V8_BUILD_PATH}"
    echo "         The container will start but may fail if V8 binary is not found"
fi

echo "Configuration:"
echo "  V8 Build Path: ${V8_BUILD_PATH}"
echo "  Timeout: ${TIMEOUT}ms"
echo ""

# Generate docker-compose worker file with all services
cat > "${WORKER_COMPOSE}" <<EOF
version: '3.8'

services:
EOF

# Generate worker services (fuzzer only, no local postgres)
for i in $(seq 1 $NUM_WORKERS); do
    cat >> "${WORKER_COMPOSE}" <<EOF

  # Worker $i - Fuzzilli Container
  fuzzer-worker-${i}:
    build:
      context: ${PROJECT_ROOT}
      dockerfile: Cloud/VRIG/Dockerfile.distributed
    container_name: fuzzer-worker-${i}
    environment:
      - POSTGRES_URL=postgresql://fuzzilli:${POSTGRES_PASSWORD}@postgres-master:5432/fuzzilli_master
      - FUZZER_INSTANCE_NAME=fuzzer-${i}
      - TIMEOUT=${TIMEOUT}
      - MIN_MUTATIONS_PER_SAMPLE=${MIN_MUTATIONS_PER_SAMPLE}
      - DEBUG_LOGGING=${DEBUG_LOGGING}
    depends_on:
      postgres-master:
        condition: service_healthy
    volumes:
      - fuzzer_data_${i}:/home/app/Corpus
      - ${V8_BUILD_PATH}:/home/app/fuzzbuild:ro
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pgrep -f FuzzilliCli || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    networks:
      - fuzzing-network
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 1G

EOF
done

# Add volumes section
cat >> "${WORKER_COMPOSE}" <<EOF

volumes:
EOF

for i in $(seq 1 $NUM_WORKERS); do
    cat >> "${WORKER_COMPOSE}" <<EOF
  fuzzer_data_${i}:
EOF
done

echo "Generated docker-compose files:"
echo "  Master: ${MASTER_COMPOSE}"
echo "  Workers: ${WORKER_COMPOSE}"
echo ""
echo "Starting services..."

# Start master postgres first
cd "${PROJECT_ROOT}"
echo "Starting master postgres..."
docker compose -f "${MASTER_COMPOSE}" up -d

# Wait for master postgres to be healthy
echo "Waiting for master postgres to be ready..."
timeout=60
while [ $timeout -gt 0 ]; do
    if docker exec fuzzilli-postgres-master pg_isready -U fuzzilli -d fuzzilli_master > /dev/null 2>&1; then
        echo "✓ Master postgres is ready"
        break
    fi
    sleep 1
    timeout=$((timeout - 1))
done

if [ $timeout -eq 0 ]; then
    echo "✗ Error: Master postgres failed to start"
    exit 1
fi

# Start worker services
echo "Starting worker services..."
docker compose -f "${MASTER_COMPOSE}" -f "${WORKER_COMPOSE}" up -d --build

# Wait a bit for fuzzers to start
echo ""
echo "Waiting for fuzzer containers to initialize..."
sleep 10

echo ""
echo "=========================================="
echo "Distributed fuzzing setup complete!"
echo "=========================================="
echo ""
echo "Services started:"
echo "  Master Postgres: fuzzilli-postgres-master"
for i in $(seq 1 $NUM_WORKERS); do
    echo "  Worker $i: fuzzer-worker-${i}"
done
echo ""
echo "To view logs:"
echo "  docker compose -f ${MASTER_COMPOSE} -f ${WORKER_COMPOSE} logs -f"
echo ""
echo "To view specific worker logs:"
echo "  docker compose -f ${MASTER_COMPOSE} -f ${WORKER_COMPOSE} logs -f fuzzer-worker-1"
echo ""
echo "To check status:"
echo "  docker compose -f ${MASTER_COMPOSE} -f ${WORKER_COMPOSE} ps"
echo ""
echo "To stop all services:"
echo "  docker compose -f ${MASTER_COMPOSE} -f ${WORKER_COMPOSE} down"
echo ""
echo "To stop a specific worker:"
echo "  docker stop fuzzer-worker-<N>"
echo ""
