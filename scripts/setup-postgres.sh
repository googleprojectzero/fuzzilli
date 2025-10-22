#!/bin/bash

# Setup PostgreSQL for Fuzzilli testing
set -e

echo "=== Fuzzilli PostgreSQL Setup ==="

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null; then
    echo "Error: docker-compose is not installed"
    echo "Please install docker-compose to continue"
    exit 1
fi

# Check if docker is running
if ! docker info &> /dev/null; then
    echo "Error: Docker is not running"
    echo "Please start Docker and try again"
    exit 1
fi

echo "Starting PostgreSQL container..."
docker-compose up -d postgres

echo "Waiting for PostgreSQL to be ready..."
timeout=60
counter=0
while ! docker-compose exec postgres pg_isready -U fuzzilli -d fuzzilli &> /dev/null; do
    if [ $counter -ge $timeout ]; then
        echo "Error: PostgreSQL failed to start within $timeout seconds"
        docker-compose logs postgres
        exit 1
    fi
    echo "Waiting for PostgreSQL... ($counter/$timeout)"
    sleep 2
    counter=$((counter + 2))
done

echo "PostgreSQL is ready!"

# Test connection
echo "Testing database connection..."
docker-compose exec postgres psql -U fuzzilli -d fuzzilli -c "SELECT version();"

echo "Checking if tables exist..."
docker-compose exec postgres psql -U fuzzilli -d fuzzilli -c "
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
ORDER BY table_name;
"

echo "Checking execution types..."
docker-compose exec postgres psql -U fuzzilli -d fuzzilli -c "
SELECT id, title, description 
FROM execution_type 
ORDER BY id;
"

echo "Checking mutator types..."
docker-compose exec postgres psql -U fuzzilli -d fuzzilli -c "
SELECT id, name, category 
FROM mutator_type 
ORDER BY id;
"

echo "Checking execution outcomes..."
docker-compose exec postgres psql -U fuzzilli -d fuzzilli -c "
SELECT id, outcome, description 
FROM execution_outcome 
ORDER BY id;
"

echo ""
echo "=== PostgreSQL Setup Complete ==="
echo "Connection string: postgresql://fuzzilli:fuzzilli123@localhost:5433/fuzzilli"
echo ""
echo "To start pgAdmin (optional):"
echo "  docker-compose up -d pgadmin"
echo "  Open http://localhost:8080"
echo "  Login: admin@fuzzilli.local / admin123"
echo ""
echo "To stop PostgreSQL:"
echo "  docker-compose down"
echo ""
echo "To view logs:"
echo "  docker-compose logs postgres"
