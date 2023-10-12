# Container Jailer

Append a build stage to your containers and run them as microVMs with Firecracker!

## What is Firecracker?

[Firecracker](https://firecracker-microvm.github.io/) is an open source virtualization technology that is purpose-built for creating and managing secure, multi-tenant container and function-based services that provide serverless operational models. Firecracker runs workloads in lightweight virtual machines, called microVMs, which combine the security and isolation properties provided by hardware virtualization technology with the speed and flexibility of containers.

## Benefits

- Privileged containers can be run in an isolated virtual environment
- Container root filesystem is truly ephemeral and [recreated on each restart](#filesystem)
- Container networks are segmented with one TAP/TUN interface per VM
- Allows for runtime secrets by deleting environment files after use
- Ideal for services exposed to the public, without risking the host OS

## Caveats

- The guest container OS must follow [some guidelines](#guest-container)
- Environment variables need to be read from a file, and [are not exported by default](#environment-variables)
- Only one persistent volume is supported right now, and [it needs to be mounted](filesystem)
- Ports can not be exposed without custom iptables rules (TBD)

## Requirements

### Kernel Modules

Firecracker supports x86_64 and AARCH64 Linux, see [specific supported kernels](https://github.com/firecracker-microvm/firecracker/blob/main/docs/kernel-policy.md).

Firecracker also requires [the KVM Linux kernel module](https://www.linux-kvm.org/).

The presence of the KVM module can be checked with:

```bash
lsmod | grep kvm
```

### balenaOS

balenaOS is not a requirement of this project, but it is well suited to container-based operating systems.

The following device types have been tested with balenaOS as they have the required kernel modules.

- Generic x86_64 (GPT)
- Generic AARCH64

### Guest Container

Guest containers based on Alpine, Debian, and Ubuntu have been tested and must have the following binaries
available from a shell.

- `sh`
- `mount`

Distroless containers are not expected to work as the kernel init binary is a shell script.

## Getting Started

Add the following lines to the end of your existing Dockerfile for publishing.

```Dockerfile
# The rest of your docker instructions up here AS my-rootfs

# Include firecracker wrapper and scripts
FROM ghcr.io/balena-io-experimental/ctr-jailer

# Copy the root file system from your existing final stage
COPY --from=my-rootfs / /usr/src/app/rootfs

# Provide your desired command to exec after init.
# Setting your own ENTRYPOINT is unsupported, use the CMD field only.
CMD /start.sh
```

Then you can publish your container image as you normally would via container registries
or deploy it directly via Docker Compose.

```yml
version: "2"

services:
  my-app:
    build: .
    # Privileged is required to setup the rootfs and jailer
    # but permissions are dropped to non-root when starting Firecracker
    privileged: true
    # Host networking is required to create a TAP device and update iptables
    network_mode: host
    # Optionally run the VM rootfs and kernel in-memory
    tmpfs:
      - /tmp
      - /run
      - /srv
    # Optionally persist the data volume which is available as /dev/vdb in the VM
    volumes:
      - data:/jail/data

volumes:
  data: {}
```

That's it! The firecracker runtime image will execute your container as a MicroVM.

Reference: <https://github.com/firecracker-microvm/firecracker/blob/main/docs/getting-started.md>

## Usage

### Environment Variables

Environment variables made available to the jailer runtime will be written to `/var/environment` in
the VM for optional use.

For use with secrets, it is recommended to source the values as needed, and delete the file.

### Networking

A TAP/TUN device will be automatically created for the guest to have network access.

The IP address/netmask can be configured via `TAP_IP`, otherwise a random address in the 10.x.x.1/30 range will be assigned.

The host interface for routing can be configured via `HOST_IFACE` otherwise the default route interface will be used.

In order to create the TAP device, and update iptables rules, the container jailer must be run in host networking mode.

Reference: <https://github.com/firecracker-microvm/firecracker/blob/main/docs/network-setup.md>

Exposing ports is TBD.

### Resources

Resources like virtual CPUs and Memory can be overprovisioned and adjusted via the env vars `VCPU_COUNT` and `MEM_SIZE_MIB`.

The default is the maximum available on the host.

The [jailer](https://github.com/firecracker-microvm/firecracker/blob/main/docs/jailer.md) also allows for resource slicing, but that implementation is TBD.

### Filesystem

The root filesystem is recreated on every run, so anything written to the root partition will not persist restarts and
is considered ephemeral similar to container layers.

However an optional data drive `/dev/vdb` will be created and can be made persistent by mounting a volume
or host path to `/jail/data`.

## Contributing

Please open an issue or submit a pull request with any features, fixes, or changes.
