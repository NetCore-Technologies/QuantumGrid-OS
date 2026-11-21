#!/usr/bin/env bash
# Convert the reviewed Qosmio NSS feed branches to immutable commit-pinned feeds.
set -Eeuo pipefail

OPENWRT_DIR="${1:-}"
MANIFEST="${2:-}"
[[ -n "$OPENWRT_DIR" && -d "$OPENWRT_DIR" ]] || { echo "ERROR: Usage: $0 <OpenWrt checkout> <pinned feed manifest>" >&2; exit 2; }
[[ -s "$MANIFEST" ]] || { echo "ERROR: NSS pinned feed manifest is missing or empty." >&2; exit 1; }
FEEDS_DEFAULT="$OPENWRT_DIR/feeds.conf.default"
[[ -s "$FEEDS_DEFAULT" ]] || { echo "ERROR: NSS source feeds.conf.default is missing or empty." >&2; exit 1; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

declare -A expected_urls expected_shas seen
manifest_count=0
while IFS= read -r raw || [[ -n "$raw" ]]; do
  line="${raw%%#*}"
  read -r -a fields <<< "$line"
  [[ "${#fields[@]}" -eq 0 ]] && continue
  [[ "${#fields[@]}" -eq 3 && "${fields[0]}" == "src-git" ]] || die "Malformed NSS feed manifest declaration: $raw"
  name="${fields[1]}"
  source="${fields[2]}"
  [[ "$source" == *^* ]] || die "NSS feed '$name' is not pinned to a full commit SHA."
  url="${source%%^*}"
  sha="${source##*^}"
  [[ "$sha" =~ ^[[:xdigit:]]{40}$ ]] || die "NSS feed '$name' does not use a full 40-character commit SHA."
  [[ -z "${expected_shas[$name]:-}" ]] || die "Duplicate NSS feed '$name' in pinned manifest."
  expected_urls[$name]="$url"
  expected_shas[$name]="$(printf '%s' "$sha" | tr 'A-F' 'a-f')"
  manifest_count=$((manifest_count + 1))
done < "$MANIFEST"
[[ "$manifest_count" -gt 0 ]] || die "NSS feed manifest contains no pinned feeds."

tmp="$(mktemp "${FEEDS_DEFAULT}.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
seen_count=0
while IFS= read -r raw || [[ -n "$raw" ]]; do
  line="${raw%%#*}"
  read -r -a fields <<< "$line"
  [[ "${#fields[@]}" -eq 0 ]] && continue
  [[ "${#fields[@]}" -eq 3 && "${fields[0]}" == "src-git" ]] || die "Unsupported NSS feed declaration: $raw"
  name="${fields[1]}"
  source="${fields[2]}"
  [[ -n "${expected_shas[$name]:-}" ]] || die "Unexpected NSS feed '$name' is not present in the reviewed pin manifest."
  url="${source%%;*}"
  url="${url%%^*}"
  [[ "$url" == "${expected_urls[$name]}" ]] || die "NSS feed '$name' URL differs from the reviewed repository URL."
  [[ -z "${seen[$name]:-}" ]] || die "Duplicate NSS feed '$name' in upstream feed configuration."
  seen[$name]=1
  seen_count=$((seen_count + 1))
  printf 'src-git %s %s^%s\n' "$name" "$url" "${expected_shas[$name]}" >> "$tmp"
done < "$FEEDS_DEFAULT"
[[ "$seen_count" -eq "$manifest_count" ]] || die "NSS feed set is incomplete: found $seen_count of $manifest_count reviewed feeds."
for name in "${!expected_shas[@]}"; do
  [[ -n "${seen[$name]:-}" ]] || die "Required NSS feed '$name' is missing from the upstream feed configuration."
done
mv "$tmp" "$FEEDS_DEFAULT"
trap - EXIT
printf 'Installed %s reviewed NSS feed pin(s):\n' "$seen_count"
cat "$FEEDS_DEFAULT"
