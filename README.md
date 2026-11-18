# QuantumGrid OS

**Your network. Your rules.**

QuantumGrid OS is an OpenWrt-based network operating system initially built for the **Arcadyan AW1000**. It combines a hardware-specific firmware configuration, the existing QuantumGrid React control centre and AW1000 integration work.

- **Target:** `qualcommax / ipq807x / arcadyan_aw1000`
- **Firmware base:** OpenWrt `v25.12.6` (pinned for reproducible builds)
- **Cellular modem:** Quectel RG500Q-EA
- **Voice hardware:** RJ11 / FXS with Skyworks Si32261 SLIC
- **Control centre:** `ui/quantumgrid`

## Website

**[QuantumGrid OS](https://netcore-technologies.github.io/QuantumGrid-OS/)**

Explore the [platform](https://netcore-technologies.github.io/QuantumGrid-OS/features.html), [AW1000 hardware](https://netcore-technologies.github.io/QuantumGrid-OS/hardware.html), [downloads](https://netcore-technologies.github.io/QuantumGrid-OS/downloads.html), [documentation](https://netcore-technologies.github.io/QuantumGrid-OS/docs.html), [roadmap](https://netcore-technologies.github.io/QuantumGrid-OS/roadmap.html) and [community](https://netcore-technologies.github.io/QuantumGrid-OS/community.html).

## Project principles

1. Build on upstream OpenWrt rather than shipping an opaque router image.
2. Make each control use a real service API; do not label simulated values as hardware telemetry.
3. Keep the existing QuantumGrid control-centre design and improve it in place.
4. Gate hardware-sensitive changes behind compatibility checks, safe defaults and recovery instructions.
5. Publish device-specific firmware with build provenance and SHA-256 checksums.

## Hardware target

| Component | Platform |
|---|---|
| Router | Arcadyan AW1000 |
| SoC | Qualcomm IPQ8074 |
| OpenWrt target | `qualcommax/ipq807x` |
| Device profile | `arcadyan_aw1000` |
| Cellular modem | Quectel RG500Q-EA |
| Voice interface | RJ11 / FXS, Si32261 SLIC |
| Wireless | Qualcomm Wi-Fi 6 platform |

The current firmware is based on the upstream OpenWrt networking stack. **NSS acceleration is not included or claimed** until a compatible kernel/driver integration is selected and validated.

## AW1000 RJ11 phone port

The AW1000 analogue phone port is integrated from the GPL-2.0-only
[openwrt-aw1000-phone](https://github.com/Perz3us/openwrt-aw1000-phone) project at tag `v0.9.0`.
The build includes `kmod-aw1000-fxs`, `fxsd` and `luci-app-fxs`.

The FXS service is disabled by default. It requires a kernel-matched module, a VoLTE-enabled
SIM and a separately obtained Skyworks SLIC DSP patch. QuantumGrid does not redistribute that
proprietary patch. Starting the service changes modem audio configuration and can restart the
RG500Q-EA, temporarily interrupting mobile data.

Read [Docs/PHONE-PORT.md](Docs/PHONE-PORT.md) before enabling the line. Emergency calling has
not been validated; keep an independent certified emergency calling option.

## Build

The normal build pins OpenWrt to `v25.12.6`:

```bash
git clone https://github.com/NetCore-Technologies/QuantumGrid-OS.git
cd QuantumGrid-OS
./build.sh
```

The build script fetches the pinned RJ11 source feed, updates OpenWrt feeds, applies
`configs/aw1000-max.config`, installs QuantumGrid first-boot files and builds the AW1000 target.

To use a different OpenWrt revision deliberately:

```bash
QG_OPENWRT_REF=v25.12.6 ./build.sh
```

The build host must have the OpenWrt build prerequisites installed. Firmware compilation
requires substantial disk space, RAM and time; use a Linux build host with sufficient resources.

## Firmware images

| Artifact | Intended use |
|---|---|
| `*-squashfs-sysupgrade.bin` | Upgrade an existing compatible OpenWrt installation |
| `*-squashfs-factory.ubi` | Supported factory/recovery installation route |
| `*-initramfs-uImage.itb` | Temporary RAM boot / recovery workflows |
| `*-packages.tar.zst` | Package output from the same firmware build |
| `SHA256SUMS` | Verify the published release assets |
| `BUILDINFO.txt` | Source commits, configuration hash and build metadata |

The factory image is **not** a universal stock-firmware installer. Follow
[Docs/RECOVERY.md](Docs/RECOVERY.md), back up first and verify the exact image and checksum.
Do not flash an image whose installation route you have not confirmed.

## Releases

Release tags use the `qg-v*` pattern, for example `qg-v0.1.0-alpha.1`. A tagged release
builds three AW1000 image formats, packages, the pinned RJ11 feed source, recovery/phone guides,
a build provenance file and `SHA256SUMS`.

The release workflow can also be run manually to produce a downloadable CI artifact without
publishing a GitHub Release. The public Downloads page reads the release inventory from GitHub;
it does not fabricate assets before a build completes.

QuantumGrid is router firmware, not a desktop application. We do not publish macOS DMG or
Windows EXE/MSI installers for this project.

## Quality gates

CI checks the existing React control centre with ESLint, TypeScript and Vite; validates the
static website's local links and metadata; checks the website JavaScript; and verifies the AW1000
profile, RJ11 packages and shell script syntax. The full OpenWrt firmware build runs separately
from a release tag or manual firmware workflow dispatch.

A successful compile does not prove RF performance, voice-call compatibility, emergency calling,
flash compatibility or NSS acceleration. Those require separate hardware tests and are reported
as such.

## Development status

- **Integrated:** AW1000 target profile, existing React control centre, pinned RJ11 source feed,
  safe first-boot default for the FXS service, Pages workflow and release build workflow.
- **Active development:** service-backed telemetry, UI-to-ubus control wiring, radio intelligence,
  latency policy and modem observability.
- **Research / planned:** compatible NSS/EDMA/PPE path, hardware benchmark suite and wider device support.

See the [public roadmap](https://netcore-technologies.github.io/QuantumGrid-OS/roadmap.html).

## Contributing and security

Open issues with the exact hardware, firmware/kernel version, logs and reproducible steps.
Focused pull requests should include tests and documentation. See
[CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## Licensing

QuantumGrid's repository files are licensed as described in [LICENSE](LICENSE). Third-party
feeds retain their own licences and notices. The AW1000 phone feed is GPL-2.0-only; Skyworks
SLIC patch firmware is proprietary and is not bundled by QuantumGrid.
