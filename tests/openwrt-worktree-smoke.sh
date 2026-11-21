#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/scripts/check-openwrt-worktree.sh"
bash -n "$CHECK"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
REMOTE="$TEST_DIR/openwrt-origin.git"
SOURCE="$TEST_DIR/source"
CHECKOUT="$TEST_DIR/checkout"
git init --bare -q "$REMOTE"
git init -q "$SOURCE"
git -C "$SOURCE" config user.name "QuantumGrid CI"
git -C "$SOURCE" config user.email "ci@example.invalid"
printf "tracked source\\n" > "$SOURCE/README"
git -C "$SOURCE" add README
git -C "$SOURCE" commit -q -m "source fixture"
git -C "$SOURCE" remote add origin "$REMOTE"
git -C "$SOURCE" push -q origin HEAD:refs/heads/main
git clone -q "$REMOTE" "$CHECKOUT"
bash "$CHECK" "$CHECKOUT" "$REMOTE"

# Tracked modifications must be rejected.
printf "changed\\n" >> "$CHECKOUT/README"
if bash "$CHECK" "$CHECKOUT" "$REMOTE" >/dev/null 2>&1; then echo "ERROR: modified tracked source accepted." >&2; exit 1; fi
git -C "$CHECKOUT" reset --hard -q HEAD

# Non-ignored untracked source files must be rejected.
printf "injected code\\n" > "$CHECKOUT/injected.c"
if bash "$CHECK" "$CHECKOUT" "$REMOTE" >/dev/null 2>&1; then echo "ERROR: untracked source accepted." >&2; exit 1; fi
rm -f "$CHECKOUT/injected.c"

# A checkout from a different origin must not be silently rewritten.
if bash "$CHECK" "$CHECKOUT" "$TEST_DIR/wrong-origin.git" >/dev/null 2>&1; then echo "ERROR: mismatched origin accepted." >&2; exit 1; fi

# Ignored build outputs are allowed so normal incremental builds remain usable.
printf "build output\\n" > "$CHECKOUT/ignored-output"
printf "/ignored-output\\n" >> "$CHECKOUT/.git/info/exclude"
bash "$CHECK" "$CHECKOUT" "$REMOTE"

echo "OpenWrt checkout provenance and clean-tree checks passed."
