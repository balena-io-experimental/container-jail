#!/bin/sh

set -ex

id

date

uname -a

df -h
lsblk

printenv

if [ -n "${HOSTNAME}" ]; then
    test "${HOSTNAME}" = "$(hostname)"
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
    ping -c 1 "$(ip route | awk '/default/ {print $3}')"
    ping -c 1 "$(head -1 /etc/resolv.conf | awk '{print $2}')"
    ping -c 1 -M "do" -s 1472 "$(head -1 /etc/resolv.conf | awk '{print $2}')"
fi

if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://raw.githubusercontent.com/dylanaraps/neofetch/7.1.0/neofetch | bash
fi

set +x

echo "Hello, World!" >/dev/stdout
echo "Hello, World!" >/dev/stderr
