#!/usr/bin/env bash
# Verify that every Git feed is checked out at the exact revision pinned in feeds.conf.
set -Eeuo pipefail

OPENWRT_DIR="${1:-}"
[[ -n "$OPENWRT_DIR" && -d "$OPENWRT_DIR" ]] || { echo "ERROR: Usage: $0 <OpenWrt checkout>" >&2; exit 2; }
FEEDS_CONFIG="$OPENWRT_DIR/feeds.conf"
[[ -s "$FEEDS_CONFIG" ]] || { echo "ERROR: OpenWrt feeds.conf is missing or empty." >&2; exit 1; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

git_count=0
link_count=0
while IFS= read -r raw || [[ -n "$raw" ]]; do
  line="${raw%%#*}"
  read -r -a fields <<< "$line"
  [[ "${#fields[@]}" -gt 0 ]] || continue
  type="${fields[0]}"
  index=1
  while [[ $index -lt ${#fields[@]} && "${fields[$index]}" == --* ]]; do index=$((index + 1)); done
  [[ $index -lt ${#fields[@]} ]] || die "Malformed feed declaration: $raw"
  name="${fields[$index]}"
  source_index=$((index + 1))
  [[ $source_index -lt ${#fields[@]} ]] || die "Feed '$name' has no source URL."
  [[ $((source_index + 1)) -eq ${#fields[@]} ]] || die "Feed '$name' has unsupported extra fields."
  source="${fields[$source_index]}"
  feed_dir="$OPENWRT_DIR/feeds/$name"
  case "$type" in
    src-git|src-git-full)
      [[ "$source" == *^* ]] || die "Git feed '$name' is not pinned with a full commit SHA."
      expected="${source##*^}"
      remote="${source%%^*}"
      [[ "$expected" =~ ^[[:xdigit:]]{40}$ ]] || die "Git feed '$name' does not use a full 40-character commit SHA."
      [[ -n "$remote" && "$remote" != *";"* ]] || die "Git feed '$name' has an unsupported source expression."
      [[ -d "$feed_dir/.git" ]] || die "Git feed '$name' was not checked out: $feed_dir"
      actual="$(git -C "$feed_dir" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" || die "Could not resolve Git feed '$name' HEAD."
      expected="$(printf '%s' "$expected" | tr 'A-F' 'a-f')"
      actual="$(printf '%s' "$actual" | tr 'A-F' 'a-f')"
      [[ "$actual" == "$expected" ]] || die "Git feed '$name' resolved to $actual, expected $expected."
      origin="$(git -C "$feed_dir" remote get-url origin 2>/dev/null || true)"
      [[ "$origin" == "$remote" ]] || die "Git feed '$name' origin does not match the pinned feeds.conf URL."
      dirty="$(git -C "$feed_dir" status --porcelain --untracked-files=all)"
      [[ -z "$dirty" ]] || die "Git feed '$name' contains modified or untracked files."
      git_count=$((git_count + 1))
      printf 'Verified feed %-12s %s\n' "$name" "$actual"
      ;;
    src-link)
      [[ -d "$source" ]] || die "Linked feed '$name' source directory is missing: $source"
      [[ -L "$feed_dir" ]] || die "Linked feed '$name' is not registered as a symlink."
      resolved_source="$(readlink -f "$source")"
      resolved_feed="$(readlink -f "$feed_dir")"
      [[ "$resolved_source" == "$resolved_feed" ]] || die "Linked feed '$name' resolves to an unexpected source directory."
      [[ -d "$source/.git" ]] || die "Linked feed '$name' must be a Git checkout with a recorded commit."
      linked_sha="$(git -C "$source" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" || die "Could not resolve linked feed '$name' commit."
      linked_dirty="$(git -C "$source" status --porcelain --untracked-files=all)"
      [[ -z "$linked_dirty" ]] || die "Linked feed '$name' contains modified or untracked files."
      link_count=$((link_count + 1))
      printf 'Verified linked feed %-8s %s\n' "$name" "$linked_sha"
      ;;
    *) die "Unsupported unpinned feed type '$type' for '$name'."; ;;
  esac
done < "$FEEDS_CONFIG"
[[ "$git_count" -gt 0 ]] || die "No commit-pinned Git feeds were found in feeds.conf."
printf 'Verified %s pinned Git feed(s) and %s linked feed(s).\n' "$git_count" "$link_count"
