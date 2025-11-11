#!/bin/bash

# Script to fully clear all PostgreSQL databases (master and all local workers)
# This script truncates all tables in all databases to remove all data
# Usage: ./Scripts/clear-postgres-db.sh [--force]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check for --force flag
FORCE=false
if [ "$1" == "--force" ]; then
    FORCE=true
fi

# Function to check if Docker is available
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Error: Docker command not found. Please install Docker.${NC}"
        exit 1
    fi
}

# Function to clear a database
clear_database() {
    local container_name="$1"
    local db_name="$2"
    local db_user="${3:-fuzzilli}"
    local db_password="${4:-fuzzilli123}"
    
    echo -e "${BLUE}Clearing database '${db_name}' in container '${container_name}'...${NC}"
    
    # Check if container is running (handle both short and full container names)
    local container_running=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^(${container_name}|fuzzilli-${container_name})$ ]]; then
            container_running="$line"
            break
        fi
    done < <(docker ps --format "{{.Names}}")
    
    if [ -z "$container_running" ]; then
        echo -e "${YELLOW}Warning: Container '${container_name}' or 'fuzzilli-${container_name}' is not running. Skipping.${NC}"
        return 0
    fi
    # Use the actual running container name
    local actual_container_name="$container_running"
    
    # List of tables to truncate (in order to handle foreign keys)
    # Using TRUNCATE CASCADE to handle foreign key constraints
    local truncate_sql="
        TRUNCATE TABLE 
            coverage_detail,
            feedback_vector_detail,
            execution,
            program,
            fuzzer,
            coverage_snapshot,
            main
        CASCADE;
    "
    
    # Execute truncate (use actual container name if found)
    local exec_container="${actual_container_name:-${container_name}}"
    if docker exec -i "${exec_container}" psql -U "${db_user}" -d "${db_name}" -c "${truncate_sql}" &>/dev/null; then
        echo -e "${GREEN}Successfully cleared database '${db_name}'${NC}"
        return 0
    else
        echo -e "${RED}Error: Failed to clear database '${db_name}'${NC}"
        return 1
    fi
}

# Function to get all postgres containers
get_postgres_containers() {
    docker ps --format "{{.Names}}" | grep -E "(postgres-|fuzzilli-postgres-)(master|local-[0-9]+)" || true
}

# Main execution
main() {
    echo "=========================================="
    echo "  Clear PostgreSQL Databases"
    echo "=========================================="
    echo ""
    
    check_docker
    
    # Get all postgres containers
    local containers=$(get_postgres_containers)
    
    if [ -z "$containers" ]; then
        echo -e "${YELLOW}No PostgreSQL containers found.${NC}"
        echo "Available containers:"
        docker ps --format "table {{.Names}}\t{{.Status}}"
        exit 0
    fi
    
    echo -e "${YELLOW}Found PostgreSQL containers:${NC}"
    echo "$containers" | while read container; do
        echo "  - $container"
    done
    echo ""
    
    # Confirmation prompt (unless --force)
    if [ "$FORCE" != "true" ]; then
        echo -e "${RED}WARNING: This will DELETE ALL DATA from all PostgreSQL databases!${NC}"
        echo -e "${YELLOW}This action cannot be undone.${NC}"
        echo ""
        read -p "Are you sure you want to continue? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            echo -e "${BLUE}Operation cancelled.${NC}"
            exit 0
        fi
        echo ""
    fi
    
    # Clear master database
    echo -e "${BLUE}Clearing master database...${NC}"
    local master_container=""
    while IFS= read -r line; do
        if [[ "$line" =~ (postgres-master|fuzzilli-postgres-master) ]]; then
            master_container="$line"
            break
        fi
    done < <(docker ps --format "{{.Names}}")
    
    if [ -n "$master_container" ]; then
        clear_database "$master_container" "fuzzilli_master"
    else
        echo -e "${YELLOW}Master database container not found. Skipping.${NC}"
    fi
    echo ""
    
    # Clear all local worker databases
    echo -e "${BLUE}Clearing local worker databases...${NC}"
    local cleared_count=0
    local failed_count=0
    
    for container in $containers; do
        if [[ "$container" =~ (postgres-local-|fuzzilli-postgres-local-)[0-9]+ ]]; then
            if clear_database "$container" "fuzzilli_local"; then
                cleared_count=$((cleared_count + 1))
            else
                failed_count=$((failed_count + 1))
            fi
        fi
    done
    
    echo ""
    echo "=========================================="
    if [ $failed_count -eq 0 ]; then
        echo -e "${GREEN}Database clearing complete!${NC}"
        echo -e "${GREEN}Cleared: Master database + $cleared_count local database(s)${NC}"
    else
        echo -e "${YELLOW}Database clearing completed with some errors.${NC}"
        echo -e "${YELLOW}Cleared: Master database + $cleared_count local database(s)${NC}"
        echo -e "${RED}Failed: $failed_count database(s)${NC}"
    fi
    echo "=========================================="
}

# Run main function
main

