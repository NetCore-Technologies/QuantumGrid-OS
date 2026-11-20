#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build.sh"
NSS="$ROOT/configs/aw1000-nss.fragment"
DEFAULT="$ROOT/configs/aw1000-max.config"
BOOT="$ROOT/files/etc/uci-defaults/92-quantumgrid-nss-safe"
RELEASE="$ROOT/.github/workflows/firmware-release.yml"

# The stable config must remain free of vendor NSS packages and Kconfig flags.
! grep -Eq 'CONFIG_(ATH11K_NSS_SUPPORT|PACKAGE_MAC80211_NSS_SUPPORT|NSS_FIRMWARE_VERSION_12_5|NSS_DRV_WIFIOFFLOAD_ENABLE)=y' "$DEFAULT"
! grep -Eq 'CONFIG_PACKAGE_(kmod-qca-nss-drv|kmod-qca-nss-ecm|nss-firmware-ipq807x)=y' "$DEFAULT"

# The separate fragment must select the matching 25.12 NSS/ath11k integration.
grep -qx 'CONFIG_ATH11K_NSS_SUPPORT=y' "$NSS"
grep -qx 'CONFIG_PACKAGE_MAC80211_NSS_SUPPORT=y' "$NSS"
grep -qx 'CONFIG_NSS_FIRMWARE_VERSION_12_5=y' "$NSS"
grep -qx 'CONFIG_NSS_MEM_PROFILE_HIGH=y' "$NSS"
grep -qx 'CONFIG_NSS_DRV_WIFIOFFLOAD_ENABLE=y' "$NSS"
grep -qx 'CONFIG_NSS_DRV_WIFI_EXT_VDEV_ENABLE=y' "$NSS"
grep -qx 'CONFIG_PACKAGE_kmod-qca-mcs=y' "$NSS"
grep -qx 'CONFIG_PACKAGE_sqm-scripts-nss=y' "$NSS"
grep -Fq 'CONFIG_ATH11K_NSS_MESH_SUPPORT is not set' "$NSS"

# The profile is opt-in and pinned; do not let NSS silently replace stable builds.
grep -Fq 'QG_ENABLE_NSS="${QG_ENABLE_NSS:-0}"' "$BUILD"
grep -Fq 'https://github.com/qosmio/openwrt-ipq.git' "$BUILD"
grep -Fq 'd6848fa2ea00193b5b7d3973e3990da7f608027c' "$BUILD"
grep -Fq 'configs/aw1000-nss.fragment' "$BUILD"
grep -Fq 'CONFIG_ATH11K_NSS_SUPPORT=y' "$BUILD"
grep -Fq 'CONFIG_PACKAGE_kmod-qca-nss-drv=y' "$BUILD"
grep -Fq 'CONFIG_PACKAGE_kmod-qca-nss-ecm=y' "$BUILD"
grep -Fq 'CONFIG_PACKAGE_kmod-qca-nss-dp=y' "$BUILD"
grep -Fq 'CONFIG_PACKAGE_kmod-qca-ssdk=y' "$BUILD"
grep -Fq 'CONFIG_PACKAGE_nss-firmware-ipq807x=y' "$BUILD"
grep -Fq 'CONFIG_PACKAGE_kmod-qca-nss-drv-bridge-mgr=y' "$BUILD"
grep -Fq 'CONFIG_NSS_DRV_WIFIOFFLOAD_ENABLE=y' "$BUILD"
grep -Fq 'enable_nss:' "$RELEASE"
grep -Fq 'default: false' "$RELEASE"
grep -Fq 'QG_ENABLE_NSS:' "$RELEASE"

# The first-boot script only acts on an image that actually contains NSS.
grep -Fq '[ -x /etc/init.d/qca-nss-drv ] || exit 0' "$BOOT"
grep -Fq 'qca-nss-ecm' "$BOOT"
grep -Fq 'packet_steering' "$BOOT"
grep -Fq 'flow_offloading_hw' "$BOOT"

echo "QuantumGrid optional NSS profile, pinned source, Kconfig and safe defaults passed."
