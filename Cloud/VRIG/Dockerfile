# Stage 1: Build our v8 build
FROM docker.io/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV SHELL=bash

RUN apt-get -y update && apt-get -y upgrade
RUN apt-get install -y python3 git curl sudo lsb-release file

RUN useradd -m builder

# Fetch v8 source code
WORKDIR /home/builder
RUN git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
ENV PATH="${PATH}:/home/builder/depot_tools"

RUN mkdir v8 && cd v8 && fetch v8 && gclient sync
WORKDIR /home/builder/v8/v8

ARG rev=b0157a634e584163cbe6004db3161dc16dea20f9
run git pull origin $rev
RUN git checkout $rev

# Apply custom patches
ADD Targets/V8/Patches/ Patches
RUN for i in `ls Patches`; do patch -p1 < Patches/$i; done

# Build
RUN ./build/install-build-deps.sh

ADD Targets/V8/fuzzbuild.sh fuzzbuild.sh
RUN ./fuzzbuild.sh

########################
# Stage 2: Build Fuzzili
FROM docker.io/swift:latest

ENV DEBIAN_FRONTEND=noninteractive
ENV SHELL=bash

RUN apt-get -y update && apt-get -y upgrade
RUN apt-get -y install nodejs

RUN useradd -m builder
WORKDIR /home/builder

ADD .. fuzzillai

# build Fuzzilai
RUN cd fuzzillai && swift test && swift build -c release

#####################
# Stage 3: Run itself
FROM docker.io/swift:latest

ENV DEBIAN_FRONTEND=noninteractive
ENV SHELL=bash

RUN apt-get -y update && apt-get -y upgrade

RUN useradd -m app

WORKDIR /home/app

# Copy everything we've build
COPY --from=0 /home/builder/v8/v8/out/fuzzbuild fuzzbuild
COPY --from=1 /home/builder/fuzzillai/.build/release/ Fuzzilli

RUN mkdir -p ./Corpus


CMD ["./Fuzzilli/FuzzilliCli", "--profile=v8debug", "--engine=multi", "--resume", "--corpus=basic", "--storagePath=./Corpus", "./fuzzbuild/d8"]
