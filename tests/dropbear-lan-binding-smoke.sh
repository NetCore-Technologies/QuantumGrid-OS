#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT/files/etc/config/dropbear"
test -s "$CONFIG"
grep -Fqx 'config dropbear main' "$CONFIG"
grep -Fqx "	option enable '1'" "$CONFIG"
grep -Fqx "	option PasswordAuth 'on'" "$CONFIG"
grep -Fqx "	option RootPasswordAuth 'on'" "$CONFIG"
grep -Fqx "	option Interface 'lan'" "$CONFIG"
grep -Fqx "	option Port '22'" "$CONFIG"
grep -Fqx "	option GatewayPorts 'off'" "$CONFIG"
test "$(grep -Fc "option Interface" "$CONFIG")" -eq 1
grep -Fqx "	option Interface 'lan'" "$CONFIG"
echo 'Dropbear LAN-only management binding tests passed.'
