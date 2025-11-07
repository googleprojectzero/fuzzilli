#!/bin/bash

# Script to show JavaScript code from crash programs
# Usage: ./Scripts/show-crash-javascript.sh [worker_num]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

# Colors for output
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

show_crash_javascript() {
    local worker_num=$1
    local container="postgres-local-${worker_num}"
    local database="fuzzilli_local"
    
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  Worker ${worker_num} Crash Programs${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    # Get all crash program hashes (one per line)
    local crash_hashes=$(docker exec "$container" psql -U fuzzilli -d "$database" -t -c "SELECT DISTINCT e.program_hash FROM execution e JOIN execution_outcome eo ON e.execution_outcome_id = eo.id WHERE eo.outcome = 'Crashed' ORDER BY e.program_hash;" 2>/dev/null | grep -v '^$' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
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
        
        echo -e "${GREEN}--- Crash Program: ${hash} ---${NC}"
        
        # Get execution details
        local exec_details=$(docker exec "$container" psql -U fuzzilli -d "$database" -t -c "SELECT e.execution_id, e.signal_code, e.exit_code, eo.description, e.created_at FROM execution e JOIN execution_outcome eo ON e.execution_outcome_id = eo.id WHERE e.program_hash = '${hash}' AND eo.outcome = 'Crashed' ORDER BY e.created_at DESC LIMIT 1;" 2>/dev/null)
        
        if [ -n "$exec_details" ]; then
            echo -e "${YELLOW}Execution Details:${NC}"
            echo "$exec_details" | sed 's/^/  /'
            echo ""
        fi
        
        # Get and decode the JavaScript
        echo -e "${YELLOW}JavaScript Code:${NC}"
        local base64_program=$(docker exec "$container" psql -U fuzzilli -d "$database" -t -c "SELECT program_base64 FROM program WHERE program_hash = '${hash}';" 2>/dev/null | tr -d ' \n\r')
        
        if [ -n "$base64_program" ]; then
            # Decode base64 and extract JavaScript strings
            local javascript=$(echo "$base64_program" | base64 -d 2>/dev/null | strings | grep -E "(fuzzilli|function|var|let|const|if|for|while|return)" | head -10)
            
            if [ -n "$javascript" ]; then
                echo "$javascript" | sed 's/^/  /'
            else
                # Try to get any readable strings
                local all_strings=$(echo "$base64_program" | base64 -d 2>/dev/null | strings | grep -v "^$" | tail -5)
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
    # Show both workers
    show_crash_javascript 1
    show_crash_javascript 2
fi

