# Release process

QuantumGrid publishes router firmware releases, not desktop installers.

## Version tags

Use tags matching `qg-v<semver>`, for example:

- `qg-v0.1.0-alpha.1` for an early preview
- `qg-v0.1.0` for a first stable release

The release workflow uses upstream OpenWrt `v25.12.6` by default and the AW1000 FXS source
at `v0.9.0`. Manual firmware dispatches can opt into the experimental NSS profile, which pins
`qosmio/openwrt-ipq` at `d6848fa2ea00193b5b7d3973e3990da7f608027c`; NSS artefacts carry an
`-nss` suffix. The NSS profile also pins all seven OpenWrt and Qosmio package feeds in
`configs/aw1000-nss-feeds.conf`. Resolved source commits and profile configuration hashes are
written into `BUILDINFO.txt`; package-feed commit revisions are listed in
`OPENWRT-FEEDS.txt`. Automatic release-tag builds remain on the stable upstream profile.

## AW1000 image formats

Every completed build must include:

- Exactly one non-empty Arcadyan AW1000 squashfs factory UBI image (`.ubi`), validated for the UBI erase-counter header
- Exactly one non-empty AW1000 squashfs sysupgrade archive (`.bin`), validated for the AW1000 board metadata and required kernel/root payloads
- One AW1000 initramfs image (`.itb`) for temporary RAM boot and recovery/development
- Package archive produced by the same build
- `OPENWRT-FEEDS.txt` listing verified package-feed commit revisions
- Pinned AW1000 phone-feed source archive
- Exact installed-package manifest used by the SBOM generator
- CycloneDX 1.6 SBOM with SHA-256 evidence references for both persistent firmware images
- Phone-port and recovery guides
- The exact AW1000 build configuration
- `BUILDINFO.txt` and `SHA256SUMS`
- `verify-aw1000-release-manifest.sh` for on-router checksum enforcement
- `verify-aw1000-release-attestation.sh` for host-side GitHub/Sigstore provenance verification
- `verify-aw1000-sysupgrade.sh` for sysupgrade archive-content validation
- `inspect-aw1000-install-target.sh` for read-only board, mount, MTD and tool inspection
- `install-aw1000-ubi.sh` for guarded first installation from a matching AW1000 initramfs

The factory `.ubi` is the first-install/recovery image; the `.bin` is the in-service update
image for a compatible, already-running OpenWrt-based AW1000 system. Neither is interchangeable
with the other. The UBI installer verifies its exact filename and SHA-256 digest against
`SHA256SUMS` before permitting either preflight completion or a flash write. The manifest is
an integrity check, not a cryptographic signature or proof of publisher identity.

After creating `SHA256SUMS`, the firmware release workflow creates a GitHub artifact attestation
for every file in `dist/` using Sigstore-backed SLSA provenance. This binds each asset's SHA-256
digest to the repository, source commit, workflow identity and build run. The CycloneDX SBOM
hashes the factory image, sysupgrade image, installed-package manifest, resolved OpenWrt feed
report, pinned AW1000 phone-source archive, `BUILDINFO.txt`, exact AW1000 build configuration
and package archive. Package inventory entries are limited to the names and versions present in
the image manifest; the generator does not fabricate license or transitive-dependency data that
the manifest does not contain. The checksum manifest remains useful for transfer-corruption
checks, but it is not the publisher-authentication mechanism.

Install and authenticate GitHub CLI, download the release assets, then verify the image you
intend to install or upgrade before transferring it to the router:

```bash
sha256sum -c SHA256SUMS
sh verify-aw1000-release-attestation.sh QuantumGrid-OS-<version>-AW1000-squashfs-factory.ubi SHA256SUMS
sh verify-aw1000-release-attestation.sh QuantumGrid-OS-<version>-AW1000-squashfs-sysupgrade.bin SHA256SUMS
```

The bundled host-side verifier checks the image digest first, then requires a GitHub artifact
attestation from this repository. It pins the signer with
`--signer-workflow NetCore-Technologies/QuantumGrid-OS/.github/workflows/firmware-release.yml`,
and requires the precise `refs/tags/qg-v…` source ref inferred from the versioned image filename,
SLSA provenance v1 and a GitHub-hosted runner. It rejects manual-build filenames and requires
GitHub CLI 2.102.0 or newer because an older CLI compared `--source-ref` case-insensitively.
The publish job itself runs only for a pushed version tag; a manual dispatch can build and attest
inspection artifacts but cannot publish a release, even when dispatched against a tag. Do not
flash an image when any verification step fails. The on-router installer still enforces SHA-256
only; it does not verify Sigstore attestations itself. Keep host-side verification as a required
first-install/upgrade step.

The initramfs `.itb` is a RAM-boot artifact and does not install persistent firmware. The
sysupgrade archive is intended for compatible running OpenWrt installations only; it must never
be presented as an initial-install image for stock/vendor firmware.

The workflow fails if either persistent image is missing, empty, duplicated, or malformed. The
factory UBI must have a valid UBI header. The sysupgrade archive must contain exactly one
AW1000 `CONTROL`, `kernel` and `root` entry, with `BOARD=arcadyan_aw1000`. It also fails
if the expected AW1000 initramfs image is missing or empty. A release must never be published
with placeholder, empty or copied images.

## Build and verification

1. Run the normal CI gates.
2. Check the AW1000 profile, both persistent image validators and phone package dependencies.
3. Create a `qg-v*` tag only from the source commit intended for release.
4. Let the firmware release workflow build the exact tagged source.
5. Verify `SHA256SUMS`, review `BUILDINFO.txt` and read the build logs.
6. Test both the first-install UBI path and the in-service sysupgrade path on recoverable AW1000
   hardware before recommending installation.

Manual workflow dispatch creates CI artifacts for inspection and does not publish a GitHub Release.

## Safety and compatibility

Do not pass the factory UBI image to a generic LuCI sysupgrade handler or assume that stock
firmware accepts the AW1000 sysupgrade archive. Follow the route for the currently running
firmware, confirm the exact board and partition layout, and retain a known-good recovery path.

The FXS phone service ships disabled by default and needs a compatible kernel, VoLTE service
and user-supplied Skyworks patch. Never claim emergency-call certification without dedicated
testing. The stable upstream image does not include NSS. The opt-in NSS profile selects the
AW1000 NSS device-tree include, EDMA/PPE switch path, NSS 12.5 firmware for both cores, NSS core
and ECM modules, and ath11k/mac80211 NSS Wi-Fi hooks. Presence of these components or a loaded
`qca-nss-dp`/`qca-nss-drv` module does not establish that NSS firmware booted or that flows
are being offloaded. Keep the generic OpenWrt packet-steering/software/hardware flow-offload
options disabled on NSS builds. DSA bridge-VLAN filtering is incompatible with NSS Wi-Fi offload.
Do not claim working NSS acceleration until packet-path counters, throughput/latency benchmarks
and recovery have been validated on physical AW1000 hardware.
