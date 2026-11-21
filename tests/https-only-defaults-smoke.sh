#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY="$ROOT/files/etc/uci-defaults/95-quantumgrid-https-only"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
export UCI_LOG="$TMP/uci.log"
export UCI_HTTP_LISTENER="$TMP/http-listener-present"
cat > "$TMP/bin/uci" <<'UCI'
#!/bin/sh
if [ "${1:-}" = "-q" ]; then shift; fi
case "${1:-}" in
  get) [ -f "$UCI_HTTP_LISTENER" ] ;;
  delete) printf '%s\n' "$*" >> "$UCI_LOG"; rm -f "$UCI_HTTP_LISTENER" ;;
  set|commit) printf '%s\n' "$*" >> "$UCI_LOG" ;;
  *) echo "unexpected uci command: $*" >&2; exit 64 ;;
esac
UCI
chmod +x "$TMP/bin/uci"
export PATH="$TMP/bin:$PATH"
touch "$UCI_HTTP_LISTENER"
sh -n "$POLICY"

# First boot removes the HTTP listener, enables the HTTPS redirect setting and commits.
sh "$POLICY"
test ! -e "$UCI_HTTP_LISTENER"
grep -Fqx 'delete uhttpd.main.listen_http' "$UCI_LOG"
grep -Fqx 'set uhttpd.main.redirect_https=1' "$UCI_LOG"
grep -Fqx 'commit uhttpd' "$UCI_LOG"

# The policy remains idempotent when the HTTP listener is already absent.
before="$(wc -l < "$UCI_LOG")"
sh "$POLICY"
after="$(wc -l < "$UCI_LOG")"
test "$after" -eq $((before + 2))
test "$(grep -Fc 'delete uhttpd.main.listen_http' "$UCI_LOG")" -eq 1
test "$(grep -Fc 'set uhttpd.main.redirect_https=1' "$UCI_LOG")" -eq 2
test "$(grep -Fc 'commit uhttpd' "$UCI_LOG")" -eq 2

echo "HTTPS-only first-boot policy tests passed."
