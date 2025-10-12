FROM swift:latest

ENV DEBIAN_FRONTEND=noninteractive
ENV SHELL=bash

RUN apt-get -y update && apt-get -y upgrade

RUN useradd -m builder
WORKDIR /home/builder

ADD fuzzilli fuzzilli

RUN cd fuzzilli && swift test && swift build -c release
