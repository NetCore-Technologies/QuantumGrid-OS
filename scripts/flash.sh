#!/bin/bash

VENDOR="Netcore Technologies"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
    echo "Usage: $0 <target> <router-ip> [ssh-user]"
    echo "Example: $0 arcadyan-aw1000 192.168.1.1 root"
    exit 1
}

[ $# -lt 2 ] && usage

TARGET="$1"
ROUTER_IP="$2"
SSH_USER="${3:-root}"
DIST_DIR="$ROOT/dist/$TARGET"

if [ ! -d "$DIST_DIR" ]; then
    echo "[ERROR] No build found for $TARGET — run build.sh first"
    exit 1
fi

echo ""
echo "  QuantumGrid OS — Flash Tool"
echo "  $VENDOR"
echo "  Target : $TARGET"
echo "  Router : $SSH_USER@$ROUTER_IP"
echo ""

# Find sysupgrade image
SYSUPGRADE=$(ls "$DIST_DIR"/*sysupgrade*.bin 2>/dev/null | head -1)
FACTORY=$(ls "$DIST_DIR"/*.ubi 2>/dev/null | head -1)

echo "  Available images:"
[ -n "$SYSUPGRADE" ] && echo "    sysupgrade : $(basename $SYSUPGRADE)"
[ -n "$FACTORY"    ] && echo "    factory    : $(basename $FACTORY)"
echo ""

read -p "  Flash type [sysupgrade/factory]: " FLASH_TYPE

case "$FLASH_TYPE" in
    sysupgrade)
        IMAGE="$SYSUPGRADE"
        REMOTE_CMD="sysupgrade -v /tmp/$(basename $IMAGE)"
        ;;
    factory)
        IMAGE="$FACTORY"
        REMOTE_CMD="mtd write /tmp/$(basename $IMAGE) firmware"
        ;;
    *)
        echo "[ERROR] Unknown type"
        exit 1
        ;;
esac

echo ""
echo "  Image  : $(basename $IMAGE)"
echo "  SHA256 : $(sha256sum $IMAGE | awk '{print $1}')"
echo ""
read -p "  Confirm flash? [yes/NO]: " CONFIRM
[ "$CONFIRM" != "yes" ] && echo "Aborted." && exit 0

echo ""
echo "  [1/3] Uploading image..."
scp "$IMAGE" "$SSH_USER@$ROUTER_IP:/tmp/"

echo "  [2/3] Verifying upload..."
REMOTE_SHA=$(ssh "$SSH_USER@$ROUTER_IP" "sha256sum /tmp/$(basename $IMAGE) | awk '{print \$1}'")
LOCAL_SHA=$(sha256sum "$IMAGE" | awk '{print $1}')

if [ "$REMOTE_SHA" != "$LOCAL_SHA" ]; then
    echo "[ERROR] Checksum mismatch — aborting"
    exit 1
fi
echo "  Checksum OK"

echo "  [3/3] Flashing..."
ssh "$SSH_USER@$ROUTER_IP" "$REMOTE_CMD" || true
echo ""
echo "  Flash sent. Router is rebooting."
echo "  Wait ~3 minutes then SSH back in."
