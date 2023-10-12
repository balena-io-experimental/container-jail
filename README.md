# Container Jailer

Append a build stage to your containers and run them as microVMs with Firecracker!

## What is Firecracker?

[Firecracker](https://firecracker-microvm.github.io/) is an open source virtualization technology that is purpose-built for creating and managing secure, multi-tenant container and function-based services that provide serverless operational models. Firecracker runs workloads in lightweight virtual machines, called microVMs, which combine the security and isolation properties provided by hardware virtualization technology with the speed and flexibility of containers.

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
- `ip` via `iproute2`
- `mount`
- `awk`

Distroless containers are not expected to work as the kernel init binary is a shell script.

## Getting Started

Add the following lines to the end of your existing Dockerfile for publishing.

```Dockerfile
# The rest of your docker instructions up here AS my-rootfs

# Include firecracker wrapper and scripts
FROM ghcr.io/balena-io/ctr-jailer AS runtime

# Copy the root file system from your container final stage
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
    # but permissions are dropped to a chroot in order to start your VM
    privileged: true
    network_mode: host
    # Optionally run the VM rootfs and kernel in-memory to save storage wear
    tmpfs:
      - /tmp
      - /run
      - /srv
    # Optionally mount a persistent data volume where a data drive will be created for the VM
    volumes:
      - persistent-data:/data

volumes:
  persistent-data: {}
```

That's it! The firecracker runtime image will execute your rootfs as a MicroVM.

Reference: <https://github.com/firecracker-microvm/firecracker/blob/main/docs/getting-started.md>

## Usage

### Environment Variables

Since traditional container environment variables are not available in the VM, this wrapper will
inject them into the VM rootfs and export them at runtime.

Provide environment variables or secrets with the `CTR_` prefix, like `CTR_SECRET_KEY=secretvalue`.

If the values have spaces, or special characters, it is recommended to encode your secret values
with `base64` and have your init service decode them.

After being exported to the running process, the files are removed so they can safely
be used for secrets as long as the init stage of your service calls `unset <SECRET_KEY>` after using them.

### Networking

A TAP/TUN device will be automatically created for the guest to have network access.

The IP address/netmask can be configured via `TAP_IP`, otherwise a random address in the 10.x.x.1/30 range will be assigned.

The host interface for routing can be configured via `INTERFACE` otherwise the default route interface will be used.

In order to create the TAP device, and update iptables rules, the container jailer must be run in host networking mode.

Reference: <https://github.com/firecracker-microvm/firecracker/blob/main/docs/network-setup.md>

Exposing ports is TBD.

### Resources

Resources like virtual CPUs and Memory can be overprovisioned and adjusted via the env vars `VCPU_COUNT` and `MEM_SIZE_MIB`.

The default is the maximum available on the host.

### Persistent Storage

The root filesystem is recreated on every run, so anything written to the root partition will not persist restarts and
is considered ephemeral similar to container layers.

However an optional data drive `/dev/vdb` will be created and can be made persistent by mounting a volume
or host path to `/jail/data`.

## Contributing

Please open an issue or submit a pull request with any features, fixes, or changes.
