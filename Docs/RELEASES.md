# Release process

QuantumGrid publishes router firmware releases, not desktop installers.

## Version tags

Use tags matching `qg-v<semver>`, for example:

- `qg-v0.1.0-alpha.1` for an early preview
- `qg-v0.1.0` for a first stable release

The release workflow pins OpenWrt to `v25.12.6` by default and the AW1000 FXS source to
`v0.9.0`. Both resolved commit hashes are written into `BUILDINFO.txt`.

## Assets

Every completed build must include:

- AW1000 squashfs sysupgrade image
- AW1000 squashfs factory UBI image
- AW1000 initramfs image
- Package archive produced by the same build
- Pinned AW1000 phone-feed source archive
- Package manifest when generated
- Phone-port and recovery guides
- The exact AW1000 build configuration
- `BUILDINFO.txt` and `SHA256SUMS`

The workflow fails if one of the three required AW1000 images is missing. A release must
never be published with placeholder, empty or copied images.

## Build and verification

1. Run the normal CI gates.
2. Check the AW1000 image profile and phone package dependencies.
3. Create a `qg-v*` tag only from the source commit intended for release.
4. Let the firmware release workflow build the exact tagged source.
5. Verify `SHA256SUMS`, review `BUILDINFO.txt` and read the build logs.
6. Test on recoverable AW1000 hardware before recommending upgrades.

Manual workflow dispatch creates CI artifacts for inspection and does not publish a release.

## Safety and compatibility

The FXS phone service ships disabled by default and needs a compatible kernel, VoLTE service
and user-supplied Skyworks patch. Never claim emergency-call certification without dedicated
testing. The base OpenWrt build does not claim NSS acceleration.
