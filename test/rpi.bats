#!/usr/bin/env bats

bats_load_library bats-assert
bats_load_library bats-file
bats_load_library bats-support

setup_file() {
  PATH="$BATS_SUITE_TMPDIR:src/rootfs/usr/local/bin:$PATH"

  mock openssl 'cat -'
  stub qemu-system-aarch64
}

setup() {
  export RPI_ROOT="$BATS_TEST_TMPDIR"
  mkdir -p $RPI_ROOT/boot/firmware
}

mock() {
  local mock="$BATS_SUITE_TMPDIR/$1"
  shift

  printf "#!/bin/sh\n" >$mock
  printf "%s\n" "$@" >>$mock
  chmod +x $mock
}

stub() {
  mock "$1" 'printf '"'%s\n'"' "$(basename "$0")" "$@"'
}

@test "overrides root path" {
  run rpi

  assert_output --regexp "-virtfs[[:space:]]+local,id=boot,[^[:space:]]+,path=$RPI_ROOT/boot/firmware,"
  assert_output --regexp "-virtfs[[:space:]]+local,id=cache,[^[:space:]]+,path=$RPI_ROOT/var/cache,"
  assert_output --regexp "-virtfs[[:space:]]+local,id=root,[^[:space:]]+,path=$RPI_ROOT,"
  assert_output --regexp "-append[[:space:]]+extends=$RPI_ROOT/boot/firmware/cmdline.txt[[:space:]]"
}

@test "uses default parameters" {
  run rpi

  assert_line --index 0 --partial "qemu-system-aarch64"
  assert_output --regexp "-cpu[[:space:]]+cortex-a72[[:space:]]"
  assert_output --regexp "-m[[:space:]]+1G[[:space:]]"
  assert_output --regexp "-smp[[:space:]]+4[[:space:]]"
  assert_output --regexp "-netdev[[:space:]]+user,id=net0,hostfwd=tcp::22-:22[[:space:]]"
}

@test "uses 32-bit ARM when specified" {
  export RPI_ARCH=arm
  stub qemu-system-arm
  run rpi

  assert_line --index 0 --partial "qemu-system-arm"
  refute_line --partial "-cpu"
}

@test "uses custom RAM size when specified" {
  export RPI_RAM=512M
  run rpi

  assert_output --regexp "-m[[:space:]]+512M[[:space:]]"
}

@test "uses custom CPU cores when specified" {
  export RPI_CPU=2
  run rpi

  assert_output --regexp "-smp[[:space:]]+2[[:space:]]"
}

@test "uses custom ports when specified" {
  export RPI_PORT="80/tcp 443/tcp 1194/udp"
  run rpi

  assert_output --regexp "-netdev[[:space:]]+user,id=net0,hostfwd=tcp::80-:80,hostfwd=tcp::443-:443,hostfwd=udp::1194-:1194[[:space:]]"
}

@test "appends custom kernel parameters when specified" {
  export RPI_CMDLINE="console=serial0,115200 root=/dev/mmcblk0p2"
  run rpi /bin/bash -c "echo Test"

  assert_line --regexp "^extends=$RPI_ROOT/boot/firmware/cmdline.txt[[:space:]].*[[:space:]]init=\"/bin/bash\" \"-c\" \"echo Test\"[[:space:]]*$"
}

@test "uses the default user and password" {
  run rpi

  assert_file_contains "$BATS_TEST_TMPDIR/boot/firmware/userconf.txt" "pi:raspberry"
}

@test "uses custom user and password when specified" {
  export RPI_USER=admin
  export RPI_PASSWORD=something
  run rpi

  assert_file_contains "$BATS_TEST_TMPDIR/boot/firmware/userconf.txt" "admin:something"
}

@test "creates an SSH file by default" {
  run rpi

  assert_file_empty "$BATS_TEST_TMPDIR/boot/firmware/ssh.txt"
}

@test "does not create an SSH file when disabled" {
  export RPI_SSH=0
  run rpi

  assert_file_not_exists "$BATS_TEST_TMPDIR/boot/firmware/ssh.txt"
}
