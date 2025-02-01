# syntax=docker/dockerfile:1.3-labs

FROM --platform=$BUILDPLATFORM ubuntu:latest AS kernel

ARG arch
ARG kernel

# hadolint ignore=DL3020
ADD $kernel /tmp/kernel.tar.gz

WORKDIR /tmp/kernel

SHELL ["/bin/bash", "-ec"]

# https://github.com/raspberrypi/linux/blob/HEAD/.github/workflows/kernel-build.yml
# https://wiki.qemu.org/Documentation/9psetup#Preparation
# https://superuser.com/a/1301973
# hadolint ignore=SC2086
RUN --mount=type=cache,id=apt-$arch-$kernel,target=/var/lib/apt \
    --mount=type=cache,id=build-$arch-$kernel,target=/tmp/build \
    --mount=type=cache,id=cache-$arch-$kernel,target=/var/cache \
    --mount=type=cache,id=kernel-$arch-$kernel,target=/tmp/kernel \
    --mount=type=tmpfs,target=/var/log <<EOF
  case "$arch" in
    aarch64)
      export ARCH=arm64
      export DEFCONFIG=bcm2711_defconfig
      export GCC=gcc-aarch64-linux-gnu
      export IMAGE=Image.gz
      export CROSS_COMPILE=aarch64-linux-gnu-
      ;;
    arm)
      export ARCH=arm
      export DEFCONFIG=bcm2711_defconfig
      export GCC=gcc-arm-linux-gnueabihf
      export IMAGE=zImage
      export CROSS_COMPILE=arm-linux-gnueabihf-
      ;;
  esac

  apt-get update
  apt-get install --mark-auto --no-install-recommends -y \
    bc \
    bison \
    flex \
    gcc \
    $GCC \
    libc6-dev \
    libc6-dev-arm64-cross \
    libssl-dev \
    kmod \
    make \
    xz-utils

  [ -z "$(ls -A)" ] && tar --strip-components=1 -xzf /tmp/kernel.tar.gz
  make O=/tmp/build $DEFCONFIG
  scripts/config --file /tmp/build/.config \
    --enable CONFIG_9P_FS \
    --enable CONFIG_9P_FS_POSIX_ACL \
    --enable CONFIG_9P_FS_SECURITY \
    --enable CONFIG_BINFMT_MISC \
    --enable CONFIG_NET_9P \
    --enable CONFIG_NET_9P_VIRTIO \
    --enable CONFIG_NETWORK_FILESYSTEMS \
    --enable CONFIG_PCI \
    --enable CONFIG_PCI_HOST_COMMON \
    --enable CONFIG_PCI_HOST_GENERIC \
    --disable CONFIG_PCI_MSI \
    --disable CONFIG_PCI_MSI_IRQ_DOMAIN \
    --enable CONFIG_VIRTIO_BLK \
    --enable CONFIG_VIRTIO_MMIO \
    --enable CONFIG_VIRTIO_NET \
    --enable CONFIG_VIRTIO_PCI \
    --enable CONFIG_WERROR
  echo +rpt-rpi >/tmp/build/localversion
  make O=/tmp/build -j 3 $IMAGE modules
  make O=/tmp/build INSTALL_MOD_PATH=/media/sd/usr modules_install
  find /media/sd/usr/lib/modules -type l -name build -delete

  mkdir -p /media/sd/boot/firmware
  cp /tmp/build/arch/$ARCH/boot/$IMAGE /media/sd/boot/firmware/qemu.img

  apt-get autoremove --purge -y
EOF

FROM --platform=$BUILDPLATFORM alpine:latest AS image

ARG image

# hadolint ignore=DL3020
ADD $image /sd.img.xz

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# hadolint ignore=DL3001
RUN --security=insecure <<EOF
  apk add --no-cache --virtual=.tools \
    e2fsprogs \
    jq \
    sfdisk \
    qemu-img
  unxz -ck /sd.img.xz >/tmp/sd.img

  mkdir -p \
    /media/sd/boot/firmware \
    /media/sd/usr/lib/locale
  qemu-img create -f raw /media/sd/boot/firmware/locale.img 10M
  mkfs.ext4 /media/sd/boot/firmware/locale.img
  mount -o loop,offset="$(sfdisk -J /tmp/sd.img | jq '.partitiontable.sectorsize * .partitiontable.partitions[1].start')" /tmp/sd.img /mnt
  mount -o loop,offset="$(sfdisk -J /tmp/sd.img | jq '.partitiontable.sectorsize * .partitiontable.partitions[0].start')" /tmp/sd.img /mnt/boot/firmware
  mount -o loop /media/sd/boot/firmware/locale.img /media/sd/usr/lib/locale
  cp -pr /mnt/* /media/sd
  rm \
    /media/sd/etc/init.d/resize2fs_once \
    /media/sd/etc/systemd/system/multi-user.target.wants/rpi-eeprom-update.service
  umount \
    /media/sd/usr/lib/locale \
    /mnt/boot/firmware \
    /mnt

  rm -rf /tmp/sd.img
  apk del .tools
EOF

# Workaround to support `update-initramfs`.
COPY <<EOF /media/sd/etc/initramfs-tools/conf.d/modules
MODULES=most
EOF

# Workaround to emulate WLAN.
COPY <<EOF /media/sd/etc/modprobe.d/mac80211_hwsim.conf
options mac80211_hwsim radios=1
EOF

COPY <<EOF /media/sd/etc/modules-load.d/mac80211_hwsim.conf
mac80211_hwsim
EOF

FROM --platform=$BUILDPLATFORM scratch AS rootfs

COPY --from=image /media/sd /media/sd
COPY --from=kernel /media/sd /media/sd
COPY /rootfs /

# https://gitlab.com/qemu-project/qemu/-/commit/d06a9d843fb65351e0e4dc42ba0c404f01ea92b3
# https://gitlab.com/qemu-project/qemu/-/issues/2337
FROM alpine:latest AS qemu

ARG qemu=https://gitlab.com/qemu-project/qemu/-/archive/master/qemu-master.tar.gz
ARG qemu_version=9.2.1

ADD https://gitlab.alpinelinux.org/alpine/aports/-/archive/master/aports-master.tar.gz?path=community/qemu /tmp/aports.tar.gz

WORKDIR /root/aports
SHELL ["/bin/ash", "-ec"]

RUN <<EOF
  apk add --no-cache --virtual=.tools \
    alpine-sdk
EOF

RUN --mount=type=cache,id=aports-$qemu,target=/root/aports <<EOF
  USER=root abuild-keygen --append -n
  cp /root/.abuild/*.rsa.pub /etc/apk/keys

  tar  --strip-components=3 -xzf /tmp/aports.tar.gz
  sed \
      -e "s|pkgver=.*|pkgver=$qemu_version|g" \
      -e "s|https://download\.qemu\.org/qemu-.*\.tar\.xz|$qemu|g" \
      -re "s|(pkgname=.*)|\1\nbuilddir=\"\$srcdir\"/\$pkgname-master|g" \
      -i APKBUILD

  abuild -F checksum deps
  abuild -F
EOF

FROM alpine:latest

ARG arch

ENV RPI_ARCH=$arch

RUN --mount=type=bind,from=qemu,source=/root/packages/root,target=/root/packages \
  apk add --no-cache \
    expect \
    openssl \
    --repository=/root/packages --allow-untrusted qemu-system-$arch

COPY --from=rootfs / /

ENTRYPOINT ["rpi"]
