FROM swift:latest

ENV DEBIAN_FRONTEND=noninteractive
ENV SHELL=bash

RUN apt-get -y update && apt-get -y upgrade
RUN apt-get install -y git make clang bc curl python-pip nodejs npm

# Update NodeJS and NPM to the latest versions
RUN npm install -g n
RUN n latest
RUN npm install -g npm

# Dependency of the duktape build process
RUN pip install pyyaml

RUN useradd -m builder

RUN git clone https://github.com/svaarala/duktape.git /home/builder/duktape
WORKDIR /home/builder/duktape

# The hash of the most recent commit is passed in from the build script, to ensure proper caching behavior
ARG rev
RUN git pull && git checkout $rev

# Update system packages first
RUN apt-get -y update && apt-get -y upgrade

# Make normally to pull down NodeJS deps
RUN make

# Assume that the current master branch maintains duk-fuzzilli
# No need to patch, as the fuzz target is maintained in the duktape repo
# Start building!
RUN make build/duk-fuzzilli
