#!/bin/sh
set -e

# Check if the first argument (path to d8) is provided and points to a file
if [ -z "$1" ] || [ ! -f "$1" ]; then
    echo "Error: Please provide the path to the 'd8' binary as the first argument."
    echo "Usage: $0 /path/to/d8"
    exit 1
fi

# Assign the provided path to a variable for clarity
D8_PATH="$1"

# Run Fuzzilli with the provided d8 path
swift run FuzzilliCli \
  --profile=v8 \
  --engine=multi \
  --resume \
  --corpus=postgresql \
  --postgres-url="postgresql://fuzzilli:fuzzilli123@localhost:5433/fuzzilli" \
  --storagePath=./Corpus \
  --logLevel=verbose \
  --timeout=1500 \
  --diagnostics "$D8_PATH"