# Release process

QuantumGrid publishes router firmware releases, not desktop installers.

## Version tags

Use tags matching `qg-v<semver>`, for example:

- `qg-v0.1.0-alpha.1` for an early preview
- `qg-v0.1.0` for a first stable release

The release workflow pins OpenWrt to `v25.12.6` by default and the AW1000 FXS source to
`v0.9.0`. Both resolved commit hashes are written into `BUILDINFO.txt`.

## AW1000 image formats

Every completed build must include:

- Exactly one non-empty Arcadyan AW1000 squashfs factory UBI image (`.ubi`), validated for the UBI erase-counter header
- One AW1000 initramfs image (`.itb`) for temporary RAM boot and recovery/development
- Package archive produced by the same build
- Pinned AW1000 phone-feed source archive
- Package manifest when generated
- Phone-port and recovery guides
- The exact AW1000 build configuration
- `BUILDINFO.txt` and `SHA256SUMS`
- `verify-aw1000-release-manifest.sh` for on-router checksum enforcement

The factory `.ubi` is the only persistent AW1000 firmware image published by QuantumGrid.
The bundled installer verifies its exact filename and SHA-256 digest against `SHA256SUMS`
before permitting either preflight completion or a flash write. The manifest is an integrity
check, not a cryptographic signature or proof of publisher identity.
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
testing. The base OpenWrt build does not claim NSS acceleration.
