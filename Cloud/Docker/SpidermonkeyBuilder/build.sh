#!/bin/bash

set -e

cd $(dirname $0)
FUZZILLI_ROOT=../../..

# Setup build context
REV=$(cat $FUZZILLI_ROOT/Targets/Spidermonkey/REVISION)
cp -R $FUZZILLI_ROOT/Targets/Spidermonkey/Patches .
cp $FUZZILLI_ROOT/Targets/Spidermonkey/fuzzbuild.sh .

# Fetch the source code, apply patches, and compile the engine
docker build --build-arg rev=$REV -t spidermonkey_builder .

# Copy build products
mkdir -p out
docker create --name temp_container spidermonkey_builder
docker cp temp_container:/home/builder/firefox/obj-fuzzbuild/dist/bin/js out/js
docker rm temp_container

# Clean up
rm -r Patches
rm fuzzbuild.sh
