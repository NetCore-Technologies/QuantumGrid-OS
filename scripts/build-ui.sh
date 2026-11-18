#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
OPENWRT_DIR="${2:-$PROJECT_ROOT/openwrt}"
UI_DIR="$PROJECT_ROOT/ui/quantumgrid"
DIST_DIR="$UI_DIR/dist"
DEST_DIR="$OPENWRT_DIR/files/www/quantumgrid"

die() {
    printf '\nERROR: %s\n' "$*" >&2
    exit 1
}

command -v npm >/dev/null 2>&1 || die "npm is required to build the QuantumGrid control centre"
[[ -f "$UI_DIR/package.json" ]] || die "QuantumGrid UI package.json not found: $UI_DIR"
[[ -f "$UI_DIR/package-lock.json" ]] || die "QuantumGrid UI package-lock.json is required for a reproducible build"
[[ -d "$OPENWRT_DIR" ]] || die "OpenWrt build tree not found: $OPENWRT_DIR"

printf '\nQuantumGrid control-centre build\n'
printf 'UI source: %s\n' "$UI_DIR"
printf 'Firmware overlay destination: %s\n' "$DEST_DIR"

(
    cd "$UI_DIR"
    npm ci --no-audit --no-fund
    npm run lint
    npm run build
)

[[ -s "$DIST_DIR/index.html" ]] || die "Vite did not produce dist/index.html"
[[ -d "$DIST_DIR/assets" ]] || die "Vite output is missing the assets directory"
find "$DIST_DIR/assets" -maxdepth 1 -type f -print -quit | grep -q . || die "Vite emitted no JavaScript or CSS assets"

rm -rf "$DEST_DIR"
install -d "$DEST_DIR"
cp -a "$DIST_DIR/." "$DEST_DIR/"
[[ -s "$DEST_DIR/index.html" ]] || die "QuantumGrid UI was not copied into the OpenWrt rootfs overlay"

printf '\nQuantumGrid UI installed into firmware overlay:\n'
find "$DEST_DIR" -maxdepth 2 -type f -printf '  %P (%s bytes)\n' | sort
printf '\nAfter boot, the static control centre is available at /quantumgrid/.\n'
