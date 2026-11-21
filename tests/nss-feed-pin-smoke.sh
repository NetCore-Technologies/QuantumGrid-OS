#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN_SCRIPT="$ROOT/scripts/pin-aw1000-nss-feeds.sh"
MANIFEST="$ROOT/configs/aw1000-nss-feeds.conf"
bash -n "$PIN_SCRIPT"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
OPENWRT="$TEST_DIR/openwrt"
mkdir -p "$OPENWRT"
ORIGINAL="$TEST_DIR/feeds.conf.default.original"
cat > "$ORIGINAL" <<'FEEDS'
src-git packages https://git.openwrt.org/feed/packages.git;openwrt-25.12
src-git luci https://git.openwrt.org/project/luci.git;openwrt-25.12
src-git routing https://git.openwrt.org/feed/routing.git;openwrt-25.12
src-git telephony https://git.openwrt.org/feed/telephony.git;openwrt-25.12
src-git nss_packages https://github.com/qosmio/nss-packages.git;NSS-12.5-K6.x
src-git sqm_scripts_nss https://github.com/qosmio/sqm-scripts-nss.git
src-git video https://github.com/openwrt/video.git;openwrt-25.12
FEEDS
cp "$ORIGINAL" "$OPENWRT/feeds.conf.default"
bash "$PIN_SCRIPT" "$OPENWRT" "$MANIFEST"
diff -u "$MANIFEST" "$OPENWRT/feeds.conf.default"

# Unexpected source URLs must not be silently pinned.
sed -i 's#https://git.openwrt.org/feed/packages.git#https://example.invalid/packages.git#' "$OPENWRT/feeds.conf.default"
# Restore the branch-style source config to simulate the upstream input.
sed -i 's#https://example.invalid/packages.git#https://git.openwrt.org/feed/packages.git;openwrt-25.12#' "$OPENWRT/feeds.conf.default"
sed -i 's#https://git.openwrt.org/feed/packages.git;openwrt-25.12#https://example.invalid/packages.git;openwrt-25.12#' "$OPENWRT/feeds.conf.default"
if bash "$PIN_SCRIPT" "$OPENWRT" "$MANIFEST" >/dev/null 2>&1; then
  echo "ERROR: unexpected NSS feed repository URL was accepted." >&2
  exit 1
fi

# Restore the pristine source fixture, then remove one required feed.
cp "$ORIGINAL" "$OPENWRT/feeds.conf.default"
sed -i '/src-git video /d' "$OPENWRT/feeds.conf.default"
if bash "$PIN_SCRIPT" "$OPENWRT" "$MANIFEST" >/dev/null 2>&1; then
  echo "ERROR: incomplete NSS feed set was accepted." >&2
  exit 1
fi

# Restore the pristine source fixture, then add an unexpected feed.
cp "$ORIGINAL" "$OPENWRT/feeds.conf.default"
printf 'src-git unexpected https://example.invalid/unexpected.git;main\n' >> "$OPENWRT/feeds.conf.default"
if bash "$PIN_SCRIPT" "$OPENWRT" "$MANIFEST" >/dev/null 2>&1; then
  echo "ERROR: unexpected NSS feed was accepted." >&2
  exit 1
fi
echo "AW1000 NSS feed pin checks passed."
