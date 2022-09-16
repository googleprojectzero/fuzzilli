FROM swift:latest

ENV DEBIAN_FRONTEND=noninteractive
ENV SHELL=bash

RUN apt-get -y update && apt-get -y upgrade
RUN apt-get install -y git python3 python3-pip python3-virtualenv

RUN useradd -m builder

# Fetch Firefox source code
RUN git clone https://github.com/mozilla/gecko-dev.git /home/builder/firefox
WORKDIR /home/builder/firefox

# Docker will attempt to cache the output of every step. That's fine (and useful to speed things up, e.g. by avoiding
# the need to download the entire source repository again every time!). However, whenever the following ARG is changed
# (i.e. we are building a new version of the engine), a cache miss occurs (because the build context changed) and all
# steps from here on are rerun. That, however, means we might be operating on an old checkout of the source code from
# the cache, and so we update it again before checking out the requested revision.
ARG rev=master

# Update system packages first
RUN apt-get -y update && apt-get -y upgrade

# Fetch latest source code and checkout requested source revision
RUN git pull
RUN git checkout $rev

# Prepare for building
RUN ./mach bootstrap --application-choice=js

# Upload and apply patches
ADD Patches Patches
RUN for i in `ls Patches`; do patch -p1 < Patches/$i; done

# Start building!
ADD fuzzbuild.sh fuzzbuild.sh
RUN ./fuzzbuild.sh
