#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENWRT_DIR="${PROJECT_ROOT}/openwrt"
QG_ENABLE_NSS="${QG_ENABLE_NSS:-0}"
case "$QG_ENABLE_NSS" in
    1|true|TRUE|yes|YES) QG_ENABLE_NSS=1 ;;
    0|false|FALSE|no|NO) QG_ENABLE_NSS=0 ;;
    *) printf '\nERROR: QG_ENABLE_NSS must be 0/1, true/false or yes/no\n' >&2; exit 1 ;;
esac

if [[ "$QG_ENABLE_NSS" == "1" ]]; then
    OPENWRT_REPO="${QG_NSS_OPENWRT_REPO:-https://github.com/qosmio/openwrt-ipq.git}"
    OPENWRT_REF="${QG_NSS_OPENWRT_REF:-25.12-nss}"
    OPENWRT_EXPECTED_SHA="${QG_NSS_EXPECTED_SHA:-d6848fa2ea00193b5b7d3973e3990da7f608027c}"
    BUILD_PROFILE="AW1000 NSS (experimental)"
else
    OPENWRT_REPO="${QG_OPENWRT_REPO:-https://github.com/openwrt/openwrt.git}"
    OPENWRT_REF="${QG_OPENWRT_REF:-v25.12.6}"
    # The default v25.12.6 annotated tag is GPG-verified upstream and is
    # pinned here to its reviewed commit. Custom refs must supply their own SHA.
    OPENWRT_EXPECTED_SHA="${QG_OPENWRT_EXPECTED_SHA:-64900e756efa667774214f9c6b17c113222e01f7}"
    BUILD_PROFILE="AW1000 stable OpenWrt"
fi
BUILD_JOBS="${QG_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc)}"

die() {
    printf '\nERROR: %s\n' "$*" >&2
    exit 1
}

[[ "$BUILD_JOBS" =~ ^[1-9][0-9]*$ ]] || die "QG_BUILD_JOBS must be a positive integer"
[[ -n "$OPENWRT_REF" ]] || die "QG_OPENWRT_REF cannot be empty"

for command in git make python3; do
    command -v "$command" >/dev/null 2>&1 || die "$command is required"
done

printf '\n==============================================\n'
printf '        QUANTUMGRID OS BUILD SYSTEM\n'
printf '==============================================\n'
printf 'Build profile: %s\n' "$BUILD_PROFILE"
printf 'OpenWrt repo: %s\n' "$OPENWRT_REPO"
printf 'OpenWrt ref:  %s\n' "$OPENWRT_REF"
printf 'Expected SHA: %s\n' "$OPENWRT_EXPECTED_SHA"
printf 'Build jobs:   %s\n' "$BUILD_JOBS"

printf '\n[1/9] Preparing OpenWrt source...\n'
if [[ ! -d "$OPENWRT_DIR/.git" ]]; then
    if [[ -e "$OPENWRT_DIR" ]]; then
        die "$OPENWRT_DIR exists but is not a Git checkout; move it aside or configure the build path first"
    fi
    git clone --filter=blob:none --no-checkout "$OPENWRT_REPO" "$OPENWRT_DIR"
else
    if [[ -n "$(git -C "$OPENWRT_DIR" status --porcelain --untracked-files=no)" ]]; then
        die "OpenWrt checkout has modified tracked files; refusing to overwrite local source changes"
    fi
    CURRENT_ORIGIN="$(git -C "$OPENWRT_DIR" remote get-url origin 2>/dev/null || true)"
    if [[ "$CURRENT_ORIGIN" != "$OPENWRT_REPO" ]]; then
        git -C "$OPENWRT_DIR" remote set-url origin "$OPENWRT_REPO"
    fi
fi

printf '\n[2/9] Checking out pinned OpenWrt ref %s...\n' "$OPENWRT_REF"
git -C "$OPENWRT_DIR" remote get-url origin >/dev/null 2>&1 || die "OpenWrt checkout has no origin remote"
git -C "$OPENWRT_DIR" fetch --depth 1 origin "$OPENWRT_REF"
git -C "$OPENWRT_DIR" checkout --detach FETCH_HEAD
OPENWRT_SHA="$(git -C "$OPENWRT_DIR" rev-parse HEAD)"
sh "$PROJECT_ROOT/scripts/verify-openwrt-source.sh" "$OPENWRT_DIR" "$OPENWRT_EXPECTED_SHA"
printf 'OpenWrt commit: %s\n' "$OPENWRT_SHA"

printf '\n[3/9] Registering pinned AW1000 RJ11 phone feed...\n'
"$PROJECT_ROOT/scripts/setup-aw1000-phone-feed.sh" "$PROJECT_ROOT" "$OPENWRT_DIR"

printf '\n[4/9] Updating and installing OpenWrt feeds...\n'
cd "$OPENWRT_DIR"
./scripts/feeds update -a
./scripts/feeds install -a

printf '\n[5/10] Building and installing the QuantumGrid control centre...\n'
"$PROJECT_ROOT/scripts/build-ui.sh" "$PROJECT_ROOT" "$OPENWRT_DIR"

printf '\n[6/10] Installing QuantumGrid first-boot files...\n'
mkdir -p "$OPENWRT_DIR/files"
if [[ -d "$PROJECT_ROOT/files" ]]; then
    cp -a "$PROJECT_ROOT/files/." "$OPENWRT_DIR/files/"
fi

printf '\n[7/10] Applying AW1000 firmware configuration...\n'
CONFIG_FILE="$PROJECT_ROOT/configs/aw1000-max.config"
if [[ -f "$PROJECT_ROOT/configs/aw1000.config" ]]; then
    CONFIG_FILE="$PROJECT_ROOT/configs/aw1000.config"
fi
[[ -s "$CONFIG_FILE" ]] || die "AW1000 configuration not found: $CONFIG_FILE"
cp "$CONFIG_FILE" "$OPENWRT_DIR/.config"
if [[ "$QG_ENABLE_NSS" == "1" ]]; then
    NSS_FRAGMENT="$PROJECT_ROOT/configs/aw1000-nss.fragment"
    [[ -s "$NSS_FRAGMENT" ]] || die "NSS configuration fragment not found: $NSS_FRAGMENT"
    printf '\nApplying opt-in AW1000 NSS configuration fragment...\n'
    cat "$NSS_FRAGMENT" >> "$OPENWRT_DIR/.config"
fi
cd "$OPENWRT_DIR"
make defconfig
grep -qx 'CONFIG_TARGET_qualcommax=y' .config || die "qualcommax target was not selected"
grep -qx 'CONFIG_TARGET_qualcommax_ipq807x=y' .config || die "ipq807x subtarget was not selected"
grep -qx 'CONFIG_TARGET_qualcommax_ipq807x_DEVICE_arcadyan_aw1000=y' .config || die "Arcadyan AW1000 profile was not selected"
if [[ "$QG_ENABLE_NSS" == "1" ]]; then
    grep -qx 'CONFIG_ATH11K_NSS_SUPPORT=y' .config || die "ath11k NSS Wi-Fi support was not selected"
    grep -qx 'CONFIG_PACKAGE_MAC80211_NSS_SUPPORT=y' .config || die "mac80211 NSS support was not selected"
    grep -qx 'CONFIG_NSS_FIRMWARE_VERSION_12_5=y' .config || die "NSS firmware 12.5 was not selected"
    grep -qx 'CONFIG_PACKAGE_kmod-qca-nss-drv=y' .config || die "NSS core driver package was not selected"
    grep -qx 'CONFIG_PACKAGE_kmod-qca-nss-ecm=y' .config || die "NSS ECM package was not selected"
    grep -qx 'CONFIG_PACKAGE_kmod-qca-nss-dp=y' .config || die "NSS datapath driver package was not selected"
    grep -qx 'CONFIG_PACKAGE_kmod-qca-ssdk=y' .config || die "Qualcomm SSDK package was not selected"
    grep -qx 'CONFIG_PACKAGE_kmod-qca-nss-drv-bridge-mgr=y' .config || die "NSS bridge manager package was not selected"
    grep -qx 'CONFIG_PACKAGE_nss-firmware-ipq807x=y' .config || die "IPQ807x NSS firmware package was not selected"
    grep -qx 'CONFIG_PACKAGE_kmod-qca-mcs=y' .config || die "NSS multicast snooping package was not selected"
    grep -qx 'CONFIG_PACKAGE_sqm-scripts-nss=y' .config || die "NSS SQM scripts package was not selected"
    grep -qx 'CONFIG_ATH11K_MEM_PROFILE_1G=y' .config || die "1 GiB ath11k memory profile was not selected"
    grep -qx 'CONFIG_NSS_MEM_PROFILE_HIGH=y' .config || die "high-memory NSS profile was not selected"
    grep -qx 'CONFIG_NSS_DRV_BRIDGE_ENABLE=y' .config || die "NSS bridge support was not enabled"
    grep -qx 'CONFIG_NSS_DRV_IPV6_ENABLE=y' .config || die "NSS IPv6 support was not enabled"
    grep -qx 'CONFIG_NSS_DRV_PPPOE_ENABLE=y' .config || die "NSS PPPoE support was not enabled"
    grep -qx 'CONFIG_NSS_DRV_VLAN_ENABLE=y' .config || die "NSS VLAN support was not enabled"
    grep -qx 'CONFIG_NSS_DRV_WIFIOFFLOAD_ENABLE=y' .config || die "NSS Wi-Fi offload support was not enabled"
    printf 'Validated NSS Wi-Fi, firmware, core-driver and ECM selections.\n'
fi

printf '\n[8/10] Running OpenWrt prerequisites...\n'
make prereq

printf '\n[9/10] Downloading source packages...\n'
make download -j"$BUILD_JOBS"

printf '\n[10/10] Building QuantumGrid AW1000 firmware...\n'
make -j"$BUILD_JOBS" V=s

printf '\n==============================================\n'
printf '       QUANTUMGRID BUILD COMPLETE\n'
printf '==============================================\n'
printf 'OpenWrt commit: %s\n' "$OPENWRT_SHA"
printf '\nFirmware outputs:\n'
find "$OPENWRT_DIR/bin/targets/qualcommax/ipq807x" -maxdepth 1 -type f \
    \( -name '*arcadyan_aw1000-squashfs-factory.ubi' -o -name '*arcadyan_aw1000-initramfs-uImage.itb' \) \
    -print | sort
