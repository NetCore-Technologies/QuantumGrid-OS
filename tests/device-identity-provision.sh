#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
SCRIPT="$ROOT/files/etc/uci-defaults/96-quantumgrid-device-id"

make_test_script() {
    local id_file="$1"
    local output="$2"
    sed "s|^ID_FILE=\"/etc/quantumgrid/device-id\"$|ID_FILE=\"$id_file\"|" "$SCRIPT" > "$output"
    test -s "$output"
}

run_as_uci_default() {
    # /etc/init.d/boot sources each default in a subshell; mirror that execution.
    sh -c '. "$1"' sh "$1"
}

ID_FILE="$TEMP_DIR/device-id"
PROVISION_SCRIPT="$TEMP_DIR/provision.sh"
make_test_script "$ID_FILE" "$PROVISION_SCRIPT"
bash -n "$PROVISION_SCRIPT"
run_as_uci_default "$PROVISION_SCRIPT"
test -f "$ID_FILE"
DEVICE_ID="$(cat "$ID_FILE")"
[[ "$DEVICE_ID" =~ ^[0-9a-f]{32}$ ]]
test "$(wc -c < "$ID_FILE" | tr -d '[:space:]')" = "33"
test "$(stat -c '%a' "$ID_FILE")" = "644"

# Re-running first-boot provisioning must preserve the existing inventory key.
run_as_uci_default "$PROVISION_SCRIPT"
test "$(cat "$ID_FILE")" = "$DEVICE_ID"

# A damaged pre-existing identity is never silently rotated.
CORRUPT_ID="$TEMP_DIR/corrupt-id"
CORRUPT_SCRIPT="$TEMP_DIR/corrupt-provision.sh"
printf 'invalid-device-id\n' > "$CORRUPT_ID"
make_test_script "$CORRUPT_ID" "$CORRUPT_SCRIPT"
run_as_uci_default "$CORRUPT_SCRIPT"
test "$(cat "$CORRUPT_ID")" = "invalid-device-id"

# Refuse to follow a symlink for the identity path.
TARGET="$TEMP_DIR/target"
SYMLINK_ID="$TEMP_DIR/symlink-id"
SYMLINK_SCRIPT="$TEMP_DIR/symlink-provision.sh"
printf 'target-must-not-change\n' > "$TARGET"
ln -s "$TARGET" "$SYMLINK_ID"
make_test_script "$SYMLINK_ID" "$SYMLINK_SCRIPT"
run_as_uci_default "$SYMLINK_SCRIPT"
test -L "$SYMLINK_ID"
test "$(cat "$TARGET")" = "target-must-not-change"

printf 'device-identity: sourced UCI-default provisioning, idempotency and corruption guards passed\n'
