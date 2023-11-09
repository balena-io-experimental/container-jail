# ARG TEST_IMAGE=debian:bullseye-slim
# ARG TEST_IMAGE=alpine:3.18
ARG TEST_IMAGE=ubuntu:jammy

FROM debian:bullseye-slim AS linux.git

WORKDIR /src

ARG DEBIAN_FRONTEND=noninteractive

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    bc \
    binutils \
    bison \
    build-essential \
    ca-certificates \
    cpio \
    flex \
    git \
    libelf-dev \
    libncurses-dev \
    libssl-dev \
    lz4 \
    vim-tiny \
    && rm -rf /var/lib/apt/lists/*

ARG KERNEL_BRANCH=5.10

RUN git clone --depth 1 -c advice.detachedHead=false \
    --branch "v${KERNEL_BRANCH}" https://github.com/torvalds/linux.git .

###############################################

FROM linux.git AS vmlinux

COPY vmlinux/*.config ./

RUN if [ "$(uname -m)" = "aarch64" ] ; \
    then ln -sf "microvm-kernel-arm64-5.10.config" .config && make Image && \
    lz4 -9 ./arch/arm64/boot/Image ./vmlinux.bin.lz4 ; \
    else ln -sf "microvm-kernel-x86_64-5.10.config" .config && make vmlinux &&\
    lz4 -9 ./vmlinux ./vmlinux.bin.lz4 ; \
    fi

###############################################

FROM debian:bullseye-slim AS firecracker

WORKDIR /src

ARG DEBIAN_FRONTEND=noninteractive

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# renovate: datasource=github-releases depName=firecracker-microvm/firecracker
ARG FIRECRACKER_VERSION=v1.4.1
ARG FIRECRACKER_URL=https://github.com/firecracker-microvm/firecracker/releases/download/${FIRECRACKER_VERSION}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN curl -fsSL -O "${FIRECRACKER_URL}/firecracker-${FIRECRACKER_VERSION}-$(uname -m).tgz" \
    && curl -fsSL "${FIRECRACKER_URL}/firecracker-${FIRECRACKER_VERSION}-$(uname -m).tgz.sha256.txt" | sha256sum -c - \
    && tar -xzf "firecracker-${FIRECRACKER_VERSION}-$(uname -m).tgz" --strip-components=1 \
    && for bin in *-"$(uname -m)" ; do install -v "${bin}" "/usr/local/bin/$(echo "${bin}" | sed -rn 's/(.+)-.+-.+/\1/p')" ; done \
    && rm "firecracker-${FIRECRACKER_VERSION}-$(uname -m).tgz"

###############################################

FROM debian:bullseye-slim AS jailer

WORKDIR /usr/src/app

ARG DEBIAN_FRONTEND=noninteractive

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    bridge-utils \
    ca-certificates \
    curl \
    e2fsprogs \
    file \
    gettext \
    ipcalc \
    iproute2 \
    iptables \
    jq \
    lz4 \
    procps \
    rsync \
    tcpdump \
    uuid-runtime \
    && rm -rf /var/lib/apt/lists/*

COPY --from=firecracker /usr/local/bin/* /usr/local/bin/
COPY --from=vmlinux /src/vmlinux.bin.lz4 /jail/boot/vmlinux.bin.lz4

RUN addgroup --system firecracker \
    && adduser --system firecracker --ingroup firecracker \
    && chown -R firecracker:firecracker ./

RUN firecracker --version \
    && jailer --version

COPY overlay ./overlay
COPY start.sh config.json ./

RUN chmod +x start.sh overlay/sbin/*

ENTRYPOINT [ "/usr/src/app/start.sh" ]

###############################################

# hadolint ignore=DL3006
FROM ${TEST_IMAGE} AS sut-rootfs

COPY test/ /test/

RUN mv /test/"$(awk -F'=' '/^ID=/ {print $2}' /etc/os-release)"/* /test/ \
    && chmod +x /test/*.sh \
    && /test/install.sh

FROM jailer AS sut

COPY --from=sut-rootfs / /usr/src/app/rootfs/

CMD [ "/test/healthcheck.sh" ]

#dev-cmd-live="/test/healthcheck.sh ; sleep infinity"
