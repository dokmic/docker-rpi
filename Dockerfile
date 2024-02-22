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
  && mkdir -p /sd/boot/firmware \
  && cp /tmp/build/arch/$ARCH/boot/Image.gz /sd/boot/firmware/kernel8.img

FROM ubuntu:latest AS image

ARG image

# hadolint ignore=DL3020
ADD $image /sd.img.xz

RUN --mount=type=cache,id=apt,target=/var/lib/apt \
    --mount=type=cache,id=cache,target=/var/cache \
    --mount=type=tmpfs,target=/var/log \
  apt-get update \
  && apt-get install -y --no-install-recommends 7zip \
  && 7z x -o/tmp /sd.img.xz \
  && 7z x -o/tmp /tmp/sd.img 0.fat 1.img \
  && 7z x -o/sd/boot/firmware /tmp/0.fat \
  && 7z x -o/sd -snld /tmp/1.img \
  && apt-get purge -y 7zip \
  && apt-get autoremove -y \
  && rm -rf '/sd/[SYS]' /tmp/sd.img /tmp/0.fat /tmp/1.img \
  && find /sd -lname '/sd/*' -exec sh -c ' \
    link="$1"; \
    ln --force --no-dereference --symbolic "$( \
      realpath --no-symlinks --relative-to="$(dirname "$link")" "$(readlink "$link")" \
    )" "$link" \
  ' shell {} \;

COPY --from=kernel /sd /sd

FROM alpine:latest

RUN apk add --no-cache qemu-system-aarch64

COPY --from=image /sd /sd
COPY /rootfs /

CMD ["rpi"]
