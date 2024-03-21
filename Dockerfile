# syntax=docker/dockerfile:1.3-labs

FROM ubuntu:latest AS kernel

ARG kernel

ENV ARCH=arm64
ENV CROSS_COMPILE=aarch64-linux-gnu-
ENV dependencies="\
  bc \
  bison \
  flex \
  gcc \
  gcc-aarch64-linux-gnu \
  libc6-dev \
  libc6-dev-arm64-cross \
  libssl-dev \
  make \
"

# hadolint ignore=DL3020
ADD $kernel /kernel.tar.gz

WORKDIR /tmp/kernel

# https://github.com/raspberrypi/linux/blob/HEAD/.github/workflows/kernel-build.yml
# https://wiki.qemu.org/Documentation/9psetup#Preparation
# https://superuser.com/a/1301973
RUN --mount=type=cache,id=apt,target=/var/lib/apt \
    --mount=type=cache,id=build,target=/tmp/build \
    --mount=type=cache,id=cache,target=/var/cache \
    --mount=type=tmpfs,target=/var/log \
  apt-get update \
  && apt-get install -y --no-install-recommends $dependencies \
  && tar --strip-components=1 -xzf /kernel.tar.gz \
  && make O=/tmp/build defconfig \
  && scripts/config --file /tmp/build/.config \
    --set-val CONFIG_WERROR y \
    --set-val CONFIG_9P_FS y \
    --set-val CONFIG_9P_FS_POSIX_ACL y \
    --set-val CONFIG_9P_FS_SECURITY y \
    --set-val CONFIG_NETWORK_FILESYSTEMS y \
    --set-val CONFIG_NET_9P y \
    --set-val CONFIG_NET_9P_VIRTIO y \
    --set-val CONFIG_PCI y \
    --set-val CONFIG_PCI_HOST_COMMON y \
    --set-val CONFIG_PCI_HOST_GENERIC y \
    --set-val CONFIG_VIRTIO_PCI y \
    --set-val CONFIG_VIRTIO_BLK y \
    --set-val CONFIG_VIRTIO_NET y \
  && make O=/tmp/build -j 3 Image.gz \
  && apt-get purge -y $dependencies \
  && apt-get autoremove --purge -y \
  && rm -rf /tmp/kernel \
  && mkdir -p /media/sd/boot/firmware \
  && cp /tmp/build/arch/$ARCH/boot/Image.gz /media/sd/boot/firmware/kernel8.img

FROM alpine:latest AS image

ARG image

# hadolint ignore=DL3020
ADD $image /sd.img.xz

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# hadolint ignore=DL3001
RUN --security=insecure \
  unxz -ck /sd.img.xz >/tmp/sd.img \
  && apk add --no-cache --virtual=.tools \
    jq \
    sfdisk \
  && mkdir -p /tmp/sd \
  && mount -o loop,offset="$(sfdisk -J /tmp/sd.img | jq '.partitiontable.sectorsize * .partitiontable.partitions[1].start')" /tmp/sd.img /tmp/sd \
  && mount -o loop,offset="$(sfdisk -J /tmp/sd.img | jq '.partitiontable.sectorsize * .partitiontable.partitions[0].start')" /tmp/sd.img /tmp/sd/boot/firmware \
  && cp -pr /tmp/sd /media/sd \
  && umount /tmp/sd/boot/firmware /tmp/sd \
  && rm -rf /tmp/sd /tmp/sd.img \
  && apk del .tools

RUN rm \
  /media/sd/etc/init.d/resize2fs_once \
  /media/sd/etc/systemd/system/multi-user.target.wants/rpi-eeprom-update.service

FROM scratch AS rootfs

COPY --from=image /media/sd /media/sd
COPY --from=kernel /media/sd /media/sd
COPY /rootfs /

FROM alpine:latest

RUN apk add --no-cache \
  expect \
  openssl \
  qemu-system-aarch64

COPY --from=rootfs / /

ENV RPI_PORT 22/tcp
ENV RPI_SSH true
ENV RPI_USER pi
ENV RPI_PASSWORD raspberry

ENTRYPOINT ["rpi"]
