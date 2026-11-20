#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT/scripts/install-aw1000-ubi.sh"
VERIFIER="$ROOT/scripts/verify-aw1000-release-manifest.sh"

test -s "$INSTALLER"
test -s "$VERIFIER"
bash -n "$INSTALLER"
sh -n "$INSTALLER"
sh -n "$VERIFIER"

grep -Fq 'arcadyan_aw1000|arcadyan,aw1000' "$INSTALLER"
grep -Fq 'rootfs|tmpfs|ramfs' "$INSTALLER"
grep -Fq 'ROOTFS_SIZE" = "06400000"' "$INSTALLER"
grep -Fq 'ROOTFS_ERASE" = "00040000"' "$INSTALLER"
grep -Fq 'ROOTFS1_MTD" = "mtd20"' "$INSTALLER"
grep -Fq 'ubiformat "$TARGET" -y -f "$IMAGE"' "$INSTALLER"
grep -Fq 'ERASE rootfs' "$INSTALLER"
grep -Fq 'Dry run only. No flash writes were made.' "$INSTALLER"
grep -Fq 'verify-aw1000-release-manifest.sh' "$INSTALLER"
grep -Fq 'sh "$SCRIPT_DIR/verify-aw1000-release-manifest.sh" "$IMAGE" "$MANIFEST"' "$INSTALLER"
grep -Fq 'sha256sum' "$VERIFIER"
grep -Fq 'count != 1' "$VERIFIER"

if sh "$INSTALLER" >/dev/null 2>&1; then
  echo "ERROR: installer accepted a missing image argument." >&2
  exit 1
fi

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
IMAGE="$TEST_DIR/QuantumGrid-OS-test-AW1000-squashfs-factory.ubi"
MANIFEST="$TEST_DIR/SHA256SUMS"

# Valid exact-filename manifest entries pass; tampering and ambiguity fail.
printf 'synthetic AW1000 image fixture\n' > "$IMAGE"
DIGEST="$(sha256sum "$IMAGE" | awk '{ print $1 }')"
printf '%s  %s\n' "$DIGEST" "${IMAGE##*/}" > "$MANIFEST"
sh "$VERIFIER" "$IMAGE" "$MANIFEST"

printf 'tampered AW1000 image fixture\n' > "$IMAGE"
if sh "$VERIFIER" "$IMAGE" "$MANIFEST" >/dev/null 2>&1; then
  echo "ERROR: release verifier accepted a tampered image." >&2
  exit 1
fi

printf 'synthetic AW1000 image fixture\n' > "$IMAGE"
DIGEST="$(sha256sum "$IMAGE" | awk '{ print $1 }')"
printf '%s  %s\n' "$DIGEST" "${IMAGE##*/}" > "$MANIFEST"
cat "$MANIFEST" >> "$MANIFEST.duplicate"
cat "$MANIFEST.duplicate" >> "$MANIFEST"
if sh "$VERIFIER" "$IMAGE" "$MANIFEST" >/dev/null 2>&1; then
  echo "ERROR: release verifier accepted duplicate manifest entries." >&2
  exit 1
fi

WRONG_IMAGE="$TEST_DIR/not-an-aw1000-image.ubi"
cp "$IMAGE" "$WRONG_IMAGE"
if sh "$VERIFIER" "$WRONG_IMAGE" "$MANIFEST" >/dev/null 2>&1; then
  echo "ERROR: release verifier accepted a non-AW1000 image name." >&2
  exit 1
fi

# Exercise the same /proc/mtd field parser used by the installer.
MTD_FIXTURE="$TEST_DIR/proc-mtd"
cat > "$MTD_FIXTURE" <<'MTD'
dev:    size   erasesize  name
mtd18: 06400000 00040000 "rootfs"
mtd20: 06400000 00040000 "rootfs_1"
MTD

mtd_entry_fixture() {
  local source=$1 wanted=$2
  awk -F '[:, ]+' -v wanted="$wanted" '$4 == "\"" wanted "\"" { count++; print $1, $2, $3 } END { if (count != 1) exit 1 }' "$source"
}

validate_standard_entry() {
  local source=$1 name=$2 expected_mtd=$3
  local entry
  entry="$(mtd_entry_fixture "$source" "$name")" || return 1
  local mtd size erase
  read -r mtd size erase <<< "$entry"
  [[ "$mtd" == "$expected_mtd" && "$size" == "06400000" && "$erase" == "00040000" ]]
}

[[ "$(mtd_entry_fixture "$MTD_FIXTURE" rootfs)" == "mtd18 06400000 00040000" ]]
[[ "$(mtd_entry_fixture "$MTD_FIXTURE" rootfs_1)" == "mtd20 06400000 00040000" ]]
validate_standard_entry "$MTD_FIXTURE" rootfs mtd18
validate_standard_entry "$MTD_FIXTURE" rootfs_1 mtd20

cp "$MTD_FIXTURE" "$MTD_FIXTURE.duplicate"
printf 'mtd21: 06400000 00040000 "rootfs"\n' >> "$MTD_FIXTURE.duplicate"
if mtd_entry_fixture "$MTD_FIXTURE.duplicate" rootfs >/dev/null 2>&1; then
  echo "ERROR: MTD parser accepted duplicate rootfs entries." >&2
  exit 1
fi

sed 's/mtd20: 06400000 00040000 "rootfs_1"/mtd20: 06400000 00020000 "rootfs_1"/' "$MTD_FIXTURE" > "$MTD_FIXTURE.wrong-erase"
if validate_standard_entry "$MTD_FIXTURE.wrong-erase" rootfs_1 mtd20; then
  echo "ERROR: MTD parser accepted an incompatible erase geometry." >&2
  exit 1
fi

sed 's/mtd20: 06400000 00040000 "rootfs_1"/mtd19: 06400000 00040000 "rootfs_1"/' "$MTD_FIXTURE" > "$MTD_FIXTURE.wrong-index"
if validate_standard_entry "$MTD_FIXTURE.wrong-index" rootfs_1 mtd20; then
  echo "ERROR: MTD parser accepted an unexpected rootfs_1 MTD index." >&2
  exit 1
fi

# Symlinked image or manifest inputs must be refused.
ln -s "$IMAGE" "$TEST_DIR/image-link.ubi"
if sh "$VERIFIER" "$TEST_DIR/image-link.ubi" "$MANIFEST" >/dev/null 2>&1; then
  echo "ERROR: release verifier accepted a symlinked image." >&2
  exit 1
fi
ln -s "$MANIFEST" "$TEST_DIR/manifest-link"
if sh "$VERIFIER" "$IMAGE" "$TEST_DIR/manifest-link" >/dev/null 2>&1; then
  echo "ERROR: release verifier accepted a symlinked manifest." >&2
  exit 1
fi

echo "AW1000 UBI installer and release SHA-256 manifest checks passed."
