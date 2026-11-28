# Arcadyan AW1000 firmware installation and recovery

This project targets the Arcadyan AW1000 hardware profile
(`qualcommax/ipq807x/arcadyan_aw1000`). Releases contain a factory UBI image for first
installation/recovery, a standard OpenWrt sysupgrade archive for in-service updates, and an
initramfs image for temporary RAM boot.

**These images have different purposes.** Never pass the factory UBI image to the generic
sysupgrade handler. The sysupgrade archive is not a stock/vendor-firmware installer.

## Image types

| File | Purpose |
|---|---|
| `*-squashfs-factory.ubi` | First installation/recovery through the guarded AW1000-specific UBI route |
| `*-squashfs-sysupgrade.bin` | In-service update from an already-running compatible OpenWrt/QuantumGrid AW1000 installation |
| `*-initramfs-uImage.itb` | Temporary RAM-boot image for supported U-Boot/UART recovery and testing; not a persistent install |

Always use the image built for `arcadyan_aw1000`. An image for a different IPQ807x device is
not interchangeable merely because it has the same SoC family.

## Before attempting any installation or upgrade

1. Confirm the board identity is the Arcadyan AW1000 and record the running firmware/kernel.
2. Keep a recoverable copy of the stock firmware and configuration where available.
3. Record the bootloader environment and the complete flash/MTD partition map over UART.
4. Download the exact AW1000 release assets and verify `SHA256SUMS` and the GitHub/Sigstore
   attestation for the exact firmware image you intend to use.
5. Have a working serial console and a tested recovery path before changing persistent flash.

## In-service update — compatible OpenWrt/QuantumGrid only

The release `*-squashfs-sysupgrade.bin` is the target-specific OpenWrt sysupgrade tar for
`arcadyan_aw1000`. It is intended only for a router already running a compatible OpenWrt-based
AW1000 firmware with the normal OpenWrt sysupgrade handler. It is not for the stock vendor
firmware and is not the first-install path.

1. Back up the current configuration and keep a working UART/recovery route. Download the
   sysupgrade image, `SHA256SUMS` and `verify-aw1000-release-attestation.sh`.
2. On a trusted Linux host, verify the full release checksums and publisher/build attestation:

   ```sh
   sha256sum -c SHA256SUMS
   sh verify-aw1000-release-attestation.sh QuantumGrid-OS-<version>-AW1000-squashfs-sysupgrade.bin SHA256SUMS
   ```

3. Copy the sysupgrade image, `SHA256SUMS` and `verify-aw1000-release-manifest.sh` to the
   router (for example, under `/tmp`). Check the exact image digest on the router:

   ```sh
   sh /tmp/verify-aw1000-release-manifest.sh /tmp/QuantumGrid-OS-<version>-AW1000-squashfs-sysupgrade.bin /tmp/SHA256SUMS
   ```

4. Run OpenWrt's test-only validation before any write:

   ```sh
   sysupgrade -T /tmp/QuantumGrid-OS-<version>-AW1000-squashfs-sysupgrade.bin
   ```

5. Only after a successful test, perform the update while maintaining stable power and a wired
   management connection:

   ```sh
   sysupgrade /tmp/QuantumGrid-OS-<version>-AW1000-squashfs-sysupgrade.bin
   ```

The default command uses OpenWrt's normal configuration-preservation mechanism. Use
`sysupgrade -n` only when deliberately discarding the saved configuration. Do not run
sysupgrade from stock/vendor firmware, from a different board, or with an image whose
`sysupgrade -T` check fails. Test mode is not proof of flash hardware health; retain UART
recovery. The sysupgrade image uses the upstream AW1000 device's OpenWrt image definition,
but QuantumGrid maintainers still require physical-device testing before treating this route
as hardware-validated.

## Read-only inspection on the currently installed router

Before a first installation, inspect the router while it is still running its current firmware.
Download `inspect-aw1000-install-target.sh` from the matching QuantumGrid release (or copy
it from `scripts/` in the repository) to the router, for example with `scp` to `/tmp`, then run:

```sh
sh /tmp/inspect-aw1000-install-target.sh
```

The script only reads the board identity, root mount and `/proc/mtd` partition geometry. It
does not write flash, change UCI settings, restart services or change bootloader variables.
It reports whether the exact standard `mtd18` / `mtd20` geometry is present and whether the
current root looks like the required temporary initramfs environment. Running it from an
installed NoobWRT/OpenWrt system is expected to report **INSPECTION ONLY**; that does not mean
the MTD layout is incompatible. Save its output and compare the complete partition map before
proceeding.

A geometry mismatch, duplicate/missing partition, unknown board identity or unexpected layout
is a hard stop for the existing installer. Do not edit the installer or substitute another
flash command to bypass that result. After a supported initramfs is booted, run the inspector
again, then run the official UBI install script without `--write` to validate the image,
manifest and all device checks.

## Temporary recovery boot

The AW1000 initramfs `.itb` is intended for a supported temporary RAM-boot path. Use the
device's documented U-Boot/UART/TFTP workflow for the exact bootloader environment. Confirm that
the resulting userspace reports the expected AW1000 board identity before doing anything else.

A successful initramfs boot does not install QuantumGrid to persistent storage. It is a
diagnostic/recovery environment only.

## First installation — factory UBI, standard AW1000 layout only

The release includes `install-aw1000-ubi.sh`. It is deliberately limited to the original
standard AW1000 MTD layout documented by the OpenWrt AW1000 device instructions. It does not
repartition flash, change MIBIB, write bootloader data or attempt to support expanded layouts.

1. Connect the UART console and boot the matching AW1000 initramfs temporarily using the
   device's U-Boot/TFTP procedure above. Do not run the installer from an installed NoobWRT or
   OpenWrt root filesystem.
2. On the trusted Linux host, verify all release checksums and the factory image's GitHub attestation:

   ```sh
   sha256sum -c SHA256SUMS
   sh verify-aw1000-release-attestation.sh QuantumGrid-OS-<version>-AW1000-squashfs-factory.ubi SHA256SUMS
   ```

   Copy the read-only `inspect-aw1000-install-target.sh` helper as well if the target layout has not yet been recorded. Copy only the factory UBI image, `install-aw1000-ubi.sh`, `verify-aw1000-release-manifest.sh`
   and `SHA256SUMS` into the same directory on the RAM-booted router (for example `/tmp`). The host-side attestation tool runs on the trusted Linux workstation, not on the router.
3. Run the read-only preflight first:

   ```sh
   sh /tmp/install-aw1000-ubi.sh /tmp/QuantumGrid-OS-<version>-AW1000-squashfs-factory.ubi --manifest /tmp/SHA256SUMS
   ```

4. Proceed only when the script confirms the correct board, a RAM initramfs root, and the
   expected `mtd18`/`mtd20` standard 100 MiB rootfs partitions. Expanded or unknown layouts
   are refused.
5. To write, run the same command with `--write` (and keep `--manifest /tmp/SHA256SUMS`).
   At the UART console, type exactly `ERASE rootfs` when prompted. The script invokes
   `ubiformat` only for `/dev/mtd18`;
   `rootfs_1` (`/dev/mtd20`) and bootloader/calibration partitions are not written.

The default invocation is read-only. Both dry-run and write modes require a matching SHA-256
entry in the release manifest, checked by the bundled verifier. The write path also requires root,
a valid UBI# image header, the exact standard partition sizes/erase geometry, the initramfs root
check and interactive confirmation. A failed check stops before `ubiformat`.

**Do not use this installer for an expanded/merged MTD layout, a different AW1000 partition
map, or any other device.** Those layouts need a separately built and independently validated
image and installation procedure. Do not substitute a guessed `mtd write`, `nand write`,
generic sysupgrade or vendor web-upload flow. A wrong target or erase operation can permanently
brick the router.

The factory UBI first-install route follows the documented AW1000 initramfs plus UBI procedure.
It has not been hardware-validated by QuantumGrid maintainers on every MTD variant. Keep UART
connected and retain a known-good recovery image throughout.

## UART reference

See [UART-GUIDE.md](UART-GUIDE.md) for the serial-console wiring and terminal settings. Keep the
console connected during recovery and capture the complete boot log for diagnosis.

## After recovery

Before reconnecting the router to a production network, change default credentials, verify the
firewall and wireless settings, confirm modem and phone service state, and retain a known-good
recovery image. The RJ11/FXS service remains disabled by default; emergency calling is not
certified by this project.
