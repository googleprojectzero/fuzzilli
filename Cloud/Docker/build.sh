#!/bin/bash

set -e

CONTAINER_NAME=fuzzilli

if [ $# -eq 0 ]; then
    echo "Usage: $0 [fuzzilli|jsc|spidermonkey|v8|duktape|jerryscript|major]"
    exit 1
fi

BUILD_JSC=false
BUILD_SPIDERMONKEY=false
BUILD_V8=false
BUILD_DUKTAPE=false
BUILD_JERRYSCRIPT=false

while test $# -gt 0
do
    case "$1" in
        fuzzilli)
            # We'll build fuzzilli anyway :)
            ;;
        jsc)
            BUILD_JSC=true
            ;;
        spidermonkey)
            BUILD_SPIDERMONKEY=true
            ;;
        v8)
            BUILD_V8=true
            ;;
        duktape)
            BUILD_DUKTAPE=true
            ;;
        jerryscript)
            BUILD_JERRYSCRIPT=true
            ;;
        major)
            BUILD_JSC=true
            BUILD_SPIDERMONKEY=true
            BUILD_V8=true
            ;;
        *)
            echo "Usage: $0 [fuzzilli|jsc|spidermonkey|v8|duktape|jerryscript|major]"
            exit 1
            ;;
    esac
    shift
done

#
# Always build Fuzzilli
#
echo "[*] Building Fuzzilli"
./FuzzilliBuilder/build.sh

#
# Selectively (re)build the JavaScript engines
#

# Ensure output directories are always present as they will be copied into the final container
mkdir -p JSCBuilder/out
mkdir -p SpidermonkeyBuilder/out
mkdir -p V8Builder/out
mkdir -p DuktapeBuilder/out
mkdir -p JerryScriptBuilder/out

if [ "$BUILD_JSC" = true ]; then
    echo "[*] Building JavaScriptCore"
    ./JSCBuilder/build.sh
fi

if [ "$BUILD_SPIDERMONKEY" = true ]; then
    echo "[*] Building Spidermonkey"
    ./SpidermonkeyBuilder/build.sh
fi

if [ "$BUILD_V8" = true ]; then
    echo "[*] Building V8"
    ./V8Builder/build.sh
fi

if [ "$BUILD_DUKTAPE" = true ]; then
    echo "[*] Building Duktape"
    ./DuktapeBuilder/build.sh
fi

if [ "$BUILD_JERRYSCRIPT" = true ]; then
    echo "[*] Building JerryScript"
    ./JerryScriptBuilder/build.sh
fi

#
# Build the final container image which only contains the binaries (no intermediate build artifacts, source code, etc.).
#
echo "[*] Packing Fuzzilli container image"
docker build -t $CONTAINER_NAME .
