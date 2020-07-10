#!/bin/bash

set -e

cd $(dirname $0)
FUZZILLI_ROOT=../../..

# Setup build context
REV=$(cat $FUZZILLI_ROOT/Targets/JavaScriptCore/REVISION)
cp -R $FUZZILLI_ROOT/Targets/JavaScriptCore/Patches .
cp $FUZZILLI_ROOT/Targets/JavaScriptCore/fuzzbuild.sh .

# Fetch the source code, apply patches, and compile the engine
docker build --build-arg rev=$REV -t jsc_builder .

# Copy build products
mkdir -p out
docker create --name temp_container jsc_builder
docker cp temp_container:/home/builder/webkit/FuzzBuild/Debug/bin/jsc out/jsc
docker rm temp_container

# Clean up
rm -r Patches
rm fuzzbuild.sh
