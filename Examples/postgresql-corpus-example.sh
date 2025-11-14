#!/bin/bash

# PostgreSQL Corpus Example for Fuzzilli
# This script demonstrates how to use the new PostgreSQL corpus feature

echo "=== Fuzzilli PostgreSQL Corpus Example ==="
echo ""

echo "1. Basic PostgreSQL corpus usage:"
echo "swift run FuzzilliCli --corpus=postgresql --postgres-url=postgresql://localhost:5432/fuzzilli --profile=v8 /path/to/d8"
echo ""

echo "2. With custom sync interval and validation:"
echo "swift run FuzzilliCli --corpus=postgresql --postgres-url=postgresql://user:pass@host:5432/db --sync-interval=30 --validate-before-cache --execution-history-size=20 --profile=v8 /path/to/d8"
echo ""

echo "3. Multiple fuzzer instances sharing the same PostgreSQL database:"
echo "# Fuzzer 1:"
echo "swift run FuzzilliCli --corpus=postgresql --postgres-url=postgresql://localhost:5432/fuzzilli --profile=v8 /path/to/d8"
echo ""
echo "# Fuzzer 2 (in another terminal):"
echo "swift run FuzzilliCli --corpus=postgresql --postgres-url=postgresql://localhost:5432/fuzzilli --profile=v8 /path/to/d8"
echo ""

echo "4. Available PostgreSQL corpus options:"
echo "  --corpus=postgresql                    : Use PostgreSQL corpus"
echo "  --postgres-url=url                     : PostgreSQL connection string (required)"
echo "  --sync-interval=n                      : Sync interval in seconds (default: 10)"
echo "  --validate-before-cache                : Enable program validation (default: true)"
echo "  --execution-history-size=n             : Recent executions to keep in memory (default: 10)"
echo ""

echo "5. PostgreSQL connection string format:"
echo "  postgresql://username:password@hostname:port/database"
echo "  Example: postgresql://fuzzilli:password@localhost:5432/fuzzilli"
echo ""

echo "6. Features of PostgreSQL corpus:"
echo "  - In-memory caching for fast access"
echo "  - PostgreSQL backend for persistence and sharing"
echo "  - Execution metadata tracking (coverage, execution count, etc.)"
echo "  - Periodic synchronization with central database"
echo "  - Thread-safe operations"
echo "  - Distributed fuzzing support"
echo ""

echo "7. Help and validation:"
echo "swift run FuzzilliCli --help                    # Show all options"
echo "swift run FuzzilliCli --corpus=postgresql       # Shows validation error"
echo ""

echo "=== Example Complete ==="
