#!/bin/bash

# Setup PostgreSQL for Fuzzilli testing
set -e

echo "=== Fuzzilli PostgreSQL Setup ==="

# Detect container runtime
if command -v docker &> /dev/null; then
    CONTAINER_RUNTIME="docker"
    echo "Using Docker"
elif command -v podman &> /dev/null; then
    CONTAINER_RUNTIME="podman"
    echo "Using Podman"
else
    echo "Error: Neither docker-compose nor podman is available"
    echo "Please install docker-compose or podman to continue"
    exit 1
fi

# Detect compose command
if command -v docker &> /dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v podman-compose &> /dev/null; then
    COMPOSE_CMD="podman-compose"
else
    echo "Error: No compose command found, do you have docker-compose or po installed?"
    exit 1
fi

# Check if container runtime is accessible
if ! $CONTAINER_RUNTIME info &> /dev/null; then
    echo "Error: $CONTAINER_RUNTIME is not accessible"
    echo "Please ensure $CONTAINER_RUNTIME is running and try again"
    exit 1
fi

echo "Starting PostgreSQL container..."
$COMPOSE_CMD up -d postgres

echo "Waiting for PostgreSQL to be ready..."
timeout=60
counter=0
while ! $COMPOSE_CMD exec postgres pg_isready -U fuzzilli -d fuzzilli &> /dev/null; do
    if [ $counter -ge $timeout ]; then
        echo "Error: PostgreSQL failed to start within $timeout seconds"
        $COMPOSE_CMD logs postgres
        exit 1
    fi
    echo "Waiting for PostgreSQL... ($counter/$timeout)"
    sleep 2
    counter=$((counter + 2))
done

echo "PostgreSQL is ready!"

# Test connection
echo "Testing database connection..."
$COMPOSE_CMD exec postgres psql -U fuzzilli -d fuzzilli -c "SELECT version();"

echo "Checking if tables exist..."
$COMPOSE_CMD exec postgres psql -U fuzzilli -d fuzzilli -c "
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
ORDER BY table_name;
"

echo "Checking execution types..."
$COMPOSE_CMD exec postgres psql -U fuzzilli -d fuzzilli -c "
SELECT id, title, description 
FROM execution_type 
ORDER BY id;
"

echo "Checking mutator types..."
$COMPOSE_CMD exec postgres psql -U fuzzilli -d fuzzilli -c "
SELECT id, name, category 
FROM mutator_type 
ORDER BY id;
"

echo "Checking execution outcomes..."
$COMPOSE_CMD exec postgres psql -U fuzzilli -d fuzzilli -c "
SELECT id, outcome, description 
FROM execution_outcome 
ORDER BY id;
"

echo ""
echo "=== PostgreSQL Setup Complete ==="
echo "Connection string: postgresql://fuzzilli:fuzzilli123@localhost:5433/fuzzilli"
echo ""
echo "To start pgAdmin (optional):"
echo "  $COMPOSE_CMD up -d pgadmin"
echo "  Open http://localhost:8080"
echo "  Login: admin@fuzzilli.local / admin123"
echo ""
echo "To stop PostgreSQL:"
echo "  $COMPOSE_CMD down"
echo ""
echo "To view logs:"
echo "  $COMPOSE_CMD logs postgres"
