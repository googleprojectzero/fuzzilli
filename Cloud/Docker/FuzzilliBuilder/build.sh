#!/bin/bash

set -e

cd $(dirname $0)
FUZZILLI_ROOT=../../..

# Setup build context
rm -rf fuzzilli && mkdir fuzzilli
cp -r $FUZZILLI_ROOT/Sources fuzzilli
cp -r $FUZZILLI_ROOT/Tests fuzzilli
cp -r $FUZZILLI_ROOT/Package.swift fuzzilli

# Compile Fuzzilli
sudo docker build -t fuzzilli_builder .

# Copy build products
mkdir -p out
sudo docker create --name temp_container fuzzilli_builder
sudo docker cp temp_container:/home/builder/fuzzilli/.build/release/FuzzilliCli out/Fuzzilli
sudo docker rm temp_container

# Clean up
rm -rf fuzzilli
