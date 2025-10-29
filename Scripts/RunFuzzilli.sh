#!/bin/sh
set -e

if [ -z "$1" ] || [ ! -f "$1" ]; then
    echo "Error: Please provide the path to the 'd8' binary as the first argument."
    echo "Usage: $0 /path/to/d8"
    exit 1
fi

swift run FuzzilliCli \
  --profile=v8 \
  --engine=multi \
  --resume \
  --corpus=postgresql \
  --postgres-url="postgresql://fuzzilli:fuzzilli123@localhost:5433/fuzzilli" \
  --storagePath=./Corpus \
  --logLevel=verbose \
  --timeout=1500 \
  --diagnostics "$1"