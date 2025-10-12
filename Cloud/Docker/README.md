# Fuzzilli in Docker

Scripts and Dockerfiles to create a docker image for fuzzing with Fuzzilli.

## Overview

The container image produced by the main build script ([build.sh](./build.sh)) will contain

- The Fuzzilli binary at ~/Fuzzilli compiled from the current source code, and
- One or more JavaScript engines compiled as specified in their respective [target directory](../../Targets). The necessary files to run the engine (the binary, possibly various libraries, and any other resource files required by the engine) will be located in a subdirectory of the home directory: ~/jsc, ~/spidermonkey, ~/v8, ~/duktape, ~/jerryscript

The container image will *not* contain any temporary build artifacts, source code, etc. to reduce its size.

## Quickstart

1. Make sure docker is installed
2. Run `./build.sh [jsc|spidermonkey|v8|duktape|jerryscript|major]`

The build script might have to run as root, depending on how [docker is configured](https://docs.docker.com/engine/install/linux-postinstall/#manage-docker-as-a-non-root-user).

Afterwards, a docker image named "fuzzilli" will be available and can be used to fuzz any of the compiled JS engines (in this example JavaScriptCore) with Fuzzilli: `docker run -ti fuzzilli ./Fuzzilli --profile=jsc ./jsc/jsc`

It is also possible to only rebuild Fuzzilli and use previously compiled engines by running `./build.sh fuzzilli`

Under the hood, here is roughly what happens during building:

- Depending on the arguments, the [root build script](./build.sh) will invoke a number of builders, located in the \*Builder subdirectories. Fuzzilli is always (re-)build (by the FuzzilliBuilder) as well as all of the requested JS engines
- The builders will generally first copy all the necessary files (Fuzzilli soure code, engine patches, target revision, etc.) from the repository root into the builder's directory (this is necessary as they have to be in a subdirectory for docker to be able to access them), then build the docker image, fetching any source code, checking out the requested revision (from the [target's](../../Targets) REVISION file) and building the final product (e.g. Fuzzilli or a JS engine). Afterwards, all build products are copied out of the container image into the out/ directory of that builder.
- Finally, the root build script copies all available build products (that may include build products from previous builds if an engine had been built before and not rebuilt this time) into the final fuzzilli docker image.
