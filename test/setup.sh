#!/bin/sh

# This script is run as Dockerfile step to setup the dependencies required by
# healthchecks. It is not run when the container is started.

set -e

# shellcheck disable=SC1091
distro_id="$(. /etc/os-release && echo "$ID" | tr '[:upper:]' '[:lower:]')"
# shellcheck disable=SC1091,SC2153
version_codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"

cleanup() {
    status=$?
    echo "$0 exited with status $status"
    exit ${status}
}

trap cleanup EXIT

case ${distro_id} in
ubuntu | debian)
    export DEBIAN_FRONTEND=noninteractive

    # install packages required by healthchecks
    apt-get update
    apt-get install -y ca-certificates cpu-checker curl gnupg iproute2 iptables iputils-ping kmod util-linux

    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/ubuntu/gpg" | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Add the repository to Apt sources
    # shellcheck disable=SC1091
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/${distro_id} ${version_codename} stable" >/etc/apt/sources.list.d/docker.list

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io

    # create nonroot user for healthchecks
    adduser --disabled-password --gecos "" nonroot

    # add user to docker group
    adduser nonroot docker

    # set iptables to legacy mode
    update-alternatives --set iptables /usr/sbin/iptables-legacy

    # allow nonroot to use ping
    chmod u+s /bin/ping
    ;;
alpine)
    # install packages required by healthchecks
    apk add --no-cache bash ca-certificates curl docker iproute2 iputils-ping kmod lsblk util-linux

    # create nonroot user for healthchecks
    adduser --disabled-password --gecos "" nonroot

    # add user to docker group
    addgroup nonroot docker
    ;;
*)
    echo "Unsupported distribution: ${distro_id}" >/dev/stderr
    exit 1
    ;;
esac
