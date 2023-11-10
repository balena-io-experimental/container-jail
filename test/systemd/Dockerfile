FROM ubuntu:jammy

# Set a working directory
WORKDIR /app

# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends npm \
    && rm -rf /var/lib/apt/lists/*

# hadolint ignore=DL3016
RUN npm ping && npm install express lodash moment

RUN dpkg --print-architecture

ENV container docker

# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends systemd systemd-sysv \
    && rm -rf /var/lib/apt/lists/*

# Remove unnecessary systemd services.
RUN find /etc/systemd/system \
    /lib/systemd/system \
    \( -path '*.wants/*' \
    -name '*swapon*' \
    -or -name '*ntpd*' \
    -or -name '*resolved*' \
    -or -name '*udev*' \
    -or -name '*e2scrub_all*' \
    -or -name '*e2scrub_reap*' \
    -or -name '*lvm2*' \
    -or -name '*mdadm*' \
    -or -name '*quotacheck*' \
    -or -name '*hwclock*' \
    -or -name '*sys-fs-fuse-connections.mount*' \
    -or -name '*sys-kernel-config.mount*' \
    -or -name '*sys-kernel-debug.mount*' \
    -or -name '*sys-kernel-tracing.mount*' \
    -or -name '*udev*' \
    -or -name '*getty*' \
    -or -name '*console-getty*' \) -exec rm {} \;

# hadolint ignore=DL3059
RUN printf '[Unit]\n\
Description=Shutdown service to terminate the container\n\
Requires=multi-user.target\n\
After=multi-user.target\n\
\n\
[Service]\n\
Type=oneshot\n\
ExecStart=/bin/systemctl poweroff\n\
RemainAfterExit=yes\n\
\n\
[Install]\n\
WantedBy=multi-user.target' > /etc/systemd/system/shutdown-container.service

# hadolint ignore=DL3059
RUN systemctl enable shutdown-container.service

VOLUME [ "/sys/fs/cgroup" ]

CMD ["/lib/systemd/systemd"]
