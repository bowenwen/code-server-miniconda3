# use cuda devel base image to enable nvidia gpu compute
FROM nvidia/cuda:11.7.1-devel-ubuntu22.04

# # use ubuntu base image for cpu compute only
# FROM ubuntu:jammy-20230301

LABEL authors="Bo Wen"

# credits:
# - miniconda: https://github.com/ContinuumIO/docker-images/blob/master/miniconda3/debian/Dockerfile
# - code server: https://github.com/coder/code-server/blob/main/ci/release-image/Dockerfile
# - nvidia: https://hub.docker.com/r/nvidia/cuda/tags?page=1&name=22.04

USER root
WORKDIR /tmp

# set language and locale
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

# packages required by code server
RUN apt-get update \
    && apt-get install -y \
    curl \
    dumb-init \
    zsh \
    htop \
    locales \
    man \
    nano \
    git \
    git-lfs \
    procps \
    openssh-client \
    sudo \
    vim.tiny \
    lsb-release \
    && git lfs install \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# packages required by miniconda
# hadolint ignore=DL3008
RUN apt-get update -q && \
    apt-get install -q -y --no-install-recommends \
    bzip2 \
    ca-certificates \
    git \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    mercurial \
    openssh-client \
    procps \
    subversion \
    wget \
    rsync \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# install kubectl v1.23.5
RUN curl -LO "https://dl.k8s.io/release/v1.23.5/bin/linux/amd64/kubectl" && \
    curl -LO "https://dl.k8s.io/v1.23.5/bin/linux/amd64/kubectl.sha256" && \
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
    rm kubectl && \
    rm kubectl.sha256

# set up user for code server
RUN adduser --gecos '' --disabled-password coder \
    && echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/nopasswd

RUN ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL "https://github.com/boxboat/fixuid/releases/download/v0.5/fixuid-0.5-linux-${ARCH}.tar.gz" | tar -C /usr/local/bin -xzf - \
    && chown root:root /usr/local/bin/fixuid \
    && chmod 4755 /usr/local/bin/fixuid \
    && mkdir -p /etc/fixuid \
    && printf "user: coder\ngroup: coder\n" > /etc/fixuid/config.yml

# download and install code server
ARG CODE_SERVER_VERSION=4.11.0
RUN ARCH="$(dpkg --print-architecture)" \ 
    && curl -LO "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server_${CODE_SERVER_VERSION}_${ARCH}.deb" \
    && curl -LO "https://raw.githubusercontent.com/coder/code-server/v${CODE_SERVER_VERSION}/ci/release-image/entrypoint.sh" \
    && mv /tmp/entrypoint.sh /usr/bin/entrypoint.sh \
    && chmod +x /usr/bin/entrypoint.sh \
    && dpkg -i /tmp/code-server_${CODE_SERVER_VERSION}_${ARCH}.deb \
    && rm /tmp/code-server_${CODE_SERVER_VERSION}_${ARCH}.deb

# Allow users to have scripts run on container startup to prepare workspace.
# https://github.com/coder/code-server/issues/5177
ENV ENTRYPOINTD=${HOME}/entrypoint.d

EXPOSE 8080
# This way, if someone sets $DOCKER_USER, docker-exec will still work as
# the uid will remain the same. note: only relevant if -u isn't passed to
# docker-run.
USER 1000
ENV USER=coder
WORKDIR /home/coder

# install conda as regular user
ENV PATH /home/coder/conda/bin:$PATH
ARG CONDA_VERSION=py310_23.1.0-1
RUN set -x && \
    UNAME_M="$(uname -m)" && \
    if [ "${UNAME_M}" = "x86_64" ]; then \
    MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-${CONDA_VERSION}-Linux-x86_64.sh"; \
    SHA256SUM="32d73e1bc33fda089d7cd9ef4c1be542616bd8e437d1f77afeeaf7afdb019787"; \
    elif [ "${UNAME_M}" = "s390x" ]; then \
    MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-${CONDA_VERSION}-Linux-s390x.sh"; \
    SHA256SUM="0d00a9d34c5fd17d116bf4e7c893b7441a67c7a25416ede90289d87216104a97"; \
    elif [ "${UNAME_M}" = "ppc64le" ]; then \
    MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-${CONDA_VERSION}-Linux-ppc64le.sh"; \
    SHA256SUM="9ca8077a0af8845fc574a120ef8d68690d7a9862d354a2a4468de5d2196f406c"; \
    elif [ "${UNAME_M}" = "aarch64" ]; then \
    MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-${CONDA_VERSION}-Linux-aarch64.sh"; \
    SHA256SUM="80d6c306b015e1e3b01ea59dc66c676a81fa30279bc2da1f180a7ef7b2191d6e"; \
    fi && \
    wget "${MINICONDA_URL}" -O miniconda.sh -q && \
    echo "${SHA256SUM} miniconda.sh" > shasum && \
    if [ "${CONDA_VERSION}" != "latest" ]; then sha256sum --check --status shasum; fi && \
    mkdir -p /home/coder && \
    sh miniconda.sh -b -p /home/coder/conda && \
    rm miniconda.sh shasum && \
    echo ". /home/coder/conda/etc/profile.d/conda.sh" >> ~/.bashrc && \
    echo "conda activate base" >> ~/.bashrc && \
    find /home/coder/conda/ -follow -type f -name '*.a' -delete && \
    find /home/coder/conda/ -follow -type f -name '*.js.map' -delete && \
    /home/coder/conda/bin/conda clean -afy

USER root

RUN ln -s /home/coder/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh

# set up two factor auth
# guide: https://github.com/Ikysu/guide-code-server-2fa
RUN apt-get update -q && apt-get install -y npm nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
RUN npm install --prefix /usr/lib/code-server node-2fa \
    && npm install --prefix /usr/lib/code-server qrcode
# RUN node gen.js
RUN echo 'make sure ~/.config/code-server/config.yaml contains password and tfa key'
RUN cp /usr/lib/code-server/out/node/cli.js /usr/lib/code-server/out/node/cli.js_bk \
    && cp /usr/lib/code-server/out/node/routes/login.js /usr/lib/code-server/out/node/routes/login.js_bk \
    && cp /usr/lib/code-server/src/browser/pages/login.html /usr/lib/code-server/src/browser/pages/login.html_bk
COPY /rootfs/node/cli.js /usr/lib/code-server/out/node/cli.js
COPY /rootfs/node/routes/login.js /usr/lib/code-server/out/node/routes/login.js
COPY /rootfs/login.html /usr/lib/code-server/src/browser/pages/login.html

# NOTE: when bumping version, comment out previous block for two factor auth,
# and build a basic version of the image (name it with dev tag),
# docker build -t code-server-miniconda3:temp .
# then copy the relevant files out of the image and then resolve conflict.
# uncomment previous block after conflicts are all resolved.
# id=$(docker create code-server-miniconda3:temp)
# [docker cp $id:path - > local-tar-file]
# docker cp $id:/usr/lib/code-server/out/node/cli.js -> rootfs/node/cli.js
# docker cp $id:/usr/lib/code-server/out/node/routes/login.js -> rootfs/node/routes/login.js
# docker cp $id:/usr/lib/code-server/src/browser/pages/login.html -> rootfs/login.html
# mkdir -p tmp
# docker cp $id:/home/coder/. ./tmp/coder
# docker rm -v $id

USER 1000
ENV USER=coder
WORKDIR /home/coder

ENTRYPOINT ["/usr/bin/entrypoint.sh", "--bind-addr", "0.0.0.0:8443", "."]
