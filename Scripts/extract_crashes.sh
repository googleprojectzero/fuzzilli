#!/bin/bash

# Extract all programs that crashed V8 or Fuzzilli (Crashed and SigCheck outcomes)
# Programs are saved in FuzzIL binary format (.fzil)

DB_CONTAINER="fuzzilli-postgres-master"
DB_NAME="fuzzilli_master"
DB_USER="fuzzilli"
DB_PASSWORD="fuzzilli123"

OUTPUT_DIR="crashes_extracted"
mkdir -p "$OUTPUT_DIR"

echo "Extracting all crashing and signaled programs in FuzzIL binary format..."
echo "Including: Crashed (SIGSEGV) and SigCheck (SIGTRAP) outcomes"

# Get all crash and sigcheck information
docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -A -F'|' -c "
SELECT 
    p.program_hash,
    e.execution_id,
    eo.outcome,
    e.signal_code,
    e.execution_time_ms,
    e.created_at,
    p.program_base64,
    p.program_size,
    p.fuzzer_id,
    LEFT(COALESCE(e.stderr, ''), 500) as crash_info
FROM execution e
JOIN execution_outcome eo ON e.execution_outcome_id = eo.id
JOIN program p ON e.program_hash = p.program_hash
WHERE eo.outcome IN ('Crashed', 'SigCheck')
ORDER BY eo.outcome, e.created_at DESC;
" | while IFS='|' read -r hash execution_id outcome signal_code exec_time created_at base64_program program_size fuzzer_id crash_info; do
    
    # Trim whitespace
    hash=$(echo "$hash" | xargs)
    execution_id=$(echo "$execution_id" | xargs)
    outcome=$(echo "$outcome" | xargs)
    signal_code=$(echo "$signal_code" | xargs)
    exec_time=$(echo "$exec_time" | xargs)
    created_at=$(echo "$created_at" | xargs)
    base64_program=$(echo "$base64_program" | xargs)
    program_size=$(echo "$program_size" | xargs)
    fuzzer_id=$(echo "$fuzzer_id" | xargs)
    crash_info=$(echo "$crash_info" | xargs)
    
    if [ -z "$hash" ]; then
        continue
    fi
    
    # Determine signal name
    signal_name="UNKNOWN"
    if [ "$outcome" = "Crashed" ] && [ "$signal_code" = "11" ]; then
        signal_name="SIGSEGV (Segmentation Fault)"
        prefix="crash"
    elif [ "$outcome" = "SigCheck" ] && [ "$signal_code" = "5" ]; then
        signal_name="SIGTRAP (Debug Assertion)"
        prefix="sigcheck"
    else
        signal_name="Signal $signal_code"
        prefix="signaled"
    fi
    
    echo "Processing $outcome: $hash (execution_id: $execution_id, signal: $signal_code)"
    
    # Decode base64 to binary FuzzIL protobuf format
    binary_program=$(echo "$base64_program" | base64 -d 2>/dev/null)
    
    if [ -z "$binary_program" ]; then
        echo "  ERROR: Failed to decode base64 program"
        continue
    fi
    
    # Save as .fzil file (FuzzIL binary protobuf format)
    fzil_filename="${OUTPUT_DIR}/${prefix}_${execution_id}_${hash}.fzil"
    echo -n "$binary_program" > "$fzil_filename"
    
    # Create metadata file
    meta_filename="${OUTPUT_DIR}/${prefix}_${execution_id}_${hash}.txt"
    cat > "$meta_filename" <<EOF
================================================================================
${outcome} REPORT
================================================================================
Program Hash: $hash
Execution ID: $execution_id
Outcome: $outcome
Signal Code: $signal_code ($signal_name)
Execution Time: ${exec_time}ms
Program Size: ${program_size} bytes (protobuf binary)
Fuzzer ID: $fuzzer_id
Created At: $created_at
================================================================================

Crash/Signal Information (STDERR):
$crash_info

================================================================================
Files:
- FuzzIL Binary: ${prefix}_${execution_id}_${hash}.fzil
- Metadata: ${prefix}_${execution_id}_${hash}.txt

To view the FuzzIL program, use:
  FuzzILTool decode ${prefix}_${execution_id}_${hash}.fzil

To lift to JavaScript:
  FuzzILTool lift ${prefix}_${execution_id}_${hash}.fzil
================================================================================
EOF
    
    echo "  Saved FuzzIL binary: $fzil_filename"
    echo "  Saved metadata: $meta_filename"
done

# Count extracted files
crash_count=$(ls -1 "${OUTPUT_DIR}"/crash_*.fzil 2>/dev/null | wc -l)
sigcheck_count=$(ls -1 "${OUTPUT_DIR}"/sigcheck_*.fzil 2>/dev/null | wc -l)
total_count=$(ls -1 "${OUTPUT_DIR}"/*.fzil 2>/dev/null | wc -l)

echo ""
echo "Extraction complete!"
echo "  Crashed (SIGSEGV): $crash_count programs"
echo "  SigCheck (SIGTRAP): $sigcheck_count programs"
echo "  Total: $total_count programs"
echo ""
echo "All programs are saved in FuzzIL binary format (.fzil files) in $OUTPUT_DIR/"
echo "Use FuzzILTool to decode or lift them to JavaScript if needed"
