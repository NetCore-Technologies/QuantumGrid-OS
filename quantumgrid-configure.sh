#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# QuantumGrid OS MAX
# Arcadyan AW1000 / Qualcomm IPQ807x
#
# Philosophy:
#   OpenWrt = upstream operating-system foundation
#   QuantumGrid = our own OS layer
#
# Focus:
#   MAX throughput
#   MAX latency performance
#   Gaming
#   Wi-Fi
#   5G/modem
#   NSS/EDMA-ready architecture
#   Diagnostics
#   Security
#   Monitoring
#   Multi-WAN
#   VPN
#   Administration
#
# NOTE:
#   NSS/EDMA kernel/driver integration is handled separately.
#   This script does NOT pretend vanilla OpenWrt contains NSS.
# ============================================================

ROOT="${1:-$HOME/Documents/QuantumGrid-OS}"
OPENWRT="$ROOT/openwrt"

die() {
    echo
    echo "ERROR: $*"
    exit 1
}

log() {
    echo
    echo "============================================================"
    echo " $*"
    echo "============================================================"
}

[[ -d "$OPENWRT" ]] || die "OpenWrt directory not found: $OPENWRT"
[[ -f "$OPENWRT/Makefile" ]] || die "Not an OpenWrt source tree: $OPENWRT"

cd "$OPENWRT"

log "QuantumGrid OS MAX configurator"

echo "Root:    $ROOT"
echo "OpenWrt: $OPENWRT"
echo

# ------------------------------------------------------------
# Backup existing configuration
# ------------------------------------------------------------

if [[ -f .config ]]; then
    BACKUP=".config.quantumgrid-backup-$(date +%Y%m%d-%H%M%S)"
    cp .config "$BACKUP"
    echo "Existing .config backed up:"
    echo "  $BACKUP"
fi

# ------------------------------------------------------------
# feeds
# ------------------------------------------------------------

log "Updating OpenWrt feeds"

./scripts/feeds update -a
./scripts/feeds install -a

# ------------------------------------------------------------
# Start from a clean target configuration
# ------------------------------------------------------------

log "Selecting Arcadyan AW1000"

# Create a minimal target config.
cat > .config <<'EOF'
CONFIG_TARGET_qualcommax=y
CONFIG_TARGET_qualcommax_ipq807x=y
CONFIG_TARGET_qualcommax_ipq807x_DEVICE_arcadyan_aw1000=y

CONFIG_TARGET_ROOTFS_SQUASHFS=y

CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-base=y
CONFIG_PACKAGE_luci-mod-admin-full=y
CONFIG_PACKAGE_luci-mod-network=y
CONFIG_PACKAGE_luci-mod-status=y
CONFIG_PACKAGE_luci-theme-bootstrap=y

CONFIG_PACKAGE_uhttpd=y
CONFIG_PACKAGE_uhttpd-mod-ubus=y

CONFIG_PACKAGE_dropbear=y

CONFIG_PACKAGE_ubus=y
CONFIG_PACKAGE_ubusd=y
CONFIG_PACKAGE_rpcd=y
CONFIG_PACKAGE_libubox=y
CONFIG_PACKAGE_libubus=y

CONFIG_PACKAGE_dnsmasq=y
CONFIG_PACKAGE_firewall4=y
CONFIG_PACKAGE_nftables=y

CONFIG_PACKAGE_iw=y
CONFIG_PACKAGE_iwinfo=y
CONFIG_PACKAGE_hostapd-utils=y
CONFIG_PACKAGE_wpa-cli=y

CONFIG_PACKAGE_ethtool=y
CONFIG_PACKAGE_ip-full=y
CONFIG_PACKAGE_tcpdump=y
CONFIG_PACKAGE_mtr=y
CONFIG_PACKAGE_traceroute=y

CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_wget-ssl=y
CONFIG_PACKAGE_ca-bundle=y

CONFIG_PACKAGE_jq=y
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_lsof=y
CONFIG_PACKAGE_strace=y
CONFIG_PACKAGE_file=y
CONFIG_PACKAGE_nano=y

CONFIG_PACKAGE_rsync=y

CONFIG_PACKAGE_wireguard-tools=y
CONFIG_PACKAGE_kmod-wireguard=y
CONFIG_PACKAGE_openvpn-openssl=y

CONFIG_PACKAGE_mwan3=y
CONFIG_PACKAGE_sqm-scripts=y
CONFIG_PACKAGE_luci-app-sqm=y
CONFIG_PACKAGE_kmod-sched=y
CONFIG_PACKAGE_kmod-sched-core=y
CONFIG_PACKAGE_kmod-ifb=y

CONFIG_PACKAGE_collectd=y
CONFIG_PACKAGE_collectd-mod-cpu=y
CONFIG_PACKAGE_collectd-mod-memory=y
CONFIG_PACKAGE_collectd-mod-load=y
CONFIG_PACKAGE_collectd-mod-interface=y
CONFIG_PACKAGE_collectd-mod-iwinfo=y
CONFIG_PACKAGE_collectd-mod-network=y
CONFIG_PACKAGE_collectd-mod-ping=y
CONFIG_PACKAGE_collectd-mod-processes=y

CONFIG_PACKAGE_rrdtool1=y

CONFIG_PACKAGE_odhcp6c=y
CONFIG_PACKAGE_odhcpd-ipv6only=y

CONFIG_PACKAGE_unbound=y

CONFIG_PACKAGE_usbutils=y
CONFIG_PACKAGE_kmod-usb-storage=y
CONFIG_PACKAGE_kmod-usb-storage-uas=y

CONFIG_PACKAGE_kmod-fs-ext4=y
CONFIG_PACKAGE_kmod-fs-vfat=y

CONFIG_PACKAGE_kmod-tun=y
CONFIG_PACKAGE_kmod-veth=y
CONFIG_PACKAGE_kmod-macvlan=y
CONFIG_PACKAGE_kmod-bridge=y

CONFIG_PACKAGE_conntrack=y
CONFIG_PACKAGE_conntrack-tools=y

CONFIG_PACKAGE_procps-ng=y
CONFIG_PACKAGE_psmisc=y
CONFIG_PACKAGE_findutils=y
CONFIG_PACKAGE_coreutils=y

CONFIG_PACKAGE_openssl-util=y
CONFIG_PACKAGE_libsodium=y

CONFIG_PACKAGE_ntpd=y
CONFIG_PACKAGE_ntpclient=y
EOF

# ------------------------------------------------------------
# Discover package names available in this tree
# ------------------------------------------------------------

has_pkg() {
    local pkg="$1"

    # Search package definitions and feeds.
    grep -Rqs \
        --exclude-dir=.git \
        -E \
        "define Package/${pkg}([[:space:]]|$)|^[[:space:]]*Package: ${pkg}([[:space:]]|$)" \
        package feeds 2>/dev/null
}

enable_pkg() {
    local pkg="$1"

    if has_pkg "$pkg"; then
        echo " + $pkg"
        printf 'CONFIG_PACKAGE_%s=y\n' "$pkg" >> /tmp/qg-packages.conf
    else
        echo " - $pkg (not available in this source tree)"
    fi
}

log "Building QuantumGrid MAX package selection"

rm -f /tmp/qg-packages.conf

# ------------------------------------------------------------
# Core UI
# ------------------------------------------------------------

for p in \
    luci-app-firewall \
    luci-app-opkg \
    luci-app-package-manager \
    luci-app-sqm \
    luci-app-mwan3 \
    luci-app-attendedsysupgrade \
    luci-app-statistics \
    luci-app-upnp \
    luci-app-ddns \
    luci-app-watchcat
do
    enable_pkg "$p"
done

# ------------------------------------------------------------
# Networking
# ------------------------------------------------------------

for p in \
    ip-full \
    ip-tiny \
    ethtool \
    bridge \
    tcpdump \
    socat \
    netcat \
    bind-tools \
    mtr \
    traceroute \
    nmap \
    conntrack \
    conntrack-tools \
    ipset \
    nftables \
    nftables-json
do
    enable_pkg "$p"
done

# ------------------------------------------------------------
# Wi-Fi / wireless intelligence
# ------------------------------------------------------------

for p in \
    iw \
    iwinfo \
    hostapd-utils \
    wpa-cli \
    dawn \
    umdns \
    avahi-daemon \
    avahi-utils
do
    enable_pkg "$p"
done

# ------------------------------------------------------------
# Gaming / latency
# ------------------------------------------------------------

for p in \
    sqm-scripts \
    kmod-sched \
    kmod-sched-core \
    kmod-ifb \
    tc-full \
    kmod-tcp-bbr
do
    enable_pkg "$p"
done

# ------------------------------------------------------------
# VPN
# ------------------------------------------------------------

for p in \
    wireguard-tools \
    kmod-wireguard \
    openvpn-openssl \
    luci-proto-wireguard \
    luci-app-wireguard \
    luci-app-openvpn
do
    enable_pkg "$p"
done

# ------------------------------------------------------------
# DNS / privacy
# ------------------------------------------------------------

for p in \
    unbound \
    luci-app-unbound \
    adblock-fast \
    luci-app-adblock-fast \
    dnsmasq-full
do
    enable_pkg "$p"
done

# ------------------------------------------------------------
# Multi-WAN
# ------------------------------------------------------------

for p in \
    mwan3 \
    luci-app-mwan3
do
    enable_pkg "$p"
done

# ------------------------------------------------------------
# Monitoring
# ------------------------------------------------------------

for p in \
    collectd \
    collectd-mod-cpu \
    collectd-mod-memory \
    collectd-mod-load \
    collectd-mod-interface \
    collectd-mod-iwinfo \
    collectd-mod-network \
    collectd-mod-ping \
    collectd-mod-processes \
    collectd-mod-rrdtool \
    rrdtool1
do
    enable_pkg "$p"
done

# ------------------------------------------------------------
# Diagnostics
# ------------------------------------------------------------

for p in \
    htop \
    lsof \
    strace \
    sysstat \
    jq \
    curl \
    wget-ssl \
    rsync \
    nano \
    file
do
    enable_pkg "$p"
done

# ------------------------------------------------------------
# Storage / USB
# ------------------------------------------------------------

for p in \
    usbutils \
    block-mount \
    kmod-usb-storage \
    kmod-usb-storage-uas \
    kmod-fs-ext4 \
    kmod-fs-vfat \
    kmod-fs-exfat
do
    enable_pkg "$p"
done

# ------------------------------------------------------------
# 5G / modem ecosystem
# ------------------------------------------------------------

for p in \
    uqmi \
    libqmi \
    qmi-utils \
    umbim \
    modemmanager \
    mmcli \
    luci-proto-qmi \
    luci-proto-mbim \
    kmod-usb-net-qmi-wwan \
    kmod-usb-net-cdc-mbim \
    kmod-usb-serial-option \
    kmod-usb-serial-wwan
do
    enable_pkg "$p"
done

# ------------------------------------------------------------
# QoS / packet scheduling
# ------------------------------------------------------------

for p in \
    kmod-ifb \
    kmod-sched \
    kmod-sched-core \
    sqm-scripts \
    luci-app-sqm
do
    enable_pkg "$p"
done

# ------------------------------------------------------------
# Performance / platform utilities
# ------------------------------------------------------------

for p in \
    irqbalance \
    cpufrequtils \
    lm-sensors
do
    enable_pkg "$p"
done

# ------------------------------------------------------------
# Optional NoobWRT-inspired extras
#
# We don't depend on their feed or branding.
# We simply reproduce the useful functionality with our own
# QuantumGrid implementation.
# ------------------------------------------------------------

echo
echo "NoobWRT-inspired functionality planned:"
echo "  * Modem dashboard"
echo "  * Band/channel tools"
echo "  * Speed testing"
echo "  * DAWN roaming"
echo "  * Watchdog"
echo "  * SQM/CAKE"
echo "  * Multi-WAN"
echo "  * BBR"
echo "  * DNS filtering"
echo "  * Tailscale integration"
echo "  * LED control"
echo "  * Advanced network statistics"

# ------------------------------------------------------------
# Add discovered packages
# ------------------------------------------------------------

if [[ -s /tmp/qg-packages.conf ]]; then
    cat /tmp/qg-packages.conf >> .config
fi

# ------------------------------------------------------------
# Clean duplicates from .config
# ------------------------------------------------------------

awk '!seen[$0]++' .config > .config.cleaned
mv .config.cleaned .config

# ------------------------------------------------------------
# Ensure target selection is LAST and authoritative
# ------------------------------------------------------------

cat >> .config <<'EOF'

CONFIG_TARGET_qualcommax=y
CONFIG_TARGET_qualcommax_ipq807x=y
CONFIG_TARGET_qualcommax_ipq807x_DEVICE_arcadyan_aw1000=y
EOF

# ------------------------------------------------------------
# Resolve dependencies
# ------------------------------------------------------------

log "Running OpenWrt defconfig"

make defconfig V=s

# ------------------------------------------------------------
# Verify target
# ------------------------------------------------------------

log "Verifying AW1000 target"

required=(
    "CONFIG_TARGET_qualcommax=y"
    "CONFIG_TARGET_qualcommax_ipq807x=y"
    "CONFIG_TARGET_qualcommax_ipq807x_DEVICE_arcadyan_aw1000=y"
)

for item in "${required[@]}"; do
    grep -qx "$item" .config || die "Missing required configuration: $item"
done

echo "AW1000 target: OK"

# ------------------------------------------------------------
# Report
# ------------------------------------------------------------

log "QuantumGrid MAX configuration summary"

echo
echo "TARGET:"
grep '^CONFIG_TARGET_' .config | grep -E 'qualcommax|ipq807x|arcadyan_aw1000' || true

echo
echo "SELECTED PACKAGES:"
grep '^CONFIG_PACKAGE_.*=y$' .config \
    | sed 's/^CONFIG_PACKAGE_//' \
    | sort \
    | head -250

echo
echo "PACKAGE COUNT:"
grep -c '^CONFIG_PACKAGE_.*=y$' .config || true

echo
echo "NSS STATUS:"
echo
echo "NSS is NOT assumed to be present in vanilla OpenWrt."
echo "QuantumGrid will integrate an NSS-capable base/patch set next."

echo
echo "EDMA STATUS:"
echo
echo "EDMA integration will be handled in the platform layer."
echo "Do NOT enable conflicting generic flow-offload settings until"
echo "the NSS/EDMA layer has been selected."

echo
echo "CONFIGURATION COMPLETE."
echo
echo "Next:"
echo "  make download -j\$(nproc) V=s"
echo "  make -j\$(nproc) V=s"
echo
