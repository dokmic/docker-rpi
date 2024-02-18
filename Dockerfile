FROM ubuntu:latest AS image

ARG image

# hadolint ignore=DL3020
ADD $image /sd.img.xz

RUN --mount=type=cache,id=apt,target=/var/cache/apt \
    --mount=type=cache,id=debconf,target=/var/cache/debconf \
    --mount=type=cache,id=lib,target=/var/lib/apt \
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

FROM alpine:latest

COPY --from=image /sd /sd
