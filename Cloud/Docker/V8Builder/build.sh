#!/bin/bash

set -e

cd $(dirname $0)
FUZZILLI_ROOT=../../..

# Setup build context
REV=$(cat $FUZZILLI_ROOT/Targets/V8/REVISION)
cp -R $FUZZILLI_ROOT/Targets/V8/Patches .
cp $FUZZILLI_ROOT/Targets/V8/fuzzbuild.sh .

# Fetch the source code, apply patches, and compile the engine
docker build --build-arg rev=$REV -t v8_builder .

# Copy build products
mkdir -p out
docker create --name temp_container v8_builder
docker cp temp_container:/home/builder/v8/v8/out/fuzzbuild/d8 out/d8
docker cp temp_container:/home/builder/v8/v8/out/fuzzbuild/snapshot_blob.bin out/snapshot_blob.bin
docker cp temp_container:/home/builder/v8/v8/out/fuzzbuild/icudtl.dat out/icudtl.dat
docker rm temp_container

# Clean up
rm -r Patches
rm fuzzbuild.sh
