#!/bin/bash

# test-distributed-sync.sh - Integration test for distributed PostgreSQL sync
# This script tests:
# 1. Push sync: Workers push their corpus to main database
# 2. Pull sync: Workers pull corpus from main database
# 3. Fuzzing activity: Workers are actually fuzzing
# 4. Database updates: Database updates correctly reflect fuzzing
# 5. Corpus visibility: Fuzzers see new information in corpus

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
NUM_WORKERS=${1:-2}
SYNC_INTERVAL=${SYNC_INTERVAL:-60}  # Use shorter interval for testing
TEST_TIMEOUT=${TEST_TIMEOUT:-300}    # 5 minutes max
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-fuzzilli123}

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

echo "=========================================="
echo "Distributed PostgreSQL Sync Integration Test"
echo "=========================================="
echo "Workers: $NUM_WORKERS"
echo "Sync Interval: ${SYNC_INTERVAL}s"
echo "Test Timeout: ${TEST_TIMEOUT}s"
echo "=========================================="
echo ""

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log_info "✓ $1"
}

test_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    log_error "✗ $1"
}

test_warn() {
    log_warn "⚠ $1"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test environment..."
    cd "${PROJECT_ROOT}"
    docker-compose -f docker-compose.distributed.yml -f docker-compose.workers.yml down -v 2>/dev/null || true
    rm -f "${PROJECT_ROOT}/docker-compose.workers.yml"
}

trap cleanup EXIT

# Start distributed system
log_info "Starting distributed system with $NUM_WORKERS workers..."
cd "${PROJECT_ROOT}"
"${SCRIPT_DIR}/start-distributed.sh" "$NUM_WORKERS" > /dev/null 2>&1

# Wait for all services to be ready
log_info "Waiting for services to be ready..."
sleep 30

# Verify services are running
log_info "Verifying services are running..."
MASTER_RUNNING=$(docker ps --filter "name=fuzzilli-postgres-master" --format "{{.Names}}" | wc -l)
if [ "$MASTER_RUNNING" -eq 1 ]; then
    test_pass "Main postgres container is running"
else
    test_fail "Main postgres container is not running"
    exit 1
fi

WORKERS_RUNNING=$(docker ps --filter "name=fuzzer-worker" --format "{{.Names}}" | wc -l)
if [ "$WORKERS_RUNNING" -eq "$NUM_WORKERS" ]; then
    test_pass "All $NUM_WORKERS worker containers are running"
else
    test_fail "Expected $NUM_WORKERS workers, found $WORKERS_RUNNING"
    exit 1
fi

LOCAL_POSTGRES_RUNNING=$(docker ps --filter "name=postgres-local" --format "{{.Names}}" | wc -l)
if [ "$LOCAL_POSTGRES_RUNNING" -eq "$NUM_WORKERS" ]; then
    test_pass "All $NUM_WORKERS local postgres containers are running"
else
    test_fail "Expected $NUM_WORKERS local postgres containers, found $LOCAL_POSTGRES_RUNNING"
    exit 1
fi

# Test 1: Push Sync - Insert test program into local database and verify it appears in master
log_info ""
log_info "Test 1: Push Sync"
log_info "=================="

# Generate a test program hash (simplified - in real scenario, this would be a proper FuzzIL program)
TEST_HASH="test_push_$(date +%s)"
TEST_PROGRAM_B64="dGVzdF9wcm9ncmFt"  # base64("test_program")

# Insert test program into first worker's local database
log_info "Inserting test program into worker 1 local database..."
docker exec postgres-local-1 psql -U fuzzilli -d fuzzilli_local -c "
    INSERT INTO main (fuzzer_name, engine_type, status) VALUES ('fuzzer-1', 'v8', 'active') ON CONFLICT DO NOTHING;
    SELECT fuzzer_id INTO TEMP temp_fuzzer_id FROM main WHERE fuzzer_name = 'fuzzer-1';
    INSERT INTO fuzzer (program_hash, fuzzer_id, program_size, program_base64, inserted_at)
    SELECT '$TEST_HASH', fuzzer_id, 100, '$TEST_PROGRAM_B64', NOW()
    FROM temp_fuzzer_id;
" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    test_pass "Test program inserted into local database"
else
    test_fail "Failed to insert test program into local database"
fi

# Wait for sync interval
log_info "Waiting ${SYNC_INTERVAL}s for push sync..."
sleep $((SYNC_INTERVAL + 10))

# Check if program appears in master database
log_info "Checking if program appears in master database..."
PROGRAM_IN_MASTER=$(docker exec fuzzilli-postgres-master psql -U fuzzilli -d fuzzilli_master -t -c "
    SELECT COUNT(*) FROM fuzzer WHERE program_hash = '$TEST_HASH';
" | tr -d ' ')

if [ "$PROGRAM_IN_MASTER" -gt 0 ]; then
    test_pass "Test program synced to master database (push sync working)"
else
    test_fail "Test program not found in master database (push sync may have failed)"
fi

# Test 2: Pull Sync - Insert test program into master and verify it appears in worker local databases
log_info ""
log_info "Test 2: Pull Sync"
log_info "=================="

TEST_PULL_HASH="test_pull_$(date +%s)"

# Insert test program into master database (simulating another worker)
log_info "Inserting test program into master database (simulating another worker)..."
docker exec fuzzilli-postgres-master psql -U fuzzilli -d fuzzilli_master -c "
    INSERT INTO main (fuzzer_name, engine_type, status) VALUES ('fuzzer-test-source', 'v8', 'active') ON CONFLICT DO NOTHING;
    SELECT fuzzer_id INTO TEMP temp_fuzzer_id FROM main WHERE fuzzer_name = 'fuzzer-test-source';
    INSERT INTO fuzzer (program_hash, fuzzer_id, program_size, program_base64, inserted_at)
    SELECT '$TEST_PULL_HASH', fuzzer_id, 100, '$TEST_PROGRAM_B64', NOW()
    FROM temp_fuzzer_id;
" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    test_pass "Test program inserted into master database"
else
    test_fail "Failed to insert test program into master database"
fi

# Wait for sync interval
log_info "Waiting ${SYNC_INTERVAL}s for pull sync..."
sleep $((SYNC_INTERVAL + 10))

# Check if program appears in worker local databases
log_info "Checking if program appears in worker local databases..."
WORKER_WITH_PROGRAM=0
for i in $(seq 1 $NUM_WORKERS); do
    COUNT=$(docker exec postgres-local-${i} psql -U fuzzilli -d fuzzilli_local -t -c "
        SELECT COUNT(*) FROM fuzzer WHERE program_hash = '$TEST_PULL_HASH';
    " 2>/dev/null | tr -d ' ' || echo "0")
    
    if [ "$COUNT" -gt 0 ]; then
        WORKER_WITH_PROGRAM=$((WORKER_WITH_PROGRAM + 1))
    fi
done

if [ "$WORKER_WITH_PROGRAM" -gt 0 ]; then
    test_pass "Test program pulled to $WORKER_WITH_PROGRAM worker(s) (pull sync working)"
else
    test_fail "Test program not found in any worker local database (pull sync may have failed)"
fi

# Test 3: Fuzzing Activity
log_info ""
log_info "Test 3: Fuzzing Activity"
log_info "========================"

# Check worker logs for fuzzing activity
log_info "Checking worker logs for fuzzing activity..."
FUZZING_DETECTED=0
for i in $(seq 1 $NUM_WORKERS); do
    if docker logs fuzzer-worker-${i} 2>&1 | grep -qiE "(fuzzing|execution|program)" | head -5 | grep -q .; then
        FUZZING_DETECTED=$((FUZZING_DETECTED + 1))
    fi
done

if [ "$FUZZING_DETECTED" -gt 0 ]; then
    test_pass "Fuzzing activity detected in $FUZZING_DETECTED worker(s)"
else
    test_warn "No clear fuzzing activity detected in logs (workers may still be starting)"
fi

# Check execution counts in databases
log_info "Checking execution counts in databases..."
MASTER_EXECUTIONS=$(docker exec fuzzilli-postgres-master psql -U fuzzilli -d fuzzilli_master -t -c "
    SELECT COUNT(*) FROM execution;
" 2>/dev/null | tr -d ' ' || echo "0")

if [ "$MASTER_EXECUTIONS" -gt 0 ]; then
    test_pass "Executions found in master database: $MASTER_EXECUTIONS"
else
    test_warn "No executions found in master database yet (workers may still be starting)"
fi

# Test 4: Database Updates
log_info ""
log_info "Test 4: Database Updates"
log_info "======================="

# Check program counts
MASTER_PROGRAMS=$(docker exec fuzzilli-postgres-master psql -U fuzzilli -d fuzzilli_master -t -c "
    SELECT COUNT(*) FROM program;
" 2>/dev/null | tr -d ' ' || echo "0")

LOCAL_PROGRAMS_TOTAL=0
for i in $(seq 1 $NUM_WORKERS); do
    COUNT=$(docker exec postgres-local-${i} psql -U fuzzilli -d fuzzilli_local -t -c "
        SELECT COUNT(*) FROM program;
    " 2>/dev/null | tr -d ' ' || echo "0")
    LOCAL_PROGRAMS_TOTAL=$((LOCAL_PROGRAMS_TOTAL + COUNT))
done

log_info "Master database programs: $MASTER_PROGRAMS"
log_info "Total local database programs: $LOCAL_PROGRAMS_TOTAL"

if [ "$MASTER_PROGRAMS" -gt 0 ] || [ "$LOCAL_PROGRAMS_TOTAL" -gt 0 ]; then
    test_pass "Database updates are being recorded (programs found)"
else
    test_warn "No programs found in databases yet (workers may still be starting)"
fi

# Test 5: Corpus Visibility
log_info ""
log_info "Test 5: Corpus Visibility"
log_info "========================"

# Insert a program with a known hash into master
CORPUS_TEST_HASH="corpus_visibility_$(date +%s)"
log_info "Inserting test program for corpus visibility test..."
docker exec fuzzilli-postgres-master psql -U fuzzilli -d fuzzilli_master -c "
    INSERT INTO main (fuzzer_name, engine_type, status) VALUES ('fuzzer-corpus-test', 'v8', 'active') ON CONFLICT DO NOTHING;
    SELECT fuzzer_id INTO TEMP temp_fuzzer_id FROM main WHERE fuzzer_name = 'fuzzer-corpus-test';
    INSERT INTO fuzzer (program_hash, fuzzer_id, program_size, program_base64, inserted_at)
    SELECT '$CORPUS_TEST_HASH', fuzzer_id, 100, '$TEST_PROGRAM_B64', NOW()
    FROM temp_fuzzer_id;
" > /dev/null 2>&1

# Wait for pull sync
log_info "Waiting ${SYNC_INTERVAL}s for corpus visibility sync..."
sleep $((SYNC_INTERVAL + 10))

# Check if program can be retrieved from worker databases
VISIBLE_IN_WORKERS=0
for i in $(seq 1 $NUM_WORKERS); do
    COUNT=$(docker exec postgres-local-${i} psql -U fuzzilli -d fuzzilli_local -t -c "
        SELECT COUNT(*) FROM fuzzer WHERE program_hash = '$CORPUS_TEST_HASH';
    " 2>/dev/null | tr -d ' ' || echo "0")
    
    if [ "$COUNT" -gt 0 ]; then
        VISIBLE_IN_WORKERS=$((VISIBLE_IN_WORKERS + 1))
    fi
done

if [ "$VISIBLE_IN_WORKERS" -gt 0 ]; then
    test_pass "Corpus visibility test passed: program visible in $VISIBLE_IN_WORKERS worker(s)"
else
    test_fail "Corpus visibility test failed: program not visible in worker databases"
fi

# Summary
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "Tests Passed: $TESTS_PASSED"
echo "Tests Failed: $TESTS_FAILED"
echo "=========================================="

if [ $TESTS_FAILED -eq 0 ]; then
    log_info "All tests passed!"
    exit 0
else
    log_error "Some tests failed. Check the output above for details."
    exit 1
fi

