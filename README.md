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

To use a different OpenWrt revision deliberately:

```bash
QG_OPENWRT_REF=v25.12.6 ./build.sh
```

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
prefixes are neutralised in the export. The Wi-Fi page also includes an authenticated editor for existing AP interfaces: SSID, WPA2/WPA3 security, a new or preserved passphrase, hidden SSID and driver-reported unrestricted channel selection. It commits only the selected AP/radio options, reloads Wi-Fi and attempts restoration if reload fails; channel width/PHY mode and transmit power are selectable only from values reported by the selected radio driver. Band steering, radio scheduling and full radio enable/disable controls are not yet connected in QuantumGrid. The image includes upstream usteer and its LuCI app for optional multi-AP steering, but the usteer daemon is disabled by first-boot defaults until an administrator defines the participating SSIDs and policy. The native app is available at `/cgi-bin/luci/admin/network/usteer`. The Wi-Fi page also builds a read-only shortlist from
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
reports SQM queue configuration and read-only kernel qdisc
counters; it does not yet write queue policy, classify traffic or apply per-client priority.
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
tuples remain N/A rather than being guessed. The Security Center adds a read-only firewall posture review: it flags
ACCEPT input/forward defaults on standard WAN/WWAN zones and also flags enabled ACCEPT rules
whose source-zone list includes a standard WAN/WWAN name or has no explicit source-zone
restriction. Restrictive defaults are reported separately; custom external-zone names and
unavailable telemetry remain unknown. Security Center returns up to 64 firewall rule summaries
with zone direction, protocol, target, port constraints and presence flags for address matches;
raw IP and MAC values are omitted. Summaries can be searched, sorted and exported, but rule
order, NAT, full address matching and actual packet matching are not evaluated. This is not a
vulnerability scan and it does not prove that a router is exposed or secure. The Advanced page reports system.board firmware identity, a bounded installed-module inventory parsed from the running kernel's `modules.dep` and compared with live `/proc/modules` state, init-script and diagnostic-tool presence, package-manager detection, read-only Netfilter
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
reported high/low state. It flags button-like lines only when their kernel label or consumer
contains a button/reset/WPS/power/key/WLAN hint; this is not a verified physical AW1000 pin map
or a live button-event stream. The UI and `quantumgrid-hardware-io buttons` command also inventory
the native `gpio-button-hotplug` driver and existing `/etc/rc.button` handler names. OpenWrt procd
dispatches events to the handler matching the kernel-reported button name; QuantumGrid deliberately
does not wrap or replace these handlers, which may implement reset/WPS behaviour. GPIO ownership,
event interception, direction changes and output writes remain read-only/locked until the board pin
map and recovery-safe behaviour are validated. It also reads `/proc/bus/input/devices` to list
kernel input-device names, handler names and `eventN` nodes, but it never opens those event devices
or consumes input events.

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

## Office network inventory

The authenticated **Office Networks** page provides a read-only correlation of configured
network interfaces and subnet masks, IPv6 assignment prefixes, bridge devices, bridge VLAN IDs and
tagged/untagged/PVID port membership, firewall zones and their input/output/forward policies, explicit inter-zone forwarding entries,
wireless AP sections mapped to network names, DHCP scope offsets/limits/lease options, and validated
static IPv4/MAC host reservations. Interface link state is queried from the router's network-interface
status API. The page supports office network design reviews and CSV inventory hand-off without
inventing missing VLANs, expanding DHCP ranges incorrectly, or claiming isolation from names alone.

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

The System page can configure the native OpenWrt remote log forwarder through the existing
`system` UCI section. It supports an IPv4 address or DNS name, a destination port, TCP or UDP,
optional sender hostname and message prefix. Changes require an authenticated same-origin POST
and explicit confirmation, are validated before writing, and restart the native `log` service.
The previous UCI values are snapshotted and a rollback/restart is attempted if the service restart
fails. The local log buffer remains enabled.

**Transport security limitation:** OpenWrt's built-in `logread` forwarder supports TCP or UDP
syslog, not TLS. This feature does not encrypt or authenticate the remote connection and does not
verify that the collector received the messages. Use a trusted management VLAN or VPN between the
router and collector; do not send logs over an untrusted public network. IPv6 literal destinations,
TLS syslog, certificate management, collector health tests and multi-destination forwarding are not
implemented. The validation rules are covered by `tests/remote-syslog.lua` in CI.

## Configuration backup

The authenticated System page can generate a configuration archive using the router's native
`sysupgrade -b` operation. It requires a same-origin administrator POST and an explicit
confirmation checkbox, returns a no-store `.tar.gz` download, and caps the archive at 64 MiB.
The router-side temporary path is validated under `/tmp` and removed after the response is read.
The action does not reboot the router or modify its configuration.

**Treat the archive as a secret.** It may contain administrator credentials, Wi-Fi passphrases,
VPN private keys, certificates and other sensitive settings. Store it encrypted on a trusted device,
limit access and keep a separate recovery route. The current feature creates backups only; it does
not provide an automatic restore/import button. Restoring a backup must be done only with a
compatible device/firmware and the documented recovery process. Validation rules are covered by
`tests/config-backup.lua` and the normal firmware CI gate.

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

## Development status

- **Integrated:** AW1000 target profile, existing React control centre, pinned RJ11 source feed,
  safe first-boot default for the FXS service, Pages workflow, release build workflow, read-only
  IPv4/IPv6 route and policy-rule inventory, bounded edits to existing SQM queue enable/rate
  settings with restart and rollback handling, Hardware I/O with read-only GPIO/button inventory
  and guarded runtime LED brightness, Office Networks VLAN/bridge/firewall/SSID/DHCP inventory with CSV export, guarded static DHCP reservation add/edit/remove, and DHCP scope create/edit/enable/disable/remove controls, native remote syslog forwarding controls, authenticated explicit-confirmation configuration backup downloads, and a
  redacted local administrative audit history with bounded retention.
- **Active development:** wider UI-to-ubus control wiring, radio intelligence, CAKE tuning,
  traffic classification, per-client priority, controlled-load bufferbloat testing and modem
  observability.
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
