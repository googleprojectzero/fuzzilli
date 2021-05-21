FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive
ENV SHELL=bash

RUN apt-get -y update && apt-get -y upgrade
RUN apt-get install -y curl opam npm
RUN npm install -g --unsafe-perm esy

RUN useradd -m builder
WORKDIR /home/builder
USER builder

ADD --chown=builder:builder ./ Compiler
WORKDIR Compiler

# Set up Opam & Ocaml properly, for OCaml v 4.10.0
# Pin flow, and setup the package.json
RUN opam init -a --disable-sandboxing
RUN opam switch create 4.10.0 && \
    eval $(opam env) && \
    opam pin add -y flow_parser https://github.com/facebook/flow.git && \ 
    sed -i 's/.*REPLACE ME.*/    "flow_parser": "link:\/home\/builder\/.opam\/4.10.0\/.opam-switch\/sources\/flow_parser\/flow_parser.opam"/' package.json

# Install dependencies
RUN esy install

# And build!
RUN esy build

# Run the tests to verify that the compiler works correctly
RUN esy x test

# Finally, copy the compiler binary into the current directory for easy access
RUN cp _esy/default/build/default/bin/fuzzilli_compiler.exe .