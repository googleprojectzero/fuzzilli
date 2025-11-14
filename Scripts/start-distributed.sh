#!/bin/bash

# start-distributed.sh - Start distributed fuzzing with X workers
# Usage: ./Scripts/start-distributed.sh <X> [--remote-db <host>]
#   where X is the number of fuzzer workers to create
#   --remote-db <host> optionally specifies a remote PostgreSQL host (overrides POSTGRES_HOST env var)
#
# Creates:
#   - 1 master postgres database (local, unless POSTGRES_HOST is set or --remote-db is used)
#   - X fuzzer worker containers
#
# Environment variables:
#   - V8_BUILD_PATH: Path to V8 build directory on host (default: /home/tropic/vrig/fuzzilli-vrig-proj/fuzzbuild)
#   - POSTGRES_HOST: Remote PostgreSQL host/IP (if set, enables remote mode, skips local postgres)
#   - POSTGRES_PORT: PostgreSQL port (default: 5432)
#   - POSTGRES_DB: Database name (default: fuzzilli_master)
#   - POSTGRES_USER: Database user (default: fuzzilli)
#   - POSTGRES_PASSWORD: PostgreSQL password (default: fuzzilli123)
#   - POSTGRES_DATA_PATH: Custom path for PostgreSQL data directory on host (e.g., /vdc/postgres-data)
#                         If set, uses bind mount instead of Docker named volume
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
    echo "Usage: $0 <X> [--remote-db <host>]"
    echo "  where X is the number of fuzzer workers to create"
    echo "  --remote-db <host> optionally specifies a remote PostgreSQL host"
    echo ""
    echo "Examples:"
    echo "  $0 3"
    echo "    Creates: 1 local master postgres + 3 fuzzer workers"
    echo ""
    echo "  $0 8 --remote-db 192.168.1.100"
    echo "    Creates: 8 fuzzer workers connecting to remote postgres at 192.168.1.100"
    echo ""
    echo "Environment variables:"
    echo "  V8_BUILD_PATH - Path to V8 build on host (default: /home/tropic/vrig/fuzzilli-vrig-proj/fuzzbuild)"
    echo "  POSTGRES_HOST - Remote PostgreSQL host/IP (if set, enables remote mode)"
    echo "  POSTGRES_PORT - PostgreSQL port (default: 5432)"
    echo "  POSTGRES_DB - Database name (default: fuzzilli_master)"
    echo "  POSTGRES_USER - Database user (default: fuzzilli)"
    echo "  POSTGRES_PASSWORD - PostgreSQL password (default: fuzzilli123)"
    echo "  POSTGRES_DATA_PATH - Custom path for PostgreSQL data (e.g., /vdc/postgres-data)"
    exit 1
fi

NUM_WORKERS=$1
shift  # Remove first argument

# Parse command-line arguments
REMOTE_DB_HOST=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --remote-db)
            if [ -z "$2" ]; then
                echo "Error: --remote-db requires a host argument"
                exit 1
            fi
            REMOTE_DB_HOST="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown option: $1"
            echo "Usage: $0 <X> [--remote-db <host>]"
            exit 1
            ;;
    esac
done

# Validate number
if ! [[ "$NUM_WORKERS" =~ ^[0-9]+$ ]] || [ "$NUM_WORKERS" -lt 1 ]; then
    echo "Error: Number of workers must be a positive integer"
    exit 1
fi

# Load environment variables
if [ -f "${PROJECT_ROOT}/.env" ]; then
    source "${PROJECT_ROOT}/.env"
elif [ -f "${PROJECT_ROOT}/env.distributed" ]; then
    source "${PROJECT_ROOT}/env.distributed"
fi

# Set defaults
# Command-line --remote-db overrides POSTGRES_HOST environment variable
if [ -n "$REMOTE_DB_HOST" ]; then
    POSTGRES_HOST="$REMOTE_DB_HOST"
fi

POSTGRES_HOST=${POSTGRES_HOST:-}
POSTGRES_PORT=${POSTGRES_PORT:-5432}
POSTGRES_DB=${POSTGRES_DB:-fuzzilli_master}
POSTGRES_USER=${POSTGRES_USER:-fuzzilli}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-fuzzilli123}
POSTGRES_DATA_PATH=${POSTGRES_DATA_PATH:-}
V8_BUILD_PATH=${V8_BUILD_PATH:-/home/tropic/vrig/fuzzilli-vrig-proj/fuzzbuild}
TIMEOUT=${TIMEOUT:-2500}
MIN_MUTATIONS_PER_SAMPLE=${MIN_MUTATIONS_PER_SAMPLE:-25}
DEBUG_LOGGING=${DEBUG_LOGGING:-false}

# Determine if we're using remote or local postgres
USE_REMOTE_DB=false
if [ -n "$POSTGRES_HOST" ]; then
    USE_REMOTE_DB=true
fi

# Get hostname for fuzzer instance naming
HOSTNAME=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "unknown")

echo "=========================================="
echo "Starting Distributed Fuzzilli"
echo "=========================================="
echo "Workers: $NUM_WORKERS"
if [ "$USE_REMOTE_DB" = true ]; then
    echo "Master Postgres: Remote (${POSTGRES_HOST}:${POSTGRES_PORT})"
else
    echo "Master Postgres: Local (will be started)"
fi
echo ""

# Validate V8 build path
if [ ! -d "${V8_BUILD_PATH}" ]; then
    echo "Warning: V8 build path does not exist: ${V8_BUILD_PATH}"
    echo "         The container will start but may fail if V8 binary is not found"
fi

echo "Configuration:"
echo "  V8 Build Path: ${V8_BUILD_PATH}"
echo "  Timeout: ${TIMEOUT}ms"
if [ "$USE_REMOTE_DB" = true ]; then
    echo "  Database: ${POSTGRES_USER}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
elif [ -n "$POSTGRES_DATA_PATH" ]; then
    echo "  PostgreSQL Data Path: ${POSTGRES_DATA_PATH}"
fi
echo ""

# Generate docker-compose worker file with all services
cat > "${WORKER_COMPOSE}" <<EOF
version: '3.8'

services:
EOF

# Generate worker services (fuzzer only, no local postgres)
for i in $(seq 1 $NUM_WORKERS); do
    # Build connection string based on mode
    if [ "$USE_REMOTE_DB" = true ]; then
        POSTGRES_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
    else
        POSTGRES_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres-master:5432/${POSTGRES_DB}"
    fi
    
    cat >> "${WORKER_COMPOSE}" <<EOF

  # Worker $i - Fuzzilli Container
  fuzzer-worker-${i}:
    build:
      context: ${PROJECT_ROOT}
      dockerfile: Cloud/VRIG/Dockerfile.distributed
    container_name: fuzzer-worker-${i}
    environment:
      - POSTGRES_URL=${POSTGRES_URL}
      - FUZZER_INSTANCE_NAME=fuzzer-${HOSTNAME}-${i}
      - TIMEOUT=${TIMEOUT}
      - MIN_MUTATIONS_PER_SAMPLE=${MIN_MUTATIONS_PER_SAMPLE}
      - DEBUG_LOGGING=${DEBUG_LOGGING}
EOF

    # Only add depends_on for local postgres mode
    if [ "$USE_REMOTE_DB" = false ]; then
        cat >> "${WORKER_COMPOSE}" <<EOF
    depends_on:
      postgres-master:
        condition: service_healthy
EOF
    fi

    cat >> "${WORKER_COMPOSE}" <<EOF
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
EOF

    # Only add network for local mode (remote mode doesn't need docker network)
    if [ "$USE_REMOTE_DB" = false ]; then
        cat >> "${WORKER_COMPOSE}" <<EOF
    networks:
      - fuzzing-network
EOF
    fi

    cat >> "${WORKER_COMPOSE}" <<EOF
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

# Generate master compose file if using custom data path
if [ "$USE_REMOTE_DB" = false ] && [ -n "$POSTGRES_DATA_PATH" ]; then
    echo "Generating master compose file with custom data path..."
    # Create directory if it doesn't exist
    mkdir -p "${POSTGRES_DATA_PATH}"
    
    # Generate master compose file with bind mount
    cat > "${MASTER_COMPOSE}" <<EOF
version: '3.8'

services:
  postgres-master:
    image: postgres:15-alpine
    container_name: fuzzilli-postgres-master
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_INITDB_ARGS: "--encoding=UTF-8 --lc-collate=C --lc-ctype=C"
    ports:
      - "5432:5432"
    volumes:
      - ${POSTGRES_DATA_PATH}:/var/lib/postgresql/data
      - ${PROJECT_ROOT}/postgres-init.sql:/docker-entrypoint-initdb.d/init.sql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped
    networks:
      - fuzzing-network

networks:
  fuzzing-network:
    driver: bridge

EOF
fi

echo "Generated docker-compose files:"
if [ "$USE_REMOTE_DB" = false ]; then
    if [ -n "$POSTGRES_DATA_PATH" ]; then
        echo "  Master: ${MASTER_COMPOSE} (generated with custom data path: ${POSTGRES_DATA_PATH})"
    else
        echo "  Master: ${MASTER_COMPOSE}"
    fi
fi
echo "  Workers: ${WORKER_COMPOSE}"
echo ""
echo "Starting services..."

cd "${PROJECT_ROOT}"

# Start master postgres only if using local mode
if [ "$USE_REMOTE_DB" = false ]; then
    echo "Starting master postgres..."
    docker compose -f "${MASTER_COMPOSE}" up -d

    # Wait for master postgres to be healthy
    echo "Waiting for master postgres to be ready..."
    timeout=60
    while [ $timeout -gt 0 ]; do
        if docker exec fuzzilli-postgres-master pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB} > /dev/null 2>&1; then
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
else
    # Check remote postgres connection
    echo "Checking remote postgres connection..."
    timeout=60
    while [ $timeout -gt 0 ]; do
        if PGPASSWORD="${POSTGRES_PASSWORD}" psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -c "SELECT 1" > /dev/null 2>&1; then
            echo "✓ Remote postgres is ready"
            break
        fi
        sleep 1
        timeout=$((timeout - 1))
    done

    if [ $timeout -eq 0 ]; then
        echo "✗ Error: Cannot connect to remote postgres at ${POSTGRES_HOST}:${POSTGRES_PORT}"
        echo "  Please verify:"
        echo "    - PostgreSQL is running and accessible"
        echo "    - Host, port, user, password, and database name are correct"
        echo "    - Network connectivity and firewall rules allow connection"
        exit 1
    fi
fi

# Start worker services
echo "Starting worker services..."
if [ "$USE_REMOTE_DB" = false ]; then
    docker compose -f "${MASTER_COMPOSE}" -f "${WORKER_COMPOSE}" up -d --build
else
    docker compose -f "${WORKER_COMPOSE}" up -d --build
fi

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
if [ "$USE_REMOTE_DB" = false ]; then
    echo "  Master Postgres: fuzzilli-postgres-master (local)"
else
    echo "  Master Postgres: ${POSTGRES_HOST}:${POSTGRES_PORT} (remote)"
fi
for i in $(seq 1 $NUM_WORKERS); do
    echo "  Worker $i: fuzzer-worker-${i}"
done
echo ""
echo "To view logs:"
if [ "$USE_REMOTE_DB" = false ]; then
    echo "  docker compose -f ${MASTER_COMPOSE} -f ${WORKER_COMPOSE} logs -f"
else
    echo "  docker compose -f ${WORKER_COMPOSE} logs -f"
fi
echo ""
echo "To view specific worker logs:"
if [ "$USE_REMOTE_DB" = false ]; then
    echo "  docker compose -f ${MASTER_COMPOSE} -f ${WORKER_COMPOSE} logs -f fuzzer-worker-1"
else
    echo "  docker compose -f ${WORKER_COMPOSE} logs -f fuzzer-worker-1"
fi
echo ""
echo "To check status:"
if [ "$USE_REMOTE_DB" = false ]; then
    echo "  docker compose -f ${MASTER_COMPOSE} -f ${WORKER_COMPOSE} ps"
else
    echo "  docker compose -f ${WORKER_COMPOSE} ps"
fi
echo ""
echo "To stop all services:"
if [ "$USE_REMOTE_DB" = false ]; then
    echo "  docker compose -f ${MASTER_COMPOSE} -f ${WORKER_COMPOSE} down"
else
    echo "  docker compose -f ${WORKER_COMPOSE} down"
fi
echo ""
echo "To stop a specific worker:"
echo "  docker stop fuzzer-worker-<N>"
echo ""
