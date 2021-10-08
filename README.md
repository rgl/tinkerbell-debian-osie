# About

This creates a Debian based [Tinkerbell](https://tinkerbell.org/) Operating System Installation Environment (OSIE).

**this is a WIP and this repository will be rebased**

# Usage

Install the [Base Debian Vagrant Box](https://github.com/rgl/debian-vagrant).

Run `vagrant up builder --no-destroy-on-error` to build the `tinkerbell-debian-osie-amd64.iso` file.

Run `vagrant up bios` to boot the generated ISO in [BIOS](https://en.wikipedia.org/wiki/BIOS) mode.

Run `vagrant up uefi` to boot the generated ISO in [UEFI](https://en.wikipedia.org/wiki/Unified_Extensible_Firmware_Interface) mode.

The default user and password are `osie`.

To build the arm64 architecture image, set the `LB_BUILD_ARCH` environment variable to `arm64` before launching vagrant, e.g. `LB_BUILD_ARCH=arm64 vagrant up builder`. To execute this image in an emulated virtual machine see the [qemu arm64 emulation](#qemu-arm64-emulation) section.

**NB** Building the arm64 image takes longer than the native amd64. In my machine it takes about 40m (vs 10m for amd64).

# qemu arm64 emulation

The arm64 architecture image can be executed in an emulated virtual machine as:

```bash
# NB in my humble machine (i3-3245) emulating arm64 is very slow and it takes
#    several minutes until you can login.
# NB in the qemu window use the "View" menu to switch between the
#    virtio-gpu-pci and serial0 console.
mkdir tmp
cd tmp
sudo apt-get install -y qemu-efi-aarch64
cp /usr/share/AAVMF/AAVMF_CODE.fd firmware-code-arm64.fd
cp /usr/share/AAVMF/AAVMF_VARS.fd firmware-vars-arm64.fd
qemu-img create -f qcow2 hd0.img 20G
qemu-img info hd0.img
qemu-system-aarch64 \
  -name arm64 \
  -machine virt \
  --accel tcg,thread=multi \
  -cpu cortex-a57 \
  -smp cores=4 \
  -m 2g \
  -k pt \
  -device virtio-gpu-pci \
  -device nec-usb-xhci,id=usb0 \
  -device usb-kbd,bus=usb0.0 \
  -device usb-tablet,bus=usb0.0 \
  -device virtio-scsi-pci,id=scsi0 \
  -drive if=pflash,file=firmware-code-arm64.fd,format=raw,readonly \
  -drive if=pflash,file=firmware-vars-arm64.fd,format=raw \
  -drive if=none,file=hd0.img,discard=unmap,cache=unsafe,id=hd0 \
  -drive if=none,file=$PWD/../tinkerbell-debian-osie-arm64.iso,media=cdrom,cache=unsafe,readonly,id=cd0 \
  -device scsi-hd,drive=hd0,bus=scsi0.0,bootindex=1 \
  -device scsi-cd,drive=cd0,bus=scsi0.0,bootindex=2 \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=net0 \
  -device virtio-rng-pci,rng=rng0 \
  -object rng-random,filename=/dev/urandom,id=rng0 \
  -qmp unix:arm64.socket,server,nowait
echo info qtree | qmp-shell -H arm64.socket
ssh vagrant@localhost -p 2222
```

# Reference

* [rgl/debian-live-builder-vagrant](https://github.com/rgl/debian-live-builder-vagrant)
* [Live Systems Manual](https://live-team.pages.debian.net/live-manual/html/live-manual/index.en.html)
* [lb(1)](https://manpages.debian.org/bullseye/live-build/lb.1.en.html)
* [live-build(7)](https://manpages.debian.org/bullseye/live-build/live-build.7.en.html)
* [lb_config(1)](https://manpages.debian.org/bullseye/live-build/lb_config.1.en.html)
* [Debian Live Team Repositories](https://salsa.debian.org/live-team)
* [Debian Live Wiki](http://wiki.debian.org/DebianLive): Information about the Debian Live team and its contacts.
* [run emulated arm under qemu](https://gist.github.com/rgl/b02c24f9eb1b4bdb4ac6f970d4bfc885)
