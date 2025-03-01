variable "DOCKERHUB_REPOSITORY" {}

variable "matrix" {
  default = []
}

group "default" {
  targets = ["rpi"]
}

target "rpi" {
  name = item.name

  matrix = {
    item = matrix
  }

  args = {
    arch = item.arch
    image = item.image
    kernel = item.kernel
    uboot = item.uboot
  }

  cache-from = [
    "type=registry,ref=${DOCKERHUB_REPOSITORY}:${item.cache}"
  ]

  cache-to = [
    "type=registry,ref=${DOCKERHUB_REPOSITORY}:${item.cache},mode=max"
  ]

  entitlements = ["security.insecure"]

  platforms = [
    "linux/amd64",
    "linux/arm64",
    "linux/arm/v7",
    "linux/i386",
  ]

  tags = [for tag in item.tags : "${DOCKERHUB_REPOSITORY}:${tag}"]
}
