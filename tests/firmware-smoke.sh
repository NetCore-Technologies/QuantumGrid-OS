#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT/configs/aw1000-max.config"
grep -qx 'CONFIG_TARGET_qualcommax=y' "$CONFIG"
grep -qx 'CONFIG_TARGET_qualcommax_ipq807x=y' "$CONFIG"
grep -qx 'CONFIG_TARGET_qualcommax_ipq807x_DEVICE_arcadyan_aw1000=y' "$CONFIG"
for package in kmod-usb-serial-option kmod-aw1000-fxs fxsd luci-app-fxs; do
    grep -qx "CONFIG_PACKAGE_${package}=y" "$CONFIG"
done
grep -Fq 'setup-aw1000-phone-feed.sh' "$ROOT/build.sh"
grep -Fq 'setup-aw1000-phone-feed.sh' "$ROOT/quantumgrid-configure.sh"
grep -Fq 'function PhonePage()' "$ROOT/ui/quantumgrid/src/App.tsx"
grep -Fq '/cgi-bin/luci/admin/services/fxs/status' "$ROOT/ui/quantumgrid/src/App.tsx"
grep -Fq "uci -q set fxs.main.enabled='0'" "$ROOT/files/etc/uci-defaults/90-quantumgrid-fxs-safe"
echo "QuantumGrid AW1000 profile, RJ11 package and safe-default checks passed."
