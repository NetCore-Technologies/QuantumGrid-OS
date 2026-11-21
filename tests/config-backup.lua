package.path = "files/usr/lib/lua/?.lua;" .. package.path
local backup = require "luci.quantumgrid.config_backup"

assert(backup.validate_confirmation("1") == true, "confirmed backup should be accepted")
assert(backup.validate_confirmation("0") == nil, "unconfirmed backup must be rejected")
assert(backup.validate_confirmation(nil) == nil, "missing confirmation must be rejected")

assert(backup.validate_temp_path("/tmp/quantumgrid-config-backup.Abc123") == "/tmp/quantumgrid-config-backup.Abc123")
assert(backup.validate_temp_path("/tmp/lua_abc123") == nil, "only reserved QuantumGrid mktemp names are allowed")
assert(backup.validate_temp_path("/tmp/quantumgrid-config-backup.") == nil, "empty mktemp suffix must be rejected")
assert(backup.validate_temp_path("/etc/config/backup.tar.gz") == nil, "backup path must stay under /tmp")
assert(backup.validate_temp_path("/tmp/../../etc/shadow") == nil, "path traversal must be rejected")
assert(backup.validate_temp_path("/tmp/a;touch /tmp/pwned") == nil, "shell punctuation must be rejected")
assert(backup.validate_temp_path(nil) == nil, "missing path must be rejected")

assert(backup.validate_archive_size(1) == 1)
assert(backup.validate_archive_size(64 * 1024 * 1024) == 64 * 1024 * 1024)
assert(backup.validate_archive_size(0) == nil, "empty archive must be rejected")
assert(backup.validate_archive_size(64 * 1024 * 1024 + 1) == nil, "oversized archive must be rejected")
assert(backup.validate_archive_size("100") == nil, "string size must be rejected")

assert(backup.validate_restore_confirmation("1", "1") == true)
assert(backup.validate_restore_confirmation("0", "1") == nil)
assert(backup.validate_restore_confirmation("1", "0") == nil)
assert(backup.validate_restore_confirmation(nil, nil) == nil)

local valid_listing = table.concat({
  "drwxr-xr-x root/root 0 2026-11-22 00:00 ./etc/",
  "drwxr-xr-x root/root 0 2026-11-22 00:00 ./etc/config/",
  "-rw------- root/root 128 2026-11-22 00:00 ./etc/config/network",
  "-rw------- root/root 32 2026-11-22 00:00 ./etc/quantumgrid/device-id",
  "-rw------- root/root 256 2026-11-22 00:00 ./etc/quantumgrid/device-profile.json",
  "-rw-r--r-- root/root 128 2026-11-22 00:00 ./etc/openwrt_release",
  "-rw------- root/root 64 2026-11-22 00:00 ./root/.profile",
}, "\n")
local listing, listing_error = backup.validate_archive_listing(valid_listing)
assert(listing ~= nil, listing_error or "valid native backup listing should pass")
assert(listing.count == 7 and listing.device_id_path == "./etc/quantumgrid/device-id")
assert(listing.profile_path == "./etc/quantumgrid/device-profile.json")
assert(listing.release_path == "./etc/openwrt_release")

local oversized_listing = table.concat({
  "-rw------- root/root 200000000 2026-11-22 00:00 etc/config/large",
  "-rw------- root/root 32 2026-11-22 00:00 etc/quantumgrid/device-id",
}, "\n")
assert(backup.validate_archive_listing(oversized_listing) == nil,
  "expanded archive size must be bounded before restore")
assert(backup.validate_archive_listing(
  "-rw------- root/root 128 unknown-date etc/config/network\n-rw------- root/root 32 2026-11-22 00:00 etc/quantumgrid/device-id"
) == nil, "unrecognised tar listing formats must fail closed")

local rejected_listings = {
  table.concat({
    "-rw------- root/root 128 2026-11-22 00:00 etc/config/network",
    "lrwxrwxrwx root/root 0 2026-11-22 00:00 etc/config/evil -> /etc/shadow",
    "-rw------- root/root 32 2026-11-22 00:00 etc/quantumgrid/device-id",
  }, "\n"),
  table.concat({
    "-rw------- root/root 128 2026-11-22 00:00 ../etc/config/network",
    "-rw------- root/root 32 2026-11-22 00:00 etc/quantumgrid/device-id",
  }, "\n"),
  table.concat({
    "-rw------- root/root 128 2026-11-22 00:00 /etc/config/network",
    "-rw------- root/root 32 2026-11-22 00:00 etc/quantumgrid/device-id",
  }, "\n"),
  table.concat({
    "-rw------- root/root 128 2026-11-22 00:00 var/spool/cron/root",
    "-rw------- root/root 32 2026-11-22 00:00 etc/quantumgrid/device-id",
  }, "\n"),
  table.concat({
    "-rw------- root/root 128 2026-11-22 00:00 etc/config/network",
  }, "\n"),
  table.concat({
    "-rw------- root/root 128 2026-11-22 00:00 etc/config/network",
    "-rw------- root/root 32 2026-11-22 00:00 etc/quantumgrid/device-id",
    "-rw------- root/root 32 2026-11-22 00:00 etc/quantumgrid/device-id",
  }, "\n"),
  table.concat({
    "-rw------- root/root 128 2026-11-22 00:00 etc/config/network",
    "hrw-r--r-- root/root 32 2026-11-22 00:00 etc/quantumgrid/device-id link to etc/config/network",
  }, "\n"),
  table.concat({
    "-rw------- root/root 128 2026-11-22 00:00 evil etc/config/network",
    "-rw------- root/root 32 2026-11-22 00:00 etc/quantumgrid/device-id",
  }, "\n"),
  table.concat({
    "-rw------- root/root 128 2026-11-22 00:00 prefix/with space etc/config/network",
    "-rw------- root/root 32 2026-11-22 00:00 etc/quantumgrid/device-id",
  }, "\n"),
  table.concat({
    "-rw-rwSr-- root/root 128 2026-11-22 00:00 etc/config/network",
    "-rw------- root/root 32 2026-11-22 00:00 etc/quantumgrid/device-id",
  }, "\n"),
  table.concat({
    "-rwq------ root/root 128 2026-11-22 00:00 etc/config/network",
    "-rw------- root/root 32 2026-11-22 00:00 etc/quantumgrid/device-id",
  }, "\n"),
}
for _, invalid_listing in ipairs(rejected_listings) do
  assert(backup.validate_archive_listing(invalid_listing) == nil,
    "unsafe or incomplete restore archive listing must fail closed")
end
assert(backup.validate_archive_listing("") == nil)
assert(backup.validate_archive_listing(string.rep("x", 4 * 1024 * 1024 + 1)) == nil)

assert(backup.validate_platform_compatibility("qualcommax/ipq807x", "qualcommax/ipq807x", "aarch64_cortex-a53", "aarch64_cortex-a53") == true)
assert(backup.validate_platform_compatibility("qualcommax/ipq807x", "mediatek/filogic", "aarch64_cortex-a53", "aarch64_cortex-a53") == nil)
assert(backup.validate_platform_compatibility("qualcommax/ipq807x", "qualcommax/ipq807x", "aarch64_cortex-a53", "aarch64_cortex-a72") == nil)
assert(backup.validate_platform_compatibility(nil, "qualcommax/ipq807x", "aarch64_cortex-a53", "aarch64_cortex-a53") == nil)

assert(backup.validate_restore_temp_path("/tmp/quantumgrid-config-restore.a1B2") == "/tmp/quantumgrid-config-restore.a1B2")
assert(backup.validate_restore_temp_path("/tmp/other-restore.a1B2") == nil)
assert(backup.validate_rollback_temp_path("/tmp/quantumgrid-config-rollback.a1B2") == "/tmp/quantumgrid-config-rollback.a1B2")
assert(backup.validate_rollback_temp_path("/etc/quantumgrid-config-rollback.a1B2") == nil)

local set_id_listing = table.concat({
  "-rwsr-xr-x root/root 128 2026-11-22 00:00 etc/config/network",
  "-rw------- root/root 32 2026-11-22 00:00 etc/quantumgrid/device-id",
  "-rw------- root/root 256 2026-11-22 00:00 etc/quantumgrid/device-profile.json",
  "-rw-r--r-- root/root 128 2026-11-22 00:00 etc/openwrt_release",
}, "\n")
assert(backup.validate_archive_listing(set_id_listing) == nil,
  "setuid/setgid files must never be imported through configuration restore")

local regular_mode_hardlink = table.concat({
  "-rw-r--r-- root/root 128 2026-11-22 00:00 etc/config/network link to etc/config/other",
  "-rw------- root/root 32 2026-11-22 00:00 etc/quantumgrid/device-id",
  "-rw------- root/root 256 2026-11-22 00:00 etc/quantumgrid/device-profile.json",
  "-rw-r--r-- root/root 128 2026-11-22 00:00 etc/openwrt_release",
}, "\n")
assert(backup.validate_archive_listing(regular_mode_hardlink) == nil,
  "BusyBox tar's regular-permission hardlink representation must be rejected")

local device_id = "0123456789abcdef0123456789abcdef"
assert(backup.validate_device_identity(device_id .. "\n", device_id) == true)
assert(backup.validate_device_identity(device_id, "fedcba9876543210fedcba9876543210") == nil)
assert(backup.validate_device_identity("not-a-device-id", device_id) == nil)
assert(backup.validate_device_identity(nil, device_id) == nil)

print("config-backup: backup, archive type/path, same-device and restore confirmation checks passed")
