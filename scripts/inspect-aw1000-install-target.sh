#!/bin/sh
# Read-only AW1000 install-target inspection. This script never writes flash,
# UCI configuration, bootloader variables, or router settings.
set -eu

INSPECT_ROOT=${QG_INSPECT_ROOT:-}
if [ -n "$INSPECT_ROOT" ]; then
  case "$INSPECT_ROOT" in
    /*) ;;
    *) printf 'ERROR: QG_INSPECT_ROOT must be an absolute path.\n' >&2; exit 2 ;;
  esac
fi

root_path() {
  if [ -n "$INSPECT_ROOT" ]; then
    printf '%s/%s\n' "${INSPECT_ROOT%/}" "$1"
  else
    printf '/%s\n' "$1"
  fi
}

BOARD_FILE=$(root_path tmp/sysinfo/board_name)
MTD_FILE=$(root_path proc/mtd)
MOUNTS_FILE=$(root_path proc/mounts)

read_value() {
  file=$1
  [ -r "$file" ] || return 1
  IFS= read -r value < "$file" || [ -n "${value:-}" ]
  printf '%s' "${value:-}"
}

has_binary() {
  name=$1
  if [ -n "$INSPECT_ROOT" ]; then
    for candidate in "sbin/$name" "usr/sbin/$name" "bin/$name" "usr/bin/$name"; do
      [ -x "$(root_path "$candidate")" ] && return 0
    done
    return 1
  fi
  command -v "$name" >/dev/null 2>&1
}

mtd_entry() {
  wanted=$1
  awk -F '[:, ]+' -v wanted="$wanted" '
    $4 == "\"" wanted "\"" {
      count++
      entry = $1 " " $2 " " $3
    }
    END {
      if (count != 1) exit 1
      print entry
    }
  ' "$MTD_FILE"
}

printf 'QuantumGrid AW1000 install-target inspection (READ ONLY)\n'
printf 'No flash, bootloader, service, or router settings are changed.\n\n'

BOARD_NAME=$(read_value "$BOARD_FILE" 2>/dev/null || true)
ROOT_FS=$(awk '$2 == "/" { print $3; exit }' "$MOUNTS_FILE" 2>/dev/null || true)
[ -n "$BOARD_NAME" ] || BOARD_NAME="unavailable"
[ -n "$ROOT_FS" ] || ROOT_FS="unavailable"

case "$BOARD_NAME" in
  arcadyan_aw1000|arcadyan,aw1000) BOARD_OK=1 ;;
  *) BOARD_OK=0 ;;
esac

printf 'Board identity: %s\n' "$BOARD_NAME"
printf 'Root filesystem: %s\n' "$ROOT_FS"

printf 'MTD partition map (from /proc/mtd):\n'
if [ -r "$MTD_FILE" ]; then
  sed -n '1,65p' "$MTD_FILE"
else
  printf 'unavailable\n'
fi
printf '\n'

ROOTFS_ENTRY=$(mtd_entry rootfs 2>/dev/null || true)
ROOTFS1_ENTRY=$(mtd_entry rootfs_1 2>/dev/null || true)
ROOTFS_OK=0
ROOTFS1_OK=0

if [ -n "$ROOTFS_ENTRY" ]; then
  set -- $ROOTFS_ENTRY
  ROOTFS_MTD=$1
  ROOTFS_SIZE=$2
  ROOTFS_ERASE=$3
  printf 'rootfs: %s size=%s erase=%s\n' "$ROOTFS_MTD" "$ROOTFS_SIZE" "$ROOTFS_ERASE"
  if [ "$ROOTFS_MTD" = "mtd18" ] && [ "$ROOTFS_SIZE" = "06400000" ] && [ "$ROOTFS_ERASE" = "00040000" ]; then
    ROOTFS_OK=1
  fi
else
  printf 'rootfs: missing or ambiguous\n'
fi

if [ -n "$ROOTFS1_ENTRY" ]; then
  set -- $ROOTFS1_ENTRY
  ROOTFS1_MTD=$1
  ROOTFS1_SIZE=$2
  ROOTFS1_ERASE=$3
  printf 'rootfs_1: %s size=%s erase=%s\n' "$ROOTFS1_MTD" "$ROOTFS1_SIZE" "$ROOTFS1_ERASE"
  if [ "$ROOTFS1_MTD" = "mtd20" ] && [ "$ROOTFS1_SIZE" = "06400000" ] && [ "$ROOTFS1_ERASE" = "00040000" ]; then
    ROOTFS1_OK=1
  fi
else
  printf 'rootfs_1: missing or ambiguous\n'
fi

if [ "$ROOTFS_OK" -eq 1 ] && [ "$ROOTFS1_OK" -eq 1 ]; then
  LAYOUT_OK=1
  printf 'Standard AW1000 MTD geometry: MATCH (mtd18/mtd20, 100 MiB, 256 KiB erase)\n'
else
  LAYOUT_OK=0
  printf 'Standard AW1000 MTD geometry: NO MATCH / UNKNOWN\n'
fi

ROM_SQUASHFS=0
UBIBLOCK_MOUNTED=0
if awk '$2 == "/rom" && $3 == "squashfs" { found = 1 } END { exit !found }' "$MOUNTS_FILE" 2>/dev/null; then
  ROM_SQUASHFS=1
fi
if awk '$1 ~ /^\/dev\/ubiblock[0-9]+_[0-9]+$/ { found = 1 } END { exit !found }' "$MOUNTS_FILE" 2>/dev/null; then
  UBIBLOCK_MOUNTED=1
fi

case "$ROOT_FS" in
  rootfs|tmpfs|ramfs)
    if [ "$ROM_SQUASHFS" -eq 0 ] && [ "$UBIBLOCK_MOUNTED" -eq 0 ]; then
      RAM_BOOT=1
    else
      RAM_BOOT=0
    fi
    ;;
  *) RAM_BOOT=0 ;;
esac

if [ "$RAM_BOOT" -eq 1 ]; then
  printf 'Temporary initramfs boot checks: MATCH\n'
else
  printf 'Temporary initramfs boot checks: NOT MATCHED (boot the matching AW1000 initramfs before installer preflight)\n'
fi

for tool in ubiformat sha256sum od; do
  if has_binary "$tool"; then
    printf 'Required tool %s available\n' "$tool"
  else
    printf 'Required tool %s MISSING\n' "$tool"
  fi
done

printf '\n'
if [ "$BOARD_OK" -ne 1 ]; then
  printf 'RESULT: STOP — board identity is not a confirmed Arcadyan AW1000.\n'
elif [ "$LAYOUT_OK" -ne 1 ]; then
  printf 'RESULT: STOP — partition geometry is not the supported standard AW1000 layout. Do not flash with the current installer.\n'
elif [ "$RAM_BOOT" -ne 1 ]; then
  printf 'RESULT: INSPECTION ONLY — board and standard geometry match, but this is not the required RAM initramfs environment.\n'
else
  MISSING_TOOL=0
  for tool in ubiformat sha256sum od; do
    has_binary "$tool" || MISSING_TOOL=1
  done
  if [ "$MISSING_TOOL" -eq 1 ]; then
    printf 'RESULT: INSPECTION ONLY — required installer tools are missing.\n'
  else
    printf 'RESULT: TARGET CHECKS MATCH — still run install-aw1000-ubi.sh without --write and verify its full image/manifest preflight.\n'
  fi
fi

printf '\nThis inspection is not an installer and does not prove an image is flashable.\n'
