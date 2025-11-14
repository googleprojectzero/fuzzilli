#!/bin/bash

# scale-workers.sh - Scale workers up or down based on server performance
# Usage: ./Scripts/scale-workers.sh [target_count] [--auto]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Get current worker count
get_current_workers() {
    docker ps --format "{{.Names}}" | grep -c "fuzzer-worker" || echo "0"
}

# Scale workers
scale_workers() {
    local target_count=$1
    local current_count=$(get_current_workers)
    
    if [ "$target_count" -eq "$current_count" ]; then
        echo -e "${YELLOW}Already at target worker count: ${target_count}${NC}"
        return
    fi
    
    echo -e "${CYAN}Scaling workers from ${current_count} to ${target_count}...${NC}"
    
    if [ "$target_count" -gt "$current_count" ]; then
        # Scale up
        echo -e "${GREEN}Scaling UP: Adding $((target_count - current_count)) workers${NC}"
        cd "$PROJECT_DIR"
        ./Scripts/start-distributed.sh "$target_count"
    else
        # Scale down
        echo -e "${YELLOW}Scaling DOWN: Removing $((current_count - target_count)) workers${NC}"
        local to_remove=$((current_count - target_count))
        local removed=0
        
        for container in $(docker ps --format "{{.Names}}" | grep "fuzzer-worker" | sort -V | tail -n "$to_remove"); do
            echo -e "Stopping ${container}..."
            docker stop "$container" > /dev/null 2>&1 || true
            removed=$((removed + 1))
        done
        
        echo -e "${GREEN}Stopped ${removed} worker(s)${NC}"
    fi
    
    echo -e "${GREEN}Scale operation complete${NC}"
}

# Auto-scale based on performance
auto_scale() {
    echo -e "${CYAN}Auto-scaling based on server performance...${NC}"
    echo ""
    
    # Get current metrics
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    MEM_USAGE=$(free | grep Mem | awk '{printf "%.1f", ($3/$2) * 100.0}')
    CURRENT_WORKERS=$(get_current_workers)
    
    echo -e "Current CPU:  ${CYAN}${CPU_USAGE}%${NC}"
    echo -e "Current MEM: ${CYAN}${MEM_USAGE}%${NC}"
    echo -e "Current Workers: ${CYAN}${CURRENT_WORKERS}${NC}"
    echo ""
    
    # Determine target worker count
    local target_count=$CURRENT_WORKERS
    
    if (( $(echo "$CPU_USAGE < 40" | bc -l) )) && (( $(echo "$MEM_USAGE < 40" | bc -l) )); then
        # System has capacity - scale up
        target_count=$((CURRENT_WORKERS + 2))
        echo -e "${GREEN}System has capacity - scaling UP${NC}"
    elif (( $(echo "$CPU_USAGE > 80" | bc -l) )) || (( $(echo "$MEM_USAGE > 80" | bc -l) )); then
        # System under load - scale down
        target_count=$((CURRENT_WORKERS - 1))
        target_count=$((target_count > 0 ? target_count : 1))
        echo -e "${RED}System under load - scaling DOWN${NC}"
    else
        echo -e "${YELLOW}System load is moderate - no scaling needed${NC}"
        return
    fi
    
    scale_workers "$target_count"
}

# Main
main() {
    if [ "$1" = "--auto" ] || [ "$1" = "-a" ]; then
        auto_scale
    elif [ -n "$1" ] && [[ "$1" =~ ^[0-9]+$ ]]; then
        scale_workers "$1"
    else
        echo "Usage: $0 [target_count|--auto]"
        echo ""
        echo "Options:"
        echo "  target_count  - Set worker count to specific number"
        echo "  --auto, -a    - Auto-scale based on server performance"
        echo ""
        echo "Current workers: $(get_current_workers)"
        exit 1
    fi
}

# Check dependencies
if ! command -v bc &> /dev/null; then
    echo -e "${YELLOW}Warning: 'bc' not found. Installing...${NC}"
    sudo apt-get update && sudo apt-get install -y bc > /dev/null 2>&1
fi

main "$@"

