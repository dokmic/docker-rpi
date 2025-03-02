# syntax=docker/dockerfile:1.3-labs

FROM --platform=$BUILDPLATFORM ubuntu:latest AS builder

RUN \
  --mount=type=cache,id=apt,target=/var/lib/apt,sharing=locked \
  --mount=type=cache,id=cache,target=/var/cache,sharing=locked \
  --mount=type=tmpfs,target=/var/lib/apt/lists \
  --mount=type=tmpfs,target=/var/log \
  apt-get update && apt-get install --no-install-recommends -y \
    bc \
    bison \
    flex \
    gcc \
    gcc-aarch64-linux-gnu \
    gcc-arm-linux-gnueabihf \
    libc6-dev \
    libc6-dev-arm64-cross \
    libssl-dev \
    kmod \
    make \
    xz-utils

ONBUILD ARG arch
ONBUILD ENV $arch true
ONBUILD ENV ARCH ${aarch64:+arm64}${arm:+arm}
ONBUILD ENV CROSS_COMPILE ${aarch64:+aarch64-linux-gnu-}${arm:+arm-linux-gnueabihf-}
ONBUILD ENV KBUILD_OUTPUT /tmp/build
ONBUILD WORKDIR $KBUILD_OUTPUT

FROM --platform=$BUILDPLATFORM alpine:latest AS kernel-src

ARG kernel
WORKDIR /src

# hadolint ignore=DL3020
ADD $kernel /tmp/kernel.tar.gz
RUN tar --strip-components=1 -xf /tmp/kernel.tar.gz
COPY src/kernel .

FROM --platform=$BUILDPLATFORM builder AS kernel

ARG kernel
ENV defconfig ${aarch64:+bcm2711_defconfig}${arm:+bcm2711_defconfig}
ENV image ${aarch64:+Image.gz}${arm:+zImage}
ENV INSTALL_MOD_PATH /media/sd/usr
ENV INSTALL_MOD_STRIP 1

# https://github.com/raspberrypi/linux/blob/HEAD/.github/workflows/kernel-build.yml
RUN \
  --mount=type=bind,from=kernel-src,source=/src,target=/src \
  --mount=type=cache,id=build-$arch-$kernel,target=. \
  make --directory=/src $defconfig \
  && /src/scripts/kconfig/merge_config.sh -m .config /src/qemu.config \
  && make -j 3 --directory=/src olddefconfig $image modules modules_install \
  && find $INSTALL_MOD_PATH/lib/modules -type l -name build -delete \
  && install -D --mode=0644 "arch/$ARCH/boot/$image" /media/sd/boot/firmware/qemu.img

FROM --platform=$BUILDPLATFORM alpine:latest AS uboot-src

ARG uboot
WORKDIR /src

# hadolint ignore=DL3020
ADD $uboot /tmp/uboot.tar.bz2
RUN tar --strip-components=1 -xf /tmp/uboot.tar.bz2
COPY src/uboot .

FROM --platform=$BUILDPLATFORM builder AS uboot

RUN \
  --mount=type=cache,id=apt,target=/var/lib/apt,sharing=locked \
  --mount=type=cache,id=cache,target=/var/cache,sharing=locked \
  --mount=type=tmpfs,target=/var/lib/apt/lists \
  --mount=type=tmpfs,target=/var/log \
  apt-get update && apt-get install --no-install-recommends -y \
    libgnutls28-dev \
    u-boot-tools

ARG uboot
RUN \
  --mount=type=bind,from=uboot-src,source=/src,target=/src \
  --mount=type=cache,id=build-$arch-$uboot,target=. \
  make --directory=/src "qemu_${ARCH}_defconfig" \
  && /src/scripts/kconfig/merge_config.sh -m .config /src/qemu.config \
  && make olddefconfig u-boot.bin \
  && mkimage -A "$ARCH" -T script -C none -d /src/boot.scr boot.scr \
  && truncate -s $((0x200000)) u-boot.bin \
  && cat boot.scr >>u-boot.bin \
  && install -D --mode=0644 u-boot.bin /media/sd/boot/firmware/uboot.img

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
COPY --from=uboot /media/sd /media/sd
COPY src/rootfs /

FROM alpine:latest

ARG arch

ENV RPI_ARCH=$arch

RUN apk add --no-cache \
    expect \
    openssl \
    qemu-system-$arch

COPY --from=rootfs / /

ENTRYPOINT ["rpi"]
