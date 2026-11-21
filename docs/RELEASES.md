# Release process

QuantumGrid publishes router firmware releases, not desktop installers.

## Version tags

Use tags matching `qg-v<semver>`, for example:

- `qg-v0.1.0-alpha.1` for an early preview
- `qg-v0.1.0` for a first stable release

The release workflow uses upstream OpenWrt `v25.12.6` by default and the AW1000 FXS source
at `v0.9.0`. Manual firmware dispatches can opt into the experimental NSS profile, which pins
`qosmio/openwrt-ipq` at `d6848fa2ea00193b5b7d3973e3990da7f608027c`; NSS artefacts carry an
`-nss` suffix. Resolved source commits and profile configuration hashes are written into
`BUILDINFO.txt`; package-feed commit revisions are listed in `OPENWRT-FEEDS.txt`. Automatic release-tag builds remain on the stable upstream profile.

## AW1000 image formats

Every completed build must include:

- Exactly one non-empty Arcadyan AW1000 squashfs factory UBI image (`.ubi`), validated for the UBI erase-counter header
- One AW1000 initramfs image (`.itb`) for temporary RAM boot and recovery/development
- Package archive produced by the same build
- `OPENWRT-FEEDS.txt` listing verified package-feed commit revisions
- Pinned AW1000 phone-feed source archive
- Package manifest when generated
- Phone-port and recovery guides
- The exact AW1000 build configuration
- `BUILDINFO.txt` and `SHA256SUMS`
- `verify-aw1000-release-manifest.sh` for on-router checksum enforcement
- `inspect-aw1000-install-target.sh` for read-only board, mount, MTD and tool inspection

The factory `.ubi` is the only persistent AW1000 firmware image published by QuantumGrid.
The bundled installer verifies its exact filename and SHA-256 digest against `SHA256SUMS`
before permitting either preflight completion or a flash write. The manifest is an integrity
check, not a cryptographic signature or proof of publisher identity.

After creating `SHA256SUMS`, the firmware release workflow creates a GitHub artifact
attestation for every file in `dist/` using Sigstore-backed SLSA provenance. This binds each
asset's SHA-256 digest to the repository, source commit, workflow identity and build run.
The checksum manifest remains useful for transfer-corruption checks, but it is not the
publisher-authentication mechanism.

Install GitHub CLI and verify the downloaded factory image before transferring it to the router:

```bash
sha256sum -c SHA256SUMS
gh attestation verify QuantumGrid-OS-<version>-AW1000-squashfs-factory.ubi \
  --repo NetCore-Technologies/QuantumGrid-OS \
  --signer-workflow NetCore-Technologies/QuantumGrid-OS/.github/workflows/firmware-release.yml
```

Use the exact asset filename from the release. Verification checks the attested digest,
the QuantumGrid repository and the named firmware workflow. Do not flash an image when
either the checksum or attestation verification fails. The on-router installer still
checks SHA-256 only; it does not verify Sigstore attestations itself.
The initramfs `.itb` is a RAM-boot artifact and does not install persistent firmware.
The AW1000 profile does not produce or publish a `sysupgrade.bin` image; the release workflow
must never require, fabricate, rename or advertise one.

The workflow fails if the factory UBI image is missing, empty, duplicated or has an invalid
UBI header. It also fails if the expected AW1000 initramfs image is missing or empty.
A release must never be published with placeholder, empty or copied images.

## Build and verification

1. Run the normal CI gates.
2. Check the AW1000 image profile and phone package dependencies.
3. Create a `qg-v*` tag only from the source commit intended for release.
4. Let the firmware release workflow build the exact tagged source.
5. Verify `SHA256SUMS`, review `BUILDINFO.txt` and read the build logs.
6. Test on recoverable AW1000 hardware using the documented UBI installation route before recommending installation.

Manual workflow dispatch creates CI artifacts for inspection and does not publish a release.

## Safety and compatibility

Do not pass the factory UBI image to a generic LuCI sysupgrade handler or assume that a vendor
web installer accepts it. Follow the AW1000-specific recovery guide and confirm the exact
installation path before any persistent flash write.

The FXS phone service ships disabled by default and needs a compatible kernel, VoLTE service
and user-supplied Skyworks patch. Never claim emergency-call certification without dedicated
testing. The stable upstream image does not include NSS. The opt-in NSS profile selects the
AW1000 NSS device-tree include, EDMA/PPE switch path, NSS 12.5 firmware for both cores, NSS core
and ECM modules, and ath11k/mac80211 NSS Wi-Fi hooks. Presence of these components or a loaded
`qca-nss-dp`/`qca-nss-drv` module does not establish that NSS firmware booted or that flows are
being offloaded. Keep the generic OpenWrt packet-steering/software/hardware flow-offload options
disabled on NSS builds. DSA bridge-VLAN filtering is incompatible with NSS Wi-Fi offload. Do not
claim working NSS acceleration until packet-path counters, throughput/latency benchmarks and
recovery have been validated on physical AW1000 hardware.
