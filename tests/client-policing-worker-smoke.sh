#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
WORKER="$ROOT/files/usr/bin/quantumgrid-client-policing"
MANAGER="$ROOT/files/usr/lib/lua/luci/quantumgrid/client_policing.lua"
POLICY="$ROOT/files/usr/lib/lua/luci/quantumgrid/qos_policing.lua"
INIT="$ROOT/files/etc/init.d/quantumgrid-client-policing"
HOTPLUG="$ROOT/files/etc/hotplug.d/iface/98-quantumgrid-client-policing"
DEFAULTS="$ROOT/files/etc/uci-defaults/98-quantumgrid-client-policing"

for path in "$WORKER" "$MANAGER" "$POLICY" "$INIT" "$HOTPLUG" "$DEFAULTS"; do
  test -s "$path"
done
for path in "$WORKER" "$INIT" "$HOTPLUG" "$DEFAULTS"; do
  test -x "$path"
done

grep -Fq 'luci.quantumgrid.client_policing' "$WORKER"
grep -Fq 'luci.quantumgrid.qos_policing' "$WORKER"
grep -Fq 'static_leases' "$WORKER"
grep -Fq 'qdisc clsact' "$WORKER"
grep -Fq 'tc qdisc add dev ' "$WORKER"
grep -Fq 'modprobe act_police' "$WORKER"
grep -Fq 'tc filter show dev ' "$WORKER"
grep -Fq 'replace_filter' "$WORKER"
grep -Fq 'delete_filter' "$WORKER"
grep -Fq 'write_json_atomic' "$WORKER"
grep -Fq 'police rate ' "$POLICY"
grep -Fq 'conform-exceed drop/ok' "$POLICY"
grep -Fq 'does not reserve bandwidth' "$MANAGER"
grep -Fq 'ensure_clsact' "$MANAGER"
grep -Fq 'device_has_clsact' "$MANAGER"

# Root qdiscs, CAKE and unmanaged classifiers must never be replaced/removed.
! grep -Eq 'tc qdisc (replace|del) ' "$WORKER"
! grep -Eq 'tc filter (flush|del).*root' "$WORKER"

grep -Fq 'quantumgrid-client-policing' "$INIT"
grep -Fq 'ifup|ifdown|ifupdate' "$HOTPLUG"
grep -Fq 'quantumgrid-client-policing' "$DEFAULTS"

echo "client-policing-worker: executable worker, static-lease inventory, clsact-only TC plan, bounded state, init/hotplug and first-boot checks passed"
