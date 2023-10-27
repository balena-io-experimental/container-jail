#!/bin/sh

set -x

# install packages required by healthchecks
apk add --no-cache bash ca-certificates curl docker iproute2 iputils-ping lsblk

# create nonroot user for healthchecks
adduser --disabled-password --gecos "" nonroot

# add user to docker group
addgroup nonroot docker
