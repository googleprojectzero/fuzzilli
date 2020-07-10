#!/bin/bash

set -e

cd $(dirname $0)
FUZZILLI_ROOT=../../..

# Setup build context
REV=$(cat $FUZZILLI_ROOT/Targets/Jerryscript/REVISION)
cp -R $FUZZILLI_ROOT/Targets/Jerryscript/Patches .
cp $FUZZILLI_ROOT/Targets/Jerryscript/fuzzbuild.sh .

# Fetch the source code, apply patches, and compile the engine
docker build --build-arg rev=$REV -t jerryscript_builder .

# Copy build products
mkdir -p out
docker create --name temp_container jerryscript_builder
docker cp temp_container:/home/builder/jerryscript/build/bin/jerry out/jerry
docker rm temp_container

# Clean up
rm -r Patches
rm fuzzbuild.sh
