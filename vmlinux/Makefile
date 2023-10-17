
ifeq ($(shell uname -m),x86_64)
	CONFIG_FILE := microvm-kernel-x86_64-5.10.config
else
	CONFIG_FILE := microvm-kernel-arm64-5.10.config
endif

linux.git:
	docker build --tag linux.git --target linux.git ../

menuconfig: linux.git
	docker run --rm --mount type=bind,src=$(shell pwd)/,dst=/config/ linux.git \
		sh -c 'cp -a /config/$(CONFIG_FILE) .config && make menuconfig && cp -a .config /config/$(CONFIG_FILE)'

clean:  
	docker rmi linux.git
	rm .config

.PHONY: clean menuconfig linux.git
