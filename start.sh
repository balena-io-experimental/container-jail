#!/usr/bin/env bash

# https://actuated.dev/blog/kvm-in-github-actions
# https://github.com/firecracker-microvm/firecracker/blob/main/docs/getting-started.md
# https://github.com/firecracker-microvm/firecracker/blob/main/docs/rootfs-and-kernel-setup.md

set -eu

# Store the arguments in an array
args=("$@")

script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
overlay_src="${script_root}/overlay"
rootfs_src="${script_root}/rootfs"
config_src="${script_root}/config.json"

boot_jail="/jail/boot"
data_jail="/jail/data"

# The jailer will use this id to create a unique chroot directory for the MicroVM
# among other things.
id="$(uuidgen)"

# The jailer will create a chroot directory for the MicroVM under this base directory
# If this is detected as a tmpfs mount it will be remounted as rw,exec
chroot_base="/srv/jailer"
chroot_dir="${chroot_base}/firecracker/${id}/root"

# Write all environment variables to a file in the overlay
mkdir -p "${overlay_src}/var"
env >"${overlay_src}/var/environment"
# Remove environment variables that are not needed by the guest
for key in PWD TERM USER SHLVL PATH HOME _; do
    sed -e "/^${key}=/d" -i "${overlay_src}/var/environment"
done

is_tmpfs() {
    filesystem_type=$(stat -f -c '%T' "${1}")
    if [ "$filesystem_type" = "tmpfs" ]; then
        return 0
    else
        return 1
    fi
}

remount_tmpfs_exec() {
    mkdir -p "${1}"
    if is_tmpfs "${1}"; then
        echo "Remounting ${1} with the execute bit set..."
        mount -o remount,rw,exec tmpfs "${1}"
    fi
}

populate_rootfs() {
    echo "Populating rootfs..."

    local src_rootfs="${1}"
    local dst_rootfs="${2}"

    local rootfs_mnt="/tmp/rootfs"

    mkdir -p "$(dirname "${dst_rootfs}")"
    rm -f "${dst_rootfs}"

    truncate -s "${ROOTFS_SIZE}" "${dst_rootfs}"
    mkfs.ext4 -q "${dst_rootfs}"
    mkdir -p "${rootfs_mnt}"
    mount "${dst_rootfs}" "${rootfs_mnt}"

    rsync -a "${src_rootfs}"/ "${rootfs_mnt}"/
    for dir in dev proc run sys var; do mkdir -p "${rootfs_mnt}/${dir}"; done

    # alpine already has /sbin/init that we should replace, otherwise
    # we would probably use --ignore-existing as well
    rsync -a --keep-dirlinks "${overlay_src}"/ "${rootfs_mnt}"/

    # write the CMD to the end of the init script
    echo "Injecting CMD: ${args[*]}"
    echo "exec ${args[*]}" >>"${rootfs_mnt}/sbin/init"

    umount "${rootfs_mnt}"

    chown firecracker:firecracker "${dst_rootfs}"
}

populate_datafs() {

    local dst_datafs="${1}"

    mkdir -p "$(dirname "${dst_datafs}")"

    if [ ! -f "${dst_datafs}" ]; then
        echo "Populating datafs..."
        truncate -s "${DATAFS_SIZE}" "${dst_datafs}"
        mkfs.ext4 -q "${dst_datafs}"
        chown firecracker:firecracker "${dst_datafs}"
    fi
}

prepare_config() {
    echo "Preparing config..."

    local src_config="${1}"
    local dst_config="${2}"

    envsubst <"${src_config}" >"${dst_config}"

    jq ".\"boot-source\".boot_args = \"${KERNEL_BOOT_ARGS}\"" "${dst_config}" >"${dst_config}".tmp
    mv "${dst_config}".tmp "${dst_config}"

    jq ".\"machine-config\".vcpu_count = ${VCPU_COUNT}" "${dst_config}" >"${dst_config}".tmp
    mv "${dst_config}".tmp "${dst_config}"

    jq ".\"machine-config\".mem_size_mib = ${MEM_SIZE_MIB}" "${dst_config}" >"${dst_config}".tmp
    mv "${dst_config}".tmp "${dst_config}"

    jq ".\"network-interfaces\"[0].iface_id = \"eth0\"" "${dst_config}" >"${dst_config}".tmp
    mv "${dst_config}".tmp "${dst_config}"

    jq ".\"network-interfaces\"[0].guest_mac = \"${guest_mac}\"" "${dst_config}" >"${dst_config}".tmp
    mv "${dst_config}".tmp "${dst_config}"

    jq ".\"network-interfaces\"[0].host_dev_name = \"${tap_dev}\"" "${dst_config}" >"${dst_config}".tmp
    mv "${dst_config}".tmp "${dst_config}"

    # jq . "${dst_config}"
}

create_tap_device() {
    local _tap_dev="${1}"
    local _tap_ip_mask="${2}/${3}"

    echo "Creating ${_tap_dev} device..."

    # delete existing tap device
    ip link del "${_tap_dev}" 2>/dev/null || true

    # create tap device
    ip tuntap add dev "${tap_dev}" mode tap user firecracker
    # ip tuntap add dev "${_tap_dev}" mode tap
    ip addr add "${_tap_ip_mask}" dev "${_tap_dev}"
    ip link set dev "${_tap_dev}" up

    sysctl -w net.ipv4.ip_forward=1
    # sysctl -w net.ipv4.conf.${_tap_dev}.proxy_arp=1
    # sysctl -w net.ipv6.conf.${_tap_dev}.disable_ipv6=1
}

apply_routing() {
    local _tap_dev="${1}"
    local _iface_id="${2}"

    echo "Applying iptables rules..."

    # delete rules matching comment
    iptables-legacy-save | grep -v "comment ${_tap_dev}" | iptables-legacy-restore || true

    # create FORWARD and POSTROUTING rules
    iptables-legacy -t nat -A POSTROUTING -o "${_iface_id}" -j MASQUERADE -m comment --comment "${_tap_dev}"
    # iptables-legacy -I FORWARD 1 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT -m comment --comment "${_tap_dev}"
    # iptables-legacy -I FORWARD 1 -i "${_tap_dev}" -o "${_iface_id}" -j ACCEPT -m comment --comment "${_tap_dev}"
    iptables-legacy -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT -m comment --comment "${_tap_dev}"
    iptables-legacy -A FORWARD -i "${_tap_dev}" -o "${_iface_id}" -j ACCEPT -m comment --comment "${_tap_dev}"
}

ip_to_mac() {
    local ip="${1}"
    local mac
    # shellcheck disable=SC2183,SC2046
    mac="$(printf '52:54:%02X:%02X:%02X:%02X\n' $(echo "${ip}" | tr '.' ' '))"
    echo "${mac}"
}

create_logs_fifo() {
    local fifo="${1}"
    local out="${2}"

    mkdir -p "$(dirname "${fifo}")"
    rm -f "${fifo}"

    # Create a named pipe
    mkfifo "${fifo}"
    # Redirect the output of the named pipe to /dev/stdout
    cat "${fifo}" >"${out}" &
    # Take ownership of the named pipe
    chown firecracker:firecracker "${fifo}"
}

cleanup() {
    echo "Cleaning up..."
    # delete tap device
    ip link del "${tap_dev}" 2>/dev/null || true
    # delete rules matching comment
    iptables-legacy-save | grep -v "comment ${tap_dev}" | iptables-legacy-restore
}

# Check for root filesystem
if ! ls "${rootfs_src}" &>/dev/null; then
    echo "Root Filesystem not found in ${rootfs_src}. Did you forget to COPY it?"
    sleep infinity
fi

# Check for hardware acceleration
if ! ls /dev/kvm &>/dev/null; then
    echo "KVM hardware acceleration unavailable. Pass --device /dev/kvm in your Docker run command."
    sleep infinity
fi

# Set default cores to same as system if not specified
if [ -z "${VCPU_COUNT:-}" ]; then
    VCPU_COUNT=$(nproc --all)
fi

if [ "${VCPU_COUNT}" -gt 32 ]; then
    echo "Maximum VCPU count is 32."
    VCPU_COUNT=32
fi

# Set default memory to same as system if not specified
if [ -z "${MEM_SIZE_MIB:-}" ]; then
    MEM_SIZE_MIB=$(($(free -m | grep -oP '\d+' | head -6 | tail -1) - 50))
fi

# Set default space to same as available on system if not specified
if [ -z "${ROOTFS_SIZE:-}" ]; then
    ROOTFS_SIZE=$(df -Ph . | tail -1 | awk '{print $4}')
fi

# Set default space to same as available on system if not specified
if [ -z "${DATAFS_SIZE:-}" ]; then
    DATAFS_SIZE=$(df -Ph . | tail -1 | awk '{print $4}')
fi

if [ -z "${KERNEL_BOOT_ARGS:-}" ]; then
    KERNEL_BOOT_ARGS="console=ttyS0 reboot=k panic=1 pci=off random.trust_cpu=on"

    if [ "$(uname -m)" = "aarch64" ]; then
        KERNEL_BOOT_ARGS="keep_bootcon ${KERNEL_BOOT_ARGS}"
    fi
fi

# Network settings

if [ -z "${INTERFACE:-}" ]; then
    INTERFACE="$(ip route | awk '/default/ {print $5}')"
fi

if [ -z "${TAP_IP:-}" ]; then
    # generate random number between 1 and 254
    TAP_IP=10.$((1 + RANDOM % 254)).$((1 + RANDOM % 254)).1/30
fi

iface_id="${INTERFACE}"
tap_ip="$(ipcalc -nb "${TAP_IP}" | awk '/^Address:/ {print $2}')"
# long_netmask="$(ipcalc -nb "${TAP_IP}" | awk '/^Netmask:/ {print $2}')"
short_netmask="$(ipcalc -nb "${TAP_IP}" | awk '/^Netmask:/ {print $4}')"

# must be less than 16 characters
# https://git.kernel.org/pub/scm/network/iproute2/iproute2.git/tree/lib/utils.c?id=1f420318bda3cc62156e89e1b56d60cc744b48ad#n827
tap_dev="tap-${tap_ip//./-}"
tap_dev="${tap_dev%??}"
guest_mac="$(ip_to_mac "${tap_ip%?}2")"

echo "Host Interface: ${iface_id}"
echo "Guest Address: ${guest_mac}"
echo "TAP Device: ${tap_dev}"

echo "VCPUs: ${VCPU_COUNT}"
echo "Memory: ${MEM_SIZE_MIB}M"
echo "Root Drive (vda): ${ROOTFS_SIZE}"
echo "Data Drive (vdb): ${DATAFS_SIZE}"
echo "Kernel boot args: ${KERNEL_BOOT_ARGS}"

trap cleanup EXIT

remount_tmpfs_exec "/tmp"
remount_tmpfs_exec "/run"
remount_tmpfs_exec "/srv"

create_tap_device "${tap_dev}" "${tap_ip}" "${short_netmask}"
apply_routing "${tap_dev}" "${iface_id}"

echo "Creating jailer chroot..."
mkdir -p "${boot_jail}" "${chroot_dir}"/boot
mkdir -p "${data_jail}" "${chroot_dir}"/data

mount --bind "${boot_jail}" "${chroot_dir}"/boot
mount --bind "${data_jail}" "${chroot_dir}"/data

populate_rootfs "${rootfs_src}" "${chroot_dir}"/boot/rootfs.ext4
populate_datafs "${chroot_dir}"/data/datafs.ext4
prepare_config "${config_src}" "${chroot_dir}"/boot/config.json
create_logs_fifo "${chroot_dir}"/logs.fifo /dev/stdout

# /usr/local/bin/firecracker --help

echo "Starting firecracker via jailer..."
# https://github.com/firecracker-microvm/firecracker/blob/main/docs/jailer.md
/usr/local/bin/jailer --id "${id}" \
    --exec-file /usr/local/bin/firecracker \
    --chroot-base-dir "${chroot_base}" \
    --uid "$(id -u firecracker)" \
    --gid "$(id -g firecracker)" \
    -- \
    --no-api \
    --config-file /boot/config.json \
    --log-path logs.fifo
