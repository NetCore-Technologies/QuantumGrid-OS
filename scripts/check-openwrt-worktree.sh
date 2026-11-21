#!/usr/bin/env bash
# Refuse reuse of an OpenWrt checkout containing untracked or modified source.
set -Eeuo pipefail

OPENWRT_DIR="${1:-}"
EXPECTED_ORIGIN="${2:-}"
[[ -n "$OPENWRT_DIR" && -d "$OPENWRT_DIR/.git" ]] || { echo "ERROR: Usage: $0 <OpenWrt Git checkout> <expected origin URL>" >&2; exit 2; }
[[ -n "$EXPECTED_ORIGIN" ]] || { echo "ERROR: Expected OpenWrt origin URL is required." >&2; exit 2; }
git -C "$OPENWRT_DIR" rev-parse --verify "HEAD^{commit}" >/dev/null 2>&1 || { echo "ERROR: OpenWrt checkout has no valid HEAD commit." >&2; exit 1; }
ACTUAL_ORIGIN="$(git -C "$OPENWRT_DIR" remote get-url origin 2>/dev/null || true)"
[[ "$ACTUAL_ORIGIN" == "$EXPECTED_ORIGIN" ]] || { printf "ERROR: OpenWrt checkout origin is %s, expected %s. Refusing to rewrite repository identity.\\n" "${ACTUAL_ORIGIN:-missing}" "$EXPECTED_ORIGIN" >&2; exit 1; }
DIRTY="$(git -C "$OPENWRT_DIR" status --porcelain --untracked-files=all)"
[[ -z "$DIRTY" ]] || { printf "ERROR: OpenWrt checkout contains modified or untracked files:\\n%s\\nRefusing to reuse contaminated source.\\n" "$DIRTY" >&2; exit 1; }
printf "Verified clean OpenWrt checkout origin: %s\\n" "$ACTUAL_ORIGIN"
