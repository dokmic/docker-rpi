# Raspberry Pi OS Docker Image

[![Version](https://img.shields.io/github/v/release/dokmic/docker-rpi?label=version)](https://github.com/dokmic/docker-rpi/releases/latest)
[![License][license-image]][license]

This is an unofficial Docker image of Raspberry Pi OS running in QEMU.

Unlike others, this image is optimized to run inside a container with volumes support.

## Features

- Optimized for Docker Desktop.
- Volumes support.
- Power Management support.
- `cmdline.txt` support.

## Context

### Motivation

Sometimes, testing your work on the Raspberry Pi OS is much easier without running it on real hardware.
Things like Ansible Playbooks, cloud-init configurations, or a Kubernetes cluster, in most cases, can be tested in a virtualized environment.

There are plenty of tutorials and other Docker images running Raspberry Pi OS using QEMU, but all of them extract the OS image at runtime.
Hence, they do not support mounting volumes to share the filesystem.

### Performance Optimization

First off, the Docker image is running QEMU using the `virt` generic virtual platform.
The QEMU developers [claim](https://www.qemu.org/docs/master/system/arm/virt.html) that it is designed for use in virtual machines.
As Docker Desktop is already running on a virtual machine, using the `virt` machine type gives a noticeable performance increase.

Another optimization is using the [9P passthrough filesystem](https://wiki.qemu.org/Documentation/9p).
Compared to mounting a binary image, this filesystem significantly improves I/O throughput.

### Power Management Support

The hypervisor automatically restarts the virtual machine on reboot.
On shutdown, the container will be exited with a zero exit code.

The image contains a boot-loader that reads `cmdline.txt` and sets the kernel command-line parameters.
That means the file can be edited, and the Raspberry OS kernel should pick up the updated options after the next reboot, just like the normal Raspberry Pi OS.

## Usage

The container can be started using the [`run`](https://docs.docker.com/reference/cli/docker/container/run/) command:

```bash
docker run -it dokmic/rpi
```

Starting from the Trixie release, the default user should be unlocked using the cloud-init configuration:

```yaml
#cloud-config

user:
  lock_passwd: false
  name: pi
  plain_text_passwd: raspberry
```

And then, the `run` command would look something like that:

```bash
docker run -it -v ./user-data:/media/sd/boot/firmware/user-data:ro dokmic/rpi
```

After the boot, it should be possible to log in with the default user `pi` and password `raspberry`.

### SSH

To access the SSH service, the related port should be forwarded to the host system:

```bash
docker run -it -p 2222:22 -e RPI_PORT=22/tcp dokmic/rpi
```

Additionally, the SSH server should be enabled via the cloud-init configuration:

```yaml
#cloud-config

enable_ssh: true
```

### Custom Command

To override the kernel init command, the `command` argument in the `run` command should be specified:

```bash
docker run dokmic/rpi /bin/bash -c 'echo "hello world"'
```

### Custom Parameters

Some of the parameters can be customized via the environment variables (e.g., CPU or RAM):

```bash
docker run -it -e RPI_CPU=2 -e RPI_RAM=4G dokmic/rpi
```

### Shared Volumes

To share data from your host with the running Raspberry Pi OS, the [Docker Volumes](https://docs.docker.com/engine/storage/volumes/) should be mounted below `/media/sd`:

```bash
docker run -it -v .:/media/sd/root/app dokmic/rpi
```

### Stopping Container

The container can be stopped using the [`kill`](https://docs.docker.com/reference/cli/docker/container/kill/) and [`stop`](https://docs.docker.com/reference/cli/docker/container/stop/) commands.

Or within the container using power management commands, e.g.:
```bash
sudo poweroff
```

### Docker Compose

It is also possible to create a service using Docker Compose:

```yaml
services:
  rpi:
    configs:
      - source: user-data
        target: /media/sd/boot/firmware/user-data
    environment:
      - RPI_CPU
      - RPI_PORT
      - RPI_RAM
    image: dokmic/rpi:latest
    ports:
      - 2222:22

configs:
  user-data:
    content: |
      #cloud-config

      enable_ssh: ${RPI_SSH:-false}
      user:
        lock_passwd: false
        name: ${RPI_USER:-pi}
        plain_text_passwd: ${RPI_PASSWORD:-raspberry}
```

## Parameters

Name | Default | Description
--- | --- | ---
`RPI_CPU` | `4` | The number of CPU cores.
`RPI_RAM` | `1G` | The amount of available RAM.
`RPI_PORT` | `22/tcp` | The space-separated set of ports forwarded inside the running container (e.g., `22/tcp 80/tcp 53/udp`).

## Tags

The image tags follow the Raspberry Pi OS release dates and architectures:

- [`latest`](https://hub.docker.com/layers/dokmic/rpi/latest), [`arm64`](https://hub.docker.com/layers/dokmic/rpi/arm64) &mdash; points to the most recent 64-bit ARM build.
- [`arm`](https://hub.docker.com/layers/dokmic/rpi/arm) &mdash; points to the most recent 32-bit ARM build.
- `YYYYMMDD`, `YYYYMMDD-arm64` &mdash; points to the specific 64-bit ARM release.
- `YYYYMMDD-arm` &mdash; points to the specific 32-bit ARM release.

See all the available tags on [Docker Hub](https://hub.docker.com/r/dokmic/rpi/tags).

## License

[WTFPL 2.0][license]

[license]: http://www.wtfpl.net/
[license-image]: https://img.shields.io/badge/license-WTFPL-blue
