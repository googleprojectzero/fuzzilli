FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV SWIFT_VERSION=5.9

# Install system dependencies including V8 build requirements
RUN apt-get update && apt-get install -y \
    git \
    wget \
    curl \
    build-essential \
    cmake \
    ninja-build \
    clang \
    llvm \
    python3 \
    python3-pip \
    python3-venv \
    redis-server \
    pkg-config \
    libnss3-dev \
    libatk-bridge2.0-dev \
    libdrm2 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    libgbm1 \
    libxss1 \
    libasound2 \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q https://download.swift.org/swift-${SWIFT_VERSION}-release/ubuntu2204/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-ubuntu22.04.tar.gz \
    && tar xzf swift-${SWIFT_VERSION}-RELEASE-ubuntu22.04.tar.gz \
    && mv swift-${SWIFT_VERSION}-RELEASE-ubuntu22.04 /opt/swift \
    && rm swift-${SWIFT_VERSION}-RELEASE-ubuntu22.04.tar.gz

ENV PATH="/opt/swift/usr/bin:${PATH}"

WORKDIR /app

RUN git clone https://github.com/VRIG-Ritsec/fuzzillai.git .

# Download and build V8
RUN cd /tmp && \
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git && \
    export PATH="/tmp/depot_tools:$PATH" && \
    fetch v8 && \
    cd v8 && \
    git checkout 11.8.172.18 && \
    gclient sync && \
    tools/dev/v8gen.py fuzzbuild --args='is_debug=false dcheck_always_on=true v8_static_library=true v8_enable_verify_heap=true v8_fuzzilli=true sanitizer_coverage_flags="trace-pc-guard" target_cpu="x64"' && \
    ninja -C out/fuzzbuild d8

# Copy V8 binary to our app directory
RUN cp /tmp/v8/out/fuzzbuild/d8 /app/d8

RUN swift build -c release

RUN mkdir -p ./Corpus

EXPOSE 6379

CMD ["sh", "-c", "redis-server --daemonize yes && swift run -c release FuzzilliCli --profile=v8 --engine=multi --resume --corpus=basic --storagePath=./Corpus ./d8"]
