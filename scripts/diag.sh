#!/bin/bash

ROUTER="${1:-192.168.1.1}"
USER="${2:-root}"

PASS="✓" ; FAIL="✗"

run() { ssh -o ConnectTimeout=5 "$USER@$ROUTER" "$1" 2>/dev/null; }

check() {
    local label="$1" cmd="$2"
    if run "$cmd" >/dev/null 2>&1; then
        printf "  %s  %-30s OK\n" "$PASS" "$label"
    else
        printf "  %s  %-30s FAIL\n" "$FAIL" "$label"
    fi
}

echo ""
echo "  QuantumGrid OS — Remote Diagnostics"
echo "  Netcore Technologies"
echo "  Router : $USER@$ROUTER"
echo "  $(date)"
echo ""

echo "  [ CONNECTIVITY ]"
check "Gateway ping"          "ping -c 2 -W 2 $(run 'ip route | awk /default/{print \$3; exit}')"
check "1.1.1.1"               "ping -c 2 -W 2 1.1.1.1"
check "8.8.8.8"               "ping -c 2 -W 2 8.8.8.8"
check "DNS resolution"        "nslookup google.com"
check "IPv6"                  "ping6 -c 2 2606:4700:4700::1111"

echo ""
echo "  [ 5G MODEM ]"
check "Modem device"          "ls /dev/cdc-wdm0"
check "QMI"                   "command -v qmicli"
check "uqmi"                  "command -v uqmi"
check "Qmodem running"        "/etc/init.d/qmodem status"
check "WAN IP"                "ip addr show wwan0 2>/dev/null | grep inet"

echo ""
echo "  [ PERFORMANCE ]"
check "CAKE qdisc"            "tc qdisc show | grep -q cake"
check "BBR"                   "sysctl net.ipv4.tcp_congestion_control | grep -q bbr"
check "HW offload"            "uci get network.@device[0].offloading | grep -q 1"
check "irqbalance"            "pgrep irqbalance"

echo ""
echo "  [ QUANTUMGRID ]"
check "quantumgridd"          "pgrep -x quantumgridd"
check "Config file"           "test -f /etc/config/quantumgrid"

echo ""
echo "  [ SYSTEM INFO ]"
printf "  %-30s " "Hostname"
run "uci get system.@system[0].hostname"
printf "  %-30s " "Firmware"
run "cat /etc/openwrt_release | grep DISTRIB_DESCRIPTION | cut -d= -f2"
printf "  %-30s " "Kernel"
run "uname -r"
printf "  %-30s " "Uptime"
run "uptime"
printf "  %-30s " "CPU temp"
run "cat /sys/class/thermal/thermal_zone0/temp | awk '{printf \"%.1f°C\n\", \$1/1000}'"
printf "  %-30s " "RAM"
run "free -m | awk '/Mem/{printf \"%dMB used / %dMB total\n\", \$3, \$2}'"
printf "  %-30s " "Overlay free"
run "df -h /overlay | awk 'NR==2{print \$4 \" free\"}'"

echo ""
echo "  [ LATENCY ]"
printf "  %-30s " "Ping 1.1.1.1"
run "ping -c 4 -q 1.1.1.1 | awk -F'/' '/rtt/{printf \"%.1f ms avg\n\", \$5}'"
printf "  %-30s " "Ping 8.8.8.8"
run "ping -c 4 -q 8.8.8.8 | awk -F'/' '/rtt/{printf \"%.1f ms avg\n\", \$5}'"

echo ""
