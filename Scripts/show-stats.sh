#!/bin/bash

# Script to show current statistics for distributed Fuzzilli setup
# Usage: ./Scripts/show-stats.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

MASTER_COMPOSE="docker-compose.master.yml"
WORKERS_COMPOSE="docker-compose.workers.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Distributed Fuzzilli Statistics${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Check if containers are running
check_container() {
    local container=$1
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        return 0
    else
        return 1
    fi
}

# Get database stats
get_db_stats() {
    local container=$1
    local database=$2
    local label=$3
    
    if ! check_container "$container"; then
        echo -e "${RED}${label}: Container not running${NC}"
        return
    fi
    
    echo -e "${BLUE}=== ${label} ===${NC}"
    
    # Fuzzer registrations
    echo -e "${YELLOW}Fuzzer Registrations:${NC}"
    docker exec "$container" psql -U fuzzilli -d "$database" -c "SELECT fuzzer_id, fuzzer_name, status, created_at FROM main ORDER BY fuzzer_id;" 2>/dev/null || echo "  No fuzzers registered"
    
    # Program counts
    local program_count=$(docker exec "$container" psql -U fuzzilli -d "$database" -t -c "SELECT COUNT(*) FROM fuzzer;" 2>/dev/null | tr -d ' ' || echo "0")
    local execution_count=$(docker exec "$container" psql -U fuzzilli -d "$database" -t -c "SELECT COUNT(*) FROM execution;" 2>/dev/null | tr -d ' ' || echo "0")
    local program_table_count=$(docker exec "$container" psql -U fuzzilli -d "$database" -t -c "SELECT COUNT(*) FROM program;" 2>/dev/null | tr -d ' ' || echo "0")
    
    # Crash count
    local crash_count=$(docker exec "$container" psql -U fuzzilli -d "$database" -t -c "SELECT COUNT(*) FROM execution e JOIN execution_outcome eo ON e.execution_outcome_id = eo.id WHERE eo.outcome = 'Crashed';" 2>/dev/null | tr -d ' ' || echo "0")
    
    echo -e "${YELLOW}Statistics:${NC}"
    echo "  Programs (corpus): $program_count"
    echo "  Programs (executed): $program_table_count"
    echo "  Executions: $execution_count"
    echo "  Crashes: $crash_count"
    
    # Recent activity (last 5 programs)
    echo -e "${YELLOW}Recent Programs (last 5):${NC}"
    docker exec "$container" psql -U fuzzilli -d "$database" -c "SELECT program_hash, program_size, created_at FROM fuzzer ORDER BY created_at DESC LIMIT 5;" 2>/dev/null || echo "  No programs found"
    
    # Crash details
    if [ "$crash_count" != "0" ] && [ "$crash_count" != "" ]; then
        echo -e "${YELLOW}Crashes (last 3):${NC}"
        docker exec "$container" psql -U fuzzilli -d "$database" -c "SELECT e.execution_id, e.program_hash, e.execution_time_ms, e.signal_code, e.exit_code, eo.description, e.created_at FROM execution e JOIN execution_outcome eo ON e.execution_outcome_id = eo.id WHERE eo.outcome = 'Crashed' ORDER BY e.created_at DESC LIMIT 3;" 2>/dev/null || echo "  No crash details available"
    fi
    
    echo ""
}

# Get worker container stats
get_worker_stats() {
    local worker_num=$1
    local container="fuzzer-worker-${worker_num}"
    local postgres_container="postgres-local-${worker_num}"
    
    if ! check_container "$container"; then
        echo -e "${RED}Worker ${worker_num}: Container not running${NC}"
        echo ""
        return
    fi
    
    echo -e "${GREEN}=== Worker ${worker_num} ===${NC}"
    
    # Container status
    local status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null)
    local health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "no-healthcheck")
    echo -e "${YELLOW}Container Status:${NC} $status (health: $health)"
    
    # Get database stats
    get_db_stats "$postgres_container" "fuzzilli_local" "Local Database"
    
    # Get recent logs
    echo -e "${YELLOW}Recent Activity (last 3 lines):${NC}"
    docker compose -f "$MASTER_COMPOSE" -f "$WORKERS_COMPOSE" logs --tail=3 "$container" 2>&1 | grep -v "level=warning" | tail -3 || echo "  No recent activity"
    echo ""
}

# Master stats
echo -e "${GREEN}=== Master Database ===${NC}"
if check_container "fuzzilli-postgres-master"; then
    status=$(docker inspect --format='{{.State.Status}}' "fuzzilli-postgres-master" 2>/dev/null)
    health=$(docker inspect --format='{{.State.Health.Status}}' "fuzzilli-postgres-master" 2>/dev/null || echo "no-healthcheck")
    echo -e "${YELLOW}Container Status:${NC} $status (health: $health)"
    echo ""
    get_db_stats "fuzzilli-postgres-master" "fuzzilli_master" "Master Database"
else
    echo -e "${RED}Master container not running${NC}"
    echo ""
fi

# Worker stats
get_worker_stats 1
get_worker_stats 2

# Summary
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Summary${NC}"
echo -e "${CYAN}========================================${NC}"

if check_container "fuzzilli-postgres-master"; then
    master_programs=$(docker exec fuzzilli-postgres-master psql -U fuzzilli -d fuzzilli_master -t -c "SELECT COUNT(*) FROM fuzzer;" 2>/dev/null | tr -d ' ' || echo "0")
    master_executions=$(docker exec fuzzilli-postgres-master psql -U fuzzilli -d fuzzilli_master -t -c "SELECT COUNT(*) FROM execution;" 2>/dev/null | tr -d ' ' || echo "0")
    echo -e "Master: ${GREEN}${master_programs}${NC} programs, ${GREEN}${master_executions}${NC} executions"
fi

if check_container "postgres-local-1"; then
    w1_programs=$(docker exec postgres-local-1 psql -U fuzzilli -d fuzzilli_local -t -c "SELECT COUNT(*) FROM fuzzer;" 2>/dev/null | tr -d ' ' || echo "0")
    w1_executions=$(docker exec postgres-local-1 psql -U fuzzilli -d fuzzilli_local -t -c "SELECT COUNT(*) FROM execution;" 2>/dev/null | tr -d ' ' || echo "0")
    echo -e "Worker 1: ${GREEN}${w1_programs}${NC} programs, ${GREEN}${w1_executions}${NC} executions"
fi

if check_container "postgres-local-2"; then
    w2_programs=$(docker exec postgres-local-2 psql -U fuzzilli -d fuzzilli_local -t -c "SELECT COUNT(*) FROM fuzzer;" 2>/dev/null | tr -d ' ' || echo "0")
    w2_executions=$(docker exec postgres-local-2 psql -U fuzzilli -d fuzzilli_local -t -c "SELECT COUNT(*) FROM execution;" 2>/dev/null | tr -d ' ' || echo "0")
    echo -e "Worker 2: ${GREEN}${w2_programs}${NC} programs, ${GREEN}${w2_executions}${NC} executions"
fi

echo ""
echo -e "${CYAN}========================================${NC}"

