#!/bin/bash

# Script to show JavaScript code from crash programs
# Usage: ./Scripts/show-crash-javascript.sh [worker_num]
# If no worker_num is specified, shows crashes for all postgres-local-* containers

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

# Colors for output
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get all postgres-local-* containers
get_local_postgres_containers() {
    docker ps --format '{{.Names}}' | grep '^postgres-local-' | sort
}

# Get worker number from container name
get_worker_num() {
    local container=$1
    echo "$container" | sed 's/.*-\([0-9]*\)$/\1/'
}

# Check if a container is running
check_container() {
    local container=$1
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        return 0
    else
        return 1
    fi
}

show_crash_javascript() {
    local worker_num=$1
    local container="postgres-local-${worker_num}"
    local database="fuzzilli_local"
    
    if ! check_container "$container"; then
        echo -e "${RED}Worker ${worker_num}: Container ${container} not running${NC}"
        echo ""
        return
    fi
    
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  Worker ${worker_num} Crash Programs${NC}"
    echo -e "${CYAN}  (Excluding FUZZILLI_CRASH test cases - signal 3)${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    # Get all crash program hashes (one per line)
    # Exclude only signal_code = 3 (FUZZILLI_CRASH test cases)
    # Show all other crashes including signal 11 and all other signals
    local crash_hashes=$(docker exec "$container" psql -U fuzzilli -d "$database" -t -c "SELECT DISTINCT e.program_hash FROM execution e JOIN execution_outcome eo ON e.execution_outcome_id = eo.id WHERE eo.outcome = 'Crashed' AND (e.signal_code IS NULL OR e.signal_code != 3) ORDER BY e.program_hash;" 2>/dev/null | grep -v '^$' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    if [ -z "$crash_hashes" ]; then
        echo -e "${YELLOW}No crashes found for Worker ${worker_num}${NC}"
        echo ""
        return
    fi
    
    # Process each crash hash
    echo "$crash_hashes" | while IFS= read -r hash; do
        if [ -z "$hash" ]; then
            continue
        fi
        
        # Get execution details first to check signal code
        # Exclude only signal 3 (FUZZILLI_CRASH test cases), show all others including signal 11
        local exec_details=$(docker exec "$container" psql -U fuzzilli -d "$database" -t -c "SELECT e.execution_id, e.signal_code, e.exit_code, eo.description, e.created_at FROM execution e JOIN execution_outcome eo ON e.execution_outcome_id = eo.id WHERE e.program_hash = '${hash}' AND eo.outcome = 'Crashed' AND (e.signal_code IS NULL OR e.signal_code != 3) ORDER BY e.created_at DESC LIMIT 1;" 2>/dev/null)
        
        # Skip if no execution details found (shouldn't happen, but safety check)
        if [ -z "$exec_details" ]; then
            continue
        fi
        
        # Get and decode the JavaScript to check for FUZZILLI_CRASH
        local base64_program=$(docker exec "$container" psql -U fuzzilli -d "$database" -t -c "SELECT program_base64 FROM program WHERE program_hash = '${hash}';" 2>/dev/null | tr -d ' \n\r')
        
        # Check if program contains FUZZILLI_CRASH pattern
        if [ -n "$base64_program" ]; then
            local decoded_program=$(echo "$base64_program" | base64 -d 2>/dev/null)
            if echo "$decoded_program" | grep -q "FUZZILLI_CRASH"; then
                # Skip this crash - it's a test case
                continue
            fi
        fi
        
        echo -e "${GREEN}--- Crash Program: ${hash} ---${NC}"
        
        if [ -n "$exec_details" ]; then
            echo -e "${YELLOW}Execution Details:${NC}"
            echo "$exec_details" | sed 's/^/  /'
            echo ""
        fi
        
        # Get and decode the JavaScript
        echo -e "${YELLOW}JavaScript Code:${NC}"
        
        if [ -n "$base64_program" ]; then
            # Decode base64 and extract JavaScript strings
            # Using awk to limit output without head/tail
            local javascript=$(echo "$base64_program" | base64 -d 2>/dev/null | strings | grep -E "(fuzzilli|function|var|let|const|if|for|while|return)" | awk 'NR <= 10 { print; if (NR == 10) exit }')
            
            if [ -n "$javascript" ]; then
                echo "$javascript" | sed 's/^/  /'
            else
                # Try to get any readable strings without tail
                local all_strings=$(echo "$base64_program" | base64 -d 2>/dev/null | strings | grep -v "^$" | awk '{ lines[NR] = $0 } END { start = (NR > 5) ? NR - 4 : 1; for (i = start; i <= NR; i++) print lines[i] }')
                if [ -n "$all_strings" ]; then
                    echo "$all_strings" | sed 's/^/  /'
                else
                    echo "  (Could not extract JavaScript - program may be in binary format)"
                fi
            fi
        else
            echo "  (Program not found in database)"
        fi
        
        echo ""
    done <<< "$crash_hashes"
}

# If worker number specified, show only that worker
if [ -n "$1" ]; then
    show_crash_javascript "$1"
else
    # Dynamically discover and show crashes for all postgres-local-* containers
    local_postgres_containers=($(get_local_postgres_containers))
    if [ ${#local_postgres_containers[@]} -eq 0 ]; then
        echo -e "${YELLOW}No postgres-local-* containers found${NC}"
        echo ""
    else
        for postgres_container in "${local_postgres_containers[@]}"; do
            worker_num=$(get_worker_num "$postgres_container")
            show_crash_javascript "$worker_num"
        done
    fi
fi

