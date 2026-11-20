# Arcadyan AW1000 firmware installation and recovery

This project targets the Arcadyan AW1000 hardware profile
(`qualcommax/ipq807x/arcadyan_aw1000`). Its persistent firmware artifact is the
`*-squashfs-factory.ubi` image.

**There is no QuantumGrid AW1000 `sysupgrade.bin` image.** Do not feed the factory UBI
image to the generic LuCI sysupgrade handler. Do not assume the stock vendor web UI accepts it.

## Image types

| File | Purpose |
|---|---|
| `*-squashfs-factory.ubi` | Persistent AW1000 firmware image; use only with a verified AW1000-specific flash route |
| `*-initramfs-uImage.itb` | Temporary RAM-boot image for supported U-Boot/UART recovery and testing; not a persistent install |

Always use the image built for `arcadyan_aw1000`. An image for a different IPQ807x device is
not interchangeable merely because it has the same SoC family.

## Before attempting any installation

1. Confirm the board identity is the Arcadyan AW1000 and record the running firmware/kernel.
2. Keep a recoverable copy of the stock firmware and configuration where available.
3. Record the bootloader environment and the complete flash/MTD partition map over UART.
4. Download the exact AW1000 release assets and verify the factory image against the release
   manifest with `sha256sum -c SHA256SUMS`.
5. Have a working serial console and a tested recovery path before changing persistent flash.

## Temporary recovery boot

The AW1000 initramfs `.itb` is intended for a supported temporary RAM-boot path. Use the
device's documented U-Boot/UART/TFTP workflow for the exact bootloader environment. Confirm that
the resulting userspace reports the expected AW1000 board identity before doing anything else.

A successful initramfs boot does not install QuantumGrid to persistent storage. It is a
diagnostic/recovery environment only.

## Persistent UBI installation — standard AW1000 layout only

The release includes `install-aw1000-ubi.sh`. It is deliberately limited to the original
standard AW1000 MTD layout documented by the OpenWrt AW1000 device instructions. It does not
repartition flash, change MIBIB, write bootloader data or attempt to support expanded layouts.

1. Connect the UART console and boot the matching AW1000 initramfs temporarily using the
   device's U-Boot/TFTP procedure above. Do not run the installer from an installed NoobWRT or
   OpenWrt root filesystem.
2. Copy the factory UBI image, `install-aw1000-ubi.sh`, `verify-aw1000-release-manifest.sh` and `SHA256SUMS` into the same directory on the RAM-booted router (for example `/tmp`). You may also verify the release on your Linux host with `sha256sum -c SHA256SUMS` before transfer.
4. Run the read-only preflight first:

   ```sh
   sh /tmp/install-aw1000-ubi.sh /tmp/QuantumGrid-OS-<version>-AW1000-squashfs-factory.ubi --manifest /tmp/SHA256SUMS
   ```

5. Proceed only when the script confirms the correct board, a RAM initramfs root, and the
   expected `mtd18`/`mtd20` standard 100 MiB rootfs partitions. Expanded or unknown layouts
   are refused.
6. To write, run the same command with `--write` (and keep `--manifest /tmp/SHA256SUMS`). At the UART console, type exactly
   `ERASE rootfs` when prompted. The script invokes `ubiformat` only for `/dev/mtd18`;
   `rootfs_1` (`/dev/mtd20`) and bootloader/calibration partitions are not written.

The default invocation is read-only. Both dry-run and write modes require a matching SHA-256 entry in the release manifest, checked by the bundled verifier. The write path also requires root, a valid UBI# image header,
the exact standard partition sizes/erase geometry, the initramfs root check and interactive
confirmation. A failed check stops before `ubiformat`.

**Do not use this installer for an expanded/merged MTD layout, a different AW1000 partition
map, or any other device.** Those layouts need a separately built and independently validated
image and installation procedure. Do not substitute a guessed `mtd write`, `nand write`,
generic sysupgrade or vendor web-upload flow. A wrong target or erase operation can permanently
brick the router.

The initial installation route follows the documented AW1000 initramfs plus UBI procedure. It has
not been hardware-validated by QuantumGrid maintainers on every MTD variant. Keep UART connected
and retain a known-good recovery image throughout.

## UART reference

See [UART-GUIDE.md](UART-GUIDE.md) for the serial-console wiring and terminal settings. Keep
the console connected during recovery and capture the complete boot log for diagnosis.

## After recovery

Before reconnecting the router to a production network, change default credentials, verify
the firewall and wireless settings, confirm modem and phone service state, and retain a known-good
recovery image. The RJ11/FXS service remains disabled by default; emergency calling is not
certified by this project.
