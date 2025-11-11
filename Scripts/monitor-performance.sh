#!/bin/bash

# monitor-performance.sh - Monitor server performance and fuzzing metrics
# Usage: ./Scripts/monitor-performance.sh [interval_seconds]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

INTERVAL=${1:-5}  # Default 5 seconds
DB_CONTAINER="fuzzilli-postgres-master"
DB_NAME="fuzzilli_master"
DB_USER="fuzzilli"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Function to get CPU usage
get_cpu_usage() {
    top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}'
}

# Function to get memory usage
get_memory_usage() {
    free | grep Mem | awk '{printf "%.1f", ($3/$2) * 100.0}'
}

# Function to get disk I/O
get_disk_io() {
    iostat -x 1 2 | tail -n +4 | awk '{sum+=$10} END {printf "%.1f", sum/NR}'
}

# Function to get database connection count
get_db_connections() {
    if docker ps --format "{{.Names}}" | grep -q "^${DB_CONTAINER}$"; then
        docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "SELECT count(*) FROM pg_stat_activity WHERE datname = '$DB_NAME';" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Function to get total executions per second across all fuzzers
get_total_execs_per_sec() {
    if docker ps --format "{{.Names}}" | grep -q "^${DB_CONTAINER}$"; then
        docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "
            SELECT COALESCE(SUM(execs_per_second), 0) 
            FROM fuzzer_performance_summary 
            WHERE status = 'active';
        " 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Function to get active worker count
get_active_workers() {
    docker ps --format "{{.Names}}" | grep -c "fuzzer-worker" || echo "0"
}

# Function to get database size
get_db_size() {
    if docker ps --format "{{.Names}}" | grep -q "^${DB_CONTAINER}$"; then
        docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "
            SELECT pg_size_pretty(pg_database_size('$DB_NAME'));
        " 2>/dev/null || echo "N/A"
    else
        echo "N/A"
    fi
}

# Function to get total programs and executions
get_db_stats() {
    if docker ps --format "{{.Names}}" | grep -q "^${DB_CONTAINER}$"; then
        docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -A -F'|' -c "
            SELECT total_programs, total_executions, total_crashes, active_fuzzers 
            FROM global_statistics;
        " 2>/dev/null || echo "0|0|0|0"
    else
        echo "0|0|0|0"
    fi
}

# Function to get per-worker performance
get_worker_performance() {
    if docker ps --format "{{.Names}}" | grep -q "^${DB_CONTAINER}$"; then
        docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -A -F'|' -c "
            SELECT 
                fuzzer_id,
                ROUND(execs_per_second::numeric, 2),
                executions_count,
                crash_count
            FROM fuzzer_performance_summary 
            WHERE status = 'active'
            ORDER BY fuzzer_id;
        " 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Main monitoring loop
monitor() {
    local iteration=0
    
    while true; do
        clear
        echo -e "${CYAN}========================================${NC}"
        echo -e "${CYAN}  Fuzzilli Performance Monitor${NC}"
        echo -e "${CYAN}========================================${NC}"
        echo ""
        
        # System metrics
        echo -e "${BLUE}=== System Resources ===${NC}"
        CPU=$(get_cpu_usage)
        MEM=$(get_memory_usage)
        DB_CONN=$(get_db_connections)
        DB_SIZE=$(get_db_size)
        
        # Color code CPU usage
        if (( $(echo "$CPU > 80" | bc -l) )); then
            CPU_COLOR=$RED
        elif (( $(echo "$CPU > 60" | bc -l) )); then
            CPU_COLOR=$YELLOW
        else
            CPU_COLOR=$GREEN
        fi
        
        # Color code memory usage
        if (( $(echo "$MEM > 80" | bc -l) )); then
            MEM_COLOR=$RED
        elif (( $(echo "$MEM > 60" | bc -l) )); then
            MEM_COLOR=$YELLOW
        else
            MEM_COLOR=$GREEN
        fi
        
        echo -e "CPU Usage:        ${CPU_COLOR}${CPU}%${NC}"
        echo -e "Memory Usage:     ${MEM_COLOR}${MEM}%${NC}"
        echo -e "DB Connections:  ${CYAN}${DB_CONN}${NC}"
        echo -e "DB Size:          ${CYAN}${DB_SIZE}${NC}"
        echo ""
        
        # Fuzzing metrics
        echo -e "${BLUE}=== Fuzzing Metrics ===${NC}"
        ACTIVE_WORKERS=$(get_active_workers)
        TOTAL_EXECS=$(get_total_execs_per_sec)
        DB_STATS=$(get_db_stats)
        
        IFS='|' read -r total_programs total_executions total_crashes active_fuzzers <<< "$DB_STATS"
        
        echo -e "Active Workers:    ${GREEN}${ACTIVE_WORKERS}${NC}"
        echo -e "Total Execs/sec:   ${GREEN}${TOTAL_EXECS}${NC}"
        echo -e "Total Programs:    ${CYAN}${total_programs}${NC}"
        echo -e "Total Executions:  ${CYAN}${total_executions}${NC}"
        echo -e "Total Crashes:     ${RED}${total_crashes}${NC}"
        echo ""
        
        # Per-worker breakdown
        echo -e "${BLUE}=== Per-Worker Performance ===${NC}"
        WORKER_PERF=$(get_worker_performance)
        if [ -n "$WORKER_PERF" ]; then
            echo -e "${YELLOW}Worker | Execs/sec | Executions | Crashes${NC}"
            echo "$WORKER_PERF" | while IFS='|' read -r worker_id execs_per_sec executions crashes; do
                printf "  %-4s | %9s | %10s | %7s\n" "$worker_id" "$execs_per_sec" "$executions" "$crashes"
            done
        else
            echo -e "${YELLOW}No worker data available${NC}"
        fi
        echo ""
        
        # Recommendations
        echo -e "${BLUE}=== Recommendations ===${NC}"
        if (( $(echo "$CPU > 80" | bc -l) )); then
            echo -e "${RED}⚠ High CPU usage - consider reducing workers${NC}"
        elif (( $(echo "$CPU < 40" | bc -l) )); then
            echo -e "${GREEN}✓ CPU has capacity - could add more workers${NC}"
        fi
        
        if (( $(echo "$MEM > 80" | bc -l) )); then
            echo -e "${RED}⚠ High memory usage - consider reducing workers${NC}"
        elif (( $(echo "$MEM < 40" | bc -l) )); then
            echo -e "${GREEN}✓ Memory has capacity - could add more workers${NC}"
        fi
        
        if (( $(echo "$DB_CONN > 50" | bc -l) )); then
            echo -e "${YELLOW}⚠ High database connection count${NC}"
        fi
        
        echo ""
        echo -e "${CYAN}Press Ctrl+C to stop${NC}"
        echo -e "${CYAN}Update interval: ${INTERVAL}s${NC}"
        
        sleep "$INTERVAL"
        iteration=$((iteration + 1))
    done
}

# Check dependencies
if ! command -v bc &> /dev/null; then
    echo -e "${YELLOW}Warning: 'bc' not found. Installing...${NC}"
    sudo apt-get update && sudo apt-get install -y bc
fi

# Start monitoring
monitor

