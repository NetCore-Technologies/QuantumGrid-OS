#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFY="$ROOT/scripts/verify-openwrt-feeds.sh"
bash -n "$VERIFY"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
OPENWRT="$TEST_DIR/openwrt"
REMOTE="$TEST_DIR/packages.git"
WORK="$TEST_DIR/packages-work"
PHONE="$TEST_DIR/phone/openwrt"
mkdir -p "$OPENWRT/feeds" "$PHONE"
git init --bare -q "$REMOTE"
git init -q "$WORK"
git -C "$WORK" config user.name "QuantumGrid CI"
git -C "$WORK" config user.email "ci@example.invalid"
printf 'pinned feed fixture\n' > "$WORK/README"
git -C "$WORK" add README
git -C "$WORK" commit -q -m "pinned feed fixture"
PINNED="$(git -C "$WORK" rev-parse HEAD)"
git -C "$WORK" remote add origin "$REMOTE"
git -C "$WORK" push -q origin HEAD:refs/heads/master
git clone -q "$REMOTE" "$OPENWRT/feeds/packages"
ln -s "$PHONE" "$OPENWRT/feeds/quantumgrid_phone"
printf 'src-git packages %s^%s\nsrc-link quantumgrid_phone %s\n' "$REMOTE" "$PINNED" "$PHONE" > "$OPENWRT/feeds.conf"
bash "$VERIFY" "$OPENWRT"

printf 'injected package code\n' > "$OPENWRT/feeds/packages/injected.c"
if bash "$VERIFY" "$OPENWRT" >/dev/null 2>&1; then echo "ERROR: untracked feed content was accepted." >&2; exit 1; fi
rm -f "$OPENWRT/feeds/packages/injected.c"
printf 'modified feed code\n' >> "$OPENWRT/feeds/packages/README"
if bash "$VERIFY" "$OPENWRT" >/dev/null 2>&1; then echo "ERROR: modified feed content was accepted." >&2; exit 1; fi
git -C "$OPENWRT/feeds/packages" reset --hard -q "$PINNED"
git -C "$OPENWRT/feeds/packages" remote set-url origin "$TEST_DIR/wrong-origin"
if bash "$VERIFY" "$OPENWRT" >/dev/null 2>&1; then echo "ERROR: unexpected feed origin was accepted." >&2; exit 1; fi
git -C "$OPENWRT/feeds/packages" remote set-url origin "$REMOTE"
git -C "$WORK" commit --allow-empty -q -m "new unpinned revision"
git -C "$WORK" push -q origin HEAD:refs/heads/master
git -C "$OPENWRT/feeds/packages" fetch -q origin master
git -C "$OPENWRT/feeds/packages" checkout -q --detach FETCH_HEAD
if bash "$VERIFY" "$OPENWRT" >/dev/null 2>&1; then echo "ERROR: a feed at a different commit was accepted." >&2; exit 1; fi
printf 'src-git packages %s\nsrc-link quantumgrid_phone %s\n' "$REMOTE" "$PHONE" > "$OPENWRT/feeds.conf"
if bash "$VERIFY" "$OPENWRT" >/dev/null 2>&1; then echo "ERROR: an unpinned Git feed was accepted." >&2; exit 1; fi
echo "OpenWrt feed pin and clean-source checks passed."
