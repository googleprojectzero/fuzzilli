#!/bin/bash

set -e

cd $(dirname $0)
FUZZILLI_ROOT=../../..

# Setup build context
REV=$(cat $FUZZILLI_ROOT/Targets/duktape/REVISION)
# Since fuzzilli is integrated as a duktape make target, no need to pull over patches or a build script

# Fetch the source code, apply patches, and compile the engine
sudo docker build --build-arg rev=$REV -t duktape_builder .

# Copy build products
mkdir -p out
sudo docker create --name temp_container duktape_builder
sudo docker cp temp_container:/home/builder/duktape/duk-fuzzilli out/duk-fuzzilli
sudo docker rm temp_container

# Nothing extra to clean up!