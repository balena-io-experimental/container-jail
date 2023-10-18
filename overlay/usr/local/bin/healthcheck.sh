#!/bin/sh

set -ex

date

uname -a

df -h
lsblk

ip link list
ip route

ping -c 4 "$(ip route | awk '/default/ {print $3}')"
ping -c 4 "$(head -1 /etc/resolv.conf | awk '{print $2}')"
ping -c 4 -M "do" -s 1472 "$(head -1 /etc/resolv.conf | awk '{print $2}')"

curl -fsSL https://raw.githubusercontent.com/dylanaraps/neofetch/7.1.0/neofetch | bash

mkdir -p /mnt/data
mount -v /dev/vdb /mnt/data
touch /mnt/data/healthy
