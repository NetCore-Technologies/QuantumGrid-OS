#!/bin/sh
# Verify an AW1000 persistent firmware checksum and its GitHub build attestation.
set -eu

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[ "$#" -eq 2 ] || die "Usage: $0 <versioned-AW1000-factory.ubi|versioned-AW1000-sysupgrade.bin> <SHA256SUMS>"
IMAGE=$1
MANIFEST=$2
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

[ -f "$IMAGE" ] && [ -r "$IMAGE" ] && [ ! -L "$IMAGE" ] || die "Firmware image must be a readable regular, non-symlink file."
[ -f "$MANIFEST" ] && [ -r "$MANIFEST" ] && [ ! -L "$MANIFEST" ] || die "SHA256SUMS must be a readable regular, non-symlink file."

IMAGE_NAME=${IMAGE##*/}
case "$IMAGE_NAME" in
  QuantumGrid-OS-v*-AW1000-squashfs-factory.ubi)
    VERSION=${IMAGE_NAME#QuantumGrid-OS-}
    VERSION=${VERSION%-AW1000-squashfs-factory.ubi}
    ;;
  QuantumGrid-OS-v*-AW1000-squashfs-sysupgrade.bin)
    VERSION=${IMAGE_NAME#QuantumGrid-OS-}
    VERSION=${VERSION%-AW1000-squashfs-sysupgrade.bin}
    ;;
  *) die "Attestation verification is restricted to versioned QuantumGrid AW1000 firmware images." ;;
esac
printf '%s\n' "$VERSION" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?(\+[A-Za-z0-9.-]+)?$' ||
  die "Firmware image filename does not contain a valid release version."
SOURCE_REF="refs/tags/qg-$VERSION"

# Reject transfer corruption before making a network request to GitHub.
sh "$SCRIPT_DIR/verify-aw1000-release-manifest.sh" "$IMAGE" "$MANIFEST"

command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) is required for publisher/build-provenance verification."
GH_VERSION=$(gh version 2>/dev/null | awk 'NR == 1 && $1 == "gh" && $2 == "version" { print $3 }')
printf '%s\n' "$GH_VERSION" | awk -F. '
  NF != 3 || $1 !~ /^[0-9]+$/ || $2 !~ /^[0-9]+$/ || $3 !~ /^[0-9]+$/ { exit 1 }
  {
    if (($1 + 0) > 2 ||
        (($1 + 0) == 2 && ($2 + 0) > 102) ||
        (($1 + 0) == 2 && ($2 + 0) == 102 && ($3 + 0) >= 0)) exit 0
    exit 1
  }
' || die "GitHub CLI 2.102.0 or newer is required for exact case-sensitive source-ref verification."
gh attestation verify "$IMAGE" \
  --repo NetCore-Technologies/QuantumGrid-OS \
  --signer-workflow NetCore-Technologies/QuantumGrid-OS/.github/workflows/firmware-release.yml \
  --predicate-type https://slsa.dev/provenance/v1 \
  --source-ref "$SOURCE_REF" \
  --deny-self-hosted-runners
