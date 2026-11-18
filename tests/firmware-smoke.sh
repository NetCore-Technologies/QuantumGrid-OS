#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT/configs/aw1000-max.config"

grep -qx 'CONFIG_TARGET_qualcommax=y' "$CONFIG"
grep -qx 'CONFIG_TARGET_qualcommax_ipq807x=y' "$CONFIG"
grep -qx 'CONFIG_TARGET_qualcommax_ipq807x_DEVICE_arcadyan_aw1000=y' "$CONFIG"

for package in kmod-usb-serial-option kmod-aw1000-fxs fxsd luci-app-fxs; do
    grep -qx "CONFIG_PACKAGE_${package}=y" "$CONFIG"
done

grep -Fq 'setup-aw1000-phone-feed.sh' "$ROOT/build.sh"
grep -Fq 'scripts/build-ui.sh' "$ROOT/build.sh"
grep -Fq 'npm ci --no-audit --no-fund' "$ROOT/scripts/build-ui.sh"
grep -Fq 'files/www/quantumgrid' "$ROOT/scripts/build-ui.sh"
grep -Fq "base: './'" "$ROOT/ui/quantumgrid/vite.config.ts"
grep -Fq 'src-link quantumgrid_phone ' "$ROOT/scripts/setup-aw1000-phone-feed.sh"
! grep -Fq 'src-link quantumgrid-phone ' "$ROOT/scripts/setup-aw1000-phone-feed.sh"
grep -Fq 'setup-aw1000-phone-feed.sh' "$ROOT/quantumgrid-configure.sh"
grep -Fq 'OPENWRT_REF="${QG_OPENWRT_REF:-v25.12.6}"' "$ROOT/build.sh"
grep -Fq 'QG_OPENWRT_REF:' "$ROOT/.github/workflows/firmware-release.yml"
grep -Fq 'squashfs-sysupgrade.bin' "$ROOT/.github/workflows/firmware-release.yml"
grep -Fq 'squashfs-factory.ubi' "$ROOT/.github/workflows/firmware-release.yml"
grep -Fq 'initramfs-uImage.itb' "$ROOT/.github/workflows/firmware-release.yml"
grep -Fq 'function PhonePage()' "$ROOT/ui/quantumgrid/src/App.tsx"
grep -Fq 'admin/services/quantumgrid/api' "$ROOT/ui/quantumgrid/src/routerApi.ts"
grep -Fq 'loginToRouter' "$ROOT/ui/quantumgrid/src/App.tsx"
grep -Fq 'network.interface' "$ROOT/files/usr/lib/lua/luci/controller/quantumgrid.lua"
grep -Fq 'network.wireless' "$ROOT/files/usr/lib/lua/luci/controller/quantumgrid.lua"
grep -Fq 'http.write_json' "$ROOT/files/usr/lib/lua/luci/controller/quantumgrid.lua"
grep -Fq 'action_set_password' "$ROOT/files/usr/lib/lua/luci/controller/quantumgrid.lua"
grep -Fq 'sys.user.setpasswd' "$ROOT/files/usr/lib/lua/luci/controller/quantumgrid.lua"
grep -Fq 'The router already has a root password.' "$ROOT/files/usr/lib/lua/luci/controller/quantumgrid.lua"
grep -Fq 'authenticate(username, "")' "$ROOT/ui/quantumgrid/src/routerApi.ts"
grep -Fq '/cgi-bin/luci/admin/services/fxs/status' "$ROOT/ui/quantumgrid/src/App.tsx"
grep -Fq "uci -q set fxs.main.enabled='0'" "$ROOT/files/etc/uci-defaults/90-quantumgrid-fxs-safe"

echo "QuantumGrid AW1000 target, pinned firmware source, RJ11 and release asset checks passed."
