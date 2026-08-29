#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENWRT_DIR="${PROJECT_ROOT}/openwrt"

OPENWRT_REPO="https://github.com/openwrt/openwrt.git"
OPENWRT_BRANCH="openwrt-25.12"

echo
echo "=============================================="
echo "        QUANTUMGRID OS BUILD SYSTEM"
echo "=============================================="
echo

echo "[1/8] Checking host environment..."

command -v git >/dev/null || {
    echo "ERROR: git is not installed"
    exit 1
}

command -v make >/dev/null || {
    echo "ERROR: make is not installed"
    exit 1
}

command -v python3 >/dev/null || {
    echo "ERROR: python3 is not installed"
    exit 1
}

echo "Host environment OK."

echo
echo "[2/8] Getting OpenWrt ${OPENWRT_BRANCH}..."

if [ ! -d "${OPENWRT_DIR}/.git" ]; then
    git clone \
        --branch "${OPENWRT_BRANCH}" \
        --single-branch \
        "${OPENWRT_REPO}" \
        "${OPENWRT_DIR}"
else
    echo "OpenWrt source already exists."
fi

cd "${OPENWRT_DIR}"

echo
echo "[3/8] OpenWrt version:"
git describe --tags --always || true

echo
echo "[4/8] Updating feeds..."

./scripts/feeds update -a
./scripts/feeds install -a

echo
echo "[5/8] Installing QuantumGrid files..."

cd "${PROJECT_ROOT}"

mkdir -p "${OPENWRT_DIR}/files"

if [ -d "${PROJECT_ROOT}/files" ]; then
    cp -a "${PROJECT_ROOT}/files/." "${OPENWRT_DIR}/files/"
fi

echo
echo "[6/8] Applying QuantumGrid configuration..."

cd "${OPENWRT_DIR}"

if [ -f "${PROJECT_ROOT}/configs/aw1000.config" ]; then
    cp "${PROJECT_ROOT}/configs/aw1000.config" .config
    make defconfig
else
    echo
    echo "No AW1000 configuration exists yet."
    echo "Run:"
    echo
    echo "    make menuconfig"
    echo
    echo "and create configs/aw1000.config"
    echo
    exit 2
fi

echo
echo "[7/8] Running prerequisite checks..."

make prereq

echo
echo "[8/8] QuantumGrid build"

make download -j"$(nproc)"

make -j"$(nproc)" V=s

echo
echo "=============================================="
echo "       QUANTUMGRID BUILD COMPLETE"
echo "=============================================="
echo
echo "Firmware:"
echo
find "${OPENWRT_DIR}/bin/targets" \
    -type f \
    \( -name "*.bin" -o -name "*.img" -o -name "*.itb" \) \
    -print
