#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

INIT="$WORK/openwrt/feeds/packages/net/net-snmp/files/snmpd.init"
mkdir -p "$(dirname "$INIT")"
cat > "$INIT" <<'INIT'
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1

start_service() {
	[ -f "$CONFIGFILE" ] && rm -f "$CONFIGFILE"
	config_load snmpd
	procd_close_instance
}

service_stopped() {
	rm -f "$CONFIGFILE"
}
INIT
chmod 0755 "$INIT"

bash "$ROOT/scripts/secure-aw1000-snmpd-runtime-config.sh" "$WORK/openwrt"
grep -Fq '# QuantumGrid: protect generated SNMPv3 runtime credentials' "$INIT"
grep -Fq $'\tumask 077' "$INIT"
python3 - "$INIT" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
start = text.index("start_service() {")
umask = text.index("umask 077", start)
remove = text.index('rm -f "$CONFIGFILE"', start)
assert start < umask < remove, "umask must be set before runtime config is deleted/recreated"
PY

before="$(sha256sum "$INIT" | awk '{print $1}')"
bash "$ROOT/scripts/secure-aw1000-snmpd-runtime-config.sh" "$WORK/openwrt"
after="$(sha256sum "$INIT" | awk '{print $1}')"
[ "$before" = "$after" ] || {
  echo "ERROR: applying the Net-SNMP umask patch twice changed the file" >&2
  exit 1
}
[ "$(stat -c '%a' "$INIT")" = "755" ] || {
  echo "ERROR: init script executable mode was not preserved" >&2
  exit 1
}

# Unexpected upstream layout must be rejected without modifying the file.
UNSUPPORTED="$WORK/unsupported/feeds/packages/net/net-snmp/files/snmpd.init"
mkdir -p "$(dirname "$UNSUPPORTED")"
printf '#!/bin/sh\nstart_service() {\n' > "$UNSUPPORTED"
cp "$UNSUPPORTED" "$WORK/unsupported.before"
if bash "$ROOT/scripts/secure-aw1000-snmpd-runtime-config.sh" "$WORK/unsupported" >/dev/null 2>&1; then
  echo "ERROR: unsupported upstream init script was accepted" >&2
  exit 1
fi
cmp -s "$UNSUPPORTED" "$WORK/unsupported.before" || {
  echo "ERROR: unsupported init script was modified" >&2
  exit 1
}

# A symlinked package init script is never rewritten through the build overlay.
LINKROOT="$WORK/symlink"
mkdir -p "$LINKROOT/feeds/packages/net/net-snmp/files"
ln -s "$INIT" "$LINKROOT/feeds/packages/net/net-snmp/files/snmpd.init"
if bash "$ROOT/scripts/secure-aw1000-snmpd-runtime-config.sh" "$LINKROOT" >/dev/null 2>&1; then
  echo "ERROR: symlinked Net-SNMP init script was accepted" >&2
  exit 1
fi

echo "AW1000 Net-SNMP credential umask patch: pre-write privacy, idempotence and upstream-layout rejection passed"
