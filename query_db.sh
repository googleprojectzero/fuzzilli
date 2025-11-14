#!/bin/bash

# Fuzzilli PostgreSQL Database Query Script using Docker
# This script uses Docker to connect to the PostgreSQL container and run queries

# Database connection parameters
DB_CONTAINER="fuzzilli-postgres-master"  # Adjust this to match your container name
DB_NAME="fuzzilli_master"
DB_USER="fuzzilli"
DB_PASSWORD="fuzzilli123"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to run a query using Docker
run_query() {
    local title="$1"
    local query="$2"
    
    echo -e "\n${BLUE}=== $title ===${NC}"
    echo -e "${YELLOW}Query:${NC} $query"
    echo -e "${GREEN}Results:${NC}"
    
    docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "$query" 2>/dev/null
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to execute query${NC}"
    fi
}

# Function to check if Docker is available
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Error: Docker command not found. Please install Docker.${NC}"
        exit 1
    fi
}

# Function to check if PostgreSQL container is running
check_container() {
    if ! docker ps --format "table {{.Names}}" | grep -q "$DB_CONTAINER"; then
        echo -e "${RED}Error: PostgreSQL container '$DB_CONTAINER' is not running${NC}"
        echo "Available containers:"
        docker ps --format "table {{.Names}}\t{{.Status}}"
        echo ""
        echo "Please start the PostgreSQL container or update the DB_CONTAINER variable in this script"
        exit 1
    fi
}

# Function to test database connection
test_connection() {
    echo -e "${BLUE}Testing database connection...${NC}"
    docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT version();" &>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Database connection successful${NC}"
    else
        echo -e "${RED}✗ Database connection failed${NC}"
        echo "Please check:"
        echo "1. PostgreSQL container is running"
        echo "2. Database credentials are correct"
        echo "3. Container name is correct"
        exit 1
    fi
}

# Main execution
main() {
    echo -e "${GREEN}Fuzzilli Database Query Tool (Docker)${NC}"
    echo "============================================="
    
    check_docker
    check_container
    test_connection
    
    # Basic database info
    run_query "Database Information" "SELECT current_database() as database_name, current_user as user_name, version() as postgres_version;"
    
    # List all tables
    run_query "Available Tables" "SELECT table_name, table_type FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;"
    
    # Program statistics
    run_query "Program Count by Fuzzer" "
        SELECT 
            p.fuzzer_id,
            COUNT(*) as program_count,
            MIN(p.created_at) as first_program,
            MAX(p.created_at) as latest_program
        FROM program p 
        GROUP BY p.fuzzer_id 
        ORDER BY program_count DESC;
    "
    
    # Total program count
    run_query "Total Program Statistics" "
        SELECT 
            COUNT(*) as total_programs,
            COUNT(DISTINCT fuzzer_id) as active_fuzzers,
            AVG(program_size) as avg_program_size,
            MAX(program_size) as max_program_size,
            MIN(created_at) as first_program,
            MAX(created_at) as latest_program
        FROM program;
    "
    
    # Execution statistics
    run_query "Execution Statistics" "
        SELECT 
            eo.outcome,
            COUNT(*) as count,
            ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percentage
        FROM execution e
        JOIN execution_outcome eo ON e.execution_outcome_id = eo.id
        GROUP BY eo.outcome 
        ORDER BY count DESC;
    "
    
    # Recent programs
    run_query "Recent Programs (Last 10)" "
        SELECT 
            LEFT(program_base64, 20) as program_preview,
            fuzzer_id,
            LEFT(program_hash, 12) as hash_prefix,
            program_size,
            created_at
        FROM program 
        ORDER BY created_at DESC 
        LIMIT 10;
    "
    
    # Recent executions
    run_query "Recent Executions (Last 10)" "
        SELECT 
            e.execution_id,
            p.fuzzer_id,
            LEFT(p.program_hash, 12) as hash_prefix,
            eo.outcome,
            e.execution_time_ms,
            e.created_at
        FROM execution e
        JOIN program p ON e.program_base64 = p.program_base64
        JOIN execution_outcome eo ON e.execution_outcome_id = eo.id
        ORDER BY e.created_at DESC 
        LIMIT 10;
    "
    
    # Crash analysis
    run_query "Crash Analysis" "
        SELECT 
            p.fuzzer_id,
            COUNT(*) as crash_count,
            MIN(e.created_at) as first_crash,
            MAX(e.created_at) as latest_crash
        FROM execution e
        JOIN program p ON e.program_base64 = p.program_base64
        JOIN execution_outcome eo ON e.execution_outcome_id = eo.id
        WHERE eo.outcome = 'Crashed'
        GROUP BY p.fuzzer_id
        ORDER BY crash_count DESC;
    "
    
    # Coverage statistics
    run_query "Coverage Statistics" "
        SELECT 
            COUNT(*) as executions_with_coverage,
            AVG(coverage_total) as avg_coverage_percentage,
            MAX(coverage_total) as max_coverage_percentage,
            COUNT(CASE WHEN coverage_total > 0 THEN 1 END) as executions_with_positive_coverage
        FROM execution 
        WHERE coverage_total IS NOT NULL;
    "
    
    # Coverage snapshot statistics
    run_query "Coverage Snapshot Statistics" "
        SELECT 
            COUNT(*) as total_snapshots,
            AVG(coverage_percentage) as avg_coverage_percentage,
            MAX(coverage_percentage) as max_coverage_percentage,
            AVG(edges_found) as avg_edges_found,
            MAX(edges_found) as max_edges_found,
            AVG(total_edges) as avg_total_edges,
            MAX(total_edges) as max_total_edges,
            COUNT(CASE WHEN edges_found > 0 THEN 1 END) as snapshots_with_coverage
        FROM coverage_snapshot 
        WHERE edges_found IS NOT NULL AND total_edges IS NOT NULL;
    "
    
    # Recent coverage snapshots
    run_query "Recent Coverage Snapshots (Last 10)" "
        SELECT 
            snapshot_id,
            fuzzer_id,
            ROUND(coverage_percentage::numeric, 6) as coverage_pct,
            edges_found,
            total_edges,
            LEFT(program_hash, 12) as hash_prefix,
            created_at
        FROM coverage_snapshot 
        WHERE edges_found IS NOT NULL AND total_edges IS NOT NULL
        ORDER BY created_at DESC 
        LIMIT 10;
    "
    
    # Performance metrics
    run_query "Performance Metrics" "
        SELECT 
            AVG(execution_time_ms) as avg_execution_time_ms,
            MIN(execution_time_ms) as min_execution_time_ms,
            MAX(execution_time_ms) as max_execution_time_ms,
            COUNT(*) as total_executions
        FROM execution 
        WHERE execution_time_ms > 0;
    "
    
    # Database size info
    run_query "Database Size Information" "
        SELECT 
            schemaname,
            tablename,
            pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
        FROM pg_tables 
        WHERE schemaname = 'public'
        ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
    "
    
    echo -e "\n${GREEN}Database query completed successfully!${NC}"
}

# Handle command line arguments
case "${1:-}" in
    "programs")
        run_query "All Programs" "SELECT LEFT(program_base64, 30) as program_preview, fuzzer_id, program_size, created_at FROM program ORDER BY created_at DESC LIMIT 20;"
        ;;
    "executions")
        run_query "All Executions" "SELECT e.execution_id, LEFT(p.program_base64, 20) as program_preview, eo.outcome, e.execution_time_ms, e.created_at FROM execution e JOIN program p ON e.program_base64 = p.program_base64 JOIN execution_outcome eo ON e.execution_outcome_id = eo.id ORDER BY e.created_at DESC LIMIT 20;"
        ;;
    "crashes")
        run_query "All Crashes" "SELECT e.execution_id, LEFT(p.program_base64, 20) as program_preview, e.stdout, e.stderr, e.created_at FROM execution e JOIN program p ON e.program_base64 = p.program_base64 JOIN execution_outcome eo ON e.execution_outcome_id = eo.id WHERE eo.outcome = 'Crashed' ORDER BY e.created_at DESC LIMIT 20;"
        ;;
    "stats")
        run_query "Quick Stats" "SELECT COUNT(*) as programs, (SELECT COUNT(*) FROM execution) as executions, (SELECT COUNT(*) FROM execution e JOIN execution_outcome eo ON e.execution_outcome_id = eo.id WHERE eo.outcome = 'Crashed') as crashes FROM program;"
        ;;
    "containers")
        echo -e "${BLUE}Available PostgreSQL containers:${NC}"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(postgres|fuzzilli)"
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  (no args)  - Run full database analysis"
        echo "  programs   - Show recent programs"
        echo "  executions - Show recent executions"
        echo "  crashes    - Show recent crashes"
        echo "  stats      - Show quick statistics"
        echo "  containers - List available PostgreSQL containers"
        echo "  help       - Show this help"
        echo ""
        echo "Note: Update DB_CONTAINER variable in script if your container has a different name"
        ;;
    "")
        main
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac