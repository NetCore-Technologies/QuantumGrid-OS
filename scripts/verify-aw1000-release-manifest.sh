#!/bin/sh
# Verify that an AW1000 UBI or sysupgrade image matches its release SHA-256 manifest.
set -eu

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[ "$#" -eq 2 ] || die "Usage: $0 <AW1000-factory.ubi|AW1000-sysupgrade.bin> <SHA256SUMS>"
IMAGE=$1
MANIFEST=$2

[ -f "$IMAGE" ] && [ -r "$IMAGE" ] && [ ! -L "$IMAGE" ] || die "Image must be a readable regular file, not a symlink."
[ -f "$MANIFEST" ] && [ -r "$MANIFEST" ] && [ ! -L "$MANIFEST" ] || die "SHA256SUMS must be a readable regular file, not a symlink."

IMAGE_NAME=${IMAGE##*/}
case "$IMAGE_NAME" in
  *arcadyan_aw1000-squashfs-factory.ubi|QuantumGrid-OS-*-AW1000-squashfs-factory.ubi) ;;
  *arcadyan_aw1000-squashfs-sysupgrade.bin|QuantumGrid-OS-*-AW1000-squashfs-sysupgrade.bin) ;;
  *) die "Manifest verification is limited to Arcadyan AW1000 factory UBI and sysupgrade images: $IMAGE_NAME" ;;
esac
case "$IMAGE_NAME" in
  *[!A-Za-z0-9._+-]*) die "Image filename contains characters not supported by the release manifest verifier." ;;
esac

command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required; refusing to skip release integrity verification."

EXPECTED_SHA=$(awk -v name="$IMAGE_NAME" '
  $2 == name || $2 == "*" name {
    if ($1 ~ /^[[:xdigit:]]+$/ && length($1) == 64) {
      count++
      digest = tolower($1)
    }
  }
  END {
    if (count != 1) exit 1
    print digest
  }
' "$MANIFEST") || die "SHA256SUMS must contain exactly one valid SHA-256 entry for $IMAGE_NAME."

ACTUAL_LINE=$(sha256sum "$IMAGE") || die "Could not calculate the image SHA-256 digest."
ACTUAL_SHA=$(printf '%s\n' "$ACTUAL_LINE" | awk 'NR == 1 { print tolower($1) }')
[ "${#ACTUAL_SHA}" -eq 64 ] || die "sha256sum returned an invalid digest."

if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
  die "SHA-256 mismatch for $IMAGE_NAME. Do not flash this image."
fi

printf 'Verified release SHA-256: %s  %s\n' "$ACTUAL_SHA" "$IMAGE_NAME"
