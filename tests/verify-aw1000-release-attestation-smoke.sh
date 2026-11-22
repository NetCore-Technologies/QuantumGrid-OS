#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"
IMAGE="$WORK/QuantumGrid-OS-v0.4.0-AW1000-squashfs-factory.ubi"
MANIFEST="$WORK/SHA256SUMS"
printf 'test-factory-ubi-image\n' > "$IMAGE"
(
  cd "$WORK"
  sha256sum "$(basename "$IMAGE")" > "$MANIFEST"
)

cat > "$WORK/bin/gh" <<'GH'
#!/bin/sh
printf '%s\n' "$@" > "$GH_ARGS_LOG"
if [ "${GH_FAIL:-0}" = "1" ]; then
  exit 23
fi
GH
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"
export GH_ARGS_LOG="$WORK/gh-args.txt"

"$ROOT/scripts/verify-aw1000-release-attestation.sh" "$IMAGE" "$MANIFEST"
grep -Fxq 'attestation' "$GH_ARGS_LOG"
grep -Fxq 'verify' "$GH_ARGS_LOG"
grep -Fxq "$IMAGE" "$GH_ARGS_LOG"
grep -Fxq -- '--repo' "$GH_ARGS_LOG"
grep -Fxq 'NetCore-Technologies/QuantumGrid-OS' "$GH_ARGS_LOG"
grep -Fxq -- '--signer-workflow' "$GH_ARGS_LOG"
grep -Fxq 'NetCore-Technologies/QuantumGrid-OS/.github/workflows/firmware-release.yml' "$GH_ARGS_LOG"

# A bad checksum must stop before GitHub is contacted.
: > "$GH_ARGS_LOG"
printf '%064d  %s\n' 0 "$(basename "$IMAGE")" > "$MANIFEST"
if "$ROOT/scripts/verify-aw1000-release-attestation.sh" "$IMAGE" "$MANIFEST" >/dev/null 2>&1; then
  echo "ERROR: checksum mismatch was accepted" >&2
  exit 1
fi
[ ! -s "$GH_ARGS_LOG" ] || {
  echo "ERROR: GitHub was contacted before checksum verification succeeded" >&2
  exit 1
}

# A failed attestation must fail even when the SHA-256 manifest is correct.
(
  cd "$WORK"
  sha256sum "$(basename "$IMAGE")" > "$MANIFEST"
)
if GH_FAIL=1 "$ROOT/scripts/verify-aw1000-release-attestation.sh" "$IMAGE" "$MANIFEST" >/dev/null 2>&1; then
  echo "ERROR: failed GitHub attestation was accepted" >&2
  exit 1
fi

echo "AW1000 release attestation verification: checksum-first and signer-workflow enforcement passed"
