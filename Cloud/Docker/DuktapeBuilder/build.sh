#!/bin/bash

set -e

cd $(dirname $0)
FUZZILLI_ROOT=../../..

# Get the hash of the most recent commit on master. This is to ensure proper caching behavior in docker
REV=$(git ls-remote https://github.com/svaarala/duktape.git | grep refs/heads/master | awk '{print $1;}')

# Since fuzzilli is integrated as a duktape make target, no need to pull over patches or a build script

# Fetch the source code, get the current master commit, and compile the engine
docker build --build-arg rev=$REV -t duktape_builder .

# Copy build products
mkdir -p out
docker create --name temp_container duktape_builder
docker cp temp_container:/home/builder/duktape/build/duk-fuzzilli out/duk-fuzzilli
docker rm temp_container

# Nothing extra to clean up!
