FROM alpine:latest

ARG image

# hadolint ignore=DL3020
ADD $image /sd.img.xz

RUN apk add --no-cache --virtual=.tools \
    7zip \
  && unxz -kc /sd.img.xz >/tmp/sd.img \
  && 7z x -o/tmp /tmp/sd.img 0.fat 1.img \
  && 7z x -o/sd/boot/firmware /tmp/0.fat \
  && 7z x -o/sd -snld /tmp/1.img \
  && rm /tmp/sd.img /tmp/0.fat /tmp/1.img \
  && apk del --purge .tools
