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

## Persistent UBI installation

The factory `.ubi` file is the persistent AW1000 firmware artifact, but a correct UBI write
requires a confirmed device-specific target partition, erase geometry, image layout and
bootloader/recovery procedure.

**This repository does not currently document a fully hardware-validated, one-command persistent
flash procedure.** Until that procedure is documented and tested against a recoverable AW1000,
stop after verifying the image and do not guess a partition name or write command.

Do not substitute generic `sysupgrade`, `mtd write`, `nand write`, arbitrary USB imaging,
or an unverified vendor web-upload flow. A wrong target or erase operation can permanently
brick the router.

## UART reference

See [UART-GUIDE.md](UART-GUIDE.md) for the serial-console wiring and terminal settings. Keep
the console connected during recovery and capture the complete boot log for diagnosis.

## After recovery

Before reconnecting the router to a production network, change default credentials, verify
the firewall and wireless settings, confirm modem and phone service state, and retain a known-good
recovery image. The RJ11/FXS service remains disabled by default; emergency calling is not
certified by this project.
