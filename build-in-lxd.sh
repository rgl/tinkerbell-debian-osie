#!/bin/bash
set -euo pipefail

function install-builder {
    set -x
    #echo "IP address: $(wget -qO- https://api.ipify.org)"
    lxd --version
    lxd init --auto
}

function start-builder {
    set -x
    lxc init --quiet images:debian/11 builder
    lxc config device add builder mnt disk source=$PWD path=/mnt
    lxc start builder
    lxc exec builder -- bash -c 'while [ "$(systemctl is-system-running)" != "running" ]; do sleep 1; done'
    lxc list
}

function build {
    set -x
    case "$(uname -m)" in
        x86_64)
            local LB_BUILD_ARCH='amd64'
            ;;
        aarch64)
            local LB_BUILD_ARCH='arm64'
            ;;
        *)
            echo "Unsupported Host Arch: $(uname -m)"
            exit 1
            ;;
    esac
    lxc exec builder -- bash -c 'echo quiet=on >~/.wgetrc'
    lxc exec builder \
        --env 'DEBIAN_MIRROR=http://ftp.us.debian.org/debian/' \
        --env "LB_BUILD_ARCH=$LB_BUILD_ARCH" \
        -- bash /mnt/build.sh
    lxc file pull \
        "builder/root/osie-$LB_BUILD_ARCH/live-image-$LB_BUILD_ARCH.hybrid.iso" \
        "tinkerbell-debian-osie-$LB_BUILD_ARCH.iso"
}

case "$1" in
    install-builder)
        install-builder
        ;;
    start-builder)
        start-builder
        ;;
    build)
        build
        ;;
    *)
        echo "Unknown command: $1"
        exit 1
        ;;
esac
