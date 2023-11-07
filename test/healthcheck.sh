#!/bin/sh

set -ex

id

date

uname -a

df -h

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

if command -v npm >/dev/null 2>&1; then
    npm ping
fi

if command -v ping >/dev/null 2>&1; then
    ping -c 1 "localhost"
    ping -c 1 "$(ip route | awk '/default/ {print $3}')"
    ping -c 1 "$(head -1 /etc/resolv.conf | awk '{print $2}')"
    ping -c 1 -M "do" -s 1472 "$(head -1 /etc/resolv.conf | awk '{print $2}')"
fi

if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://raw.githubusercontent.com/dylanaraps/neofetch/7.1.0/neofetch | bash
fi

if command -v dockerd >/dev/null 2>&1; then
    case $(id -u) in
    0)
        # start the daemon in the background when running as root
        dockerd &
        ;;
    *)
        # run the client tests when running as nonroot
        docker info
        docker build /test --progress=plain --pull
        docker run hello-world

        case $(uname -m) in
        aarch64)
            # try running arm32 docker images on arm64
            docker build /test --progress=plain --pull --platform=linux/arm/v7
            ;;
        *)
            uname -m
            ;;
        esac
        ;;
    esac
fi

case $(id -u) in
"0")
    # re-run healthchecks as nonroot user
    exec su - nonroot -c /test/healthcheck.sh
    ;;
*)
    # print the nonroot user id and continue to finish the healthchecks
    id
    ;;
esac

set +x

echo "Hello, World!" >/dev/stdout
echo "Hello, World!" >/dev/stderr
