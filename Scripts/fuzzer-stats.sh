#!/bin/bash

# Fuzzilli Fuzzer Statistics Script
# Shows comprehensive statistics including highest coverage and per-fuzzer information
# Usage: ./Scripts/fuzzer-stats.sh
#
# Environment variables (optional, for remote PostgreSQL):
#   - POSTGRES_HOST: Remote PostgreSQL host/IP (if set, connects to remote instead of local container)
#   - POSTGRES_PORT: PostgreSQL port (default: 5432)
#   - POSTGRES_DB: Database name (default: fuzzilli_master)
#   - POSTGRES_USER: Database user (default: fuzzilli)
#   - POSTGRES_PASSWORD: PostgreSQL password (default: fuzzilli123)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load environment variables
if [ -f "${PROJECT_ROOT}/.env" ]; then
    source "${PROJECT_ROOT}/.env"
elif [ -f "${PROJECT_ROOT}/env.distributed" ]; then
    source "${PROJECT_ROOT}/env.distributed"
fi

# Database connection parameters
# Defaults for local container mode
DB_CONTAINER=${DB_CONTAINER:-"fuzzilli-postgres-master"}
DB_NAME=${POSTGRES_DB:-"fuzzilli_master"}
DB_USER=${POSTGRES_USER:-"fuzzilli"}
DB_PASSWORD=${POSTGRES_PASSWORD:-"fuzzilli123"}

# Remote database parameters (if POSTGRES_HOST is set, use remote mode)
POSTGRES_HOST=${POSTGRES_HOST:-}
POSTGRES_PORT=${POSTGRES_PORT:-5432}

# Determine if we're using remote or local postgres
USE_REMOTE_DB=false
if [ -n "$POSTGRES_HOST" ]; then
    USE_REMOTE_DB=true
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Function to check if Docker is available (only needed for local mode)
check_docker() {
    if [ "$USE_REMOTE_DB" = false ]; then
        if ! command -v docker &> /dev/null; then
            echo -e "${RED}Error: Docker command not found. Please install Docker.${NC}"
            exit 1
        fi
    fi
}

# Function to check if psql is available (only needed for remote mode)
check_psql() {
    if [ "$USE_REMOTE_DB" = true ]; then
        if ! command -v psql &> /dev/null; then
            echo -e "${RED}Error: psql command not found. Please install PostgreSQL client.${NC}"
            echo "  On Ubuntu/Debian: sudo apt-get install postgresql-client"
            echo "  On RHEL/CentOS: sudo yum install postgresql"
            exit 1
        fi
    fi
}

# Function to check if PostgreSQL is accessible
check_database() {
    if [ "$USE_REMOTE_DB" = true ]; then
        # Check remote postgres connection
        if ! PGPASSWORD="${DB_PASSWORD}" psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -c "SELECT 1" > /dev/null 2>&1; then
            echo -e "${RED}Error: Cannot connect to remote PostgreSQL at ${POSTGRES_HOST}:${POSTGRES_PORT}${NC}"
            echo "  Please verify:"
            echo "    - PostgreSQL is running and accessible"
            echo "    - Host, port, user, password, and database name are correct"
            echo "    - Network connectivity and firewall rules allow connection"
            exit 1
        fi
    else
        # Check local container
        if ! docker ps --format "table {{.Names}}" | grep -q "$DB_CONTAINER"; then
            echo -e "${RED}Error: PostgreSQL container '$DB_CONTAINER' is not running${NC}"
            echo "Available containers:"
            docker ps --format "table {{.Names}}\t{{.Status}}"
            exit 1
        fi
    fi
}

# Function to run a query and return results
run_query() {
    local query="$1"
    if [ "$USE_REMOTE_DB" = true ]; then
        PGPASSWORD="${DB_PASSWORD}" psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -t -A -F'|' -c "$query" 2>/dev/null
    else
        docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -A -F'|' -c "$query" 2>/dev/null
    fi
}

# Function to format number with commas
format_number() {
    printf "%'d" "$1" 2>/dev/null || echo "$1"
}

# Function to format decimal
format_decimal() {
    printf "%.2f" "$1" 2>/dev/null || echo "$1"
}

# Main execution
main() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  Fuzzilli Fuzzer Statistics${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    check_docker
    check_psql
    check_database
    
    # Get highest coverage (overall)
    echo -e "${GREEN}=== Highest Coverage (Overall) ===${NC}"
    highest_coverage=$(run_query "SELECT COALESCE(MAX(highest_coverage_pct), 0) FROM global_statistics;")
    if [ -n "$highest_coverage" ] && [ "$highest_coverage" != "0" ]; then
        echo -e "  ${YELLOW}Highest Coverage:${NC} ${GREEN}$(format_decimal "$highest_coverage")%${NC}"
    else
        echo -e "  ${YELLOW}Highest Coverage:${NC} ${RED}No coverage data available${NC}"
    fi
    echo ""
    
    # Get global statistics
    echo -e "${GREEN}=== Global Statistics ===${NC}"
    global_stats=$(run_query "SELECT total_programs, total_executions, total_crashes, active_fuzzers FROM global_statistics;" | xargs)
    if [ -n "$global_stats" ] && [ "$global_stats" != "" ]; then
        IFS='|' read -r total_programs total_executions total_crashes active_fuzzers <<< "$global_stats"
        echo -e "  ${YELLOW}Total Programs:${NC} $(format_number "$total_programs")"
        echo -e "  ${YELLOW}Total Executions:${NC} $(format_number "$total_executions")"
        echo -e "  ${YELLOW}Total Crashes:${NC} ${RED}$(format_number "$total_crashes")${NC}"
        echo -e "  ${YELLOW}Active Fuzzers:${NC} $(format_number "$active_fuzzers")"
    else
        echo -e "  ${YELLOW}No global statistics available${NC}"
    fi
    echo ""
    
    # Get per-fuzzer performance summary
    echo -e "${GREEN}=== Per-Fuzzer Performance Summary ===${NC}"
    echo ""
    
    # Header
    printf "%-6s %-20s %-10s %-12s %-12s %-12s %-10s %-15s\n" \
        "ID" "Name" "Status" "Execs/s" "Programs" "Executions" "Crashes" "Highest Coverage %"
    echo "--------------------------------------------------------------------------------------------------------"
    
    # Get per-fuzzer data
    fuzzer_data=$(run_query "
        SELECT 
            fuzzer_id,
            fuzzer_name,
            status,
            COALESCE(execs_per_second, 0),
            COALESCE(programs_count, 0),
            COALESCE(executions_count, 0),
            COALESCE(crash_count, 0),
            COALESCE(highest_coverage_pct, 0)
        FROM fuzzer_performance_summary
        ORDER BY fuzzer_id;
    ")
    
    if [ -z "$fuzzer_data" ]; then
        echo -e "${YELLOW}No fuzzer data available${NC}"
    else
        while IFS='|' read -r fuzzer_id fuzzer_name status execs_per_sec programs executions crashes highest_cov; do
            # Format execs/s
            execs_formatted=$(printf "%.2f" "$execs_per_sec" 2>/dev/null || echo "0.00")
            
            # Format coverage
            cov_formatted=$(printf "%.2f" "$highest_cov" 2>/dev/null || echo "0.00")
            
            # Color code based on status
            if [ "$status" = "active" ]; then
                status_color="${GREEN}"
            else
                status_color="${RED}"
            fi
            
            printf "%-6s %-20s ${status_color}%-10s${NC} %-12s %-12s %-12s ${RED}%-10s${NC} ${CYAN}%-15s${NC}\n" \
                "$fuzzer_id" \
                "$fuzzer_name" \
                "$status" \
                "$execs_formatted" \
                "$(format_number "$programs")" \
                "$(format_number "$executions")" \
                "$(format_number "$crashes")" \
                "${cov_formatted}%"
        done <<< "$fuzzer_data"
    fi
    echo ""
    
    # Get crash breakdown by signal per fuzzer
    echo -e "${GREEN}=== Crash Breakdown by Signal (Per Fuzzer) ===${NC}"
    echo ""
    
    crash_data=$(run_query "
        SELECT 
            fuzzer_id,
            fuzzer_name,
            signal_code,
            signal_name,
            crash_count
        FROM crash_by_signal
        ORDER BY fuzzer_id, crash_count DESC;
    ")
    
    if [ -z "$crash_data" ]; then
        echo -e "${YELLOW}No crash data available${NC}"
    else
        current_fuzzer=""
        while IFS='|' read -r fuzzer_id fuzzer_name signal_code signal_name crash_count; do
            if [ "$current_fuzzer" != "$fuzzer_id" ]; then
                if [ -n "$current_fuzzer" ]; then
                    echo ""
                fi
                echo -e "${CYAN}Fuzzer ${fuzzer_id} (${fuzzer_name}):${NC}"
                current_fuzzer="$fuzzer_id"
            fi
            printf "  ${YELLOW}%-15s${NC} (Signal %-3s): ${RED}%s${NC} crashes\n" \
                "$signal_name" \
                "${signal_code:-N/A}" \
                "$(format_number "$crash_count")"
        done <<< "$crash_data"
    fi
    echo ""
    
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  Statistics Complete${NC}"
    echo -e "${CYAN}========================================${NC}"
}

# Handle command line arguments
case "${1:-}" in
    "help"|"-h"|"--help")
        echo "Usage: $0"
        echo ""
        echo "Shows comprehensive fuzzer statistics including:"
        echo "  - Highest coverage (overall)"
        echo "  - Global statistics"
        echo "  - Per-fuzzer information (execs/s, programs, executions, crashes, highest coverage %)"
        echo "  - Crash breakdown by signal per fuzzer"
        echo ""
        echo "Database connection:"
        echo "  By default, connects to local Docker container 'fuzzilli-postgres-master'"
        echo ""
        echo "  For remote PostgreSQL, set environment variables:"
        echo "    POSTGRES_HOST - Remote PostgreSQL host/IP (required for remote mode)"
        echo "    POSTGRES_PORT - PostgreSQL port (default: 5432)"
        echo "    POSTGRES_DB - Database name (default: fuzzilli_master)"
        echo "    POSTGRES_USER - Database user (default: fuzzilli)"
        echo "    POSTGRES_PASSWORD - PostgreSQL password (default: fuzzilli123)"
        echo ""
        echo "  Example: POSTGRES_HOST=192.168.1.100 $0"
        ;;
    "")
        main
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac

