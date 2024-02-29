#!/usr/bin/env bash

# This script is run as the healthcheck command for the VM image and
# the logs are grepped for the exit status message to determine success/fail.

set -ex

cleanup() {
    status=$?
    echo "$0 exited with status $status"
    exit ${status}
}

trap cleanup EXIT

id

date

userspace_arch="$(dpkg --print-architecture 2>/dev/null || apk --print-arch)"
case ${userspace_arch} in
x86_64 | amd64)
    uname -a | grep x86_64
    ;;
aarch64 | arm64)
    uname -a | grep aarch64
    setarch linux32 uname -m | tee /dev/stderr | grep armv7l
    setarch linux32 --uname-2.6 uname -m | tee /dev/stderr | grep armv6l
    ;;
*)
    echo "Unsupported architecture: ${userspace_arch}"
    exit 1
    ;;
esac

df -h

ls -al /dev/

echo "Testing stdout" >&1
echo "Testing stderr" >&2
echo "Testing stdout" >/dev/stdout
echo "Testing stderr" >/dev/stderr

echo "Testing stdout" 1> >(tee "$HOME"/stdout)
echo "Testing stderr" 2> >(tee "$HOME"/stderr)

script -q -e -c "echo 'Testing pseudo-terminal'"

if [ -n "${HOSTNAME}" ]; then
    test "${HOSTNAME}" = "$(hostname)"
fi

if command -v lsblk >/dev/null 2>&1; then
    lsblk
fi

if command -v printenv >/dev/null 2>&1; then
    printenv
fi

if command -v ip >/dev/null 2>&1; then
    ip addr
    ip link list
    ip route
fi

case $(id -u) in
0)
    if command -v iptables >/dev/null 2>&1; then
        iptables -V
        iptables -L
    fi

    if command -v iptables-legacy >/dev/null 2>&1; then
        iptables-legacy -V
        iptables-legacy -L
    fi

    if command -v iptables-nft >/dev/null 2>&1; then
        iptables-nft -V
        iptables-nft -L
        iptables-nft -N DOCKER-ISOLATION-STAGE-1
        iptables-nft -L
        iptables-nft -I DOCKER-ISOLATION-STAGE-1 -j RETURN
    fi
    ;;
*) ;;
esac

case $(uname -m) in
x86_64)
    ls -l /dev/kvm
    test -w /dev/kvm || test "$(id -u)" != 0
    if which kvm-ok >/dev/null; then
        kvm-ok
    fi
    ;;
*)
    # https://github.com/balena-io-experimental/container-jail/issues/44
    # https://github.com/firecracker-microvm/firecracker/issues/1721
    echo "Nested KVM unavailable on this architecture!"
    ;;
esac

if command -v npm >/dev/null 2>&1; then
    npm ping
fi

if command -v ping >/dev/null 2>&1; then
    ping -c 1 "localhost"
    ping -c 1 "$(ip route | awk '/default/ {print $3}')"
    ping -c 1 "$(head -1 /etc/resolv.conf | awk '{print $2}')"
    ping -c 1 -M "do" -s 1472 "$(head -1 /etc/resolv.conf | awk '{print $2}')"
fi

# test mounting nfs shares
# if this share goes away, just delete this test, no one will miss it
case $(id -u) in
0)
    # (modprobe cachefiles && /sbin/cachefilesd -s) || true
    mkdir -p /var/lib/yocto
    mount -v -t nfs nfs.product-os.io:/ /var/lib/yocto -o fsc
    ls -al /var/lib/yocto/
    ;;
*) ;;
esac

if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://raw.githubusercontent.com/dylanaraps/neofetch/7.1.0/neofetch | bash
fi

if command -v dockerd >/dev/null 2>&1; then
    case $(id -u) in
    0)
        # start the daemon in the background when running as root
        dockerd -D &
        sleep 5
        ;;
    *)
        # run the client tests when running as nonroot
        docker version
        docker info

        if [ -n "${DOCKERHUB_USERNAME}" ] && [ -n "${DOCKERHUB_PASSWORD}" ]; then
            echo "${DOCKERHUB_PASSWORD}" | docker login --username "${DOCKERHUB_USERNAME}" --password-stdin
        fi

        docker run --rm hello-world
        docker pull --platform linux/arm/v7 arm32v7/hello-world

        case $(uname -m) in
        aarch64)
            # try running arm32 docker images on arm64
            docker run --rm arm32v7/hello-world
            ;;
        *)
            # try running arm32 docker images on x86_64 with QEMU emulation
            docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
            docker run --rm arm32v7/hello-world
            ;;
        esac

        # build test image that includes systemd
        docker build /test/systemd --progress=plain --pull -t systemd:sut

        # test running a systemd in a container
        docker run --rm -it --cap-add SYS_ADMIN -v /sys/fs/cgroup:/sys/fs/cgroup:ro systemd:sut |
            tee -a /dev/stderr | grep -q "Powering off."
        ;;
    esac
fi

case $(id -u) in
"0")
    # re-run healthchecks as nonroot user
    exec su - nonroot -c "DOCKERHUB_USERNAME=${DOCKERHUB_USERNAME} DOCKERHUB_PASSWORD=${DOCKERHUB_PASSWORD} /test/healthcheck.sh"
    ;;
*)
    # print the nonroot user id and continue to finish the healthchecks
    id
    ;;
esac
