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

ip link list
ip route

ping -c 4 "$(ip route | awk '/default/ {print $3}')"
ping -c 4 "$(head -1 /etc/resolv.conf | awk '{print $2}')"
ping -c 4 -M "do" -s 1472 "$(head -1 /etc/resolv.conf | awk '{print $2}')"

curl -fsSL https://raw.githubusercontent.com/dylanaraps/neofetch/7.1.0/neofetch | bash

set +x

echo "Hello, World!" >/dev/stdout
echo "Hello, World!" >/dev/stderr
