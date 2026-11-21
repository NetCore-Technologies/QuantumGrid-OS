#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/setup-aw1000-phone-feed.sh"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

REMOTE="$TEST_DIR/phone-source"
PROJECT="$TEST_DIR/project"
OPENWRT="$PROJECT/openwrt"
mkdir -p "$REMOTE" "$OPENWRT" "$PROJECT"
git -C "$REMOTE" init -q
git -C "$REMOTE" config user.name "QuantumGrid CI"
git -C "$REMOTE" config user.email "ci@example.invalid"

mkdir -p "$REMOTE/openwrt/aw1000-fxs" "$REMOTE/openwrt/fxsd" "$REMOTE/openwrt/luci-app-fxs"
printf 'GPL-2.0 test fixture\n' > "$REMOTE/LICENSE"
for package in aw1000-fxs fxsd luci-app-fxs; do
  printf 'include $(TOPDIR)/rules.mk\n' > "$REMOTE/openwrt/$package/Makefile"
done
git -C "$REMOTE" add .
git -C "$REMOTE" commit -q -m "phone feed fixture"
PINNED="$(git -C "$REMOTE" rev-parse HEAD)"
git -C "$REMOTE" tag v-test

export QG_AW1000_PHONE_REPOSITORY="$REMOTE"
export QG_AW1000_PHONE_REF=v-test
export QG_AW1000_PHONE_EXPECTED_SHA="$PINNED"

bash "$SCRIPT" "$PROJECT" "$OPENWRT"
test "$(git -C "$PROJECT/third_party/openwrt-aw1000-phone" rev-parse HEAD)" = "$PINNED"
grep -Fqx "src-link quantumgrid_phone $PROJECT/third_party/openwrt-aw1000-phone/openwrt" "$OPENWRT/feeds.conf"

# Repoint the same upstream tag at new source. A fresh build must reject it.
printf 'changed source\n' >> "$REMOTE/LICENSE"
git -C "$REMOTE" add LICENSE
git -C "$REMOTE" commit -q -m "moved phone feed tag fixture"
git -C "$REMOTE" tag -f v-test
rm -rf "$PROJECT/third_party/openwrt-aw1000-phone"
if bash "$SCRIPT" "$PROJECT" "$OPENWRT" >/dev/null 2>&1; then
  echo "ERROR: moved phone-feed tag was accepted." >&2
  exit 1
fi

# Malformed SHA values must fail before attempting another fetch.
rm -rf "$PROJECT/third_party/openwrt-aw1000-phone"
if QG_AW1000_PHONE_EXPECTED_SHA=bad bash "$SCRIPT" "$PROJECT" "$OPENWRT" >/dev/null 2>&1; then
  echo "ERROR: malformed phone-feed expected SHA was accepted." >&2
  exit 1
fi

echo "AW1000 phone feed pin checks passed."
