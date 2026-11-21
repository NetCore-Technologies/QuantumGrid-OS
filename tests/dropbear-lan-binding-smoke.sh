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
if grep -Eq "option[[:space:]]+Interface[[:space:]]+['\"]?(wan|any|\\*)" "$CONFIG"; then
  echo 'ERROR: Dropbear must not bind to WAN or all interfaces.' >&2
  exit 1
fi
echo 'Dropbear LAN-only management binding tests passed.'
