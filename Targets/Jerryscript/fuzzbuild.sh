#!/bin/bash

export CC=clang
python tools/build.py --compile-flag=-fsanitize-coverage=trace-pc-guard --profile=es2015-subset --lto=off --compile-flag=-D_POSIX_C_SOURCE=200809 --compile-flag=-Wno-strict-prototypes --stack-limit=15
