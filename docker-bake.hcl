variable "IMAGE" {}

variable "KERNEL" {}

variable "REPOSITORY" {}

variable "TAG" {}

group "default" {
  targets = ["rpi"]
}

target "rpi" {
  name = item.arch

  matrix = {
    item = [
      {
        arch = "arm"
        tags = ["${TAG}-arm", "arm"]
      },
      {
        arch = "aarch64"
        tags = ["${TAG}-arm64", "arm64", "${TAG}", "latest"]
      },
    ]
  }

  args = {
    arch = item.arch
    image = IMAGE
    kernel = KERNEL
  }

  cache-from = [
    "type=registry,ref=${REPOSITORY}:${item.arch}-cache"
  ]

  cache-to = [
    "type=registry,ref=${REPOSITORY}:${item.arch}-cache,mode=max"
  ]

  entitlements = ["security.insecure"]

  platforms = [
    "linux/amd64",
    "linux/arm64",
    "linux/arm/v7",
    "linux/i386",
  ]

  tags = [for tag in item.tags : "${REPOSITORY}:${tag}"]
}
