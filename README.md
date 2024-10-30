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
Sometimes, testing your work on the Raspberry Pi OS is easier without running it on real hardware.
Things like Ansible Playbooks or a Kubernetes cluster in most of the cases can be tested in a virtualized environment.

There are plenty of tutorials and other Docker images running Raspberry Pi OS using QEMU, but all of them extract the OS image at runtime.
Hence, they do not support mounting volumes to share file system.

### Performance Optimization
First off, the Docker image is running QEMU using the `virt` generic virtual platform.
The QEMU developers [claim](https://www.qemu.org/docs/master/system/arm/virt.html) that it is designed for use in virtual machines.
As Docker Desktop is already running on a virtual machine, using the `virt` machine type gives a noticeable performance increase.

Another optimization is using the [9P passthrough filesystem](https://wiki.qemu.org/Documentation/9p).
Compared to mounting a binary image, this filesystem significantly improves I/O throughput.

### Power Management Support
The image has a wrapper that restarts the virtual machine on reboot.
On shutdown, the container is exited with a zero exit code.

If the OS kernel throws a panic, the panic code will be returned.

The reboot support without stopping the container simulates the `cmdline.txt` behavior.
That means the file can be edited, and the Raspberry OS kernel should pick up the updated options after the next reboot, just like the normal Raspberry Pi OS.

## Usage
The container can be started using the [`run`](https://docs.docker.com/reference/cli/docker/container/run/) command:

```bash
docker run -it dokmic/rpi
```

After the boot, it should be possible to log in with the default user `pi` and password `raspberry`.

### SSH
To access the SSH service, the related port should be forwarded to the host system:
```bash
docker run -it -p 2222:22 dokmic/rpi
```

### Custom Command
To override the kernel init command, the `command` argument in the `run` command should be specified:
```bash
docker run dokmic/rpi /bin/bash -c 'echo "hello world"'
```

The image's entry point will also handle and forward the init process' exit code:
```bash
docker run -it dokmic/rpi /bin/bash -c 'exit 123'; echo $?
```

### Custom Parameters
Some of the parameters can be customized via the environment variables (e.g., CPU, RAM, or user credentials):
```bash
docker run -it -e RPI_USER=user -e RPI_PASSWORD=password dokmic/rpi
```

### Stopping Container
The container can be stopped using the [`kill`](https://docs.docker.com/reference/cli/docker/container/kill/) and [`stop`](https://docs.docker.com/reference/cli/docker/container/stop/) commands.

Or within the container using power management commands, e.g.:
```
sudo poweroff
```

### Docker Compose
It is also possible to create a service using Docker Compose:
```yaml
services:
  rpi:
    environment:
      - RPI_CPU
      - RPI_PASSWORD
      - RPI_PORT
      - RPI_RAM
      - RPI_SSH
      - RPI_USER
    image: dokmic/rpi:latest
    ports:
      - 2222:22
```

## Parameters
Name | Default | Description
--- | --- | ---
`RPI_CPU` | `4` | The number of CPU cores.
`RPI_RAM` | `1G` | The amount of available RAM.
`RPI_PORT` | `22/tcp` | The space-separated set of ports forwarded inside the running container (e.g., `22/tcp 80/tcp 53/udp`).
`RPI_SSH` | `true` | The boolean flag enables the SSH server.
`RPI_USER` | `pi` | The predefined user.
`RPI_USER` | `raspberry` | The predefined user password.

## Tags
- `20241022-arm64`, `20241022`, `arm64`, `latest` &mdash; [Raspberry Pi OS Lite 64-bit ARM from 2024-10-22](https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2024-10-28/).
- `20241022-arm`, `arm` &mdash; [Raspberry Pi OS Lite 32-bit ARM from 2024-10-22](https://downloads.raspberrypi.com/raspios_lite_armhf/images/raspios_lite_armhf-2024-10-28/).
- `20240704-arm64`, `20240704` &mdash; [Raspberry Pi OS Lite 64-bit ARM from 2024-07-04](https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2024-07-04/).
- `20240704-arm` &mdash; [Raspberry Pi OS Lite 32-bit ARM from 2024-07-04](https://downloads.raspberrypi.com/raspios_lite_armhf/images/raspios_lite_armhf-2024-07-04/).

## License
[WTFPL 2.0][license]

[license]: http://www.wtfpl.net/
[license-image]: https://img.shields.io/badge/license-WTFPL-blue
