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

## Office network services

Office Networks provisions routed IPv4 office segments on pre-existing VLAN-filtered bridges. Optional dual-stack office segments request a delegated IPv6 /64 and configure DHCPv6, Router Advertisements and zone-scoped IPv6 control-plane rules while retaining the selected zone's default-deny INPUT/FORWARD policies. IPv4-only remains the default, and IPv6 requires upstream prefix delegation. Administrators can also add tightly scoped IPv6 WAN pinholes for a single, unambiguous global-unicast LAN neighbour on an active L3 device and one TCP/UDP port; the controller requires a valid unicast MAC, usable NDP state and a unique interface-to-zone binding. These are firewall allowances, not NAT, and do not alter default zone policies. The Network control centre also manages guarded IPv4/IPv6 static routes with persistent UCI storage, validation and rollback. See the [Office Networks deployment guide](Docs/OFFICE-NETWORKS.md) for prerequisites, firewall behaviour, route safeguards, recovery and physical validation.

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

The default stable firmware uses upstream OpenWrt `v25.12.6` and does not include or claim Qualcomm NSS acceleration. A separate, opt-in experimental AW1000 NSS profile uses the maintained `qosmio/openwrt-ipq` `25.12-nss` tree (Linux 6.12), the AW1000 NSS device-tree include, NSS 12.5 firmware, NSS core/ECM packages and the ath11k/mac80211 NSS Wi-Fi integration. The optional profile is not the stable default, and end-to-end NSS packet offload is **not yet verified on physical AW1000 hardware**.

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

The experimental NSS profile converts its moving upstream feed branches into the reviewed
commit pins in `configs/aw1000-nss-feeds.conf` before feed retrieval.
The build also verifies that every Git package feed remains at the full commit SHA declared
by the pinned OpenWrt release, with the configured repository origin and a clean working tree.
Locally modified or untracked feed files are refused before package installation.
Existing OpenWrt source checkouts must also match the expected upstream URL and contain no modified or untracked source files; ignored build outputs remain available for incremental builds.
Every firmware build exports the verified package-feed commit list as `OPENWRT-FEEDS.txt`.

The build pins the phone-feed tag `v0.9.0` to commit `fe85222e57d1c3e191ffb976b37667bbf221a020` and refuses to
continue when that tag resolves to different source. Use both
`QG_AW1000_PHONE_REF` and `QG_AW1000_PHONE_EXPECTED_SHA` when deliberately selecting
another feed tag; the manual firmware workflow exposes the same paired inputs.

## Validated hardware device profiles

The firmware build now consumes the declarative device profile
`profiles/arcadyan-aw1000.json`. The profile binds the OpenWrt target, subtarget and exact
device symbol to its reviewed configuration file, supported NSS and FXS build inputs, board
compatibility identifiers, output directory and required factory/initramfs artifact patterns.
`scripts/verify-device-profile.py` rejects unknown schema fields, unsafe repository paths,
missing feature inputs, incompatible device symbols and artifact names that do not identify
the selected device. The build validates this contract before cloning or modifying an OpenWrt
checkout and verifies the target/subtarget/device symbols again after `make defconfig`.

At first boot, the selected profile is embedded at
`/etc/quantumgrid/device-profile.json`. The authenticated Advanced view compares its allowed
board identifiers with the live `system.board` response and reports `matched`, `mismatch`,
`unknown` or `unavailable`. A match is explicitly only a software-reported board identity
comparison; it is not a secure hardware attestation or proof of physical flash, radio, modem,
peripheral, or recovery compatibility.

The same read-only inventory exposes the profile's NSS and FXS capability declarations as
**manifest declarations**, separately from live module, firmware, acceleration and voice-service
observations. A declared capability is not proof that a driver is loaded, packet offload works,
a telephone line is operational, or physical validation has passed. Missing or malformed
capability declarations remain `unknown`; they are never silently treated as unsupported or
operational.

Each first boot also creates a 128-bit random device inventory identifier at
`/etc/quantumgrid/device-id`. It is stable across normal reboots and is exposed only through
the authenticated platform inventory API. The ID is public metadata for distinguishing routers;
it is not a password, TLS certificate, cryptographic attestation or fleet-enrollment credential.
A factory reset or replacement of the writable overlay can create a new ID. A future central
management service must authenticate routers with a separate per-device key or certificate.

The AW1000 remains the **only supported hardware profile** today. Its manifest is the first
profile contract, not a claim of multi-vendor support. Select it explicitly with
`QG_DEVICE_PROFILE=profiles/arcadyan-aw1000.json ./build.sh`; this is also the default.
Adding another router requires its own exact upstream target/device configuration, compatible
package and hardware declarations, recovery-safe image artifacts, profile tests, a completed
firmware build and physical validation. A JSON profile by itself does not make a board supported.
The schema and failure modes are covered by `tests/device-profile.py` and the firmware CI gate.


The build script fetches the pinned RJ11 source feed, updates OpenWrt feeds, applies
`configs/aw1000-max.config`, installs QuantumGrid first-boot files and builds the AW1000 target.

To build the separate experimental NSS image instead of the stable upstream image:

```bash
QG_ENABLE_NSS=1 ./build.sh
```

That profile selects the pinned `qosmio/openwrt-ipq` 25.12 NSS commit
`d6848fa2ea00193b5b7d3973e3990da7f608027c`, appends
`configs/aw1000-nss.fragment`, and validates that ath11k/mac80211 NSS Wi-Fi support,
NSS 12.5 firmware, the NSS core driver and ECM are selected. The GitHub firmware workflow
also exposes an explicit **Enable NSS** manual-dispatch option; release-tag builds remain
on stable upstream OpenWrt. NSS images are labelled with an `-nss` suffix in their release
asset names and build provenance.

The NSS profile disables generic packet steering and generic software/hardware flow offload
at first boot so they do not compete with the NSS datapath. The upstream NSS project also
documents DSA `config bridge-vlan` filtering as incompatible with NSS Wi-Fi offload; do not
enable that topology on an NSS image. Firmware 12.5 does not support 802.11s mesh, so this
profile leaves mesh off and keeps usteer as the separately configurable roaming service.
A full hardware traffic-counter and throughput/latency validation is still required before
calling NSS offload operational.

The stable upstream base is pinned to the upstream GPG-verified
OpenWrt `v25.12.6` release commit
`64900e756efa667774214f9c6b17c113222e01f7`. The build checks the resolved checkout against this exact
40-character commit SHA before feeds, package configuration or compilation proceed.
Changing the source ref is deliberately a two-part operation: choose the ref and
provide the full commit SHA you have reviewed.

```bash
QG_OPENWRT_REF=<tag-or-commit> \
QG_OPENWRT_EXPECTED_SHA=<full-40-character-commit-sha> \
./build.sh
```

The manual firmware workflow exposes the same paired inputs and writes both
the expected and resolved commits to `BUILDINFO.txt`. An unreviewed or moved
tag therefore fails before the firmware build can continue.

The OpenWrt Apps page includes a 48-entry native LuCI launcher, a bounded APK/OPKG inventory and authenticated package controls for refreshing configured feeds and installing/removing named packages. Removal is blocked for core services, LuCI base/modules, kernel modules, Wi-Fi firmware/supplicants and NSS packages; full catalog search and dependency planning still use native LuCI Software.

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
prefixes are neutralised in the export. The Wi-Fi page also includes an authenticated editor for existing AP interfaces: SSID, WPA2/WPA3 security, a new or preserved passphrase, hidden SSID and driver-reported unrestricted channel selection. It commits only the selected AP/radio options, reloads Wi-Fi and attempts restoration if reload fails; channel width/PHY mode and transmit power are selectable only from values reported by the selected radio driver. The editor also exposes per-AP 802.11k neighbor-report and 802.11v BSS-transition settings. A native multi-AP roaming panel manages upstream `usteer`: it requires one existing static internal network for inter-AP communication, selected existing local SSIDs, all active local APs in each selected ESS attached to that same network, identical security credentials across those APs, and both 802.11k/v enabled on every participating BSS. The managed profile enables low-aggressiveness BSS-transition requests and bounded band/load steering settings. Forced disassociation, probe/association rejection, load-based kicks, minimum-SNR kicks and per-client aggressiveness overrides are disabled in the managed policy; existing per-client overrides are cleared only after the administrator applies that policy, and are restored if service activation fails. The image includes upstream `usteer` and its advanced LuCI app, but first-boot defaults disable the daemon until an administrator explicitly enables the QuantumGrid policy. The native diagnostics page remains available at `/cgi-bin/luci/admin/network/usteer`.

The Wi-Fi panel reports the local BSS inventory, associated clients and discovered remote usteer hosts separately. A running service with no discovered remote hosts is reported as **local only**, not as a working roaming cluster. A discovered remote host proves peer communication, not client acceptance of BSS transitions or successful client movement. Verify inter-AP reachability and observe actual client roam events on every participating AP before relying on roaming in production. Radio scheduling and full radio enable/disable controls are not yet connected in QuantumGrid. The Wi-Fi page also builds a read-only shortlist from
unrestricted channels returned by the radio driver, comparing nearby BSSID signal and advertised
channel-width overlap within each radio/band. The router's own BSSID is excluded when reported.
Scores are relative to that shortlist, not measured airtime, CCA busy time, noise or guaranteed
interference; unavailable widths are marked and use a 20 MHz fallback. No channel settings are
changed. Opt-in, browser-local Wi-Fi client history is also available: an administrator can manually save snapshots of currently associated stations, retain 1, 7 or 30 days (up to 10,000 observations), export CSV and clear the history. It is disabled by default, stores MAC addresses and available DHCP hostname/IP details only in that browser's local storage, and is not uploaded, encrypted or synced. A snapshot is written only after the explicit Save snapshot action; it is not an automatic monitor. The page keeps the last ten distinct manual scan
summaries plus the minimal BSSID/SSID/band/channel/signal fields needed to compare newly observed,
not-observed and signal-changing access points. This comparison is page-memory-only: it is cleared
when the Wi-Fi page is left, reloaded or its history is cleared, and is never written to browser
storage or sent to another service. A BSSID missing from one scan is only marked not observed; it
is not treated as proof that an access point is offline. The comparison can be exported as a
spreadsheet-safe CSV and the summary history can be exported as a compact CSV or cleared immediately
from the Wi-Fi page. The
The Wi-Fi and Network views also show the driver's frequency list, current channel and restricted-channel flags when iwinfo.freqlist reports them, plus the available transmit-power levels when iwinfo.txpowerlist is supported. These are driver-reported capabilities, not a replacement for the full regulatory database or a grant to use every level. Channel and power capability lists are cached for 60 seconds, while live interface state and station counters continue refreshing normally.
Devices and Wi-Fi views include unexpired DHCP leases and iwinfo station associations. The station inventory summarises current associated/authorized counts and aggregate measured RX/TX throughput for stations with valid counter samples. Connected station rows show driver-reported RX/TX PHY family, MCS, spatial streams, channel width and guard-interval data where available. They also show separate current/average signal, cumulative RX/TX bytes and packets, inactive time and transmit retry/failure counters when reported. Per-station RX/TX throughput is calculated from successive iwinfo byte-counter samples and appears after the second valid sample; counter resets are discarded. Associated clients can be filtered by hostname/MAC/SSID/radio, band and authorization state, sorted by signal, negotiated PHY or measured RX/TX throughput, and exported with their station diagnostics and active filter/sort context in a spreadsheet-safe CSV. Gaming
reports configured SQM queues and read-only kernel qdisc
counters. The Gaming page also compares each enabled queue's configured qdisc and interface with
the live kernel inventory, reporting an observed root match, a missing match, unavailable or
unconfigured state, or an inconclusive result when the 64-entry inventory is truncated. This is
an evidence check for the expected root qdisc on the configured interface only: it does not prove
the ingress IFB pairing, effective rate enforcement, client classification or end-to-end WAN path.
The Gaming page can edit enable state, rate limits and bounded link-layer calibration for an
existing queue: link-layer type (none, ethernet, atm or ptm), packet overhead (-64 to 256 bytes)
and minimum packet unit (0 to 256 bytes). The authenticated endpoint changes only those fields
plus the selected queue's enabled/download/upload values, snapshots every modified UCI option,
restarts SQM and attempts rollback if the restart fails. The queue interface, qdisc, setup script
and advanced option strings are preserved. Administrators must choose the link layer and framing
values from their ISP/connection details; QuantumGrid does not guess them. The Gaming page also
supports audited per-client upload and download DSCP marking using fixed BE, AF41, EF or CS1 classes.
Upload policies match one unicast source MAC on an internal-to-WAN/WWAN path. Download policies match
the client's destination IPv4 address on a WAN/WWAN-to-internal path; they can only be created from
one exact static DHCP reservation whose MAC/IP pair is unique and whose address belongs to one
unambiguous routed subnet attached to the selected internal zone. firewall4 does not support
destination-MAC matching, so QuantumGrid does not claim to implement it. Both directions explicitly
match all IP protocols. DHCP reservation updates that would change a referenced client's MAC or IP,
removal of a referenced reservation, and creation of a reservation that could activate a stale rule
are blocked until the download policy is removed. Policies remain capped at 32. These markings do
not provide per-client bandwidth caps/guarantees or a managed per-client queue scheduler; an existing
CAKE egress profile must use DiffServ 4 or 8 for DSCP tin selection, and actual packet-path
effectiveness still requires hardware testing.
Diagnostics has a separate on-demand five-packet ICMP test to the fixed target 1.1.1.1,
reporting the measured received/sent ratio, packet-loss percentage, RTT minimum/average/maximum
and mean absolute difference between consecutive successful RTT samples (jitter).
The 5G page reads QMI registration, serving radio interface, roaming state, data-session status
and RF measurements where the modem reports them. It retains up to 30 distinct modem RF samples
in the current UI session, without assigning a synthetic signal score. QMI values are cached
briefly and no SIM identifiers or credentials are requested. Security reports firewall zone policies, nftables table presence, Adblock Fast
configuration and WireGuard/OpenVPN service state without exposing VPN secrets or changing
router configuration. WireGuard peer rows also show measured RX/TX Mbps from successive transfer-counter
samples; first samples, counter resets, stale intervals and ambiguous duplicate interface/AllowedIPs
tuples remain N/A rather than being guessed. The Security Center adds a read-only firewall posture review:
it flags ACCEPT input/forward defaults on standard WAN/WWAN zones, enabled ACCEPT rules with WAN-like
or unrestricted sources, and broad external ACCEPT rules with no reported port/address constraints.
Custom external-zone names and unavailable telemetry remain unknown. Security Center returns up to
64 firewall rule summaries and 64 NAT redirect summaries, with explicit truncation indicators. The
redirect inventory includes source/destination zones, protocol, target and external/internal ports;
internal destination IPs and raw IP/MAC selector values are deliberately omitted. It flags enabled
external forwards, forwards with no external source-port constraint, and mappings to common
administrative/data-service ports for manual review. The Security Center also reads a bounded JSON snapshot of the running `inet/fw4` table when
the nft binary and table are available. It reports chain name, hook, policy, type, priority, device
and rule count, without returning raw nft expressions or address values. The JSON input is capped
at 512 KiB and the page displays at most 64 chains; malformed, oversized or unavailable snapshots
remain explicitly unavailable rather than being treated as complete. Summaries can be searched
and exported. These are configuration/runtime inventory signals only: QuantumGrid does not evaluate
rule order, fully resolve address sets, test public reachability, confirm a service is listening, or
prove actual packet paths. This is not a vulnerability scan and it does not prove that a router is
exposed or secure. The Advanced page reports system.board firmware identity, a bounded installed-module inventory parsed from the running kernel's `modules.dep` and compared with live `/proc/modules` state, init-script and diagnostic-tool presence, package-manager detection, read-only Netfilter
connection-tracking count, configured maximum, free capacity and 75%/90% warning thresholds, plus a
30-sample session-only occupancy trend and CSV export, MTD partitions,
block devices and important system mounts, including total/available capacity and usage where
statvfs is supported. These checks are read-only; service-script presence is not presented as proof
that a service is running. The Advanced page adds a live runtime-health snapshot from the
authenticated telemetry sample and exports uptime, CPU, memory, temperature and 1/5/15-minute
load averages alongside the hardware inventory in a spreadsheet-safe support CSV. Advanced policy
controls remain unconnected and read-only.

The build host must have the OpenWrt build prerequisites installed. Firmware compilation
requires substantial disk space, RAM and time; use a Linux build host with sufficient resources.

## Enterprise Wi-Fi (WPA2/WPA3 RADIUS)

The existing Wi-Fi AP editor supports **WPA2-Enterprise and WPA3-Enterprise with an external RADIUS authentication
server**. WPA3-Enterprise forces 802.11w Protected Management Frames to required and repairs an
existing AP whose PMF setting is missing when saved. The AW1000 firmware selects OpenWrt's full-featured wpad-openssl variant because the
basic WPA-PSK/SAE variant does not include the full EAP/RADIUS authenticator. Configure an IPv4
RADIUS address or DNS hostname, a UDP authentication port (default 1812) and a shared secret of
16–128 bytes. The server must be reachable from the router on the configured port.

The authentication shared secret is never returned by the QuantumGrid API. Leaving it blank preserves the
existing secret only while the enterprise mode and RADIUS server remain unchanged; enabling
enterprise security or changing the server requires a new secret. Optional RADIUS accounting can
use a separate IPv4/DNS server and UDP port (default 1813) with its own shared secret; leaving that
server blank disables accounting, and leaving the server blank in the editor defaults it to the
authentication server. Existing accounting secrets are preserved only while their server is
unchanged. Switching back to personal or open security removes both authentication and accounting
RADIUS options. All changed wireless options and both secrets are included in the existing rollback
snapshot if the Wi-Fi reload fails. The API exposes only whether each secret is configured, not its
value.

This editor supports WPA2-Enterprise and WPA3-Enterprise with mandatory 802.11w Protected
Management Frames on WPA3, plus optional accounting. It is not a complete NAC platform. The AP
remains attached to its existing network. Dynamic VLAN assignment, 802.1X switch-port control,
certificate provisioning and EAP policy management are not provided by this editor. Administrators must deploy and secure their own RADIUS service,
configure client EAP identities/certificates as required by their organisation, allow the router
to reach the server, and test the authentication path before production rollout. The software
tests validate configuration and rollback logic; they do not prove radio/driver compatibility or
successful authentication against a live RADIUS server.

## Firmware images

The Arcadyan AW1000 release has one persistent firmware format: the device-specific
squashfs factory UBI image. The initramfs image is a temporary RAM-boot recovery/development
artifact; it is not a persistent firmware installer. The release includes
`install-aw1000-ubi.sh` and `verify-aw1000-release-manifest.sh`: the on-router installer checks
the SHA-256 manifest, target board, RAM-boot environment and standard AW1000 MTD geometry before
it can request a confirmed write. It defaults to read-only preflight.

| Artifact | Intended use |
|---|---|
| `*-arcadyan_aw1000-squashfs-factory.ubi` | AW1000 persistent firmware image; use only with the verified AW1000-specific installation route |
| `*-arcadyan_aw1000-initramfs-uImage.itb` | Temporary RAM boot for supported recovery and development workflows |
| `install-aw1000-ubi.sh` | Read-only preflight by default; confirmed factory UBI writer for the standard AW1000 MTD layout |
| `inspect-aw1000-install-target.sh` | Read-only board, root mount, MTD geometry and required-tool inspection on the currently installed router |
| `verify-aw1000-release-manifest.sh` | Require one matching SHA-256 manifest entry before the installer proceeds |
| `*-packages.tar.zst` | Package output from the same firmware build |
| `SHA256SUMS` | Verify the published release assets |
| `BUILDINFO.txt` | Source commits, configuration hash and build metadata |

QuantumGrid intentionally publishes **no `sysupgrade.bin`** for the AW1000 build. The
persistent release artifact is the factory `.ubi` image. Do not upload it to a generic LuCI
sysupgrade form or assume a stock-firmware web installer accepts it.

For the original standard AW1000 layout, boot the matching initramfs temporarily over UART/TFTP,
run `inspect-aw1000-install-target.sh` on the currently installed router first, then boot the matching initramfs over UART/TFTP. Verify the release checksum and transfer the factory image, `SHA256SUMS`, `inspect-aw1000-install-target.sh`, `install-aw1000-ubi.sh` and `verify-aw1000-release-manifest.sh` into `/tmp`.
Then run the installer once without `--write` to inspect its preflight. It accepts only the expected AW1000
board identity and standard `mtd18`/`mtd20` 100 MiB rootfs layout; it refuses expanded layouts
and installed squashfs roots. A real write requires `--write` plus typing `ERASE rootfs` at the
router console. It writes only `rootfs` (`mtd18`) and leaves `rootfs_1` (`mtd20`) untouched.
This is a destructive recovery/install operation, not a generic in-service upgrade. See
[Docs/RECOVERY.md](Docs/RECOVERY.md) and back up first.

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
interface IPv4/IPv6 addresses, DNS servers assigned to each interface, and byte, packet, error
and drop counters with scope filtering and spreadsheet-safe CSV export including successive-sample error/drop deltas, plus searchable/sortable DHCPv4 leases with filtered CSV export, wireless radio state, live iwinfo-associated
Wi-Fi stations, modem device presence, QMI registration/data-session status and cellular RF
measurements where returned, plus RJ11 service/patch state. Signal strength and RX/TX rates
are included only when the relevant wireless or modem interface reports them. DHCP leases show address
allocation, not current reachability or wireless association.
The Network page also lists ordered IPv4/IPv6 policy-routing rules from the kernel, including
priorities, source/destination selectors, firewall marks, interfaces and lookup tables. A separate
table-coverage view cross-references lookup rules with default routes by address family and table;
it reports missing and unreferenced tables without claiming they are invalid or unused. The
Multi-WAN panel reads mwan3 tracking state, logical interface state, tracked-target latency/loss
and elapsed online/offline time, with search and spreadsheet-safe CSV export. The tracker result
and netifd interface state are deliberately shown separately. A further read-only view exposes
active IPv4/IPv6 policy weights and mwan3 directly connected networks. Each WAN also reports
measured RX/TX Mbps from successive kernel byte-counter samples, with sample interval and N/A
handling for first samples, resets or stale intervals. These rates are not link-speed estimates or
policy traffic-share measurements; the views do not change failover policy or simulate packet
routing.
The dashboard's primary WAN throughput is also calculated from successive kernel byte-counter samples. Wi-Fi association
data is read from OpenWrt's iwinfo ubus API; the client inventory can filter and sort stations by
reported TX retries and failed packets, and exports the active diagnostic filters with each row.
Missing driver counters remain unavailable rather than being inferred; retry/failure counts are
cumulative station counters, not a measured packet-loss percentage. The Security Center exports a
read-only firewall, nftables, Adblock Fast and VPN inventory without including keys or credentials.
WireGuard peer health also reports last-handshake age, receive/transmit counters and allowed IPs.
The fixed `wg show all dump` parser deliberately discards private keys, preshared keys, public
keys and endpoint addresses before the data reaches the UI or CSV export.
The 5G page exports its retained QMI RF samples as CSV, preserving unavailable readings as blank fields. Gaming provides searchable/sortable kernel qdisc inventory and exports the visible read-only byte, packet, drop, overlimit and backlog counters for support review. The dashboard single ICMP probe remains a reachability/latency sample; Diagnostics separately runs the explicitly requested five-packet test. Neither feature is a controlled-load bufferbloat benchmark.

The custom API route is protected by LuCI's authenticated administrator tree and accepts no
arbitrary shell commands, UCI writes or caller-selected ubus methods.

On first boot, the wizard first attempts the supplied root password. If that authentication
fails, it attempts an empty root password; only when that succeeds may the authenticated
password endpoint set the new root password, and only if OpenWrt still reports no password hash.
A wrong password on an already-secured router is never overwritten.

## Releases

Release tags use the `qg-v*` pattern, for example `qg-v0.1.0-alpha.1`. A tagged release
builds the AW1000 factory UBI and temporary initramfs images, packages, the pinned RJ11 feed source, recovery/phone guides,
a build provenance file and `SHA256SUMS`.

The release workflow can also be run manually to produce a downloadable CI artifact without
publishing a GitHub Release. The public Downloads page reads the release inventory from GitHub;
it does not fabricate assets before a build completes.

QuantumGrid is router firmware, not a desktop application. We do not publish macOS DMG or
Windows EXE/MSI installers for this project.

## Quality gates

CI checks the existing React control centre with ESLint, TypeScript and Vite; audits npm dependencies
and fails on high/critical advisories; validates the static website's local links and metadata;
checks the website JavaScript; verifies the AW1000 profile, RJ11 packages and shell script syntax;
and runs GitHub CodeQL analysis for Python and JavaScript/TypeScript. The full OpenWrt firmware
build runs only for a release tag or manual firmware workflow dispatch. Routine commits run the faster lint, website, Lua syntax and firmware integration gates
without launching another full OpenWrt compilation.

A successful compile does not prove RF performance, voice-call compatibility, emergency calling,
flash compatibility or NSS acceleration. Those require separate hardware tests and are reported
as such.

## Hardware I/O controls

The authenticated QuantumGrid **Hardware I/O** page reads the kernel GPIO debugfs inventory
when it is mounted and readable, including chip ranges, line labels, consumers, direction and
reported high/low state. When debugfs is unavailable, it falls back to read-only GPIO sysfs chip
metadata (controller label, base offset and line count); that fallback does not infer line ownership,
per-line state or a physical pin mapping. It flags button-like lines only when their kernel label or consumer
contains a button/reset/WPS/power/key/WLAN hint; this is not a verified physical AW1000 pin map
or an inferred physical button mapping. The UI and `quantumgrid-hardware-io buttons` command
also inventory the native `gpio-button-hotplug` driver and existing `/etc/rc.button` handler names.
A separate procd-managed service subscribes read-only to procd's `hotplug.button` ubus notification
object and keeps the latest 64 validated press/release records under `/var/run/quantumgrid`.
The authenticated Hardware I/O page and CLI show button name, action, kernel-reported SEEN duration,
sequence number and timestamp. The listener observes the notification stream; it does not execute,
wrap, replace, intercept or delay native handlers, including reset/WPS behaviour. The service is
enabled by the first-boot defaults script and automatically reconnects if ubus is unavailable.
GPIO ownership,
event interception, direction changes and output writes remain read-only/locked until the board pin
map and recovery-safe behaviour are validated. It also reads `/proc/bus/input/devices` to list
kernel input-device names, handler names and `eventN` nodes, but it never opens those event devices
or consumes input events. GPIO sysfs fallback likewise reads metadata only; it never exports or drives lines. Button telemetry comes only from procd's ubus notifications; it does not
read from input event nodes or modify native hotplug scripts.

When `/proc/device-tree/compatible` identifies `arcadyan,aw1000`, the page also shows the
upstream AW1000 board reference: Wi-Fi/WPS/reset buttons at TLMM offsets 2/62/67 (active-low),
LTE power-key/power/reset at 54/30/63, USB VBUS regulator at 9, SPI LED-expander signals at
18/19/20, and Ethernet resets at 37/64. The 74HC595 LED output indexes are displayed separately
from TLMM offsets. These values come from the upstream
[AW1000 device tree](https://github.com/openwrt/openwrt/blob/master/target/linux/qualcommax/dts/ipq8072-aw1000.dts).
TLMM offsets are local to the Qualcomm pin controller and must not be confused with the global
GPIO numbers printed by debugfs. The map is reference-only; no GPIO, regulator, SPI or PHY-reset
writes are exposed.

The same page enumerates Linux LED-class devices under `/sys/class/leds`. An administrator can
change brightness only for a discovered device whose kernel trigger is explicitly reported as
`none`, with an integer value bounded by that device's reported maximum. The authenticated
write endpoint revalidates the device, checks the trigger, verifies the resulting value and attempts
to restore the prior brightness if verification fails. This is a runtime-only change; it is not
persisted across reboot. LEDs with active or unknown trigger ownership remain locked. The Lua
parser and validation rules are covered by `tests/hardware-io.lua` and the normal firmware CI gate.
No physical button presses, LED wiring, or AW1000 pin-level behaviour are claimed as hardware-tested
by the software tests. The firmware also includes a read-only command-line inspector:
run `sh /usr/bin/quantumgrid-hardware-io` on the router, or pass `gpio`, `buttons` or `leds`
to focus the inventory.

## Managed bridge VLAN configuration

The authenticated **Office Networks → Bridge VLAN management** panel can create, edit and
remove native OpenWrt `network.bridge-vlan` sections on existing bridge devices only when
VLAN filtering is already enabled. The editor requires an explicit tagged, untagged or untagged
PVID mode for every member port. It verifies that selected ports belong to the bridge, prevents
duplicate VLAN IDs on the same bridge, rejects duplicate port entries and prevents a port from
receiving more than one PVID. A legacy port whose mode cannot be determined is never guessed:
the operator must choose a mode before saving.

Every update requires an explicit confirmation and triggers the native network reload. A failed
reload causes QuantumGrid to restore the prior UCI section (or remove a newly created section),
commit the rollback and reload networking again. Failed recovery is reported as unconfirmed and
must be inspected locally; it is not reported as a successful rollback. Change outcomes are
written to the redacted office audit log. Incorrect membership can interrupt wired, wireless or
administrator access. A separate segment provisioner can attach an existing bridge VLAN to a new
static IPv4 interface, create its DHCPv4 pool, join a pre-existing default-deny firewall zone and
add narrow DHCP/DNS access rules. It does not create the bridge VLAN itself, configure Wi-Fi SSIDs
or change downstream managed switches.
VLAN changes should be staged from a verified management path and tested with an out-of-band
recovery method available. QuantumGrid checks the current administrator's IPv4 route: it blocks
edits/removal of the VLAN carrying that session and preserves the native untagged memberships
when the session routes directly over the bridge. Untagged membership on a port already assigned
to another VLAN is also rejected.

## Managed office firewall forwarding

The Office Networks page can add and remove explicit inter-zone forwarding entries. Creation
requires two existing, distinct firewall zones; standard WAN/WWAN zones and zones mapped to
WAN/WWAN networks are blocked as sources but may be destinations. The operation creates a
native UCI `firewall.forwarding` section, commits it and reloads the native firewall service.
Removal snapshots and restores the complete forwarding section if a firewall reload fails.
Both operations require an authenticated same-origin administrator POST, explicit confirmation
and produce a redacted audit event. The controller does not modify zone input/output defaults
through this manager, so router-management access policy remains separately controlled.

A forwarding entry is a directional permission, not a firewall packet-path test. The separate
zone-policy editor can change existing zone output/forward defaults and masquerading while leaving
router INPUT read-only. This control does not edit individual rule ordering, NAT redirects, traffic
shaping, address sets or policy-routing. Review the complete fw4 ruleset and test the actual path
between clients before deploying segmentation to a production office.

## Managed firewall zone policy

Office Networks can now update the **output** and **forward** policies and masquerading state
of an existing firewall zone. Each change uses native UCI, explicit operator confirmation,
firewall reload and a rollback attempt. Existing inherited/global defaults are preserved as
distinct states: the editor can leave an option unchanged or deliberately remove its explicit
override to inherit the global default. The zone's **input** policy is intentionally not exposed
for editing; it is displayed read-only because it governs access to the router itself.

For an output policy that would become restrictive or inherit an unknown default, QuantumGrid
checks the current administrator's IPv4 route. The change is blocked when the selected zone
carries that route, or when the route cannot be proven. This is a management-plane safeguard,
not a substitute for an out-of-band recovery path. Masquerading changes source-NAT behaviour
and can alter connectivity; review the zone's networks and test real client traffic after
applying changes. The UI and API do not edit individual firewall rules, NAT redirects, address
sets or policy-routing entries through this zone editor.

## Routed IPv4 office segment provisioning

Office Networks can provision a routed IPv4 segment **on an existing bridge VLAN**. The bridge
must already have VLAN filtering enabled and the selected VLAN must already contain validated
switch-port membership. The administrator supplies a unique interface name, RFC1918 gateway
address, contiguous /1–/30 netmask, DHCPv4 pool and an existing internal firewall zone.

The selected zone must already default router INPUT and inter-zone FORWARD to REJECT or DROP.
QuantumGrid does not change those zone policies. It attaches the new network interface to the zone,
creates the DHCPv4 server scope, and installs three narrow IPv4 rules: DHCP UDP/67 and DNS UDP/53
plus TCP/53. The DNS rules are restricted to the new subnet and gateway address. DHCPv6, router
advertisements and NDP are explicitly disabled for this IPv4-only provisioner. WAN/WWAN zones,
duplicate interface/device assignments, overlapping existing static subnets, uncalculable existing
static subnets, invalid DHCP pools and truncated inventories are rejected.

Network, firewall and DHCP UCI changes are committed together as a guarded multi-package operation.
The network, firewall and dnsmasq services are then reloaded/restarted. If staging, commit or a
service reload fails, QuantumGrid attempts to remove the partial interface/scope/rules, restore the
firewall zone's original network list, commit the rollback and reload all affected services. A
rollback is reported as successful only when all recovery steps are confirmed; otherwise the
administrator is told to inspect the router locally. The action is audited.

This creates an IPv4 interface and DHCPv4 scope only; it does not create the bridge VLAN, Wi-Fi
SSID-to-VLAN binding, IPv6 configuration, static leases, NAT, inter-zone forwarding or downstream
switch/access-point configuration. The operation is a source integration, not proof of end-to-end
switch tagging, client DHCP, DNS or inter-VLAN reachability. Test on a non-management VLAN and keep
an out-of-band recovery path available before production use.

## Static SSID-to-VLAN binding

The existing AP editor can bind an SSID to one existing **static L3 network interface**, including
a routed interface created on an existing bridge VLAN by Office Networks. The selected interface
must have a validated network device and belong to exactly one internal firewall zone; WAN/WWAN
networks and ambiguous zone associations are rejected. The chosen logical network is written to
the native wireless AP `network` option in the same UCI snapshot as SSID/security changes, and is
restored if the Wi-Fi reload fails.

The editor inventories existing AP-to-network mappings without returning credentials. It requires
one explicit target network, so legacy APs with no network or multiple network attachments must be
normalized by an administrator before saving. QuantumGrid checks the current administrator's
IPv4 return route and blocks a change that would remove that network from the AP currently carrying
the admin session, or move another SSID onto that management network. Use a separate AP or an
out-of-band connection for those changes. This is static per-SSID network binding, not RADIUS
dynamic VLAN assignment; each SSID should be mapped to one routed VLAN interface and clients
should be tested on the actual switch/AP path after deployment.

## RADIUS dynamic VLAN assignment

The existing Enterprise AP editor supports an explicit allow-list of **RADIUS-assigned VLANs**
using the native OpenWrt `wifi-vlan` UCI sections and hostapd `dynamic_vlan=2` mode. Mode 2
requires the RADIUS server to return the standard tunnel attributes: Tunnel-Type = VLAN,
Tunnel-Medium-Type = IEEE-802, and Tunnel-Private-Group-ID equal to one of the configured VLAN
IDs. A client is not assigned to an arbitrary VLAN: every accepted VLAN ID is mapped to one
pre-provisioned routed IPv4 office network.

Each mapping requires an existing bridge with VLAN filtering enabled, a matching
`network.bridge-vlan` section with explicit switch-port membership, a static L3 interface on
`<bridge>.<vid>`, an IPv4 gateway, and exactly one internal firewall zone whose router INPUT and
inter-zone FORWARD policies are REJECT or DROP. Duplicate VLAN IDs, duplicate network interfaces,
external WAN/WWAN mappings, missing VLANs, untagged/unmanaged bridges, incomplete subnet inventory,
and zones without the default-deny baseline are rejected. The current implementation limits an AP
to 16 explicit mappings. It does not create VLANs, networks, DHCP pools, firewall zones or switch
port membership dynamically; provision those first in Office Networks.

QuantumGrid writes the AP's `dynamic_vlan=2` flag and deterministic `wifi-vlan` mappings together
in one wireless UCI update. The prior AP settings and owned mapping sections are snapshotted and
restored together when `wifi reload` fails. Mapping sections not clearly owned by QuantumGrid,
custom hostapd VLAN file/bridge/naming options, and unsupported optional dynamic VLAN modes are
treated as externally managed: their configuration is preserved and the GUI makes them read-only.
WPA2-Enterprise or WPA3-Enterprise is required; WPA3 keeps mandatory 802.11w Protected Management
Frames enabled.

The administrator must configure the actual RADIUS policy to send the three tunnel attributes
with the intended VLAN ID, deploy and protect the RADIUS shared secret, and verify the EAP method,
certificate trust and client identity policy separately. Source tests validate the mapping rules
and client API contract; they do not prove successful EAP authentication, RADIUS reachability,
hostapd runtime behaviour, switch tagging or client DHCP/DNS on a physical AW1000. Test with a
non-management SSID and an out-of-band recovery path before production deployment.

## DHCPv6, router advertisements and NDP

Each eligible DHCP scope now exposes per-scope **DHCPv6**, **Router Advertisement (RA)** and
**Neighbor Discovery Proxy (NDP)** controls alongside the IPv4 pool editor. DHCPv6 and RA can be
set to `server` or `disabled`; NDP can be disabled. An explicit **Keep current** choice preserves
the exact existing UCI value, including an existing relay or hybrid mode. The scope inventory
reports the current DHCPv6, RA and NDP values.

Changing any IPv6 mode writes the native `dhcp.dhcpv6`, `dhcp.ra` and/or `dhcp.ndp` options,
restarts dnsmasq and odhcpd, and verifies both restart results. If either service restart fails,
QuantumGrid restores the complete prior IPv4 pool, lease and IPv6 mode snapshot, commits it, and
attempts to restart both affected services again. A failed recovery is reported as unconfirmed.

Relay and hybrid operation is intentionally retained but not created by this editor: odhcpd relay
depends on correctly configured master/upstream interface topology. Establish and validate that
topology in native LuCI before using relay/hybrid modes. DHCPv6 does not itself provide an IPv6
default route; review RA/SLAAC and prefix delegation for each LAN, and validate client addressing,
DNS and routed reachability before a corporate rollout. These settings do not configure an ISP
delegated prefix, DHCPv6 prefix delegation, DNS RA options, static IPv6 addresses or firewall IPv6
rules.

## SSID-to-LAN/VLAN binding

Office Networks can bind an existing wireless AP section to one existing LAN or VLAN network
interface. The AP must already exist and the destination must be present in the live interface
inventory; interfaces attached to WAN/WWAN firewall zones are rejected. The operation changes
only the selected `wireless.<section>.network` list, commits it and reloads Wi-Fi. The complete
prior list, including whether it was absent, is snapshotted and restored if the Wi-Fi reload
fails. The change is recorded in the redacted office audit log.

QuantumGrid checks the current administrator's IPv4 return network before moving an AP. If the AP
currently carries that management network, the move is refused from that session. If the current
management route cannot be proven, changes to an existing AP binding fail closed. Use a separate
management AP or out-of-band access to change a management SSID.

This does not create the destination L3 interface, bridge VLAN, switch tagging, DHCP pool, firewall
zone or IPv6 prefix plan. Separately, Enterprise APs can use the allow-listed RADIUS dynamic VLAN
manager documented below; it accepts only pre-provisioned mappings and does not create VLANs or
subnets. Multiple simultaneous static network bindings, mesh topology and downstream managed-switch
configuration are not provided. Validate switch membership, firewall segmentation and DHCP/IPv6
client operation after moving a corporate, guest or IoT SSID.

## WAN port forwarding (DNAT)

The Office Networks page can create and remove explicit IPv4 DNAT rules from an existing
WAN/WWAN firewall zone to an internal host. A rule accepts one external port, one destination
port and TCP, UDP or TCP+UDP. The destination address must be a usable host inside a static IPv4
subnet attached to the selected internal firewall zone. The controller rejects internal source
zones, external destination zones, WAN-to-WAN paths, out-of-subnet targets, invalid ports and
duplicate external source-port/protocol combinations.

Rules are native `firewall.redirect` sections, committed and followed by firewall reload.
Creation rolls back the new section if reload fails; removal snapshots and restores the complete
redirect section if reload fails. Both operations require same-origin administrator POSTs and
explicit confirmation, and write redacted audit events. This is IPv4 port forwarding only; it
does not configure the internal service's host firewall, application authentication, TLS, IDS,
reverse proxy, IPv6 firewall pinholes or external DNS. Only expose a host/service after a separate
security review and verify it from an external network.

## Office network inventory

The authenticated **Office Networks** page provides a correlated inventory and guarded configuration tools for
network interfaces and subnet masks, IPv6 assignment prefixes, bridge devices, bridge VLAN IDs and
tagged/untagged/PVID port membership, firewall zones and their input/output/forward policies,
explicit inter-zone forwarding entries, routed IPv4 segments, DHCPv4 scopes and their zone associations,
wireless AP sections mapped to network names, DHCP scope offsets/limits/lease options, and validated
static IPv4/MAC host reservations. Interface link state is queried from the router's network-interface
status API. The page supports office network design reviews and CSV inventory hand-off without inventing missing
VLANs, expanding DHCP ranges incorrectly, or claiming isolation from names alone.

The reservation form can also prefill host, MAC and address fields from an unexpired DHCP lease
reported by dnsmasq. It suggests a LAN only when the lease IPv4 matches a configured eligible static
subnet; the form remains a draft and the administrator must verify the selector and explicitly confirm.

Guarded **Add**, **Edit** and **Remove** static reservation controls are also available for
existing enabled DHCP scopes on static IPv4 LAN interfaces. Creation and editing validate the
hostname, unicast MAC, canonical IPv4 address, subnet membership, duplicate reservations and
current DHCP leases. Editing preserves the original UCI host section and unrelated dnsmasq options;
removal targets a validated UCI host-section ID and snapshots the original section. All three
operations restart dnsmasq and attempt to restore the previous UCI/service state if the restart fails.
New DHCP scopes can be created on an existing static IPv4 LAN only when that interface has no
DHCP scope already. Creation validates the pool boundary and overlaps with every calculable active
pool, and fails closed if the router inventory is truncated or any existing active pool has an unknown
range. It adds a native DHCP UCI section and removes it again if dnsmasq cannot restart. Existing
DHCP scopes can be removed with a separate two-step confirmation; the entire UCI section, including
list-valued DNS and RA options, is snapshotted and restored if dnsmasq cannot restart. Removing a
scope stops new leases on that LAN, but already-issued client leases may remain valid until expiry.

Existing DHCP scope edits are limited to start offset, pool size and lease duration. The server
checks address boundaries and collisions against other enabled scopes, and fails closed if a sibling
scope on the same interface has an uncalculable range. It snapshots the three changed UCI options,
restarts dnsmasq and attempts rollback on failure. Existing scopes can also be explicitly enabled or
disabled. Enabling validates the stored pool against the network subnet and active sibling pools;
both directions restart dnsmasq and restore the previous `ignore` setting if the restart fails.
These controls do not create or alter network interfaces, VLANs, firewall zones, DNS, DHCPv6 or RA settings.

The selected LAN is used for reservation subnet validation only: a standard dnsmasq host section is
global to that dnsmasq instance, not a per-VLAN reservation binding. Removing DHCP server scopes, changing network interfaces, and migrating active clients are not exposed yet.

This inventory does not configure VLANs, DHCP pools, firewall rules, RADIUS/802.1X, VPN tunnels,
switch ports or AP uplinks. It does not inspect downstream managed switches or verify inter-VLAN
packet paths. A configured VLAN or a restrictive-looking firewall zone is not a security test or
a compliance result. Write-capable office provisioning remains gated on transaction/rollback
handling, management-plane lockout protection, and device-specific bridge/switch validation.
The parser and correlation rules, including IP/MAC validation, are covered by `tests/office-networks.lua` in the normal CI gate, including DHCP host/subnet checks and live-lease collision detection, DHCP pool range validation and overlap checks.

## Remote syslog forwarding

The System page configures the native OpenWrt remote log forwarder through the existing
`system` UCI section. It supports an IPv4 address or DNS name, a destination port, UDP, TCP or
authenticated TLS, an optional sender hostname and a message prefix. Changes require an authenticated
same-origin HTTPS POST and explicit confirmation. The local log buffer remains enabled.

For TLS, the firmware includes OpenWrt's `stunnel` client and the system CA bundle. QuantumGrid
creates or updates only its reserved `stunnel.quantumgrid_syslog` service section, binds the
plaintext side exclusively to `127.0.0.1:5514`, and forwards to the configured collector over TLS.
The client pins the TLS protocol to TLS 1.2, requires certificate-chain verification and an
exact DNS hostname or IPv4 subject alternative name match; DNS destinations also use SNI. The
control refuses to enable TLS unless the stunnel global configuration explicitly drops privileges
to a non-root user and group (the upstream package defaults are `nobody` and `nogroup`). It does
not disable certificate verification or permit a user-supplied arbitrary stunnel configuration.
Alternate stunnel configuration files are refused, as are unmanaged directives in the reserved
QuantumGrid service section. Existing unrelated stunnel sections and global options are preserved.

The controller snapshots the affected system and managed stunnel options, commits the tunnel before
the native logger, checks both service restarts, then verifies the expected stunnel PID, process name,
executable/configuration arguments, TLS policy and exact configured destination before reporting TLS
as ready. A failed post-start verification triggers the same rollback path as a failed restart. It
attempts to restore both configurations if a commit, restart or live-state check fails. The operation is recorded in the redacted administrative audit history.
A successful local restart and a valid trust configuration do **not** prove that the collector is
reachable or that it received or retained a message. Native OpenWrt `logread` sends newline-delimited
records over TCP; this tunnel does not convert them to RFC 5425 octet-counted framing. Configure the
collector for compatible LF-delimited syslog/TCP input, or place a protocol-aware relay in front of
the collector, and verify message receipt and parsing independently.

UDP and TCP modes remain unencrypted and do not authenticate the collector; use a trusted management
VLAN or VPN for those transports. The TLS mode uses the firmware's installed public CA bundle and
does not currently support private-CA import, mutual-TLS client certificates, certificate pinning,
RFC 5425 octet-counting, IPv6 literal destinations, collector health probes or multiple destinations. A production deployment
must verify the collector's certificate chain, DNS, firewall policy, receipt and retention from the
collector side. Lua validation is covered by `tests/remote-syslog.lua`, and the browser API contract
by `tests/remote-syslog-api.test.mjs` in CI.

## Configuration backup

The authenticated System page creates a configuration archive using the router's native
`sysupgrade -b` operation. It requires a same-origin administrator HTTPS POST and explicit
confirmation, returns a no-store `.tar.gz` response capped at 64 MiB, validates the router-side
temporary path under `/tmp`, and removes that file after the response is read. It does not reboot
the router or modify its configuration.

The browser immediately encrypts the archive before offering a download. The versioned `.qgbak`
container uses PBKDF2-HMAC-SHA-256 with 600,000 iterations and a random 16-byte salt to derive a
non-exportable 256-bit AES key, then AES-256-GCM with a fresh 12-byte nonce and a 128-bit
authentication tag. The full 40-byte format header (magic/version, KDF iteration count, salt and
nonce) is authenticated as additional data, preventing silent header modification or iteration
downgrades. The passphrase is never sent to the router. A minimum 16-character passphrase is
required; use a unique high-entropy passphrase and store it separately from the backup.

The System page can decrypt a `.qgbak` file locally in the browser. It verifies the container
version, fixed KDF policy and AES-GCM authentication before releasing the original gzip archive;
wrong passphrases and tampered files fail closed. Decryption does not upload the file or restore
configuration to the router. **Treat both the encrypted backup and decrypted archive as secrets.**
The feature does not provide one-click restore/import: restore only to compatible hardware and
firmware using the documented recovery process, and preserve an independent recovery route.
Cryptographic container tests are covered by `tests/config-backup-crypto.test.mjs`; router-side
archive validation remains covered by `tests/config-backup.lua` and the normal firmware CI gate.

## Administrative audit history

The Office **Admin Audit** page exposes an authenticated read-only history for supported actions:
first-boot root-password setup, Wi-Fi configuration changes, SQM queue changes, DHCP scope
updates, static DHCP reservation add/remove, APK/OPKG install/remove/feed-update operations,
manual LED brightness changes, remote syslog destination updates and configuration backup downloads. Each event records only a timestamp, the current administrator label, remote source IP,
allowlisted action, target label and success/failure outcome. Submitted passwords, SSIDs, keys,
VPN private keys, package command output and arbitrary configuration values are not part of the
event schema.

The log is stored under `/etc/quantumgrid` with restrictive directory/file permissions. It rotates
one previous file when the active log exceeds 512 KiB; the API reads no more than the last 512 KiB
of each log file and returns at most the newest 200 valid events. Oversized source files are marked
as truncated instead of being loaded wholesale into router memory. CSV export follows the visible
search/filter results. It is a local operational aid, not a
tamper-proof accounting system or a compliance certification: root access can change it, some
rejected/pre-validation requests are not recorded, and it is not a remote immutable log collector.
For production deployments, forward system logs to a separately managed, access-controlled log
server and define an independent retention policy. Parser and redaction rules are tested by
`tests/audit-log.lua` in CI.

## Administrator management-plane posture

The Security Center includes a read-only inventory of configured Dropbear SSH instances alongside
the existing uHTTPd HTTPS review. HTTPS inspection now reports a SHA-256 fingerprint of the served
certificate for independent out-of-band comparison, plus the HTTPS private-key file path, size,
regular-file status, root ownership and full group/other access check. OpenWrt `lstat` metadata is
used so symlinked key files are not accepted as regular key files. The controller invokes OpenSSL
with a fixed read-only command and returns only the fingerprint digest, never certificate PEM or
private-key contents. The fingerprint is not automatically trusted or chain-validated; administrators
must compare it against a value obtained through a separate trusted channel. It reports service/config
availability, enabled instance counts,
configured interface bindings and ports, password and root-password authentication settings,
gateway-port forwarding state, and whether the bounded eight-instance detail list is truncated.
Unknown or malformed enabled-instance settings are treated as a review item rather than as a secure
setting. Missing SSH configuration is not reported as a successful hardened state. For key-only
Dropbear configurations, the inventory also checks the metadata of the standard
`/etc/dropbear/authorized_keys` and `/root/.ssh/authorized_keys` locations: file presence, size,
regular-file type, owner-read permission, root ownership, and group/other write bits. The parent directory must also be a real,
root-owned directory that is not writable by group/others. The inspection never returns public-key
contents, and files that are empty, larger than 64 KiB, not regular files, not owner-readable,
not root-owned, or writable by group/others—or files with an unsafe/uninspectable parent directory—
are not treated as a ready key-file posture.

The current AW1000 first-boot Dropbear profile deliberately keeps password and root-password
authentication enabled for initial access while binding the daemon to the LAN interface. QuantumGrid
reports that configuration for administrator review; it does not silently disable SSH password
authentication or restart Dropbear, because doing so before a public key is installed and tested
could lock the administrator out. For a production deployment, install and verify a working
administrator SSH key using a trusted console or independent recovery path, then explicitly disable
both `PasswordAuth` and `RootPasswordAuth` for every enabled Dropbear instance. Keep SSH bound to
the dedicated trusted management interface and leave `GatewayPorts` disabled. The SSH posture
review now correlates every enabled Dropbear interface against the configured firewall-zone network
membership: only one recognised internal management zone is accepted, standard WAN/WWAN bindings
require review, and custom, missing or ambiguous mappings remain unknown. A syntactically valid
interface name is not treated as evidence of a trusted management network.

These are configuration inventory checks, not a live socket scan, firewall reachability test,
cryptographic validation of authorized-key contents, proof that a key is installed on an administrator's
client or usable for a successful login, certificate-chain validation, compliance assessment or
security certification. Confirm SSH access from a separate management host and validate the
effective firewall and management VLAN path before deploying a change to a remote device. The
reported posture must not be interpreted as proof that a service is or is not reachable from WAN.

## Development status

- **Integrated:** AW1000 target profile, existing React control centre, pinned RJ11 source feed,
  safe first-boot default for the FXS service, Pages workflow, release build workflow, read-only
  IPv4/IPv6 route and policy-rule inventory, bounded edits to existing SQM queue enable/rate
  settings plus guarded link-layer overhead/MPU calibration and curated CAKE best-effort/DiffServ
  profiles with same-origin validation, preserved unrelated qdisc options, restart checks and
  rollback handling,
  Hardware I/O with read-only GPIO/button inventory
  and guarded runtime LED brightness, Office Networks VLAN/bridge/firewall/SSID/DHCP inventory with CSV export, guarded bridge VLAN and inter-zone firewall controls, routed IPv4 segment provisioning, static DHCP reservation add/edit/remove, and DHCP scope create/edit/enable/disable/remove controls, native remote syslog forwarding controls, authenticated explicit-confirmation configuration backup downloads, a
  redacted local administrative audit history with bounded retention, read-only live root-qdisc
  matching for enabled SQM queues with explicit incomplete/unavailable states, and guarded,
  audited upload and static-reservation IPv4 download DSCP marking on validated firewall-zone paths.
  Download rules cover all IP protocols and are tied to unique static DHCP reservations; reservation
  changes that would orphan these rules are blocked.
- **Active development:** wider UI-to-ubus control wiring, per-client bandwidth and priority policies,
  controlled-load bufferbloat testing, radio
  intelligence/scheduling and modem observability. Curated CAKE profiles and upload-side DSCP
  policies are configuration controls; they do not prove ingress/egress shaping or measured
  latency improvement without hardware testing.
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
