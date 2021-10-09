#!/bin/bash
set -euxo pipefail


# the build architecture can be one of:
#   amd64 (default)
#   arm64
LB_BUILD_ARCH="${LB_BUILD_ARCH:=amd64}"

# the debian mirror to use.
DEBIAN_MIRROR_URL="${DEBIAN_MIRROR:=http://ftp.pt.debian.org/debian/}"

# where to cache files.
if [ -d /vagrant ]; then
    CACHE_PATH="${CACHE_PATH:=/vagrant/tmp}"
else
    CACHE_PATH="${CACHE_PATH:=/tmp}"
fi
if [ ! -d "$CACHE_PATH" ]; then
    install -d "$CACHE_PATH"
fi


#
# install dependencies.

if [ "$LB_BUILD_ARCH" == 'arm64' ] && [ "$(uname -m)" != "aarch64" ]; then
    apt-get install -y qemu-user-static
fi
apt-get install -y libcdio-utils
apt-get install -y live-build
apt-get install -y unzip
apt-get install -y fdisk


#
# build the osie image.

rm -rf osie-$LB_BUILD_ARCH && mkdir osie-$LB_BUILD_ARCH && pushd osie-$LB_BUILD_ARCH

# configure it.
# see https://live-team.pages.debian.net/live-manual/html/live-manual/index.en.html
# see lb(1) at https://manpages.debian.org/bullseye/live-build/lb.1.en.html
# see live-build(7) at https://manpages.debian.org/bullseye/live-build/live-build.7.en.html
# see lb_config(1) at https://manpages.debian.org/bullseye/live-build/lb_config.1.en.html
# NB default images configurations are defined in a branch at https://salsa.debian.org/live-team/live-images
#    e.g. https://salsa.debian.org/live-team/live-images/-/tree/debian/images/standard

mkdir -p auto
cp /usr/share/doc/live-build/examples/auto/* auto/

lb_config='\
    --binary-images iso-hybrid \
    --iso-application "Debian OSIE" \
    --iso-publisher https://github.com/rgl/tinkerbell-debian-osie \
    '
if [ "$LB_BUILD_ARCH" == 'arm64' ] && [ "$(uname -m)" != "aarch64" ]; then
lb_config="$lb_config \\
    --bootloader grub-efi \\
    --bootstrap-qemu-arch arm64 \\
    --bootstrap-qemu-static /usr/bin/qemu-arm-static \\
    "
fi
cat >auto/config <<EOF
#!/bin/sh
set -eux
lb config noauto \\
    $lb_config \\
    --mode debian \\
    --distribution bullseye \\
    --architectures $LB_BUILD_ARCH \\
    --bootappend-live 'boot=live components username=osie noautologin' \\
    --mirror-bootstrap $DEBIAN_MIRROR_URL \\
    --mirror-binary $DEBIAN_MIRROR_URL \\
    --apt-indices false \\
    --memtest none \\
    "\${@}"
EOF
# NB use --bootappend-live '... noautologin' to ask the user to enter a password to use the system.
# NB --bootappend-live '... keyboard-layouts=pt' is currently broken. we have to manually configure the keyboard.
#    see Re: Status of kbd console-data and console-setup at https://lists.debian.org/debian-devel/2016/08/msg00276.html
chmod +x auto/config

mkdir -p config/package-lists
cat >config/package-lists/custom.list.chroot <<'EOF'
console-data
docker.io
jq
less
openssh-server
vim
wget
EOF
# # add troubleshooting tools.
# cat >>config/package-lists/custom.list.chroot <<'EOF'
# lsof
# pciutils
# tcpdump
# EOF

mkdir -p config/preseed
cat >config/preseed/keyboard.cfg.chroot <<'EOF'
# format: <owner> <question name> <question type> <value>
# NB put just a single space or tab between <question type> and <value>.
# NB this will be eventually stored at /var/cache/debconf/config.dat
console-common  console-data/keymap/policy  select Select keymap from full list
console-common  console-data/keymap/full    select pt-latin1
EOF

mkdir -p config/includes.chroot/lib/live/config
cat >config/includes.chroot/lib/live/config/0149-keyboard <<'EOF'
#!/bin/sh
set -eux
dpkg-reconfigure console-common
EOF
chmod +x config/includes.chroot/lib/live/config/0149-keyboard

# configure the system to go get its hostname and domain from dhcp.
# NB dhclient will set the hostname from dhcp iif the current hostname
#    is blank, "(none)", or "localhost".
# see set_hostname at /sbin/dhclient-script
mkdir -p config/includes.chroot/etc
echo localhost >config/includes.chroot/etc/hostname

# configure the system to create /etc/hosts when the dhcp lease changes.
# NB this must be a sh script.
# see /sbin/dhclient-script
# see https://manpages.debian.org/bullseye/isc-dhcp-client/dhclient-script.8.en.html
mkdir -p config/includes.chroot/etc/dhcp/dhclient-exit-hooks.d
cat >config/includes.chroot/etc/dhcp/dhclient-exit-hooks.d/hosts <<'EOF'
set_hosts() {
    cat >/etc/hosts <<EOF_HOSTS
# NB this was automatically set from /etc/dhcp/dhclient-exit-hooks.d/hosts
127.0.0.1 localhost
$new_ip_address $new_host_name
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF_HOSTS
}

case $reason in
    BOUND|RENEW|REBIND|REBOOT)
        set_hosts
        ;;
esac
EOF

mkdir -p config/includes.chroot/etc
cat >config/includes.chroot/etc/motd <<'EOF'

Enter a root shell with:

    sudo -i

Change the keyboard layout with one of:

    loadkeys pt-latin1
    loadkeys us

List disks:

    lsblk -O
    lsblk -x KNAME -o KNAME,SIZE,TRAN,SUBSYSTEMS,FSTYPE,UUID,LABEL,MODEL,SERIAL

HINT: Press the up/down arrow keys to navigate the history.
EOF

mkdir -p config/includes.chroot/root
cat >config/includes.chroot/root/.bash_history <<'EOF'
loadkeys us
loadkeys pt-latin1
lsblk -x KNAME -o KNAME,SIZE,TRAN,SUBSYSTEMS,FSTYPE,UUID,LABEL,MODEL,SERIAL
EOF

mkdir -p config/includes.chroot/etc/profile.d
cat >config/includes.chroot/etc/profile.d/login.sh <<'EOF'
[[ "$-" != *i* ]] && return
echo "Firmware: $([ -d /sys/firmware/efi ] && echo 'UEFI' || echo 'BIOS')"
echo "Framebuffer resolution: $(cat /sys/class/graphics/fb0/virtual_size | tr , x)"
export EDITOR=vim
export PAGER=less
alias l='ls -lF --color'
alias ll='l -a'
alias h='history 25'
alias j='jobs -l'
EOF

cat >config/includes.chroot/etc/inputrc <<'EOF'
set input-meta on
set output-meta on
set show-all-if-ambiguous on
set completion-ignore-case on
"\e[A": history-search-backward
"\e[B": history-search-forward
"\eOD": backward-word
"\eOC": forward-word
EOF

mkdir -p config/includes.chroot/etc/vim
cat >config/includes.chroot/etc/vim/vimrc.local <<'EOF'
syntax on
set background=dark
set esckeys
set ruler
set laststatus=2
set nobackup
EOF

# NB the live environment root vfs is an overlay, and since we cannot mount an
#    overlay over an overlay (at /var/lib/docker), we have to configure (with
#    the graph property) docker to use the live tmpfs at /run/live/overlay.
mkdir -p config/includes.chroot/etc/docker
cat >config/includes.chroot/etc/docker/daemon.json <<'EOF'
{
    "experimental": false,
    "debug": false,
    "features": {
        "buildkit": true
    },
    "log-driver": "journald",
    "storage-driver": "overlay2",
    "graph": "/run/live/overlay/docker",
    "hosts": [
        "fd://"
    ],
    "containerd": "/run/containerd/containerd.sock"
}
EOF
mkdir -p config/includes.chroot/etc/systemd/system/docker.service.d
cat >config/includes.chroot/etc/systemd/system/docker.service.d/override.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/sbin/dockerd
EOF

# create the promtail service that will send the journal log messages to loki.
# NB the arm64 build does not yet support reading from journald; so the logs
#    will not be sent to loki.
#    see https://github.com/grafana/loki/issues/1459
promtail_version='2.3.0'
promtail_zip_path="$CACHE_PATH/promtail-$promtail_version-$LB_BUILD_ARCH.zip"
if [ ! -f "$promtail_zip_path" ]; then
    wget -qO "$promtail_zip_path" \
        "https://github.com/grafana/loki/releases/download/v$promtail_version/promtail-linux-$LB_BUILD_ARCH.zip"
fi
install -d config/includes.chroot/usr/local/bin
unzip -d config/includes.chroot/usr/local/bin "$promtail_zip_path"
mv config/includes.chroot/usr/local/bin/promtail{-linux-$LB_BUILD_ARCH,}
install -m 755 /dev/null config/includes.chroot/usr/local/bin/promtail.sh
cat >config/includes.chroot/usr/local/bin/promtail.sh <<'EOF'
#!/bin/bash
set -eu -o pipefail -o errtrace

function err_trap {
    local err=$?
    set +e
    echo "ERROR: Trap exit code $err at:" >&2
    echo "ERROR:   ${BASH_SOURCE[1]}:${BASH_LINENO[0]} ${BASH_COMMAND}" >&2
    if [ ${#FUNCNAME[@]} -gt 2 ]; then
        for ((i=1;i<${#FUNCNAME[@]}-1;i++)); do
            echo "ERROR:   ${BASH_SOURCE[$i+1]}:${BASH_LINENO[$i]} ${FUNCNAME[$i]}(...)" >&2
        done
    fi
    exit $err
}

trap err_trap ERR

function get-param {
    cat /proc/cmdline | tr ' ' '\n' | grep "^$1=" | sed -E 's,.+=(.*),\1,g'
}

# get the required parameters.
# TODO find a secure way to bootstrap these values and secrets.
syslog_host="$(get-param syslog_host)"
worker_id="$(get-param worker_id)"
# TODO use https.
loki_url="http://$syslog_host:3100/loki/api/v1/push"

# configure promtail.
# see https://grafana.com/docs/loki/latest/clients/promtail/configuration/#example-journal-config
# see https://grafana.com/docs/loki/latest/clients/promtail/scraping/#journal-scraping-linux-only
install -d -m 700 /var/run/promtail
install -m 600 /dev/null /var/run/promtail/config.yaml
cat >/var/run/promtail/config.yaml <<CONFIG_EOF
positions:
  filename: /var/run/promtail/positions.yaml

clients:
  - url: '$loki_url'

scrape_configs:
  - job_name: journal
    journal:
      max_age: 12h
      json: false
      labels:
        job: systemd-journal
        host: '$(hostname)'
        worker_id: '$worker_id'
    # see https://www.freedesktop.org/software/systemd/man/systemd.journal-fields.html#Trusted%20Journal%20Fields
    # see https://grafana.com/docs/loki/latest/clients/promtail/scraping/#journal-scraping-linux-only
    # NB use journalctl -n 1 -o json to see an actual journal log message (including metadata).
    # NB use journalctl -n 1 -o json CONTAINER_NAME=date-ticker to see a container log message.
    relabel_configs:
      - source_labels: [__journal__systemd_unit]
        target_label: source
      - source_labels: [__journal_container_name]
        target_label: _container_name
      - source_labels: [__journal_workflow_id]
        target_label: workflow_id
    pipeline_stages:
      - match:
          selector: '{source="docker.service"}'
          stages:
            - template:
                source: job
                template: container
            - labels:
                job:
                source: _container_name
      - labeldrop:
          - _container_name
CONFIG_EOF

# execute promtail.
exec /usr/local/bin/promtail -config.file=/var/run/promtail/config.yaml
EOF
install -m 644 /dev/null config/includes.chroot/etc/systemd/system/promtail.service
cat >config/includes.chroot/etc/systemd/system/promtail.service <<'EOF'
[Unit]
Description=Promtail

[Service]
Type=simple
ExecStart=/usr/local/bin/promtail.sh
TimeoutStopSec=15
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# create the systemd service that starts the tink-worker container.
install -d config/includes.chroot/usr/local/bin
install -m 755 /dev/null config/includes.chroot/usr/local/bin/tink-worker-start.sh
cat >config/includes.chroot/usr/local/bin/tink-worker-start.sh <<'EOF'
#!/bin/bash
set -eu -o pipefail -o errtrace

function err_trap {
    local err=$?
    set +e
    echo "ERROR: Trap exit code $err at:" >&2
    echo "ERROR:   ${BASH_SOURCE[1]}:${BASH_LINENO[0]} ${BASH_COMMAND}" >&2
    if [ ${#FUNCNAME[@]} -gt 2 ]; then
        for ((i=1;i<${#FUNCNAME[@]}-1;i++)); do
            echo "ERROR:   ${BASH_SOURCE[$i+1]}:${BASH_LINENO[$i]} ${FUNCNAME[$i]}(...)" >&2
        done
    fi
    exit $err
}

trap err_trap ERR

function get-param {
    cat /proc/cmdline | tr ' ' '\n' | grep "^$1=" | sed -E 's,.+=(.*),\1,g'
}

# get the required parameters.
# TODO find a secure way to bootstrap these values and secrets.
tinkerbell="$(get-param tinkerbell)"
packet_base_url="$(get-param packet_base_url)"
docker_registry="$(get-param docker_registry)"
registry_username="$(get-param registry_username)"
registry_password="$(get-param registry_password)"
grpc_authority="$(get-param grpc_authority)"
grpc_cert_url="$(get-param grpc_cert_url)"
worker_id="$(get-param worker_id)"
container_uuid="$(wget -qO- "$tinkerbell:50061/metadata" | jq -r .id)"

# save the registry ca certificate.
# TODO find a secure way to bootstrap this certificate.
install -d -m 755 "/etc/docker/certs.d/$docker_registry"
wget -qO "/etc/docker/certs.d/$docker_registry/ca.crt" "$packet_base_url/ca.pem"

# save the registry credentials.
install -d -m 700 ~/.docker
install -m 600 /dev/null ~/.docker/config.json
cat >~/.docker/config.json <<CONFIG_EOF
{
    "auths": {
        "$docker_registry": {
            "auth": "$(echo -n "$registry_username:$registry_password" | base64)"
        }
    }
}
CONFIG_EOF

# create the worker directory.
install -d -m 700 /worker

# destroy the tink-worker container.
# NB we have to destroy it here because we do not start the container with
#    --rm. this gives us the oportunity to troubleshoot when things go
#    wrong and we try to re-execute this script.
docker rm --force tink-worker

# start the tink-worker container.
export DOCKER_REGISTRY=$docker_registry
export REGISTRY_USERNAME=$registry_username
export REGISTRY_PASSWORD=$registry_password
export TINKERBELL_GRPC_AUTHORITY=$grpc_authority
export TINKERBELL_CERT_URL=$grpc_cert_url
export WORKER_ID=$worker_id
export ID=$worker_id
export container_uuid=$container_uuid
exec docker run \
    --name tink-worker \
    --detach \
    --env DOCKER_REGISTRY \
    --env REGISTRY_USERNAME \
    --env REGISTRY_PASSWORD \
    --env TINKERBELL_GRPC_AUTHORITY \
    --env TINKERBELL_CERT_URL \
    --env WORKER_ID \
    --env ID \
    --env container_uuid \
    --network host \
    --privileged \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /worker:/worker \
    $docker_registry/tink-worker \
    --capture-action-logs=false
EOF
install -m 755 /dev/null config/includes.chroot/usr/local/bin/tink-worker-stop.sh
cat >config/includes.chroot/usr/local/bin/tink-worker-stop.sh <<'EOF'
#!/bin/bash
set -euo pipefail

docker stop tink-worker
EOF
install -m 644 /dev/null config/includes.chroot/etc/systemd/system/tink-worker.service
cat >config/includes.chroot/etc/systemd/system/tink-worker.service <<'EOF'
[Unit]
Description=Tinkerbell Worker
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=true
Restart=no
ExecStart=/usr/local/bin/tink-worker-start.sh
ExecStop=/usr/local/bin/tink-worker-stop.sh

[Install]
WantedBy=multi-user.target
EOF

# create the systemd service that waits for the /worker/reboot file to appear
# and restart the system.
install -d config/includes.chroot/usr/local/bin
install -m 755 /dev/null config/includes.chroot/usr/local/bin/tink-reboot.sh
cat >config/includes.chroot/usr/local/bin/tink-reboot.sh <<'EOF'
#!/bin/bash
set -euo pipefail

# wait for the reboot tinkerbell action to signal us (by creating a file) to
# reboot the system.
while [ ! -f /worker/reboot ]; do
    sleep 3
done

# wait until tink-worker is the only container running.
while [ "$(docker ps | wc -l)" != "2" ]; do
    sleep 3
done

# explicitly stop tink-worker, as there's a bug somewhere that prevents a
# fast/sucessful reboot due to:
#    device-mapper: ioctl: remove_all left 1 open device(s).
# NB this problem was due to docker using the devicemapper storage-driver;
#    switching to overlay2 made it go away, but the system still hangs a bit
#    at reboot time, so we still have to use this workaround.
# TODO maybe tink-worker.service is not really stopping tink-worker?
docker stop tink-worker

# finally reboot.
reboot
EOF
install -d config/includes.chroot/etc/systemd/system
install -m 644 /dev/null config/includes.chroot/etc/systemd/system/tink-reboot.service
cat >config/includes.chroot/etc/systemd/system/tink-reboot.service <<'EOF'
[Unit]
Description=Tinkerbell Reboot

[Service]
Type=simple
ExecStart=/usr/local/bin/tink-reboot.sh

[Install]
WantedBy=multi-user.target
EOF

mkdir -p config/hooks/normal

cp /usr/share/doc/live-build/examples/hooks/stripped.hook.chroot config/hooks/normal/9991-stripped.hook.chroot
sed -i -E 's,(\s*)wget(\s*),\1\2,g' config/hooks/normal/9991-stripped.hook.chroot

cat >config/hooks/normal/9990-osie.hook.chroot <<'EOF'
#!/bin/sh
set -eux

# create the osie user and group.
adduser --gecos '' --disabled-login osie
echo osie:osie | chpasswd -m

# let osie use root permissions without sudo asking for a password.
echo 'osie ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/osie

# install the vagrant public key.
# NB vagrant will replace this insecure key on the first vagrant up.
install -d -m 700 /home/osie/.ssh
cd /home/osie/.ssh
wget -qOauthorized_keys https://raw.githubusercontent.com/hashicorp/vagrant/master/keys/vagrant.pub
chmod 600 authorized_keys
cd ..

# populate the bash history.
cat >.bash_history <<'EOS'
sudo -i
EOS

chown -R osie:osie .

systemctl enable promtail
systemctl enable tink-worker
systemctl enable tink-reboot
EOF

cat >config/hooks/normal/9990-initrd.hook.chroot <<'EOF'
#!/bin/sh
set -eux
echo nls_ascii >>etc/initramfs-tools/modules # for booting from FAT32.
EOF

if [ "$LB_BUILD_ARCH" == 'amd64' ]; then
    cat >config/hooks/normal/9990-bootloader-menu.hook.binary <<'EOF'
#!/bin/sh
set -eux
sed -i -E 's,^(set default=.+),\1\nset timeout=5,' boot/grub/config.cfg
sed -i -E 's,^(timeout ).+,\150,' isolinux/isolinux.cfg
rm isolinux/utilities.cfg
cat >isolinux/menu.cfg <<'EOM'
menu hshift 0
menu width 82
include stdmenu.cfg
include live.cfg
menu separator
label hdt
    menu label ^Hardware Detection Tool (HDT)
    com32 hdt.c32
menu clear
EOM
EOF
fi

# remove the boot files (e.g. linux and initrd) because they will be served
# from the network and do not need to use space in the filesystem.
# NB this is used by mksquashfs as -wildcards -ef /excludes.
# see /usr/lib/live/build/binary_rootfs
# see https://manpages.debian.org/bullseye/squashfs-tools/mksquashfs.1.en.html#ef
install -d config/rootfs
cat >config/rootfs/excludes <<'EOF'
boot/
vmlinuz*
initrd.img*
EOF

chmod +x config/hooks/normal/*.hook.*

# build it.
lb build

# show some information about the generated iso file.
fdisk -l live-image-$LB_BUILD_ARCH.hybrid.iso
iso-info live-image-$LB_BUILD_ARCH.hybrid.iso --no-header

# copy it on the host fs (it will be used by the target VM).
if [ -d /vagrant ]; then
    cp -f live-image-$LB_BUILD_ARCH.hybrid.iso /vagrant/tinkerbell-debian-osie-$LB_BUILD_ARCH.iso
fi

# clean it.
#lb clean
#lb clean --purge

popd
