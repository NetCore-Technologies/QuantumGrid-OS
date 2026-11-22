#!/bin/sh
# Verify the AW1000 factory image checksum and its GitHub build attestation.
set -eu

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[ "$#" -eq 2 ] || die "Usage: $0 <QuantumGrid-OS-v<version>-AW1000-squashfs-factory.ubi> <SHA256SUMS>"
IMAGE=$1
MANIFEST=$2
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

[ -f "$IMAGE" ] && [ -r "$IMAGE" ] && [ ! -L "$IMAGE" ] || die "Factory image must be a readable regular, non-symlink file."
[ -f "$MANIFEST" ] && [ -r "$MANIFEST" ] && [ ! -L "$MANIFEST" ] || die "SHA256SUMS must be a readable regular, non-symlink file."

IMAGE_NAME=${IMAGE##*/}
case "$IMAGE_NAME" in
  QuantumGrid-OS-v*-AW1000-squashfs-factory.ubi) ;;
  *) die "Attestation verification is restricted to versioned QuantumGrid AW1000 release images." ;;
esac
VERSION=${IMAGE_NAME#QuantumGrid-OS-}
VERSION=${VERSION%-AW1000-squashfs-factory.ubi}
printf '%s\n' "$VERSION" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?(\+[A-Za-z0-9.-]+)?$' ||
  die "The factory image filename does not contain a valid release version."
SOURCE_REF="refs/tags/qg-$VERSION"

# Reject transfer corruption before making a network request to GitHub.
"$SCRIPT_DIR/verify-aw1000-release-manifest.sh" "$IMAGE" "$MANIFEST"

command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) is required for publisher/build-provenance verification."
GH_VERSION=$(gh version 2>/dev/null | awk 'NR == 1 && $1 == "gh" && $2 == "version" { print $3 }')
case "$GH_VERSION" in
  ""|*[!0-9.]* ) die "Could not determine a stable GitHub CLI version." ;;
esac
MIN_GH_VERSION=$(printf '%s\n' "2.102.0" "$GH_VERSION" | sort -V | head -n 1)
[ "$MIN_GH_VERSION" = "2.102.0" ] || die "GitHub CLI 2.102.0 or newer is required for exact case-sensitive source-ref verification."
gh attestation verify "$IMAGE" \
  --repo NetCore-Technologies/QuantumGrid-OS \
  --signer-workflow NetCore-Technologies/QuantumGrid-OS/.github/workflows/firmware-release.yml \
  --predicate-type https://slsa.dev/provenance/v1 \
  --source-ref "$SOURCE_REF" \
  --deny-self-hosted-runners
