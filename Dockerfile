FROM codercom/code-server:4.8.3-bullseye
# base image credit: https://github.com/coder/code-server/blob/main/ci/release-image/Dockerfile

USER root

# use example from miniconda but install as user instead
# miniconda credit: https://github.com/ContinuumIO/docker-images/blob/master/miniconda3/debian/Dockerfile

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

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

USER 1000
ENV USER=coder
WORKDIR /home/coder

ENV PATH /home/coder/conda/bin:$PATH

# Leave these args here to better use the Docker build cache
ARG CONDA_VERSION=py39_4.12.0

RUN set -x && \
    UNAME_M="$(uname -m)" && \
    if [ "${UNAME_M}" = "x86_64" ]; then \
        MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-${CONDA_VERSION}-Linux-x86_64.sh"; \
        SHA256SUM="78f39f9bae971ec1ae7969f0516017f2413f17796670f7040725dd83fcff5689"; \
    elif [ "${UNAME_M}" = "s390x" ]; then \
        MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-${CONDA_VERSION}-Linux-s390x.sh"; \
        SHA256SUM="ff6fdad3068ab5b15939c6f422ac329fa005d56ee0876c985e22e622d930e424"; \
    elif [ "${UNAME_M}" = "aarch64" ]; then \
        MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-${CONDA_VERSION}-Linux-aarch64.sh"; \
        SHA256SUM="5f4f865812101fdc747cea5b820806f678bb50fe0a61f19dc8aa369c52c4e513"; \
    elif [ "${UNAME_M}" = "ppc64le" ]; then \
        MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-${CONDA_VERSION}-Linux-ppc64le.sh"; \
        SHA256SUM="1fe3305d0ccc9e55b336b051ae12d82f33af408af4b560625674fa7ad915102b"; \
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

USER 1000
ENV USER=coder
WORKDIR /home/coder

ENTRYPOINT ["/usr/bin/entrypoint.sh", "--bind-addr", "0.0.0.0:8080", "."]
