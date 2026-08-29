# QuantumGrid OS
**by Netcore Technologies**

High-performance OpenWrt-based firmware for Qualcomm IPQ807x routers.
Gaming-focused. CLI-first. Multi-device.

## Supported devices

| Device | SOC | WiFi | 5G Modem | Status |
|--------|-----|------|----------|--------|
| Arcadyan AW1000 | IPQ8072A | AX3600 | ✓ | Primary |
| Xiaomi AX3600 | IPQ8071A | AX3600 | ✗ | Supported |
| Xiaomi AX9000 | IPQ8072A | AX7800 | ✗ | Supported |
| Xiaomi AX10000 | IPQ8072A | AX10000 | ✗ | Supported |
| Generic IPQ807x | IPQ807x | varies | ✗ | Best effort |

## Features

- CAKE anti-bufferbloat
- BBR congestion control
- Gaming QoS + device priority
- 5G modem management (AW1000)
- Auto internet recovery
- NSS hardware acceleration
- Network diagnostics CLI
- Automated builds (GitHub Actions)

## Build

```bash
# One target
bash scripts/build.sh arcadyan-aw1000

# All targets
bash scripts/build.sh all
```

## Flash

```bash
bash scripts/flash.sh arcadyan-aw1000 192.168.1.1
```

## Diagnostics (run from your laptop)

```bash
bash scripts/diag.sh 192.168.1.1
```

## License

GPL-2.0. Built on OpenWrt and NoobWRT Pro.
Not for sale.
