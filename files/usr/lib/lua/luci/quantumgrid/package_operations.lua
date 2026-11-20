module("luci.quantumgrid.package_operations", package.seeall)

local PROTECTED_PACKAGES = {
	["base-files"] = true,
	["busybox"] = true,
	["kernel"] = true,
	["libc"] = true,
	["libgcc"] = true,
	["libpthread"] = true,
	["libstdcpp"] = true,
	["procd"] = true,
	["netifd"] = true,
	["firewall4"] = true,
	["fw4"] = true,
	["dnsmasq"] = true,
	["dropbear"] = true,
	["uhttpd"] = true,
	["rpcd"] = true,
	["luci-base"] = true,
	["luci-compat"] = true,
	["luci-lua-runtime"] = true,
	["luci-app-package-manager"] = true,
	["apk"] = true,
	["opkg"] = true,
	["uci"] = true,
	["ubus"] = true,
	["ubox"] = true,
	["libubox"] = true,
	["libubus"] = true,
	["libuci"] = true,
	["libnl-tiny"] = true,
	["rpcd-mod-ucode"] = true,
	["rpcd-mod-iwinfo"] = true,
	["kmod-aw1000-fxs"] = true,
	["luci-app-fxs"] = true,
	["libubus-lua"] = true,
	["libjson-c"] = true,
	["libblobmsg-json"] = true,
	["luci-mod-admin-full"] = true
}

local PROTECTED_PREFIXES = {
	"kmod%-",
	"wpad",
	"qca%-nss",
	"ath11k",
	"kernel%-",
	"dnsmasq",
	"luci%-mod%-"
}

local function valid_package_name(value)
	return type(value) == "string"
		and #value >= 1 and #value <= 128
		and value:match("^[%w][%w%+_.%-]*$") ~= nil
end

local function protected_from_removal(value)
	if PROTECTED_PACKAGES[value] then return true end
	for _, prefix in ipairs(PROTECTED_PREFIXES) do
		if value:match("^" .. prefix) then return true end
	end
	return false
end

local function valid_temp_path(path)
	return type(path) == "string" and path:match("^/tmp/[A-Za-z0-9_.%-]+$") ~= nil
end

-- Reserve the pathname atomically before a shell command can write to it.
-- O_CREAT|O_EXCL prevents following an attacker-precreated symlink in /tmp.
function create_secure_log_file(temp_name, nixio_module)
	if type(temp_name) ~= "function" or type(nixio_module) ~= "table"
		or type(nixio_module.open_flags) ~= "function"
		or type(nixio_module.open) ~= "function" then
		return nil, "Secure temporary-file support is unavailable."
	end

	local flags_ok, flags = pcall(nixio_module.open_flags, "creat", "excl", "wronly")
	if not flags_ok or flags == nil then
		return nil, "Exclusive temporary-file creation is unavailable."
	end

	for _ = 1, 8 do
		local name_ok, path = pcall(temp_name)
		if name_ok and valid_temp_path(path) then
			local open_ok, file = pcall(nixio_module.open, path, flags, 384)
			if open_ok and file then
				if type(file.close) ~= "function" then
					os.remove(path)
					return nil, "The temporary log file could not be closed safely."
				end
				local close_ok, close_result = pcall(file.close, file)
				if close_ok and close_result ~= false then
					return path
				end
				os.remove(path)
				return nil, "The temporary log file could not be closed safely."
			end
		end
	end

	return nil, "A private package-operation log file could not be reserved."
end

function validate(operation, package_name, confirmed)
	if operation ~= "update" and operation ~= "install" and operation ~= "remove" then
		return nil, "Choose update, install or remove."
	end
	if confirmed ~= "1" then
		return nil, "Explicit confirmation is required for package operations."
	end
	if operation == "update" then
		return { operation = operation, package = "" }
	end
	if not valid_package_name(package_name) then
		return nil, "Package names may contain only letters, numbers, plus, underscore, dot and hyphen."
	end
	if operation == "remove" and protected_from_removal(package_name) then
		return nil, "Removal is blocked for core router, wireless, NSS and kernel-module packages. Use an offline firmware build for driver changes."
	end
	return { operation = operation, package = package_name }
end

return _M
