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
    BUILD_PROFILE=""
else
    OPENWRT_REPO="${QG_OPENWRT_REPO:-https://github.com/openwrt/openwrt.git}"
    OPENWRT_REF="${QG_OPENWRT_REF:-v25.12.6}"
    # The default v25.12.6 annotated tag is GPG-verified upstream and is
    # pinned here to its reviewed commit. Custom refs must supply their own SHA.
    OPENWRT_EXPECTED_SHA="${QG_OPENWRT_EXPECTED_SHA:-64900e756efa667774214f9c6b17c113222e01f7}"
    BUILD_PROFILE=""
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

DEVICE_PROFILE="${QG_DEVICE_PROFILE:-${PROJECT_ROOT}/profiles/arcadyan-aw1000.json}"
if [[ "$DEVICE_PROFILE" != /* ]]; then
    DEVICE_PROFILE="$PROJECT_ROOT/$DEVICE_PROFILE"
fi
PROFILE_FIELDS_FILE="$(mktemp "${TMPDIR:-/tmp}/qg-device-profile.XXXXXX")" || die "Could not create temporary device-profile field file"
if ! python3 "$PROJECT_ROOT/scripts/verify-device-profile.py" "$DEVICE_PROFILE" --lines > "$PROFILE_FIELDS_FILE"; then
    rm -f "$PROFILE_FIELDS_FILE"
    die "The selected QuantumGrid device profile failed validation"
fi
mapfile -t PROFILE_FIELDS < "$PROFILE_FIELDS_FILE"
rm -f "$PROFILE_FIELDS_FILE"
((${#PROFILE_FIELDS[@]} == 17)) || die "Device profile returned an incomplete build contract"
DEVICE_PROFILE_ID="${PROFILE_FIELDS[0]}"
PLATFORM_VENDOR="${PROFILE_FIELDS[1]}"
PLATFORM_MODEL="${PROFILE_FIELDS[2]}"
OPENWRT_TARGET="${PROFILE_FIELDS[3]}"
OPENWRT_SUBTARGET="${PROFILE_FIELDS[4]}"
OPENWRT_DEVICE="${PROFILE_FIELDS[5]}"
PROFILE_CONFIG_FILE="${PROFILE_FIELDS[6]}"
NSS_SUPPORTED="${PROFILE_FIELDS[7]}"
NSS_FRAGMENT="${PROFILE_FIELDS[8]}"
NSS_FEED_PINS="${PROFILE_FIELDS[9]}"
NSS_PIN_SCRIPT="${PROFILE_FIELDS[10]}"
NSS_REQUIRED_CONFIG_SYMBOLS="${PROFILE_FIELDS[11]}"
FXS_SUPPORTED="${PROFILE_FIELDS[12]}"
FXS_SETUP_SCRIPT="${PROFILE_FIELDS[13]}"
OUTPUT_DIRECTORY="${PROFILE_FIELDS[14]}"
FACTORY_GLOB="${PROFILE_FIELDS[15]}"
INITRAMFS_GLOB="${PROFILE_FIELDS[16]}"
[[ "$NSS_SUPPORTED" == "0" || "$NSS_SUPPORTED" == "1" ]] || die "Device profile returned an invalid NSS capability"
[[ "$FXS_SUPPORTED" == "0" || "$FXS_SUPPORTED" == "1" ]] || die "Device profile returned an invalid FXS capability"
if [[ "$QG_ENABLE_NSS" == "1" && "$NSS_SUPPORTED" != "1" ]]; then
    die "Device profile $DEVICE_PROFILE_ID does not declare NSS support"
fi
CONFIG_FILE="$PROJECT_ROOT/$PROFILE_CONFIG_FILE"
NSS_FRAGMENT_PATH="$PROJECT_ROOT/$NSS_FRAGMENT"
NSS_FEED_PINS_PATH="$PROJECT_ROOT/$NSS_FEED_PINS"
NSS_PIN_SCRIPT_PATH="$PROJECT_ROOT/$NSS_PIN_SCRIPT"
FXS_SETUP_SCRIPT_PATH="$PROJECT_ROOT/$FXS_SETUP_SCRIPT"
OUTPUT_PATH="$OPENWRT_DIR/bin/targets/$OUTPUT_DIRECTORY"
if [[ "$QG_ENABLE_NSS" == "1" ]]; then
    BUILD_PROFILE="$PLATFORM_VENDOR $PLATFORM_MODEL NSS (experimental)"
else
    BUILD_PROFILE="$PLATFORM_VENDOR $PLATFORM_MODEL stable OpenWrt"
fi
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
    bash "$PROJECT_ROOT/scripts/check-openwrt-worktree.sh" "$OPENWRT_DIR" "$OPENWRT_REPO"
fi

printf '\n[2/9] Checking out pinned OpenWrt ref %s...\n' "$OPENWRT_REF"
git -C "$OPENWRT_DIR" remote get-url origin >/dev/null 2>&1 || die "OpenWrt checkout has no origin remote"
git -C "$OPENWRT_DIR" fetch --depth 1 origin "$OPENWRT_REF"
git -C "$OPENWRT_DIR" checkout --detach FETCH_HEAD
OPENWRT_SHA="$(git -C "$OPENWRT_DIR" rev-parse HEAD)"
sh "$PROJECT_ROOT/scripts/verify-openwrt-source.sh" "$OPENWRT_DIR" "$OPENWRT_EXPECTED_SHA"
if [[ "$QG_ENABLE_NSS" == "1" ]]; then
    "$NSS_PIN_SCRIPT_PATH" "$OPENWRT_DIR" "$NSS_FEED_PINS_PATH"
fi
printf 'OpenWrt commit: %s\n' "$OPENWRT_SHA"

if [[ "$FXS_SUPPORTED" == "1" ]]; then
    printf '\n[3/9] Registering the device profile's pinned FXS phone feed...\n'
    "$FXS_SETUP_SCRIPT_PATH" "$PROJECT_ROOT" "$OPENWRT_DIR"
else
    printf '\n[3/9] Skipping FXS integration: this device profile does not declare FXS support.\n'
fi

printf '\n[4/9] Updating and installing OpenWrt feeds...\n'
cd "$OPENWRT_DIR"
./scripts/feeds update -a
bash "$PROJECT_ROOT/scripts/verify-openwrt-feeds.sh" "$OPENWRT_DIR"
./scripts/feeds install -a

printf '\n[5/10] Building and installing the QuantumGrid control centre...\n'
"$PROJECT_ROOT/scripts/build-ui.sh" "$PROJECT_ROOT" "$OPENWRT_DIR"

printf '\n[6/10] Installing QuantumGrid first-boot files...\n'
mkdir -p "$OPENWRT_DIR/files"
if [[ -d "$PROJECT_ROOT/files" ]]; then
    cp -a "$PROJECT_ROOT/files/." "$OPENWRT_DIR/files/"
fi
mkdir -p "$OPENWRT_DIR/files/etc/quantumgrid"
cp "$DEVICE_PROFILE" "$OPENWRT_DIR/files/etc/quantumgrid/device-profile.json"
chmod 0644 "$OPENWRT_DIR/files/etc/quantumgrid/device-profile.json"

printf '\n[7/10] Applying validated %s firmware configuration...\n' "$DEVICE_PROFILE_ID"
[[ -s "$CONFIG_FILE" ]] || die "Device profile configuration not found: $CONFIG_FILE"
cp "$CONFIG_FILE" "$OPENWRT_DIR/.config"
if [[ "$QG_ENABLE_NSS" == "1" ]]; then
    NSS_FRAGMENT="$NSS_FRAGMENT_PATH"
    [[ -s "$NSS_FRAGMENT_PATH" ]] || die "NSS configuration fragment not found: $NSS_FRAGMENT_PATH"
    printf '\nApplying the profile's opt-in NSS configuration fragment...\n'
    cat "$NSS_FRAGMENT_PATH" >> "$OPENWRT_DIR/.config"
    [[ "$NSS_REQUIRED_CONFIG_SYMBOLS" != "-" ]] || die "Device profile $DEVICE_PROFILE_ID declares no NSS config requirements"
    IFS=';' read -r -a REQUIRED_NSS_SYMBOLS <<< "$NSS_REQUIRED_CONFIG_SYMBOLS"
    ((${#REQUIRED_NSS_SYMBOLS[@]} > 0)) || die "NSS configuration requirements are empty"
    for symbol in "${REQUIRED_NSS_SYMBOLS[@]}"; do
        [[ "$symbol" =~ ^CONFIG_[A-Za-z0-9_-]+=[A-Za-z0-9_.+-]+$ ]] || die "Device profile contains an invalid NSS config symbol"
        if ! grep -Fqx "$symbol" "$OPENWRT_DIR/.config"; then
            printf '%s\n' "$symbol" >> "$OPENWRT_DIR/.config"
        fi
    done
fi
cd "$OPENWRT_DIR"
make defconfig
grep -Fqx "CONFIG_TARGET_${OPENWRT_TARGET}=y" .config || die "OpenWrt target $OPENWRT_TARGET was not selected"
grep -Fqx "CONFIG_TARGET_${OPENWRT_TARGET}_${OPENWRT_SUBTARGET}=y" .config || die "OpenWrt subtarget $OPENWRT_SUBTARGET was not selected"
grep -Fqx "CONFIG_TARGET_${OPENWRT_TARGET}_${OPENWRT_SUBTARGET}_DEVICE_${OPENWRT_DEVICE}=y" .config || die "OpenWrt device profile $OPENWRT_DEVICE was not selected"
if [[ "$QG_ENABLE_NSS" == "1" ]]; then
    [[ "$NSS_REQUIRED_CONFIG_SYMBOLS" != "-" ]] || die "Device profile $DEVICE_PROFILE_ID declares no NSS config requirements"
    IFS=';' read -r -a REQUIRED_NSS_SYMBOLS <<< "$NSS_REQUIRED_CONFIG_SYMBOLS"
    ((${#REQUIRED_NSS_SYMBOLS[@]} > 0)) || die "NSS configuration requirements are empty"
    for symbol in "${REQUIRED_NSS_SYMBOLS[@]}"; do
        [[ "$symbol" =~ ^CONFIG_[A-Za-z0-9_-]+=[A-Za-z0-9_.+-]+$ ]] || die "Device profile contains an invalid NSS config symbol"
        grep -Fqx "$symbol" .config || die "Required NSS configuration was not selected: $symbol"
    done
    printf 'Validated %s profile-declared NSS configuration requirements.\n' "${#REQUIRED_NSS_SYMBOLS[@]}"
fi

printf '\n[8/10] Running OpenWrt prerequisites...\n'
make prereq

printf '\n[9/10] Downloading source packages...\n'
make download -j"$BUILD_JOBS"

printf '\n[10/10] Building QuantumGrid %s firmware...\n' "$PLATFORM_MODEL"
make -j"$BUILD_JOBS" V=s

printf '\n==============================================\n'
printf '       QUANTUMGRID BUILD COMPLETE\n'
printf '==============================================\n'
printf 'Device profile: %s (%s)\n' "$DEVICE_PROFILE_ID" "$OPENWRT_DEVICE"
printf 'OpenWrt commit: %s\n' "$OPENWRT_SHA"
printf '\nFirmware outputs:\n'
find "$OUTPUT_PATH" -maxdepth 1 -type f \
    \( -name "$FACTORY_GLOB" -o -name "$INITRAMFS_GLOB" \) \
    -print | sort