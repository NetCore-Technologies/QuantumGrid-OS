#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
SCRIPT="$ROOT/files/etc/uci-defaults/96-quantumgrid-device-id"
ID_FILE="$TEMP_DIR/device-id"

bash -n "$SCRIPT"
sh "$SCRIPT" "$ID_FILE"
test -f "$ID_FILE"
DEVICE_ID="$(cat "$ID_FILE")"
[[ "$DEVICE_ID" =~ ^[0-9a-f]{32}$ ]]
test "$(wc -c < "$ID_FILE" | tr -d '[:space:]')" = "33"
test "$(stat -c '%a' "$ID_FILE")" = "644"

# Re-running first-boot provisioning must preserve the existing inventory key.
sh "$SCRIPT" "$ID_FILE"
test "$(cat "$ID_FILE")" = "$DEVICE_ID"

# A damaged pre-existing identity is never silently rotated.
printf 'invalid-device-id\n' > "$TEMP_DIR/corrupt-id"
sh "$SCRIPT" "$TEMP_DIR/corrupt-id"
test "$(cat "$TEMP_DIR/corrupt-id")" = "invalid-device-id"

# Refuse to follow a symlink for the identity path.
printf 'target-must-not-change\n' > "$TEMP_DIR/target"
ln -s "$TEMP_DIR/target" "$TEMP_DIR/symlink-id"
sh "$SCRIPT" "$TEMP_DIR/symlink-id"
test -L "$TEMP_DIR/symlink-id"
test "$(cat "$TEMP_DIR/target")" = "target-must-not-change"

printf 'device-identity: first-boot provisioning, idempotency and corruption guards passed\n'
