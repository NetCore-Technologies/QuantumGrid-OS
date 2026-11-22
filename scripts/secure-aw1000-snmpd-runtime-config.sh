#!/usr/bin/env bash
set -Eeuo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ $# -eq 1 ]] || die "Usage: $0 <OpenWrt-worktree>"
OPENWRT_DIR=$1
[[ -d "$OPENWRT_DIR" ]] || die "OpenWrt worktree does not exist: $OPENWRT_DIR"
INIT_SCRIPT="$OPENWRT_DIR/feeds/packages/net/net-snmp/files/snmpd.init"
[[ -f "$INIT_SCRIPT" && ! -L "$INIT_SCRIPT" && -r "$INIT_SCRIPT" && -w "$INIT_SCRIPT" ]] ||
  die "Expected a readable, writable, regular Net-SNMP init script at $INIT_SCRIPT"

python3 - "$INIT_SCRIPT" <<'PY'
import os
import stat
import sys
import tempfile

path = sys.argv[1]
marker = "# QuantumGrid: protect generated SNMPv3 runtime credentials"
try:
    info = os.lstat(path)
    if not stat.S_ISREG(info.st_mode):
        raise ValueError("Net-SNMP init script must be a regular file")
    with open(path, "r", encoding="utf-8", newline="") as source:
        content = source.read()
except (OSError, UnicodeError, ValueError) as exc:
    raise SystemExit(f"ERROR: cannot inspect Net-SNMP init script: {exc}")

if content.count(marker) > 1:
    raise SystemExit("ERROR: multiple QuantumGrid SNMP runtime umask markers found")

lines = content.splitlines(keepends=True)
matches = [index for index, line in enumerate(lines) if line.rstrip("\r\n") == "start_service() {"]
if len(matches) != 1:
    raise SystemExit("ERROR: expected exactly one upstream start_service() function")

start = matches[0]
expected = [
    "\t" + marker + "\n",
    "\tumask 077\n",
]
already = lines[start + 1:start + 3]
if len(already) == 2 and already[0].rstrip("\r\n") == "\t" + marker and already[1].rstrip("\r\n") == "\tumask 077":
    raise SystemExit(0)
if marker in content or (start + 1 < len(lines) and lines[start + 1].strip() == "umask 077"):
    raise SystemExit("ERROR: unexpected existing SNMP runtime umask modification")

updated = "".join(lines[:start + 1] + expected + lines[start + 1:])
directory = os.path.dirname(path)
fd, temporary = tempfile.mkstemp(prefix=".snmpd.init.", dir=directory)
try:
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as target:
        target.write(updated)
        target.flush()
        os.fsync(target.fileno())
    os.chmod(temporary, stat.S_IMODE(info.st_mode))
    os.replace(temporary, path)
except OSError as exc:
    try:
        os.unlink(temporary)
    except OSError:
        pass
    raise SystemExit(f"ERROR: cannot atomically secure Net-SNMP init script: {exc}")

print("Net-SNMP start_service now uses umask 077 before creating the runtime credential file.")
PY
