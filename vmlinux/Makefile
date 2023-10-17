
ARCH ?= $(shell uname -m)
CONFIG_FILE ?= microvm-kernel-$(ARCH)-$(KERNEL_BRANCH).config

linux.git:
	docker build --tag linux.git --target linux.git ../

menuconfig: linux.git
	ln -sf $(CONFIG_FILE) .config
	docker run --rm -it --mount type=bind,src=$(shell pwd)/,dst=/config/ linux.git sh -c 'ln -sf /config/.config .config && make menuconfig'

clean:  
	docker rmi linux.git
	rm .config

.PHONY: clean menuconfig linux.git
