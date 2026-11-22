#!/bin/sh
# Verify the AW1000 factory image checksum and its GitHub build attestation.
set -eu

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[ "$#" -eq 2 ] || die "Usage: $0 <QuantumGrid-AW1000-factory.ubi> <SHA256SUMS>"
IMAGE=$1
MANIFEST=$2
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

[ -f "$IMAGE" ] && [ -r "$IMAGE" ] && [ ! -L "$IMAGE" ] || die "Factory image must be a readable regular, non-symlink file."
[ -f "$MANIFEST" ] && [ -r "$MANIFEST" ] && [ ! -L "$MANIFEST" ] || die "SHA256SUMS must be a readable regular, non-symlink file."

# Reject transfer corruption before making a network request to GitHub.
"$SCRIPT_DIR/verify-aw1000-release-manifest.sh" "$IMAGE" "$MANIFEST"

command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) is required for publisher/build-provenance verification."
gh attestation verify "$IMAGE" \
  --repo NetCore-Technologies/QuantumGrid-OS \
  --signer-workflow NetCore-Technologies/QuantumGrid-OS/.github/workflows/firmware-release.yml
