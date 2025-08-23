# use cuda devel base image to enable nvidia gpu compute
FROM nvidia/cuda:13.0.0-devel-ubuntu24.04

# # use ubuntu base image for cpu compute only
# FROM ubuntu:jammy-20230301

LABEL authors="Bo Wen"

# credits:
# - miniconda: https://github.com/ContinuumIO/docker-images/blob/master/miniconda3/debian/Dockerfile  # removed from image as of 2025-02
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

# packages for development with postgres
RUN apt-get update -q && \
    apt-get install -q -y --no-install-recommends \
    libpq-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# download and install code server
ARG CODE_SERVER_VERSION=4.103.1
RUN ARCH="$(dpkg --print-architecture)" \ 
    && curl -LO "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server_${CODE_SERVER_VERSION}_${ARCH}.deb" \
    && curl -LO "https://raw.githubusercontent.com/coder/code-server/v${CODE_SERVER_VERSION}/ci/release-image/entrypoint.sh" \
    && mv /tmp/entrypoint.sh /usr/bin/entrypoint.sh \
    && chmod +x /usr/bin/entrypoint.sh \
    && dpkg -i /tmp/code-server_${CODE_SERVER_VERSION}_${ARCH}.deb \
    && rm /tmp/code-server_${CODE_SERVER_VERSION}_${ARCH}.deb

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
# docker cp $id:/usr/lib/code-server/out/node/cli.js rootfs/node/cli.js
# docker cp $id:/usr/lib/code-server/out/node/routes/login.js rootfs/node/routes/login.js
# docker cp $id:/usr/lib/code-server/src/browser/pages/login.html rootfs/login.html
# mkdir -p tmp
# docker cp $id:/home/coder/. ./tmp/coder
# docker rm -v $id

# install miniforge
# - from https://github.com/conda-forge/miniforge-images/blob/master/ubuntu/Dockerfile
ARG MINIFORGE_NAME=Miniforge3
ARG MINIFORGE_VERSION=25.3.1-0
ENV CONDA_DIR=/opt/conda
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
ENV PATH=${CONDA_DIR}/bin:${PATH}

# 1. Install just enough for conda to work
# 2. Keep $HOME clean (no .wget-hsts file), since HSTS isn't useful in this context
# 3. Install miniforge from GitHub releases
# 4. Apply some cleanup tips from https://jcrist.github.io/conda-docker-tips.html
#    Particularly, we remove pyc and a files. The default install has no js, we can skip that
# 5. Activate base by default when running as any *non-root* user as well
#    Good security practice requires running most workloads as non-root
#    This makes sure any non-root users created also have base activated
#    for their interactive shells.
# 6. Activate base by default when running as root as well
#    The root user is already created, so won't pick up changes to /etc/skel
RUN apt-get update > /dev/null && \
    apt-get install --no-install-recommends --yes \
        wget bzip2 ca-certificates \
        git \
        tini \
        > /dev/null && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    wget --no-hsts --quiet https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/${MINIFORGE_NAME}-${MINIFORGE_VERSION}-Linux-$(uname -m).sh -O /tmp/miniforge.sh && \
    /bin/bash /tmp/miniforge.sh -b -p ${CONDA_DIR} && \
    rm /tmp/miniforge.sh && \
    conda clean --tarballs --index-cache --packages --yes && \
    find ${CONDA_DIR} -follow -type f -name '*.a' -delete && \
    find ${CONDA_DIR} -follow -type f -name '*.pyc' -delete && \
    conda clean --force-pkgs-dirs --all --yes  && \
    echo ". ${CONDA_DIR}/etc/profile.d/conda.sh && conda activate base" >> /etc/skel/.bashrc && \
    echo ". ${CONDA_DIR}/etc/profile.d/conda.sh && conda activate base" >> ~/.bashrc

# install kubectl
ARG KUBECTL_VERSION=1.33.4
RUN curl -LO "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    curl -LO "https://dl.k8s.io/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" && \
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
    rm kubectl && \
    rm kubectl.sha256

# set up user for code server
RUN userdel -r ubuntu
# see - https://github.com/boxboat/fixuid?tab=readme-ov-file#install-fixuid-in-dockerfile
RUN addgroup --gid 1000 coder && \
    adduser --uid 1000 --ingroup coder --home /home/coder --shell /bin/sh --disabled-password --gecos "" coder
RUN USER=coder && \
    GROUP=coder && \
    curl -SsL https://github.com/boxboat/fixuid/releases/download/v0.6.0/fixuid-0.6.0-linux-amd64.tar.gz | tar -C /usr/local/bin -xzf - && \
    chown root:root /usr/local/bin/fixuid && \
    chmod 4755 /usr/local/bin/fixuid && \
    mkdir -p /etc/fixuid && \
    printf "user: $USER\ngroup: $GROUP\n" > /etc/fixuid/config.yml

# Allow users to have scripts run on container startup to prepare workspace.
# https://github.com/coder/code-server/issues/5177
ENV ENTRYPOINTD=/home/coder/entrypoint.d
EXPOSE 8443
# This way, if someone sets $DOCKER_USER, docker-exec will still work as
# the uid will remain the same. note: only relevant if -u isn't passed to
# docker-run.

USER 1000
ENV USER=coder
WORKDIR /home/coder

ENTRYPOINT ["/usr/bin/entrypoint.sh", "--bind-addr", "0.0.0.0:8443", "."]
