# syntax=docker/dockerfile:1.3-labs

FROM --platform=$BUILDPLATFORM alpine:latest AS kernel-src

ARG kernel
WORKDIR /src

# hadolint ignore=DL3020
ADD $kernel /tmp/kernel.tar.gz
RUN tar --strip-components=1 -xf /tmp/kernel.tar.gz
COPY src/kernel .

FROM --platform=$BUILDPLATFORM ubuntu:latest AS kernel

RUN --mount=type=cache,id=apt,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,id=cache,target=/var/cache,sharing=locked \
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

ARG arch
ARG kernel

ENV arch_aarch64=arm64
ENV arch_arm=arm
ENV arch_ref=arch_${arch}

ENV defconfig_aarch64=bcm2711_defconfig
ENV defconfig_arm=bcm2711_defconfig
ENV defconfig=defconfig_${arch}

ENV cross_compile_aarch64=aarch64-linux-gnu-
ENV cross_compile_arm=arm-linux-gnueabihf-
ENV cross_compile=cross_compile_${arch}

ENV image_aarch64=Image.gz
ENV image_arm=zImage
ENV image=image_${arch}

ENV INSTALL_MOD_PATH=/media/sd/usr
ENV KBUILD_OUTPUT=/tmp/build

WORKDIR $KBUILD_OUTPUT

SHELL ["/bin/bash", "-ec"]

# https://github.com/raspberrypi/linux/blob/HEAD/.github/workflows/kernel-build.yml
# hadolint ignore=SC2086
RUN \
  --mount=type=bind,from=kernel-src,source=/src,target=/src \
  --mount=type=cache,id=build-$arch-$kernel,target=. \
<<EOF
  export ARCH=${!arch_ref}
  export CROSS_COMPILE=${!cross_compile}

  make --directory=/src ${!defconfig}
  /src/scripts/kconfig/merge_config.sh -m .config /src/qemu.config
  make -j 3 --directory=/src olddefconfig ${!image} modules modules_install

  find $INSTALL_MOD_PATH/lib/modules -type l -name build -delete
  install -D --mode=0644 arch/$ARCH/boot/${!image} /media/sd/boot/firmware/qemu.img
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
