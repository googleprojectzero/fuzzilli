#!/bin/bash
set -e

cd njs/
./configure --cc=clang --cc-opt="-g -fsanitize-coverage=trace-pc-guard"
make njs_fuzzilli