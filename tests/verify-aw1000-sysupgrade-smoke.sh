#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFIER="$ROOT/scripts/verify-aw1000-sysupgrade.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
test -s "$VERIFIER"
bash -n "$VERIFIER"
sh -n "$VERIFIER"
PAYLOAD="$WORK/payload"
mkdir -p "$PAYLOAD/sysupgrade-arcadyan_aw1000"
printf 'BOARD=arcadyan_aw1000\n' > "$PAYLOAD/sysupgrade-arcadyan_aw1000/CONTROL"
printf 'synthetic kernel image\n' > "$PAYLOAD/sysupgrade-arcadyan_aw1000/kernel"
dd if=/dev/zero of="$PAYLOAD/sysupgrade-arcadyan_aw1000/root" bs=1024 count=1024 status=none
IMAGE="$WORK/openwrt-arcadyan_aw1000-squashfs-sysupgrade.bin"
tar -cf "$IMAGE" -C "$PAYLOAD" sysupgrade-arcadyan_aw1000
bash "$VERIFIER" "$IMAGE"
RELEASE_IMAGE="$WORK/QuantumGrid-OS-v0.4.0-AW1000-squashfs-sysupgrade.bin"
cp "$IMAGE" "$RELEASE_IMAGE"
bash "$VERIFIER" "$RELEASE_IMAGE"
printf 'BOARD=another_router\n' > "$PAYLOAD/sysupgrade-arcadyan_aw1000/CONTROL"
tar -cf "$WORK/wrong-board.bin" -C "$PAYLOAD" sysupgrade-arcadyan_aw1000
if bash "$VERIFIER" "$WORK/wrong-board.bin" >/dev/null 2>&1; then echo "ERROR: accepted a wrong-board archive." >&2; exit 1; fi
printf 'BOARD=arcadyan_aw1000\n' > "$PAYLOAD/sysupgrade-arcadyan_aw1000/CONTROL"
rm "$PAYLOAD/sysupgrade-arcadyan_aw1000/kernel"
tar -cf "$WORK/missing-kernel.bin" -C "$PAYLOAD" sysupgrade-arcadyan_aw1000
if bash "$VERIFIER" "$WORK/missing-kernel.bin" >/dev/null 2>&1; then echo "ERROR: accepted an archive without a kernel." >&2; exit 1; fi
printf 'synthetic kernel image\n' > "$PAYLOAD/sysupgrade-arcadyan_aw1000/kernel"
printf 'unexpected content\n' > "$PAYLOAD/sysupgrade-arcadyan_aw1000/unexpected"
tar -cf "$WORK/unexpected-member.bin" -C "$PAYLOAD" sysupgrade-arcadyan_aw1000
if bash "$VERIFIER" "$WORK/unexpected-member.bin" >/dev/null 2>&1; then echo "ERROR: accepted an unexpected archive member." >&2; exit 1; fi
printf 'not a tar archive' > "$WORK/not-an-archive.bin"
if bash "$VERIFIER" "$WORK/not-an-archive.bin" >/dev/null 2>&1; then echo "ERROR: accepted a non-tar image." >&2; exit 1; fi
cp "$IMAGE" "$WORK/not-aw1000.bin"
if bash "$VERIFIER" "$WORK/not-aw1000.bin" >/dev/null 2>&1; then echo "ERROR: accepted an unknown filename." >&2; exit 1; fi
ln -s "$IMAGE" "$WORK/image-link.bin"
if bash "$VERIFIER" "$WORK/image-link.bin" >/dev/null 2>&1; then echo "ERROR: accepted a symlinked image." >&2; exit 1; fi
echo "AW1000 sysupgrade archive validation passed."
