#!/bin/sh

set -e

if [ -z "$1" ] || [ ! -f "$1" ]; then
    echo "Error: Please provide the path to the 'd8' binary as the first argument."
    echo "Usage: $0 /path/to/d8 [db-log]"
    echo "  /path/to/d8  : Path to the d8 binary"
    echo "  db-log       : Optional flag to enable PostgreSQL database logging"
    exit 1
fi

POSTGRES_LOGGING_FLAG=""
if [ "$2" = "db-log" ]; then
    POSTGRES_LOGGING_FLAG="--postgres-logging"
fi

swift run FuzzilliCli \
  --profile=v8 \
  --engine=multi \
  --resume \
  --corpus=postgresql \
  --postgres-url="postgresql://fuzzilli:fuzzilli123@localhost:5433/fuzzilli" \
  --storagePath=./Corpus \
  --logLevel=verbose \
  --timeout=3000 \
  $POSTGRES_LOGGING_FLAG \
  --diagnostics "$1"
