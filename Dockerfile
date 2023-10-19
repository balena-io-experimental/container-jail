FROM debian:bullseye-slim AS vmlinux

WORKDIR /src

COPY vmlinux/*.lz4 ./

RUN if [ "$(uname -m)" = "x86_64" ] ; \
    then lz4 -d "microvm-kernel-x86_64-5.10.lz4" vmlinux.bin ; \
    else lz4 -d "microvm-kernel-arm64-5.10.lz4" vmlinux.bin ; \
    fi \
    && rm -f ./*.lz4

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
    procps \
    rsync \
    tcpdump \
    uuid-runtime \
    && rm -rf /var/lib/apt/lists/*

COPY --from=firecracker /usr/local/bin/* /usr/local/bin/
COPY --from=vmlinux /src/vmlinux.bin /jail/boot/vmlinux.bin

RUN addgroup --system firecracker \
    && adduser --system firecracker --ingroup firecracker \
    && chown -R firecracker:firecracker ./

RUN firecracker --version \
    && jailer --version

COPY overlay ./overlay
COPY start.sh config.json ./

RUN chmod +x start.sh overlay/sbin/* overlay/usr/local/bin/*

ENTRYPOINT [ "/usr/src/app/start.sh" ]

CMD [ "/usr/local/bin/usage.sh" ]

###############################################

# Example alpine rootfs for testing, with some debug utilities
FROM alpine:3.18 AS alpine-rootfs

# hadolint ignore=DL3018
RUN apk add --no-cache bash ca-certificates ca-certificates curl iproute2 iputils-ping lsblk

FROM jailer AS alpine-test

COPY --from=alpine-rootfs / /usr/src/app/rootfs/

# Use livepush directives to conditionally run this test stage
# for livepush, but not for default builds used in publishing.
#dev-cmd-live="/usr/local/bin/healthcheck.sh && sleep infinity"

###############################################

# Example debian rootfs for testing, with some debug utilities
FROM debian:bookworm AS debian-rootfs

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl iproute2 iputils-ping ca-certificates util-linux \
    && rm -rf /var/lib/apt/lists/*

FROM jailer AS debian-test

COPY --from=debian-rootfs / /usr/src/app/rootfs/

###############################################

# Example ubuntu rootfs for testing, with some debug utilities
FROM ubuntu:jammy AS ubuntu-rootfs

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl iproute2 iputils-ping util-linux \
    && rm -rf /var/lib/apt/lists/*

FROM jailer AS ubuntu-test

COPY --from=ubuntu-rootfs / /usr/src/app/rootfs/

###############################################

# Example ubuntu rootfs for testing, with some debug utilities
FROM docker:stable-dind AS dind-rootfs

FROM jailer AS dind-test

COPY --from=dind-rootfs / /usr/src/app/rootfs/

###############################################

# This is the stage we want to publish, but it has no rootfs
# so we can't use it for livepush testing.
FROM jailer AS default
