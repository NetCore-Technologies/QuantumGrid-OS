#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSPECTOR="$ROOT/scripts/inspect-aw1000-install-target.sh"

test -s "$INSPECTOR"
sh -n "$INSPECTOR"
bash -n "$INSPECTOR"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/proc" "$TEST_ROOT/tmp/sysinfo" "$TEST_ROOT/sbin"

printf 'arcadyan_aw1000\n' > "$TEST_ROOT/tmp/sysinfo/board_name"
cat > "$TEST_ROOT/proc/mtd" <<'MTD'
dev:    size   erasesize  name
mtd18: 06400000 00040000 "rootfs"
mtd20: 06400000 00040000 "rootfs_1"
MTD

contains() {
  local output=$1 expected=$2 label=$3
  if ! grep -Fq "$expected" <<< "$output"; then
    printf 'ERROR: %s did not contain expected output: %s\n' "$label" "$expected" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

# Installed NoobWRT/OpenWrt roots are inspection-only even when MTD geometry matches.
cat > "$TEST_ROOT/proc/mounts" <<'MOUNTS'
ubi0:rootfs /rom squashfs ro,relatime 0 0
overlay / overlay rw,noatime 0 0
MOUNTS
OUTPUT="$(QG_INSPECT_ROOT="$TEST_ROOT" sh "$INSPECTOR")"
contains "$OUTPUT" "Standard AW1000 MTD geometry: MATCH" "installed root"
contains "$OUTPUT" "Temporary initramfs boot checks: NOT MATCHED" "installed root"
contains "$OUTPUT" "RESULT: INSPECTION ONLY" "installed root"

# RAM-boot checks plus the required tool set are necessary for the target-check result.
cat > "$TEST_ROOT/proc/mounts" <<'MOUNTS'
rootfs / rootfs rw 0 0
MOUNTS
for tool in ubiformat sha256sum od; do
  printf '#!/bin/sh\nexit 99\n' > "$TEST_ROOT/sbin/$tool"
  chmod 755 "$TEST_ROOT/sbin/$tool"
done
OUTPUT="$(QG_INSPECT_ROOT="$TEST_ROOT" sh "$INSPECTOR")"
contains "$OUTPUT" "Temporary initramfs boot checks: MATCH" "RAM initramfs"
contains "$OUTPUT" "RESULT: TARGET CHECKS MATCH" "RAM initramfs"
contains "$OUTPUT" "This inspection is not an installer" "RAM initramfs"

# An unexpected partition index must never be described as a supported layout.
sed 's/mtd18: 06400000 00040000 "rootfs"/mtd22: 06400000 00040000 "rootfs"/' \
  "$TEST_ROOT/proc/mtd" > "$TEST_ROOT/proc/mtd.changed"
cp "$TEST_ROOT/proc/mtd.changed" "$TEST_ROOT/proc/mtd"
OUTPUT="$(QG_INSPECT_ROOT="$TEST_ROOT" sh "$INSPECTOR")"
contains "$OUTPUT" "Standard AW1000 MTD geometry: NO MATCH / UNKNOWN" "expanded layout"
contains "$OUTPUT" "RESULT: STOP — partition geometry" "expanded layout"

# Incorrect board identity is always a hard stop.
printf 'other_device\n' > "$TEST_ROOT/tmp/sysinfo/board_name"
OUTPUT="$(QG_INSPECT_ROOT="$TEST_ROOT" sh "$INSPECTOR")"
contains "$OUTPUT" "RESULT: STOP — board identity" "wrong board"

# A squashfs /rom or mounted ubiblock is not accepted as a RAM initramfs root.
printf 'arcadyan_aw1000\n' > "$TEST_ROOT/tmp/sysinfo/board_name"
sed 's#rootfs / rootfs rw 0 0#rootfs / rootfs rw 0 0\n/dev/ubiblock0_0 /rom squashfs ro 0 0#' \
  "$TEST_ROOT/proc/mounts" > "$TEST_ROOT/proc/mounts.ubiblock"
cp "$TEST_ROOT/proc/mounts.ubiblock" "$TEST_ROOT/proc/mounts"
OUTPUT="$(QG_INSPECT_ROOT="$TEST_ROOT" sh "$INSPECTOR")"
contains "$OUTPUT" "Temporary initramfs boot checks: NOT MATCHED" "mounted ubiblock"
contains "$OUTPUT" "RESULT: INSPECTION ONLY" "mounted ubiblock"

# Test-only fixture roots must be absolute paths.
if QG_INSPECT_ROOT=relative sh "$INSPECTOR" >/dev/null 2>&1; then
  echo "ERROR: inspector accepted a relative fixture root." >&2
  exit 1
fi

echo "AW1000 read-only install-target inspector tests passed."
