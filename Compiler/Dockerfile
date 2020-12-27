FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive
ENV SHELL=bash

RUN apt-get -y update && apt-get -y upgrade
RUN apt-get install -y curl ocaml opam npm
RUN npm install -g --unsafe-perm esy

RUN useradd -m builder
WORKDIR /home/builder
USER builder

RUN opam init -a --disable-sandboxing

ADD --chown=builder:builder ./ Compiler
WORKDIR Compiler

# Pin the flow package...
RUN opam pin add -y flow_parser https://github.com/facebook/flow.git

# ... and add its path to package.json
RUN sed -i 's/.*REPLACE ME.*/    "flow_parser": "link:\/home\/builder\/.opam\/default\/.opam-switch\/sources\/flow_parser\/flow_parser.opam"/' package.json

# Install dependencies
RUN esy install

# And build!
RUN esy build

# Run the tests to verify that the compiler works correctly
RUN esy x test

# Finally, copy the compiler binary into the current directory for easy access
RUN cp _esy/default/build/default/bin/fuzzilli_compiler.exe .