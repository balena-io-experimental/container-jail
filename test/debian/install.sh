#!/bin/sh

set -x

# install packages required by healthchecks
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl iproute2 iputils-ping util-linux
rm -rf /var/lib/apt/lists/*

# create nonroot user for healthchecks
adduser --disabled-password --gecos "" nonroot

# allow nonroot to use ping
chmod u+s /bin/ping
