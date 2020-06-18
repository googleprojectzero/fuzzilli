FROM swift:latest

ENV DEBIAN_FRONTEND=noninteractive
ENV SHELL=bash

RUN apt-get -y update && apt-get -y upgrade
RUN apt-get install -y git make clang bc python-pip

# Dependency of the duktape build process
RUN pip install pyyaml

RUN useradd -m builder

RUN git clone https://github.com/svaarala/duktape.git /home/builder/duktape
WORKDIR /home/builder/duktape

# Docker will attempt to cache the output of every step. That's fine (and useful to speed things up, e.g. by avoiding
# the need to download the entire source repository again every time!). However, whenever the following ARG is changed
# (i.e. we are building a new version of the engine), a cache miss occurs (because the build context changed) and all
# steps from here on are rerun. That, however, means we might be operating on an old checkout of the source code from
# the cache, and so we update it again before checking out the requested revision.
RUN git pull && git checkout $rev

# Update system packages first
RUN apt-get -y update && apt-get -y upgrade

# Assume that the current master branch maintains duk-fuzzilli
# No need to patch, as the fuzz target is maintained in the duktape repo
# Start building!
RUN make duk-fuzzilli