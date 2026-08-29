#!/bin/bash
set -e

VENDOR="Netcore Technologies"
OS="QuantumGrid OS"
VERSION="0.1.0"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

banner() {
    echo ""
    echo "  QuantumGrid OS — $VENDOR"
    echo "  Version : $VERSION"
    echo "  Time    : $(date)"
    echo "  Target  : ${TARGET_NAME:-all}"
    echo ""
}

usage() {
    echo "Usage: $0 [target]"
    echo ""
    echo "Available targets:"
    for t in "$ROOT"/targets/*/; do
        name=$(basename "$t")
        conf="$t/target.conf"
        [ -f "$conf" ] && source "$conf" && echo "  $name — $SOC ($NOTES)" || echo "  $name"
    done
    echo ""
    echo "Examples:"
    echo "  $0 arcadyan-aw1000       # build one target"
    echo "  $0 all                   # build everything"
    echo "  $0                       # same as all"
    exit 0
}

build_target() {
    local TARGET_DIR="$ROOT/targets/$1"
    local CONF="$TARGET_DIR/target.conf"

    if [ ! -f "$CONF" ]; then
        echo "[ERROR] Unknown target: $1"
        exit 1
    fi

    source "$CONF"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Building: $TARGET_NAME"
    echo "  SOC     : $SOC"
    echo "  Base    : $BASE_REPO ($BASE_BRANCH)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    BUILD_DIR="$ROOT/build/$TARGET_NAME"
    mkdir -p "$BUILD_DIR"

    # Clone or update base
    if [ ! -d "$BUILD_DIR/openwrt/.git" ]; then
        echo "[1/6] Cloning base repo..."
        git clone --depth=1 -b "$BASE_BRANCH" "$BASE_REPO" "$BUILD_DIR/openwrt"
    else
        echo "[1/6] Updating base repo..."
        git -C "$BUILD_DIR/openwrt" pull
    fi

    cd "$BUILD_DIR/openwrt"

    # Link QuantumGrid packages
    echo "[2/6] Linking QuantumGrid packages..."
    for pkg in "$ROOT"/package/*/; do
        pname=$(basename "$pkg")
        ln -sf "$pkg" "package/$pname" 2>/dev/null || true
    done

    # Link custom files
    [ -d "$ROOT/files" ] && rsync -a "$ROOT/files/" files/

    # Build config
    echo "[3/6] Configuring..."
    echo "CONFIG_TARGET_${TARGET_SYSTEM}=y" > .config
    echo "CONFIG_TARGET_${TARGET_SYSTEM}_${TARGET_SUBTARGET}=y" >> .config
    echo "CONFIG_TARGET_${TARGET_SYSTEM}_${TARGET_SUBTARGET}_DEVICE_${TARGET_PROFILE}=y" >> .config
    while IFS= read -r pkg; do
        [[ "$pkg" =~ ^#.*$ || -z "$pkg" ]] && continue
        echo "CONFIG_PACKAGE_$pkg=y" >> .config
    done < "$ROOT/targets/$TARGET_NAME/packages.conf"

    ./scripts/feeds update -a
    ./scripts/feeds install -a
    make defconfig

    # Build
    echo "[4/6] Compiling ($(nproc) cores)..."
    make -j$(nproc) V=s 2>&1 | tee "$ROOT/logs/${TARGET_NAME}-build.log"

    # Collect
    echo "[5/6] Collecting images..."
    mkdir -p "$ROOT/dist/$TARGET_NAME"
    find bin/targets/ -name "*.bin" -o -name "*.ubi" -o -name "*.img" \
        | xargs -I{} cp {} "$ROOT/dist/$TARGET_NAME/" 2>/dev/null || true

    # Checksums
    echo "[6/6] Generating checksums..."
    sha256sum "$ROOT/dist/$TARGET_NAME"/* \
        > "$ROOT/dist/$TARGET_NAME/sha256sums.txt"

    echo ""
    echo "  DONE: $TARGET_NAME"
    ls -lh "$ROOT/dist/$TARGET_NAME/"
    echo ""
}

mkdir -p "$ROOT/logs" "$ROOT/dist"
banner

case "${1:-all}" in
    help|-h|--help) usage ;;
    all)
        for t in "$ROOT"/targets/*/; do
            build_target "$(basename "$t")"
        done
        ;;
    *)
        build_target "$1"
        ;;
esac

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  QuantumGrid OS build complete"
echo "  $VENDOR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
