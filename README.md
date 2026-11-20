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

The build also compiles the existing React control centre with Node.js 22/npm and copies
its Vite output into the firmware root filesystem at `/www/quantumgrid`. After boot it is served
at `http://<router-address>/quantumgrid/`. The dashboard, Network, Diagnostics, System and Analytics views use live router API data for
system metrics, WAN counters and a short rolling throughput window. Wi-Fi and Network show
iwinfo radio channel/frequency, driver-reported regulatory country, supported 802.11 PHY generations and channel widths, current channel centers,
AP signal/noise, bitrate, quality and transmit power where the wireless driver reports them. Current-channel busy airtime is calculated from successive
read-only iwinfo survey counters where the driver supports them; unsupported radios remain N/A.
The Wi-Fi page also provides an authenticated, manual iwinfo scan of nearby access points,
including SSID/BSSID, band, channel, frequency, signal/quality, encryption metadata (WPA
versions and authentication where exposed) and HT/VHT/HE/EHT operation width, center-channel, authentication and cipher-suite information
when returned by the driver. Unknown security metadata is not classified as open.
Scans are rate-limited and cached for 30 seconds; some radio drivers may briefly interrupt traffic
while scanning. The same page groups observed BSSIDs by reported band/channel and shows strongest
reported signal; these counts are scan visibility only, not airtime or interference measurements.
Scan inventories can be searched by SSID/BSSID/radio, band, channel, security or mode; filtered by band/security; sorted by signal, channel or SSID; and exported using the visible filtered result set with a one-click filter reset.
They can also be exported as CSV; network-controlled text is quoted and spreadsheet formula
prefixes are neutralised in the export. The page keeps summaries from the last ten distinct manual
scans in memory only; it does not persist the history or retain old network identifiers. The
history can be exported as a compact CSV or cleared immediately from the Wi-Fi page. The
The Wi-Fi and Network views also show the driver's frequency list, current channel and restricted-channel flags when iwinfo.freqlist reports them, plus the available transmit-power levels when iwinfo.txpowerlist is supported. These are driver-reported capabilities, not a replacement for the full regulatory database or a grant to use every level. Channel and power capability lists are cached for 60 seconds, while live interface state and station counters continue refreshing normally.
Devices and Wi-Fi views include unexpired DHCP leases and iwinfo station associations. The station inventory summarises current associated/authorized counts and aggregate measured RX/TX throughput for stations with valid counter samples. Connected station rows show driver-reported RX/TX PHY family, MCS, spatial streams, channel width and guard-interval data where available. They also show separate current/average signal, cumulative RX/TX bytes and packets, inactive time and transmit retry/failure counters when reported. Per-station RX/TX throughput is calculated from successive iwinfo byte-counter samples and appears after the second valid sample; counter resets are discarded. Associated clients can be filtered by hostname/MAC/SSID/radio, band and authorization state, sorted by signal, negotiated PHY or measured RX/TX throughput, and exported with their station diagnostics to a spreadsheet-safe CSV. Gaming
reports SQM queue configuration and read-only kernel qdisc
counters; it does not yet write queue policy or measure jitter, packet loss or bufferbloat.
The 5G page reads QMI registration, serving radio interface, roaming state, data-session status
and RF measurements where the modem reports them. It retains up to 30 distinct modem RF samples
in the current UI session, without assigning a synthetic signal score. QMI values are cached
briefly and no SIM identifiers or credentials are requested. Security reports firewall zone policies, nftables table presence, Adblock Fast
configuration and WireGuard/OpenVPN service state without exposing VPN secrets or changing
router configuration. Advanced policy controls
remain unconnected and read-only.

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

## Publish the website

The website is available with either supported Pages source:

- **GitHub Actions (recommended):** open repository **Settings → Pages**, set **Source** to
  **GitHub Actions**, and save. The QuantumGrid Pages workflow validates and deploys the
  lowercase `docs/` source.
- **Deploy from a branch:** select `main` and the `/docs` folder. GitHub's built-in Pages
  workflow builds and publishes that same source.

The legacy `Docs/` path remains as a compatibility mirror for existing documentation links and
firmware packaging. CI checks that both website trees stay byte-for-byte identical.

## Router authentication and telemetry

The QuantumGrid control centre authenticates with the existing LuCI/OpenWrt administrator
session. It does not create a second Linux user or store the router password in browser storage.
The read-only LuCI API reports system load, CPU/memory/temperature where available, WAN/LAN
interface counters, unexpired DHCPv4 leases, wireless radio state, live iwinfo-associated
Wi-Fi stations, modem device presence, QMI registration/data-session status and cellular RF
measurements where returned, plus RJ11 service/patch state. Signal strength and RX/TX rates
are included only when the relevant wireless or modem interface reports them. DHCP leases show address
allocation, not current reachability or wireless association.
WAN throughput is calculated from successive kernel byte-counter samples. Wi-Fi association
data is read from OpenWrt's iwinfo ubus API; missing RF fields remain unavailable rather than
being inferred. A single ICMP probe is
shown as a reachability/latency sample, not as a long-running packet-loss benchmark.

The custom API route is protected by LuCI's authenticated administrator tree and accepts no
arbitrary shell commands, UCI writes or caller-selected ubus methods.

On first boot, the wizard first attempts the supplied root password. If that authentication
fails, it attempts an empty root password; only when that succeeds may the authenticated
password endpoint set the new root password, and only if OpenWrt still reports no password hash.
A wrong password on an already-secured router is never overwritten.

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
profile, RJ11 packages and shell script syntax. The full OpenWrt firmware build runs only for a release tag or manual firmware workflow
dispatch. Routine commits run the faster lint, website, Lua syntax and firmware integration gates
without launching another full OpenWrt compilation.

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
