#!/bin/bash

# benchmark-server.sh - Benchmark server to determine optimal worker count
# Usage: ./Scripts/benchmark-server.sh

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

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Server Performance Benchmark${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Get system specs
echo -e "${BLUE}=== System Specifications ===${NC}"
CPU_CORES=$(nproc)
TOTAL_MEM=$(free -h | grep Mem | awk '{print $2}')
AVAIL_MEM=$(free -h | grep Mem | awk '{print $7}')
DISK_SPACE=$(df -h / | tail -1 | awk '{print $4}')

echo -e "CPU Cores:        ${GREEN}${CPU_CORES}${NC}"
echo -e "Total Memory:     ${GREEN}${TOTAL_MEM}${NC}"
echo -e "Available Memory: ${GREEN}${AVAIL_MEM}${NC}"
echo -e "Disk Space:       ${GREEN}${DISK_SPACE}${NC}"
echo ""

# Estimate resource usage per worker
echo -e "${BLUE}=== Resource Estimation ===${NC}"
echo "Estimating resource usage per fuzzer worker..."
echo ""

# Typical resource usage per worker (can be adjusted based on observations)
ESTIMATED_CPU_PER_WORKER=15  # percentage
ESTIMATED_MEM_PER_WORKER=512  # MB
ESTIMATED_DB_CONNECTIONS_PER_WORKER=5

# Calculate recommendations
MAX_WORKERS_BY_CPU=$((CPU_CORES * 100 / ESTIMATED_CPU_PER_WORKER))
AVAIL_MEM_MB=$(free -m | grep Mem | awk '{print $7}')
MAX_WORKERS_BY_MEM=$((AVAIL_MEM_MB / ESTIMATED_MEM_PER_WORKER))
MAX_DB_CONNECTIONS=100  # PostgreSQL default max_connections
MAX_WORKERS_BY_DB=$((MAX_DB_CONNECTIONS / ESTIMATED_DB_CONNECTIONS_PER_WORKER))

# Conservative estimate (use minimum)
RECOMMENDED_WORKERS=$((MAX_WORKERS_BY_CPU < MAX_WORKERS_BY_MEM ? MAX_WORKERS_BY_CPU : MAX_WORKERS_BY_MEM))
RECOMMENDED_WORKERS=$((RECOMMENDED_WORKERS < MAX_WORKERS_BY_DB ? RECOMMENDED_WORKERS : MAX_WORKERS_BY_DB))

# Apply safety margin (80% of calculated)
RECOMMENDED_WORKERS=$((RECOMMENDED_WORKERS * 80 / 100))
RECOMMENDED_WORKERS=$((RECOMMENDED_WORKERS > 1 ? RECOMMENDED_WORKERS : 1))

echo -e "Estimated CPU per worker:    ${YELLOW}${ESTIMATED_CPU_PER_WORKER}%${NC}"
echo -e "Estimated Memory per worker:  ${YELLOW}${ESTIMATED_MEM_PER_WORKER}MB${NC}"
echo -e "Estimated DB conns per worker: ${YELLOW}${ESTIMATED_DB_CONNECTIONS_PER_WORKER}${NC}"
echo ""

echo -e "${BLUE}=== Capacity Analysis ===${NC}"
echo -e "Max workers (CPU):     ${CYAN}${MAX_WORKERS_BY_CPU}${NC}"
echo -e "Max workers (Memory):  ${CYAN}${MAX_WORKERS_BY_MEM}${NC}"
echo -e "Max workers (DB):      ${CYAN}${MAX_WORKERS_BY_DB}${NC}"
echo ""

echo -e "${GREEN}=== Recommended Configuration ===${NC}"
echo -e "Recommended Workers:   ${GREEN}${RECOMMENDED_WORKERS}${NC}"
echo ""

# Performance test with current workers
if docker ps --format "{{.Names}}" | grep -q "fuzzer-worker"; then
    echo -e "${BLUE}=== Current Performance Test ===${NC}"
    echo "Testing current worker performance..."
    echo ""
    
    # Get current worker count
    CURRENT_WORKERS=$(docker ps --format "{{.Names}}" | grep -c "fuzzer-worker" || echo "0")
    echo -e "Current Workers: ${CYAN}${CURRENT_WORKERS}${NC}"
    
    # Monitor for 30 seconds
    echo "Monitoring for 30 seconds..."
    START_TIME=$(date +%s)
    
    # Get initial stats
    if docker ps --format "{{.Names}}" | grep -q "fuzzilli-postgres-master"; then
        DB_CONTAINER="fuzzilli-postgres-master"
        DB_NAME="fuzzilli_master"
        DB_USER="fuzzilli"
        
        INITIAL_EXECS=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "
            SELECT COUNT(*) FROM execution WHERE created_at > NOW() - INTERVAL '1 minute';
        " 2>/dev/null || echo "0")
        
        sleep 30
        
        FINAL_EXECS=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "
            SELECT COUNT(*) FROM execution WHERE created_at > NOW() - INTERVAL '1 minute';
        " 2>/dev/null || echo "0")
        
        EXECS_PER_SEC=$(( (FINAL_EXECS - INITIAL_EXECS) / 30 ))
        EXECS_PER_WORKER=$(( EXECS_PER_SEC / CURRENT_WORKERS ))
        
        echo -e "Executions/sec:    ${GREEN}${EXECS_PER_SEC}${NC}"
        echo -e "Executions/worker:  ${GREEN}${EXECS_PER_WORKER}${NC}"
        echo ""
        
        # Get system load
        CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
        MEM_USAGE=$(free | grep Mem | awk '{printf "%.1f", ($3/$2) * 100.0}')
        
        echo -e "CPU Usage:         ${CYAN}${CPU_USAGE}%${NC}"
        echo -e "Memory Usage:      ${CYAN}${MEM_USAGE}%${NC}"
        echo ""
        
        # Scaling recommendations
        echo -e "${BLUE}=== Scaling Recommendations ===${NC}"
        if (( $(echo "$CPU_USAGE < 50" | bc -l) )) && (( $(echo "$MEM_USAGE < 50" | bc -l) )); then
            SUGGESTED_WORKERS=$((CURRENT_WORKERS * 2))
            echo -e "${GREEN}✓ System has capacity${NC}"
            echo -e "Suggested workers: ${GREEN}${SUGGESTED_WORKERS}${NC} (double current)"
        elif (( $(echo "$CPU_USAGE > 80" | bc -l) )) || (( $(echo "$MEM_USAGE > 80" | bc -l) )); then
            SUGGESTED_WORKERS=$((CURRENT_WORKERS / 2))
            SUGGESTED_WORKERS=$((SUGGESTED_WORKERS > 1 ? SUGGESTED_WORKERS : 1))
            echo -e "${RED}⚠ System under high load${NC}"
            echo -e "Suggested workers: ${YELLOW}${SUGGESTED_WORKERS}${NC} (reduce by half)"
        else
            echo -e "${YELLOW}System load is moderate${NC}"
            echo -e "Current worker count seems appropriate"
        fi
    fi
else
    echo -e "${YELLOW}No workers currently running${NC}"
    echo -e "Start workers with: ${CYAN}./Scripts/start-distributed.sh ${RECOMMENDED_WORKERS}${NC}"
fi

echo ""
echo -e "${CYAN}========================================${NC}"

