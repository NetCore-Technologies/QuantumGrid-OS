#!/usr/bin/env bash
set -Eeuo pipefail

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ $# -eq 1 ]] || die "Usage: $0 <AW1000 factory UBI image>"
image="$1"
[[ -f "$image" && ! -L "$image" ]] || die "Image must be a regular, non-symlink file: $image"

filename="${image##*/}"
case "$filename" in
    *arcadyan_aw1000-squashfs-factory.ubi) ;;
    *) die "Expected an Arcadyan AW1000 squashfs factory .ubi image; refusing: $filename" ;;
esac

size="$(stat -c '%s' -- "$image")"
[[ "$size" =~ ^[0-9]+$ ]] || die "Could not determine image size: $image"
(( size >= 1048576 )) || die "UBI image is unexpectedly small (${size} bytes): $image"

magic="$(od -An -N4 -t x1 -- "$image" | tr -d '[:space:]')"
[[ "$magic" == "55424923" ]] || die "Invalid UBI erase-counter header (expected UBI#): $image"

printf 'Validated AW1000 factory UBI image: %s (%s bytes)\n' "$filename" "$size"
