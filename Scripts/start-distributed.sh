#!/bin/bash

# start-distributed.sh - Start distributed fuzzing with N workers
# Usage: ./Scripts/start-distributed.sh <number_of_workers>
#
# This script creates N worker containers, each with:
# - A fuzzilli container
# - A local postgres container
# - Proper networking and volumes

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.distributed.yml"
COMPOSE_OVERRIDE="${PROJECT_ROOT}/docker-compose.workers.yml"

# Check if number of workers is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <number_of_workers>"
    echo "Example: $0 3"
    exit 1
fi

NUM_WORKERS=$1

# Validate number
if ! [[ "$NUM_WORKERS" =~ ^[0-9]+$ ]] || [ "$NUM_WORKERS" -lt 1 ]; then
    echo "Error: Number of workers must be a positive integer"
    exit 1
fi

echo "Starting distributed fuzzing with $NUM_WORKERS workers..."

# Load environment variables
if [ -f "${PROJECT_ROOT}/.env" ]; then
    source "${PROJECT_ROOT}/.env"
elif [ -f "${PROJECT_ROOT}/env.distributed" ]; then
    source "${PROJECT_ROOT}/env.distributed"
fi

POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-fuzzilli123}
SYNC_INTERVAL=${SYNC_INTERVAL:-300}
TIMEOUT=${TIMEOUT:-2500}
MIN_MUTATIONS_PER_SAMPLE=${MIN_MUTATIONS_PER_SAMPLE:-25}
DEBUG_LOGGING=${DEBUG_LOGGING:-false}

# Generate docker-compose override file with worker services
cat > "${COMPOSE_OVERRIDE}" <<EOF
version: '3.8'

services:
EOF

# Generate worker services
for i in $(seq 1 $NUM_WORKERS); do
    cat >> "${COMPOSE_OVERRIDE}" <<EOF

  # Worker $i - Local Postgres
  postgres-local-${i}:
    image: postgres:15-alpine
    container_name: postgres-local-${i}
    environment:
      POSTGRES_DB: fuzzilli_local
      POSTGRES_USER: fuzzilli
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_INITDB_ARGS: "--encoding=UTF-8 --lc-collate=C --lc-ctype=C"
    volumes:
      - postgres_local_data_${i}:/var/lib/postgresql/data
      - ${PROJECT_ROOT}/postgres-init.sql:/docker-entrypoint-initdb.d/init.sql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U fuzzilli -d fuzzilli_local"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped
    networks:
      - fuzzing-network

  # Worker $i - Fuzzilli Container
  fuzzer-worker-${i}:
    build:
      context: ${PROJECT_ROOT}
      dockerfile: Cloud/VRIG/Dockerfile.distributed
    container_name: fuzzer-worker-${i}
    environment:
      - MASTER_POSTGRES_URL=postgresql://fuzzilli:${POSTGRES_PASSWORD}@postgres-master:5432/fuzzilli_master
      - LOCAL_POSTGRES_URL=postgresql://fuzzilli:${POSTGRES_PASSWORD}@postgres-local-${i}:5432/fuzzilli_local
      - FUZZER_INSTANCE_NAME=fuzzer-${i}
      - SYNC_INTERVAL=${SYNC_INTERVAL}
      - TIMEOUT=${TIMEOUT}
      - MIN_MUTATIONS_PER_SAMPLE=${MIN_MUTATIONS_PER_SAMPLE}
      - DEBUG_LOGGING=${DEBUG_LOGGING}
    depends_on:
      postgres-master:
        condition: service_healthy
      postgres-local-${i}:
        condition: service_healthy
    volumes:
      - fuzzer_data_${i}:/home/app/Corpus
      - /home/tropic/vrig/fuzzilli-vrig-proj/fuzzbuild:/home/app/fuzzbuild:ro
    restart: unless-stopped
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
cat >> "${COMPOSE_OVERRIDE}" <<EOF

volumes:
EOF

for i in $(seq 1 $NUM_WORKERS); do
    cat >> "${COMPOSE_OVERRIDE}" <<EOF
  postgres_local_data_${i}:
  fuzzer_data_${i}:
EOF
done

echo "Generated docker-compose override file: ${COMPOSE_OVERRIDE}"
echo "Starting services..."

# Start all services together (master and workers)
cd "${PROJECT_ROOT}"
docker-compose -f "${COMPOSE_FILE}" -f "${COMPOSE_OVERRIDE}" up -d --remove-orphans

# Wait for main postgres to be healthy
echo "Waiting for main postgres to be ready..."
timeout=60
while [ $timeout -gt 0 ]; do
    if docker exec fuzzilli-postgres-master pg_isready -U fuzzilli -d fuzzilli_master > /dev/null 2>&1; then
        echo "Main postgres is ready"
        break
    fi
    sleep 1
    timeout=$((timeout - 1))
done

if [ $timeout -eq 0 ]; then
    echo "Error: Main postgres failed to start"
    exit 1
fi

# Wait for local postgres containers to be healthy
echo "Waiting for local postgres containers to be ready..."
for i in $(seq 1 $NUM_WORKERS); do
    timeout=60
    while [ $timeout -gt 0 ]; do
        if docker exec postgres-local-${i} pg_isready -U fuzzilli -d fuzzilli_local > /dev/null 2>&1; then
            echo "Local postgres-${i} is ready"
            break
        fi
        sleep 1
        timeout=$((timeout - 1))
    done
    if [ $timeout -eq 0 ]; then
        echo "Warning: Local postgres-${i} may not be ready"
    fi
done

echo ""
echo "Distributed fuzzing setup complete!"
echo "Started $NUM_WORKERS workers:"
for i in $(seq 1 $NUM_WORKERS); do
    echo "  - fuzzer-worker-${i} (local postgres: postgres-local-${i})"
done
echo ""
echo "To view logs:"
echo "  docker-compose -f ${COMPOSE_FILE} -f ${COMPOSE_OVERRIDE} logs -f"
echo ""
echo "To stop all services:"
echo "  docker-compose -f ${COMPOSE_FILE} -f ${COMPOSE_OVERRIDE} down"
echo ""
echo "To stop a specific worker:"
echo "  docker stop fuzzer-worker-<N> postgres-local-<N>"

