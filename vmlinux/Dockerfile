FROM debian:bullseye-slim AS build-base

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
    vim-tiny \
    && rm -rf /var/lib/apt/lists/*

ARG KERNEL_BRANCH=v5.10
ARG KERNEL_CONFIG=microvm-kernel-arm64-5.10.config

RUN git clone -c advice.detachedHead=false --depth 1 --branch "${KERNEL_BRANCH}" https://github.com/torvalds/linux.git /src

COPY ${KERNEL_CONFIG} /src/.config

###############################################

FROM build-base AS arm64-build

RUN ARCH=arm64 make Image -j"$(nproc)"

###############################################

FROM build-base AS x86_64-build

RUN ARCH=x86_64 make vmlinux -j"$(nproc)"

###############################################

FROM scratch AS arm64-vmlinux

COPY --from=arm64-build /src/arch/arm64/boot/Image /vmlinux.bin

###############################################

FROM scratch AS x86_64-vmlinux

COPY --from=x86_64-build /src/vmlinux /vmlinux.bin
