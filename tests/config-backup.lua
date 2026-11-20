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

print("config-backup: confirmation, temp path and archive size checks passed")
