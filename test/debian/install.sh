#!/bin/sh

set -ex

export DEBIAN_FRONTEND=noninteractive

# install packages required by healthchecks
apt-get update
apt-get install -y ca-certificates curl gnupg iproute2 iptables iputils-ping util-linux
rm -rf /var/lib/apt/lists/*

# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/ubuntu/gpg" | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add the repository to Apt sources
# shellcheck disable=SC1091
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/$(. /etc/os-release && echo "$ID" | tr '[:upper:]' '[:lower:]') \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" >/etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io
rm -rf /var/lib/apt/lists/*

# create nonroot user for healthchecks
adduser --disabled-password --gecos "" nonroot

# add user to docker group
adduser nonroot docker

# set iptables to legacy mode
update-alternatives --set iptables /usr/sbin/iptables-legacy

# allow nonroot to use ping
chmod u+s /bin/ping
