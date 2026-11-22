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
if [ "${1:-}" = "version" ]; then
  printf 'gh version %s\n' "${GH_VERSION-2.102.0}"
  exit 0
fi
printf '%s\n' "$@" > "$GH_ARGS_LOG"
if [ "${GH_FAIL:-0}" = "1" ]; then
  exit 23
fi
GH
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"
export GH_ARGS_LOG="$WORK/gh-args.txt"

sh "$ROOT/scripts/verify-aw1000-release-attestation.sh" "$IMAGE" "$MANIFEST"
grep -Fxq 'attestation' "$GH_ARGS_LOG"
grep -Fxq 'verify' "$GH_ARGS_LOG"
grep -Fxq "$IMAGE" "$GH_ARGS_LOG"
grep -Fxq -- '--repo' "$GH_ARGS_LOG"
grep -Fxq 'NetCore-Technologies/QuantumGrid-OS' "$GH_ARGS_LOG"
grep -Fxq -- '--signer-workflow' "$GH_ARGS_LOG"
grep -Fxq 'NetCore-Technologies/QuantumGrid-OS/.github/workflows/firmware-release.yml' "$GH_ARGS_LOG"
grep -Fxq -- '--predicate-type' "$GH_ARGS_LOG"
grep -Fxq 'https://slsa.dev/provenance/v1' "$GH_ARGS_LOG"
grep -Fxq -- '--source-ref' "$GH_ARGS_LOG"
grep -Fxq 'refs/tags/qg-v0.4.0' "$GH_ARGS_LOG"
grep -Fxq -- '--deny-self-hosted-runners' "$GH_ARGS_LOG"

# GitHub CLI releases through 2.101.0 have unsafe case-insensitive source-ref comparison.
for old_version in 1.99.0 2.67.9 2.68.0 2.99.9 2.101.0; do
  : > "$GH_ARGS_LOG"
  if GH_VERSION="$old_version" sh "$ROOT/scripts/verify-aw1000-release-attestation.sh" "$IMAGE" "$MANIFEST" >/dev/null 2>&1; then
    echo "ERROR: outdated GitHub CLI $old_version was accepted" >&2
    exit 1
  fi
  [ ! -s "$GH_ARGS_LOG" ] || {
    echo "ERROR: attestation ran with outdated GitHub CLI $old_version" >&2
    exit 1
  }
done

# Supported versions include patch, minor and major releases at or above 2.102.0.
for supported_version in 2.102.0 2.102.1 2.103.0 3.0.0; do
  : > "$GH_ARGS_LOG"
  GH_VERSION="$supported_version" sh "$ROOT/scripts/verify-aw1000-release-attestation.sh" "$IMAGE" "$MANIFEST"
  grep -Fxq -- '--source-ref' "$GH_ARGS_LOG"
  grep -Fxq 'refs/tags/qg-v0.4.0' "$GH_ARGS_LOG"
done

# Missing or malformed CLI versions are rejected before contacting GitHub.
for malformed_version in "" 2.102 2.x.0 2.102.0-rc.1; do
  : > "$GH_ARGS_LOG"
  if GH_VERSION="$malformed_version" sh "$ROOT/scripts/verify-aw1000-release-attestation.sh" "$IMAGE" "$MANIFEST" >/dev/null 2>&1; then
    echo "ERROR: malformed GitHub CLI version '$malformed_version' was accepted" >&2
    exit 1
  fi
  [ ! -s "$GH_ARGS_LOG" ] || {
    echo "ERROR: attestation ran with malformed GitHub CLI version '$malformed_version'" >&2
    exit 1
  }
done

# Manual build artifacts are not tagged releases and cannot pass this verifier.
MANUAL_IMAGE="$WORK/QuantumGrid-OS-manual-build-7-AW1000-squashfs-factory.ubi"
cp "$IMAGE" "$MANUAL_IMAGE"
(
  cd "$WORK"
  sha256sum "$(basename "$MANUAL_IMAGE")" > "$MANIFEST"
)
: > "$GH_ARGS_LOG"
if sh "$ROOT/scripts/verify-aw1000-release-attestation.sh" "$MANUAL_IMAGE" "$MANIFEST" >/dev/null 2>&1; then
  echo "ERROR: a manual build artifact was accepted as a tagged release" >&2
  exit 1
fi
[ ! -s "$GH_ARGS_LOG" ] || {
  echo "ERROR: GitHub was contacted for a non-release image" >&2
  exit 1
}


# A bad checksum must stop before GitHub is contacted.
: > "$GH_ARGS_LOG"
printf '%064d  %s\n' 0 "$(basename "$IMAGE")" > "$MANIFEST"
if sh "$ROOT/scripts/verify-aw1000-release-attestation.sh" "$IMAGE" "$MANIFEST" >/dev/null 2>&1; then
  echo "ERROR: checksum mismatch was accepted" >&2
  exit 1
fi
[ ! -s "$GH_ARGS_LOG" ] || {
  echo "ERROR: GitHub was contacted before checksum verification succeeded" >&2
  exit 1
}

# Reject malformed versions before contacting GitHub.
BAD_VERSION_IMAGE="$WORK/QuantumGrid-OS-vnot-semver-AW1000-squashfs-factory.ubi"
cp "$IMAGE" "$BAD_VERSION_IMAGE"
(
  cd "$WORK"
  sha256sum "$(basename "$BAD_VERSION_IMAGE")" > "$MANIFEST"
)
: > "$GH_ARGS_LOG"
if sh "$ROOT/scripts/verify-aw1000-release-attestation.sh" "$BAD_VERSION_IMAGE" "$MANIFEST" >/dev/null 2>&1; then
  echo "ERROR: a malformed release version was accepted" >&2
  exit 1
fi
[ ! -s "$GH_ARGS_LOG" ] || {
  echo "ERROR: GitHub was contacted for an invalid release version" >&2
  exit 1
}

# A failed attestation must fail even when the SHA-256 manifest is correct.
(
  cd "$WORK"
  sha256sum "$(basename "$IMAGE")" > "$MANIFEST"
)
if GH_FAIL=1 sh "$ROOT/scripts/verify-aw1000-release-attestation.sh" "$IMAGE" "$MANIFEST" >/dev/null 2>&1; then
  echo "ERROR: failed GitHub attestation was accepted" >&2
  exit 1
fi

echo "AW1000 release attestation verification: checksum-first, exact tag, SLSA v1 and hosted-runner policy passed"
