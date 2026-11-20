#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT/scripts/install-aw1000-ubi.sh"
test -s "$INSTALLER"
sh -n "$INSTALLER"
grep -Fq 'arcadyan_aw1000|arcadyan,aw1000' "$INSTALLER"
grep -Fq 'ROOT_FS=$(awk' "$INSTALLER"
grep -Fq 'rootfs|tmpfs|ramfs' "$INSTALLER"
grep -Fq 'ROOTFS_SIZE" = "06400000"' "$INSTALLER"
grep -Fq 'ROOTFS_ERASE" = "00040000"' "$INSTALLER"
grep -Fq 'ROOTFS1_MTD" = "mtd20"' "$INSTALLER"
grep -Fq 'ubiformat "$TARGET" -y -f "$IMAGE"' "$INSTALLER"
grep -Fq 'ERASE rootfs' "$INSTALLER"
grep -Fq 'Dry run only. No flash writes were made.' "$INSTALLER"
if sh "$INSTALLER" >/dev/null 2>&1; then
  echo "ERROR: installer accepted a missing image argument." >&2
  exit 1
fi
echo "AW1000 UBI installer preflight contract checks passed."
