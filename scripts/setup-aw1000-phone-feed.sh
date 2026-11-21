#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
OPENWRT_DIR="${2:-$PROJECT_ROOT/openwrt}"
PHONE_REPOSITORY="https://github.com/Perz3us/openwrt-aw1000-phone.git"
PHONE_REF="${QG_AW1000_PHONE_REF:-v0.9.0}"
PHONE_EXPECTED_SHA="${QG_AW1000_PHONE_EXPECTED_SHA:-fe85222e57d1c3e191ffb976b37667bbf221a020}"
PHONE_DIR="$PROJECT_ROOT/third_party/openwrt-aw1000-phone"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
command -v git >/dev/null 2>&1 || die "git is required to fetch the AW1000 phone feed"
[[ "$PHONE_EXPECTED_SHA" =~ ^[[:xdigit:]]{40}$ ]] || die "Expected phone source commit must be a full 40-character hexadecimal SHA-1."
PHONE_EXPECTED_SHA="$(printf '%s' "$PHONE_EXPECTED_SHA" | tr 'A-F' 'a-f')"
[[ -d "$OPENWRT_DIR" ]] || die "OpenWrt source tree not found: $OPENWRT_DIR"
[[ -f "$OPENWRT_DIR/Makefile" ]] || die "Not an OpenWrt source tree: $OPENWRT_DIR"
mkdir -p "$(dirname "$PHONE_DIR")"
if [[ ! -d "$PHONE_DIR/.git" ]]; then
    rm -rf "$PHONE_DIR"
    git clone --filter=blob:none --no-checkout "$PHONE_REPOSITORY" "$PHONE_DIR"
fi
git -C "$PHONE_DIR" fetch --depth 1 origin "refs/tags/$PHONE_REF:refs/tags/$PHONE_REF"
git -C "$PHONE_DIR" checkout --detach "$PHONE_REF"
PHONE_ACTUAL_SHA="$(git -C "$PHONE_DIR" rev-parse --verify 'HEAD^{commit}')"
PHONE_ACTUAL_SHA="$(printf '%s' "$PHONE_ACTUAL_SHA" | tr 'A-F' 'a-f')"
[[ "$PHONE_ACTUAL_SHA" == "$PHONE_EXPECTED_SHA" ]] || die "AW1000 phone feed resolved to $PHONE_ACTUAL_SHA, expected pinned commit $PHONE_EXPECTED_SHA. Refusing to build."

for required in "$PHONE_DIR/LICENSE" "$PHONE_DIR/openwrt/aw1000-fxs/Makefile" "$PHONE_DIR/openwrt/fxsd/Makefile" "$PHONE_DIR/openwrt/luci-app-fxs/Makefile"; do
    [[ -s "$required" ]] || die "Pinned phone source is incomplete: $required"
done

FEED_LINE="src-link quantumgrid_phone $PHONE_DIR/openwrt"
if [[ ! -f "$OPENWRT_DIR/feeds.conf" ]]; then
    if [[ -f "$OPENWRT_DIR/feeds.conf.default" ]]; then cp "$OPENWRT_DIR/feeds.conf.default" "$OPENWRT_DIR/feeds.conf"; else : > "$OPENWRT_DIR/feeds.conf"; fi
fi
grep -Fqx "$FEED_LINE" "$OPENWRT_DIR/feeds.conf" || printf '%s\n' "$FEED_LINE" >> "$OPENWRT_DIR/feeds.conf"
printf 'AW1000 phone feed: %s\n' "$PHONE_REF"
printf 'Expected source revision: %s\n' "$PHONE_EXPECTED_SHA"
printf 'Verified source revision: %s\n' "$PHONE_ACTUAL_SHA"
printf 'Feed registered: %s\n' "$FEED_LINE"
printf '%s\n' "GPL-2.0 source is fetched at build time; no proprietary SLIC patch is downloaded."
