#!/bin/sh
# Refuse an OpenWrt source checkout that does not match the reviewed commit.
set -eu

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[ "$#" -eq 2 ] || die "Usage: $0 <OpenWrt checkout> <expected 40-character commit SHA>"
SOURCE=$1
EXPECTED=$2

[ -d "$SOURCE" ] || die "OpenWrt source directory does not exist: $SOURCE"
printf '%s\n' "$EXPECTED" | LC_ALL=C grep -Eq '^[[:xdigit:]]{40}$' || die "Expected OpenWrt commit must be a full 40-character hexadecimal SHA-1."

ACTUAL=$(git -C "$SOURCE" rev-parse --verify 'HEAD^{commit}' 2>/dev/null) || die "Could not resolve the OpenWrt checkout HEAD."
EXPECTED=$(printf '%s' "$EXPECTED" | tr 'A-F' 'a-f')
ACTUAL=$(printf '%s' "$ACTUAL" | tr 'A-F' 'a-f')

[ "$ACTUAL" = "$EXPECTED" ] || die "OpenWrt checkout resolved to $ACTUAL, expected reviewed commit $EXPECTED. Refusing to build."

printf 'Verified OpenWrt source commit: %s\n' "$ACTUAL"
