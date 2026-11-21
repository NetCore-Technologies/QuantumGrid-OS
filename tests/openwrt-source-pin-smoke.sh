#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFIER="$ROOT/scripts/verify-openwrt-source.sh"
test -s "$VERIFIER"
sh -n "$VERIFIER"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
SOURCE="$TEST_DIR/openwrt"
mkdir -p "$SOURCE"
git -C "$SOURCE" init -q
git -C "$SOURCE" config user.name "QuantumGrid CI"
git -C "$SOURCE" config user.email "ci@example.invalid"

printf 'reviewed source\n' > "$SOURCE/README"
git -C "$SOURCE" add README
git -C "$SOURCE" commit -q -m "reviewed source fixture"
EXPECTED="$(git -C "$SOURCE" rev-parse HEAD)"

sh "$VERIFIER" "$SOURCE" "$EXPECTED"
sh "$VERIFIER" "$SOURCE" "$(printf '%s' "$EXPECTED" | tr 'a-f' 'A-F')"

printf 'changed source\n' >> "$SOURCE/README"
git -C "$SOURCE" add README
git -C "$SOURCE" commit -q -m "unreviewed source fixture"

if sh "$VERIFIER" "$SOURCE" "$EXPECTED" >/dev/null 2>&1; then
  echo "ERROR: source verifier accepted a changed commit." >&2
  exit 1
fi
if sh "$VERIFIER" "$SOURCE" "not-a-full-commit-sha" >/dev/null 2>&1; then
  echo "ERROR: source verifier accepted an invalid expected SHA." >&2
  exit 1
fi
if sh "$VERIFIER" "$TEST_DIR/missing" "$EXPECTED" >/dev/null 2>&1; then
  echo "ERROR: source verifier accepted a missing checkout." >&2
  exit 1
fi

echo "OpenWrt reviewed-source commit pin checks passed."
