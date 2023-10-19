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
    ccache \
    cpio \
    flex \
    git \
    libelf-dev \
    libncurses-dev \
    libssl-dev \
    lz4 \
    vim-tiny \
    && rm -rf /var/lib/apt/lists/*

ARG KERNEL_BRANCH=v5.10
ARG KERNEL_CONFIG=microvm-kernel-arm64-5.10.config

RUN git clone -c advice.detachedHead=false --depth 1 --branch "${KERNEL_BRANCH}" https://github.com/torvalds/linux.git /src

COPY ${KERNEL_CONFIG} /src/.config

###############################################

FROM build-base AS arm64-build

RUN --mount=type=cache,target=/root/.ccache ccache -z \
    && KBUILD_BUILD_TIMESTAMP='' make CC="ccache gcc" -j"$(nproc)" Image \
    && ccache -s \
    && lz4 ./arch/arm64/boot/Image vmlinux.lz4

###############################################

FROM build-base AS x86_64-build

RUN --mount=type=cache,target=/root/.ccache ccache -z \
    && KBUILD_BUILD_TIMESTAMP='' make CC="ccache gcc" -j"$(nproc)" vmlinux \
    && ccache -s \
    && lz4 ./vmlinux vmlinux.lz4

###############################################

FROM scratch AS arm64-vmlinux

COPY --from=arm64-build /src/vmlinux.lz4 /vmlinux.lz4

###############################################

FROM scratch AS x86_64-vmlinux

COPY --from=x86_64-build /src/vmlinux.lz4 /vmlinux.lz4
