#!/bin/sh
# Conservative AW1000 factory-UBI installer. Run from AW1000 initramfs.
set -eu
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'EOF'
Usage:
  sh install-aw1000-ubi.sh <AW1000-factory.ubi> [--manifest <SHA256SUMS>] [--write]

The default mode is a read-only preflight. The release manifest is verified
before any installation checks. --write requires interactive confirmation.
EOF
}
[ "$#" -ge 1 ] || { usage >&2; exit 2; }
IMAGE=$1
shift
WRITE=0
IMAGE_DIR=${IMAGE%/*}
[ "$IMAGE_DIR" != "$IMAGE" ] || IMAGE_DIR=.
MANIFEST="$IMAGE_DIR/SHA256SUMS"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --write)
      [ "$WRITE" -eq 0 ] || die "--write was supplied more than once."
      WRITE=1
      shift
      ;;
    --manifest)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      MANIFEST=$2
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

[ "$(id -u)" -eq 0 ] || die "Run as root from the AW1000 initramfs."
[ -f "$IMAGE" ] && [ -r "$IMAGE" ] && [ ! -L "$IMAGE" ] || die "Image must be a readable regular file, not a symlink."
IMAGE_NAME=${IMAGE##*/}
case "$IMAGE_NAME" in
  *arcadyan_aw1000-squashfs-factory.ubi|QuantumGrid-OS-*-AW1000-squashfs-factory.ubi) ;;
  *) die "Expected a QuantumGrid Arcadyan AW1000 factory UBI image; refusing: $IMAGE_NAME" ;;
esac

# The verifier is shipped beside this installer. A matching release manifest
# is mandatory even for a dry run so no unverified image can reach the write path.
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
[ -f "$SCRIPT_DIR/verify-aw1000-release-manifest.sh" ] || die "Release manifest verifier is missing beside the installer."
sh "$SCRIPT_DIR/verify-aw1000-release-manifest.sh" "$IMAGE" "$MANIFEST"

BOARD_NAME=$(cat /tmp/sysinfo/board_name 2>/dev/null || true)
case "$BOARD_NAME" in arcadyan_aw1000|arcadyan,aw1000) ;; *) die "Board identity is '$BOARD_NAME', not a confirmed Arcadyan AW1000." ;; esac

# An installed system exposes an overlay/squashfs or UBI block root. Only
# RAM-backed initramfs roots are accepted.
ROOT_FS=$(awk '$2 == "/" { print $3; exit }' /proc/mounts)
case "$ROOT_FS" in rootfs|tmpfs|ramfs) ;; *) die "Root filesystem is '$ROOT_FS'. Boot the AW1000 initramfs over UART/TFTP first." ;; esac
if awk '$2 == "/rom" && $3 == "squashfs" { found = 1 } END { exit !found }' /proc/mounts; then
  die "An installed squashfs /rom is mounted. Refusing to flash from an installed system."
fi
if awk '$1 ~ /^\/dev\/ubiblock[0-9]+_[0-9]+$/ { found = 1 } END { exit !found }' /proc/mounts; then
  die "A UBI block device is mounted. Boot the RAM initramfs before installation."
fi

[ -r /proc/mtd ] || die "Cannot read /proc/mtd."
mtd_entry() {
  wanted=$1
  awk -F '[:, ]+' -v name="\\"$wanted\\"" '$4 == name { count++; print $1, $2, $3 } END { if (count != 1) exit 1 }' /proc/mtd
}
ROOTFS_ENTRY=$(mtd_entry rootfs) || die "Could not identify exactly one rootfs partition."
ROOTFS1_ENTRY=$(mtd_entry rootfs_1) || die "Could not identify exactly one rootfs_1 partition."
set -- $ROOTFS_ENTRY
ROOTFS_MTD=$1; ROOTFS_SIZE=$2; ROOTFS_ERASE=$3
set -- $ROOTFS1_ENTRY
ROOTFS1_MTD=$1; ROOTFS1_SIZE=$2; ROOTFS1_ERASE=$3

# This build targets the original 100 MiB AW1000 layout. Refuse expanded
# or modified layouts rather than guessing a partition or erase geometry.
[ "$ROOTFS_MTD" = "mtd18" ] || die "Expected standard rootfs at mtd18; found $ROOTFS_MTD."
[ "$ROOTFS_SIZE" = "06400000" ] && [ "$ROOTFS_ERASE" = "00040000" ] || die "rootfs is not the standard 100 MiB / 256 KiB AW1000 partition."
[ "$ROOTFS1_MTD" = "mtd20" ] || die "Expected untouched rootfs_1 at mtd20; found $ROOTFS1_MTD."
[ "$ROOTFS1_SIZE" = "06400000" ] && [ "$ROOTFS1_ERASE" = "00040000" ] || die "rootfs_1 does not match the standard AW1000 layout."
TARGET="/dev/$ROOTFS_MTD"
[ -c "$TARGET" ] || die "MTD character device is missing: $TARGET"
command -v ubiformat >/dev/null 2>&1 || die "ubiformat is missing; the initramfs must include ubi-utils."
command -v od >/dev/null 2>&1 || die "od is required to inspect the UBI image header."
IMAGE_SIZE=$(wc -c < "$IMAGE" | tr -d '[:space:]')
case "$IMAGE_SIZE" in ''|*[!0-9]*) die "Could not determine image size." ;; esac
[ "$IMAGE_SIZE" -ge 1048576 ] || die "Factory UBI image is unexpectedly small."
[ "$IMAGE_SIZE" -le 104857600 ] || die "Factory UBI image is larger than the standard rootfs partition."
MAGIC=$(dd if="$IMAGE" bs=1 count=4 2>/dev/null | od -An -N4 -tx1 | tr -d '[:space:]')
[ "$MAGIC" = "55424923" ] || die "Invalid UBI image header (expected UBI#)."

printf '\nQuantumGrid AW1000 factory image preflight passed.\n'
printf 'Board:               %s\n' "$BOARD_NAME"
printf 'Boot root:           %s (RAM initramfs)\n' "$ROOT_FS"
printf 'Image:               %s\n' "$IMAGE_NAME"
printf 'Image size:          %s bytes\n' "$IMAGE_SIZE"
printf 'Release manifest:    verified (%s)\n' "$MANIFEST"
printf 'Target:              %s (rootfs, 100 MiB)\n' "$TARGET"
printf 'Preserved partition: /dev/%s (rootfs_1)\n' "$ROOTFS1_MTD"
printf 'No MIBIB, bootloader, Wi-Fi calibration, or rootfs_1 write is requested.\n'

if [ "$WRITE" -ne 1 ]; then
  printf '\nDry run only. No flash writes were made.\n'
  printf 'After reviewing the board and MTD preflight, re-run with --write to request installation.\n'
  exit 0
fi
[ -r /dev/tty ] || die "--write requires an interactive terminal."
printf '\nWARNING: this erases and replaces /dev/mtd18 (rootfs).\n'
printf 'Keep UART connected and maintain stable power. rootfs_1 is not modified.\n'
printf 'Type exactly: ERASE rootfs\n> '
if ! read -r CONFIRMATION < /dev/tty; then die "Could not read confirmation from the terminal."; fi
[ "$CONFIRMATION" = "ERASE rootfs" ] || die "Confirmation did not match. No flash write was made."
printf 'Writing the AW1000 factory UBI image to %s...\n' "$TARGET"
ubiformat "$TARGET" -y -f "$IMAGE" || die "ubiformat failed. Keep UART connected and capture the full output."
sync
printf '\nUBI write completed. Keep UART connected and reboot the router.\n'
printf 'Do not interrupt power during the first boot.\n'
