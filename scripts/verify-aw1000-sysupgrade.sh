#!/usr/bin/env bash
set -Eeuo pipefail
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
usage() { printf 'Usage: %s <AW1000-squashfs-sysupgrade.bin>\n' "${0##*/}"; }
[[ $# -eq 1 ]] || { usage >&2; exit 2; }
IMAGE=$1
[[ -f "$IMAGE" && -r "$IMAGE" && ! -L "$IMAGE" ]] || die "Image must be a readable regular file, not a symlink."
IMAGE_NAME=${IMAGE##*/}
case "$IMAGE_NAME" in
  *arcadyan_aw1000-squashfs-sysupgrade.bin|QuantumGrid-OS-*-AW1000-squashfs-sysupgrade.bin) ;;
  *) die "Expected an Arcadyan AW1000 squashfs sysupgrade image; refusing: $IMAGE_NAME" ;;
esac
command -v tar >/dev/null 2>&1 || die "tar is required to inspect the sysupgrade archive."
command -v stat >/dev/null 2>&1 || die "stat is required to inspect the sysupgrade image."
IMAGE_SIZE=$(stat -c '%s' -- "$IMAGE")
[[ "$IMAGE_SIZE" =~ ^[0-9]+$ ]] || die "Could not determine image size."
(( IMAGE_SIZE >= 1048576 )) || die "Sysupgrade image is unexpectedly small ($IMAGE_SIZE bytes)."
(( IMAGE_SIZE <= 104857600 )) || die "Sysupgrade image exceeds the standard AW1000 100 MiB rootfs partition."
LISTING=$(mktemp "${TMPDIR:-/tmp}/qg-aw1000-sysupgrade.XXXXXX")
trap 'rm -f "$LISTING"' EXIT
tar -tf "$IMAGE" > "$LISTING" || die "Image is not a readable OpenWrt sysupgrade tar archive."
CONTROL_COUNT=0
KERNEL_COUNT=0
ROOT_COUNT=0
while IFS= read -r MEMBER; do
  case "$MEMBER" in
    sysupgrade-arcadyan_aw1000/|sysupgrade-arcadyan_aw1000) ;;
    sysupgrade-arcadyan_aw1000/CONTROL) CONTROL_COUNT=$((CONTROL_COUNT + 1)) ;;
    sysupgrade-arcadyan_aw1000/kernel) KERNEL_COUNT=$((KERNEL_COUNT + 1)) ;;
    sysupgrade-arcadyan_aw1000/root) ROOT_COUNT=$((ROOT_COUNT + 1)) ;;
    *) die "Unexpected sysupgrade archive member: $MEMBER" ;;
  esac
done < "$LISTING"
[[ "$CONTROL_COUNT" -eq 1 ]] || die "Archive must contain exactly one AW1000 CONTROL file."
[[ "$KERNEL_COUNT" -eq 1 ]] || die "Archive must contain exactly one AW1000 kernel image."
[[ "$ROOT_COUNT" -eq 1 ]] || die "Archive must contain exactly one AW1000 root filesystem."
CONTROL=$(tar -xOf "$IMAGE" sysupgrade-arcadyan_aw1000/CONTROL) || die "Could not read the sysupgrade CONTROL file."
BOARD_LINES=$(printf '%s\n' "$CONTROL" | grep -c '^BOARD=' || true)
[[ "$BOARD_LINES" -eq 1 ]] || die "CONTROL must declare exactly one board identity."
printf '%s\n' "$CONTROL" | grep -Fxq 'BOARD=arcadyan_aw1000' || die "Sysupgrade archive board identity is not arcadyan_aw1000."
for MEMBER in CONTROL kernel root; do
  MEMBER_SIZE=$(tar -xOf "$IMAGE" "sysupgrade-arcadyan_aw1000/$MEMBER" | wc -c | tr -d '[:space:]')
  [[ "$MEMBER_SIZE" =~ ^[0-9]+$ ]] && (( MEMBER_SIZE > 0 )) || die "Sysupgrade archive member is empty: $MEMBER"
done
printf 'Validated AW1000 sysupgrade archive: %s (%s bytes)\n' "$IMAGE_NAME" "$IMAGE_SIZE"
printf 'Board metadata: arcadyan_aw1000; archive members: CONTROL, kernel, root\n'
