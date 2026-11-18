#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENWRT_DIR="${PROJECT_ROOT}/openwrt"
OPENWRT_REPO="https://github.com/openwrt/openwrt.git"
OPENWRT_REF="${QG_OPENWRT_REF:-v25.12.6}"
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
printf 'OpenWrt ref: %s\n' "$OPENWRT_REF"
printf 'Build jobs:  %s\n' "$BUILD_JOBS"

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
fi

printf '\n[2/9] Checking out pinned OpenWrt ref %s...\n' "$OPENWRT_REF"
git -C "$OPENWRT_DIR" remote get-url origin >/dev/null 2>&1 || die "OpenWrt checkout has no origin remote"
git -C "$OPENWRT_DIR" fetch --depth 1 origin "$OPENWRT_REF"
git -C "$OPENWRT_DIR" checkout --detach FETCH_HEAD
OPENWRT_SHA="$(git -C "$OPENWRT_DIR" rev-parse HEAD)"
printf 'OpenWrt commit: %s\n' "$OPENWRT_SHA"

printf '\n[3/9] Registering pinned AW1000 RJ11 phone feed...\n'
"$PROJECT_ROOT/scripts/setup-aw1000-phone-feed.sh" "$PROJECT_ROOT" "$OPENWRT_DIR"

printf '\n[4/9] Updating and installing OpenWrt feeds...\n'
cd "$OPENWRT_DIR"
./scripts/feeds update -a
./scripts/feeds install -a

printf '\n[5/9] Installing QuantumGrid first-boot files...\n'
mkdir -p "$OPENWRT_DIR/files"
if [[ -d "$PROJECT_ROOT/files" ]]; then
    cp -a "$PROJECT_ROOT/files/." "$OPENWRT_DIR/files/"
fi

printf '\n[6/9] Applying AW1000 firmware configuration...\n'
CONFIG_FILE="$PROJECT_ROOT/configs/aw1000-max.config"
if [[ -f "$PROJECT_ROOT/configs/aw1000.config" ]]; then
    CONFIG_FILE="$PROJECT_ROOT/configs/aw1000.config"
fi
[[ -s "$CONFIG_FILE" ]] || die "AW1000 configuration not found: $CONFIG_FILE"
cp "$CONFIG_FILE" "$OPENWRT_DIR/.config"
cd "$OPENWRT_DIR"
make defconfig
grep -qx 'CONFIG_TARGET_qualcommax=y' .config || die "qualcommax target was not selected"
grep -qx 'CONFIG_TARGET_qualcommax_ipq807x=y' .config || die "ipq807x subtarget was not selected"
grep -qx 'CONFIG_TARGET_qualcommax_ipq807x_DEVICE_arcadyan_aw1000=y' .config || die "Arcadyan AW1000 profile was not selected"

printf '\n[7/9] Running OpenWrt prerequisites...\n'
make prereq

printf '\n[8/9] Downloading source packages...\n'
make download -j"$BUILD_JOBS"

printf '\n[9/9] Building QuantumGrid AW1000 firmware...\n'
make -j"$BUILD_JOBS" V=s

printf '\n==============================================\n'
printf '       QUANTUMGRID BUILD COMPLETE\n'
printf '==============================================\n'
printf 'OpenWrt commit: %s\n' "$OPENWRT_SHA"
printf '\nFirmware outputs:\n'
find "$OPENWRT_DIR/bin/targets/qualcommax/ipq807x" -maxdepth 1 -type f \
    \( -name '*arcadyan_aw1000*.bin' -o -name '*arcadyan_aw1000*.ubi' -o -name '*arcadyan_aw1000*.itb' \) \
    -print | sort
