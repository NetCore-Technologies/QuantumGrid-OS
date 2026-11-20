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
	["luci-app-fxs"] = true
}

local PROTECTED_PREFIXES = {
	"kmod%-",
	"wpad",
	"qca%-nss",
	"ath11k",
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
