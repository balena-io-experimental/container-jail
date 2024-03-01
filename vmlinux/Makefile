ARCH ?= $(shell uname -m)
KERNEL_BRANCH ?= 5.10
MAKEFILE_DIR := $(realpath $(shell dirname $(firstword $(MAKEFILE_LIST))))

# normalize architecture to machine and platform
ifeq ($(ARCH),x86_64)
	MACHINE := x86_64
	PLATFORM := linux/amd64
else
	MACHINE := arm64
	PLATFORM := linux/arm64
endif

TAG ?= linux.git:$(MACHINE)-$(KERNEL_BRANCH)
CONFIG_FILE ?= $(KERNEL_BRANCH)/microvm-kernel-$(MACHINE)-$(KERNEL_BRANCH).config

build:
	docker build .. \
		--platform $(PLATFORM) \
		--target vmconfig \
		--build-arg KERNEL_BRANCH=$(KERNEL_BRANCH) \
		--build-arg ARCH=$(MACHINE) \
		--tag $(TAG)

run: build
	mkdir -p out
	docker run --rm -it \
		--platform $(PLATFORM) \
		--mount type=bind,src=$(MAKEFILE_DIR)/out,dst=/out \
		$(TAG) sh -c 'make $(TARGET) && cp .config /out/.config'
	cp out/.config $(CONFIG_FILE)

menuconfig:
	make run TARGET=$@

olddefconfig:
	make run TARGET=$@

clean:
	-rm -rf out
	-docker rm $(TAG)

.PHONY: build run menuconfig olddefconfig clean
