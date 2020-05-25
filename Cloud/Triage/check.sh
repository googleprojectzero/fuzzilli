#!/bin/bash

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 path/to/js/shell path/to/crashes [arguments, ...]"
    exit 1
fi

CRASHES_DIR=$1
shift
JS_SHELL=$1
shift

for f in $(find $1 -maxdepth 1 -name '*js'); do
    echo $f
    ASAN_OPTIONS=detect_leaks=0 timeout 5s $JS_SHELL $@ $f
done &> log
