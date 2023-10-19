
ARCH ?= $(shell uname -m)
KERNEL_BRANCH ?= v5.10
OUTPUT_DIR ?= $(shell pwd)/out

ifeq ($(ARCH),x86_64)
	KERNEL_CONFIG := microvm-kernel-x86_64-5.10.config
	KERNEL_BIN := microvm-kernel-x86_64-5.10.bin
	TARGET := x86_64-vmlinux
	PLATFORM := linux/amd64
else
	KERNEL_CONFIG := microvm-kernel-arm64-5.10.config
	KERNEL_BIN := microvm-kernel-arm64-5.10.bin
	TARGET := arm64-vmlinux
	PLATFORM := linux/arm64
endif

build-base:
	DOCKER_BUILDKIT=1 docker build . \
		--target build-base \
		--tag build-base \
		--build-arg KERNEL_BRANCH="$(KERNEL_BRANCH)" \
		--build-arg KERNEL_CONFIG="$(KERNEL_CONFIG)"

vmlinux:
	DOCKER_BUILDKIT=1 docker build . \
		--target $(TARGET) \
		--output type=local,dest=$(OUTPUT_DIR) \
		--platform $(PLATFORM) \
		--build-arg KERNEL_BRANCH="$(KERNEL_BRANCH)" \
		--build-arg KERNEL_CONFIG="$(KERNEL_CONFIG)"
	mv $(OUTPUT_DIR)/vmlinux.bin $(KERNEL_BIN)

menuconfig: build-base
	mkdir -p $(OUTPUT_DIR)
	DOCKER_BUILDKIT=1 docker run --rm \
		--mount type=bind,src=$(OUTPUT_DIR)/,dst=/out/ \
		build-base sh -c 'make menuconfig && cp .config /out/'
	mv $(OUTPUT_DIR)/.config $(KERNEL_CONFIG)

clean:
	rm -rf $(OUTPUT_DIR)
	-docker rmi build-base

.PHONY: build-base menuconfig vmlinux clean
