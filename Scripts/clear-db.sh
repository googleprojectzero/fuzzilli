#!/bin/bash

# Clear PostgreSQL Database Script
# This script clears all data from the Fuzzilli PostgreSQL database
# while preserving the schema and lookup table seed data.

# Don't exit on error - we want to continue even if some operations fail
set +e

# Database connection parameters
DB_CONTAINER="fuzzilli-postgres-master"
DB_NAME="fuzzilli_master"
DB_USER="fuzzilli"
DB_PASSWORD="fuzzilli123"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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
        exit 1
    fi
}

# Function to run a query
run_query() {
    local query="$1"
    docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "$query" 2>&1
}

# Function to run a query silently (for operations that might fail)
run_query_silent() {
    local query="$1"
    docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "$query" 2>/dev/null || true
}

# Function to get table row counts
get_table_counts() {
    echo -e "${CYAN}Current database statistics:${NC}"
    run_query "
        SELECT 
            'main' as table_name, COUNT(*) as row_count FROM main
        UNION ALL
        SELECT 'fuzzer', COUNT(*) FROM fuzzer
        UNION ALL
        SELECT 'program', COUNT(*) FROM program
        UNION ALL
        SELECT 'execution', COUNT(*) FROM execution
        UNION ALL
        SELECT 'coverage_detail', COUNT(*) FROM coverage_detail
        UNION ALL
        SELECT 'feedback_vector_detail', COUNT(*) FROM feedback_vector_detail
        UNION ALL
        SELECT 'crash_analysis', COUNT(*) FROM crash_analysis
        UNION ALL
        SELECT 'fuzzer_statistics', COALESCE((SELECT COUNT(*) FROM fuzzer_statistics), 0);
    " | grep -v "row_count" | grep -v "^$" | grep -v "^-" | while read -r line; do
        if [ -n "$line" ]; then
            echo "  $line"
        fi
    done
}

# Main execution
main() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  Fuzzilli Database Cleanup${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    check_docker
    check_container
    
    # Show current statistics
    get_table_counts
    echo ""
    
    # Find all fuzzer-X tables
    fuzzer_tables=$(run_query "SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename LIKE 'fuzzer-%' ORDER BY tablename;" | grep -v "tablename" | grep -v "^-" | grep -v "^$" | grep -v "^(" | awk 'NF>0 {print $1}' | tr '\n' ' ')
    
    # Safety confirmation
    if [ "${1:-}" != "--yes" ] && [ "${1:-}" != "-y" ]; then
        echo -e "${YELLOW}WARNING: This will delete ALL data from the database!${NC}"
        echo -e "${YELLOW}The following will be cleared:${NC}"
        echo "  - All fuzzer instances (main table)"
        echo "  - All corpus programs (fuzzer table)"
        echo "  - All executed programs (program table)"
        echo "  - All execution records (execution table)"
        echo "  - All coverage details (coverage_detail table)"
        echo "  - All feedback vector details (feedback_vector_detail table)"
        echo "  - All crash analyses (crash_analysis table)"
        echo "  - All fuzzer statistics (fuzzer_statistics table)"
        if [ -n "$fuzzer_tables" ]; then
            echo -e "${YELLOW}  - All fuzzer-X tables (will be DROPPED):${NC}"
            for table in $fuzzer_tables; do
                echo "    - $table"
            done
        fi
        echo ""
        echo -e "${YELLOW}The following will be preserved:${NC}"
        echo "  - Database schema (tables, indexes, views)"
        echo "  - Lookup tables (execution_type, mutator_type, execution_outcome)"
        echo ""
        read -p "Are you sure you want to continue? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            echo -e "${GREEN}Operation cancelled.${NC}"
            exit 0
        fi
    fi
    
    echo -e "${YELLOW}Clearing database...${NC}"
    echo ""
    
    # Clear data tables in order (respecting foreign key constraints)
    # Start with child tables first, then parent tables
    # Use CASCADE to handle foreign key dependencies
    
    echo -e "${CYAN}Clearing coverage_detail...${NC}"
    run_query_silent "TRUNCATE TABLE coverage_detail CASCADE;"
    
    echo -e "${CYAN}Clearing feedback_vector_detail...${NC}"
    run_query_silent "TRUNCATE TABLE feedback_vector_detail CASCADE;"
    
    echo -e "${CYAN}Clearing crash_analysis...${NC}"
    run_query_silent "TRUNCATE TABLE crash_analysis CASCADE;"
    
    echo -e "${CYAN}Clearing execution...${NC}"
    run_query_silent "TRUNCATE TABLE execution CASCADE;"
    
    echo -e "${CYAN}Clearing program...${NC}"
    run_query_silent "TRUNCATE TABLE program CASCADE;"
    
    echo -e "${CYAN}Clearing fuzzer (corpus)...${NC}"
    run_query_silent "TRUNCATE TABLE fuzzer CASCADE;"
    
    echo -e "${CYAN}Clearing fuzzer_statistics...${NC}"
    run_query_silent "TRUNCATE TABLE fuzzer_statistics CASCADE;"
    
    echo -e "${CYAN}Clearing main (fuzzer instances)...${NC}"
    run_query_silent "TRUNCATE TABLE main CASCADE;"
    
    # Drop all fuzzer-X tables if they exist
    if [ -n "$fuzzer_tables" ]; then
        echo -e "${CYAN}Dropping fuzzer-X tables...${NC}"
        for table in $fuzzer_tables; do
            if [ -n "$table" ]; then
                echo "  Dropping table: $table"
                run_query_silent "DROP TABLE IF EXISTS \"$table\" CASCADE;"
            fi
        done
    else
        echo -e "${CYAN}No fuzzer-X tables found to drop.${NC}"
    fi
    
    # Reset sequences
    echo -e "${CYAN}Resetting sequences...${NC}"
    run_query_silent "ALTER SEQUENCE IF EXISTS main_fuzzer_id_seq RESTART WITH 1;"
    run_query_silent "ALTER SEQUENCE IF EXISTS execution_execution_id_seq RESTART WITH 1;"
    run_query_silent "ALTER SEQUENCE IF EXISTS feedback_vector_detail_id_seq RESTART WITH 1;"
    run_query_silent "ALTER SEQUENCE IF EXISTS coverage_detail_id_seq RESTART WITH 1;"
    run_query_silent "ALTER SEQUENCE IF EXISTS crash_analysis_id_seq RESTART WITH 1;"
    
    echo ""
    echo -e "${GREEN}Database cleared successfully!${NC}"
    echo ""
    
    # Show final statistics
    get_table_counts
    echo ""
    
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  Cleanup Complete${NC}"
    echo -e "${CYAN}========================================${NC}"
}

# Handle command line arguments
case "${1:-}" in
    "help"|"-h"|"--help")
        echo "Usage: $0 [--yes|-y]"
        echo ""
        echo "Clears all data from the Fuzzilli PostgreSQL database."
        echo ""
        echo "Options:"
        echo "  --yes, -y    Skip confirmation prompt"
        echo "  help, -h      Show this help message"
        echo ""
        echo "This script will:"
        echo "  - Delete all fuzzer instances, programs, executions, and related data"
        echo "  - Drop all fuzzer-X tables (fuzzer-1, fuzzer-2, etc.)"
        echo "  - Preserve the database schema and lookup tables"
        echo "  - Reset all sequences to start from 1"
        echo ""
        echo "Note: Update DB_CONTAINER variable in script if your container has a different name"
        ;;
    "")
        main
        ;;
    "--yes"|"-y")
        main "$1"
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac

