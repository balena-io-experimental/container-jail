#!/usr/bin/env bash

# https://actuated.dev/blog/kvm-in-github-actions
# https://github.com/firecracker-microvm/firecracker/blob/main/docs/getting-started.md
# https://github.com/firecracker-microvm/firecracker/blob/main/docs/rootfs-and-kernel-setup.md

set -eu

populate_rootfs() {
    echo "Populating rootfs..."

    local _src_rootfs="${1}"
    local _dst_rootfs="${2}"
    local _rootfs_mnt="/tmp/rootfs"

    mkdir -p "$(dirname "${_dst_rootfs}")"
    rm -f "${_dst_rootfs}"
    mkdir -p "${_rootfs_mnt}"

    truncate -s "${ROOTFS_SIZE}" "${_dst_rootfs}"
    mkfs.ext4 "${_dst_rootfs}"

    mount -v -t ext4 -o defaults "${_dst_rootfs}" "${_rootfs_mnt}" || {
        dmesg | tail -5
        exit 1
    }

    rsync -a "${_src_rootfs}"/ "${_rootfs_mnt}"/
    for dir in dev proc run sys var; do mkdir -p "${_rootfs_mnt}/${dir}"; done

    # alpine already has /sbin/init that we should replace, otherwise
    # we would probably use --ignore-existing as well
    rsync -a --keep-dirlinks "${overlay_src}"/ "${_rootfs_mnt}"/

    # Write all environment variable exports to a file in the rootfs
    mkdir -p "${_rootfs_mnt}/etc/profile.d"
    sh -c 'export -p' | grep -vE "^(export )?(PWD|TERM|USER|SHLVL|PATH|HOME|_)=" >"${_rootfs_mnt}/etc/profile.d/fc_exports.sh"

    # write the guest command to the end of the init script
    echo "exec ${cmd_str}" >>"${_rootfs_mnt}/sbin/init"

    umount -v "${_rootfs_mnt}"

    chown firecracker:firecracker "${_dst_rootfs}"
}

populate_datafs() {

    local _dst_datafs="${1}"

    mkdir -p "$(dirname "${_dst_datafs}")"

    if [ ! -f "${_dst_datafs}" ]; then
        echo "Populating datafs..."
        truncate -s "${DATAFS_SIZE}" "${_dst_datafs}"
        mkfs.ext4 -q "${_dst_datafs}"
        chown firecracker:firecracker "${_dst_datafs}"
    fi
}

generate_config() {
    echo "Generating Firecracker config file..."

    local _src_config="${1}"
    local _dst_config="${2}"

    envsubst <"${_src_config}" >"${_dst_config}"

    jq ".\"boot-source\".boot_args = \"${KERNEL_BOOT_ARGS}\"" "${_dst_config}" >"${_dst_config}".tmp
    mv "${_dst_config}".tmp "${_dst_config}"

    jq ".\"machine-config\".vcpu_count = ${VCPU_COUNT}" "${_dst_config}" >"${_dst_config}".tmp
    mv "${_dst_config}".tmp "${_dst_config}"

    jq ".\"machine-config\".mem_size_mib = ${MEM_SIZE_MIB}" "${_dst_config}" >"${_dst_config}".tmp
    mv "${_dst_config}".tmp "${_dst_config}"

    # It doesn't seem to matter what we call this interface, it always shows up as 'eth0' in the guest
    jq ".\"network-interfaces\"[0].iface_id = \"net0\"" "${_dst_config}" >"${_dst_config}".tmp
    mv "${_dst_config}".tmp "${_dst_config}"

    jq ".\"network-interfaces\"[0].guest_mac = \"${GUEST_MAC}\"" "${_dst_config}" >"${_dst_config}".tmp
    mv "${_dst_config}".tmp "${_dst_config}"

    jq ".\"network-interfaces\"[0].host_dev_name = \"${TAP_DEVICE}\"" "${_dst_config}" >"${_dst_config}".tmp
    mv "${_dst_config}".tmp "${_dst_config}"

    # jq . "${_dst_config}"
}

setup_networking() {
    local _tap_dev="${1}"
    local _tap_cidr="${2}"
    local _host_dev="${3}"

    # bail out if dap device already exists
    if ip link show "${_tap_dev}" >/dev/null 2>&1; then
        echo "TAP device ${_tap_dev} already exists!"
        exit 1
    fi

    echo "Creating ${_tap_dev} device..."
    # delete existing tap device
    ip link del "${_tap_dev}" 2>/dev/null || true
    # create tap device
    ip tuntap add dev "${_tap_dev}" mode tap user firecracker
    # ip tuntap add dev "${_tap_dev}" mode tap
    ip addr add "${_tap_cidr}" dev "${_tap_dev}"
    ip link set dev "${_tap_dev}" up

    echo "Enabling IP forwarding..."
    sysctl -w net.ipv4.ip_forward=1
    # sysctl -w net.ipv4.conf.${_tap_dev}.proxy_arp=1
    # sysctl -w net.ipv6.conf.${_tap_dev}.disable_ipv6=1

    echo "Applying iptables rules..."
    # delete rules matching comment
    iptables-legacy-save | grep -v "comment ${_tap_dev}" | iptables-legacy-restore || true
    # create FORWARD and POSTROUTING rules
    iptables-legacy -t nat -A POSTROUTING -o "${_host_dev}" -j MASQUERADE -m comment --comment "${_tap_dev}"
    # iptables-legacy -I FORWARD 1 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT -m comment --comment "${_tap_dev}"
    # iptables-legacy -I FORWARD 1 -i "${_tap_dev}" -o "${_host_dev}" -j ACCEPT -m comment --comment "${_tap_dev}"
    iptables-legacy -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT -m comment --comment "${_tap_dev}"
    iptables-legacy -A FORWARD -i "${_tap_dev}" -o "${_host_dev}" -j ACCEPT -m comment --comment "${_tap_dev}"
}

normalize_cidr() {
    local _address
    local _short_netmask
    local _long_netmask

    _address="$(ipcalc -nb "${1}" | awk '/^Address:/ {print $2}')"
    _long_netmask="$(ipcalc -nb "${1}" | awk '/^Netmask:/ {print $2}')"
    _short_netmask="$(ipcalc -nb "${1}" | awk '/^Netmask:/ {print $4}')"

    echo "${_address}/${_short_netmask}"
}

network_config() {
    local _client_ip="${1}"
    local _server_ip=""
    local _gw_ip="${2}"
    local _netmask=""
    local _hostname="${3}"
    local _device="${4}"
    local _autoconf=off

    # normalize addresses to remove cidr suffix
    _client_ip="$(ipcalc -nb "${_client_ip}" | awk '/^Address:/ {print $2}')"
    _gw_ip="$(ipcalc -nb "${_gw_ip}" | awk '/^Address:/ {print $2}')"
    _netmask="$(ipcalc -nb "${_client_ip}" | awk '/^Netmask:/ {print $2}')"

    echo "ip=${_client_ip}:${_server_ip}:${_gw_ip}:${_netmask}:${_hostname}:${_device}:${_autoconf}"
}

ip_to_mac() {
    # shellcheck disable=SC2183,SC2046
    printf '52:54:%02X:%02X:%02X:%02X\n' $(echo "${1}" | tr '.' ' ')
}

create_logs_fifo() {
    local _fifo="${1}"
    local _out="${2}"

    mkdir -p "$(dirname "${_fifo}")"
    rm -f "${_fifo}"

    # Create a named pipe
    mkfifo "${_fifo}"
    # Redirect the output of the named pipe to /dev/stdout
    cat "${_fifo}" >"${_out}" &
    # Take ownership of the named pipe
    chown firecracker:firecracker "${_fifo}"
}

cleanup() {
    echo "Cleaning up..."
    # delete tap device
    ip link del "${TAP_DEVICE}" 2>/dev/null || true
    # delete rules matching comment
    iptables-legacy-save | grep -v "comment ${TAP_DEVICE}" | iptables-legacy-restore
}

script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
overlay_src="${script_root}/overlay"
rootfs_src="${script_root}/rootfs"
config_src="${script_root}/config.json"

# Check that at least one argument was passed
if [ $# -eq 0 ]; then
    echo "At least one COMMAND instruction is required. See the project README for usage."
    sleep infinity
fi

# Store the script arguments as the guest command
for arg in "$@"; do
    # Remove existing quotes
    arg=${arg%\"}
    arg=${arg#\"}
    # Escape existing unescaped quotes
    arg=${arg//\"/\\\"}
    # Add quotes around arguments
    arg="\"$arg\""
    cmd_str+="$arg "
done

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
    ROOTFS_SIZE=$(df -B1 . | awk 'NR==2 {print $2}')
fi

# Set default space to same as available on system if not specified
if [ -z "${DATAFS_SIZE:-}" ]; then
    DATAFS_SIZE=$(df -B1 . | awk 'NR==2 {print $2}')
fi

if [ -z "${HOST_IFACE:-}" ]; then
    HOST_IFACE="$(ip route | awk '/default/ {print $5}')"
fi

if [ -z "${TAP_IP:-}" ]; then
    # generate random number between 1 and 254
    TAP_IP=10.$((1 + RANDOM % 254)).$((1 + RANDOM % 254)).1/30
fi

TAP_IP="$(normalize_cidr "${TAP_IP}")"

if [ -z "${GUEST_IP:-}" ]; then
    # the default guest IP is the TAP IP + 1
    GUEST_IP="$(echo "${TAP_IP}" | awk -F'[./]' '{print $1"."$2"."$3"."$4+1}')"
fi

if [ -z "${TAP_DEVICE:-}" ]; then
    # must be less than 16 characters
    TAP_DEVICE="$(echo "${TAP_IP}" | awk -F'[./]' '{print "tap-"$1"-"$2"-"$3}')"
fi

if [ -z "${GUEST_MAC:-}" ]; then
    # guest MAC is '52:54' followed by the hex encoded guest IP octets
    GUEST_MAC="$(ip_to_mac "${GUEST_IP}")"
fi

if [ -z "${KERNEL_BOOT_ARGS:-}" ]; then
    KERNEL_BOOT_ARGS="console=ttyS0 reboot=k panic=1 pci=off random.trust_cpu=on"

    if [ "$(uname -m)" = "aarch64" ]; then
        KERNEL_BOOT_ARGS="keep_bootcon ${KERNEL_BOOT_ARGS}"
    fi
fi

KERNEL_BOOT_ARGS="${KERNEL_BOOT_ARGS} $(network_config "${GUEST_IP}" "${TAP_IP}" "$(hostname)" eth0)"

echo "Virtual CPUs: ${VCPU_COUNT}"
echo "Memory: ${MEM_SIZE_MIB}M"
echo "Root Drive (vda): ${ROOTFS_SIZE}B"
echo "Data Drive (vdb): ${DATAFS_SIZE}B"
echo "Host Interface: ${HOST_IFACE}"
echo "TAP Device: ${TAP_DEVICE}"
echo "TAP IP Address: ${TAP_IP}"
echo "Guest IP Address: ${GUEST_IP}"
echo "Guest MAC Address: ${GUEST_MAC}"
echo "Kernel Boot Args: ${KERNEL_BOOT_ARGS}"
echo "Guest Command: ${cmd_str}"

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

trap cleanup EXIT

# Remount tmpfs mounts with the execute bit set
for dir in /tmp /run /srv; do
    mkdir -p "${dir}"
    if [ "$(stat -f -c '%T' "${dir}")" = "tmpfs" ]; then
        echo "Remounting ${dir} as rw,exec..."
        mount -o remount,rw,exec tmpfs "${dir}"
    fi
done

# The jailer will use this id to create a unique chroot directory for the MicroVM
# among other things.
id="$(uuidgen)"

# These directories will be bind mounted to the chroot and can
# optionally be replaced with volumes mounted by the user.
boot_jail="/jail/boot"
data_jail="/jail/data"

# The jailer will use this directory as the base for the chroot directory
chroot_base="/srv/jailer"
chroot_dir="${chroot_base}/firecracker/${id}/root"

echo "Creating jailer chroot..."
mkdir -p "${boot_jail}" "${chroot_dir}"/boot
mkdir -p "${data_jail}" "${chroot_dir}"/data

populate_rootfs "${rootfs_src}" "${boot_jail}"/rootfs.ext4
populate_datafs "${data_jail}"/datafs.ext4
setup_networking "${TAP_DEVICE}" "${TAP_IP}" "${HOST_IFACE}"
generate_config "${config_src}" "${boot_jail}"/config.json
create_logs_fifo "${boot_jail}"/logs.fifo /dev/stdout

# Bind mount /jail/boot and /jail/data to /boot and /data in the chroot.
# This way users can mount their own volumes to /jail/boot and /jail/data
# without needing to know the exact path of the chroot.
mount --bind "${boot_jail}" "${chroot_dir}"/boot
mount --bind "${data_jail}" "${chroot_dir}"/data

# /usr/local/bin/firecracker --help
# /usr/local/bin/jailer --help

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
    --log-path /boot/logs.fifo
