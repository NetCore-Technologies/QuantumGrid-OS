package.path = "files/usr/lib/lua/?.lua;" .. package.path
local package_operations = require "luci.quantumgrid.package_operations"

local temp_candidates = { "/tmp/qg-package-log-collision", "/tmp/qg-package-log-reserved" }
local temp_index = 0
local open_attempts = {}
local secure_nixio = {
	open_flags = function(create_flag, exclusive_flag, write_flag)
		assert(create_flag == "creat" and exclusive_flag == "excl" and write_flag == "wronly")
		return "exclusive-create-flags"
	end,
	open = function(path, flags, mode)
		table.insert(open_attempts, { path = path, flags = flags, mode = mode })
		if #open_attempts == 1 then return nil, "path already exists" end
		return { close = function() return true end }
	end
}
local secure_log_path, secure_log_error = package_operations.create_secure_log_file(function()
	temp_index = temp_index + 1
	return temp_candidates[temp_index]
end, secure_nixio)
assert(secure_log_path == "/tmp/qg-package-log-reserved", secure_log_error)
assert(#open_attempts == 2, "an exclusive-create collision must retry with another temporary name")
assert(open_attempts[2].flags == "exclusive-create-flags")
assert(open_attempts[2].mode == 384, "package logs must be created with mode 0600")

local open_called = false
local invalid_path, invalid_path_error = package_operations.create_secure_log_file(function()
	return "/var/run/not-a-package-log"
end, {
	open_flags = secure_nixio.open_flags,
	open = function()
		open_called = true
		return { close = function() return true end }
	end
})
assert(invalid_path == nil and type(invalid_path_error) == "string")
assert(not open_called, "temporary log paths outside /tmp must be rejected before opening")

local update = package_operations.validate("update", "", "1")
assert(update ~= nil and update.operation == "update" and update.package == "")

local install_app = package_operations.validate("install", "luci-app-sqm", "1")
assert(install_app ~= nil and install_app.operation == "install")
assert(install_app.package == "luci-app-sqm")

local install_driver = package_operations.validate("install", "kmod-ath11k", "1")
assert(install_driver ~= nil and install_driver.package == "kmod-ath11k",
	"offline image builds, not the in-app remover, are required for driver replacement")

local remove_app = package_operations.validate("remove", "luci-app-sqm", "1")
assert(remove_app ~= nil and remove_app.operation == "remove")

local function rejected(operation, name, confirmed, label)
	local result, err = package_operations.validate(operation, name, confirmed)
	assert(result == nil, label .. " should be rejected")
	assert(type(err) == "string" and #err > 0, label .. " should explain why")
end

rejected("install;touch /tmp/pwned", "luci-app-sqm", "1", "invalid operation")
rejected("install", "luci-app-sqm;touch", "1", "shell metacharacter")
rejected("install", "../luci-app-sqm", "1", "path-like package name")
rejected("install", "-f", "1", "command-line option as package")
rejected("install", string.rep("a", 129), "1", "oversized package name")
rejected("remove", "base-files", "1", "base filesystem removal")
rejected("remove", "busybox", "1", "BusyBox removal")
rejected("remove", "netifd", "1", "network manager removal")
rejected("remove", "firewall4", "1", "firewall removal")
rejected("remove", "luci-base", "1", "LuCI base removal")
rejected("remove", "luci-mod-network", "1", "network LuCI module removal")
rejected("remove", "kmod-ath11k", "1", "kernel module removal")
rejected("remove", "wpad-basic-mbedtls", "1", "wireless supplicant removal")
rejected("remove", "qca-nss-drv", "1", "NSS driver removal")
rejected("remove", "ath11k-firmware-ipq8074", "1", "Wi-Fi firmware removal")
rejected("remove", "kmod-aw1000-fxs", "1", "AW1000 FXS driver removal")
rejected("remove", "luci-app-sqm", "0", "missing removal confirmation")
rejected("update", "", "0", "missing feed update confirmation")
rejected("purge", "luci-app-sqm", "1", "unsupported operation")

print("package-operations: all validation tests passed")
