package.path = "files/usr/lib/lua/?.lua;" .. package.path
local packages = require "luci.quantumgrid.packages"

local installed = {
	packages = {
		{ name = "luci-app-sqm", version = "1.0", manager = "apk" },
		{ name = "kmod-ath11k", version = "6.12.0", manager = "apk" }
	}
}

local apk_source = {
	{
		name = "luci-app-sqm",
		version = "25.100.1-r1",
		description = "Smart Queue Management interface",
		license = "Apache-2.0",
		architecture = "aarch64_cortex-a53",
		["file-size"] = 49152,
		["installed-size"] = 98304
	},
	{
		name = "luci-app-pbr",
		version = "1.2.3-r1",
		description = "Policy based routing",
		license = "GPL-2.0"
	},
	{
		name = "kmod-ath11k",
		version = "6.12.0-r1",
		description = "Qualcomm wireless driver"
	},
	{
		name = "wireguard-tools",
		version = "1.0.2025-r1",
		description = "WireGuard user-space tools"
	},
	{
		name = "unbound-daemon",
		version = "1.23.0-r2",
		description = "Validating recursive DNS resolver"
	}
}

local all = packages.parse_available("apk", apk_source, installed, 20, 0, "")
assert(all.available == true)
assert(all.manager == "apk")
assert(all.count == 5 and #all.packages == 5)
assert(all.packages[1].name == "kmod-ath11k")
assert(all.packages[1].category == "Kernel modules")
assert(all.packages[1].installed == true)
assert(all.packages[2].name == "luci-app-pbr")
assert(all.packages[2].category == "LuCI applications")
assert(all.packages[3].name == "luci-app-sqm")
assert(all.packages[3].installed == true)
assert(all.packages[3].license == "Apache-2.0")
assert(all.packages[3].size == 49152)
assert(all.packages[3].installed_size == 98304)
assert(all.packages[4].category == "DNS and DHCP")
assert(all.packages[5].category == "VPN and tunnels")

local search = packages.parse_available("apk", apk_source, installed, 20, 0, "LuCI   routing")
assert(search.count == 1 and #search.packages == 1)
assert(search.packages[1].name == "luci-app-pbr")

local page_one = packages.parse_available("apk", apk_source, installed, 2, 0, "")
local page_two = packages.parse_available("apk", apk_source, installed, 2, 2, "")
assert(page_one.count == 5 and page_one.truncated == true)
assert(page_two.count == 5 and page_two.truncated == true)
assert(page_one.packages[1].name == "kmod-ath11k")
assert(page_one.packages[2].name == "luci-app-pbr")
assert(page_two.packages[1].name == "luci-app-sqm")
assert(page_two.packages[2].name == "unbound-daemon")

local opkg_source = table.concat({
	"luci-app-pbr - 1.2.3-1 - Policy based routing interface",
	"luci-app-sqm - 1.0.0-1 - Smart queue management interface",
	"wireguard-tools - 1.0.2025-1 - WireGuard user-space tools",
	"malformed line",
	"luci-app-pbr - 1.2.3-1 - Duplicate feed entry"
}, "\n")
local legacy = packages.parse_available("opkg", opkg_source, { packages = {
	{ name = "luci-app-sqm", version = "1.0.0-1", manager = "opkg" }
} }, 10, 0, "")
assert(legacy.available == true and legacy.manager == "opkg")
assert(legacy.count == 3 and #legacy.packages == 3)
assert(legacy.packages[1].name == "luci-app-pbr")
assert(legacy.packages[1].description == "Policy based routing interface")
assert(legacy.packages[2].installed == true)

local no_source = packages.parse_available("apk", "not-json", installed, 20, 0, "")
assert(no_source.available == false and no_source.count == 0)
local unknown = packages.parse_available("unknown", {}, installed, 20, 0, "")
assert(unknown.available == false)
local bounded = packages.parse_available("apk", apk_source, installed, 1000, 100000, "")
assert(bounded.limit == 100 and bounded.offset == 5000 and #bounded.packages == 0)
local invalid_names = packages.parse_available("apk", {
	{ name = "../escape", version = "1", description = "invalid package name" },
	{ name = "-option", version = "1" },
	{ name = "valid-package", version = "1" }
}, installed, 20, 0, "")
assert(invalid_names.count == 1 and invalid_names.packages[1].name == "valid-package")

print("packages-catalog: APK/OPKG catalog parsing, filtering, paging and installed-state tests passed")
