package.path = "files/usr/lib/lua/?.lua;" .. package.path
local packages = require "luci.quantumgrid.packages"

local apk = packages.parse("apk", table.concat({
	"base-files-1657~7f6b4a3-r1",
	"luci-base-26.100.12345~abcdef-r1",
	"kmod-ath11k-6.12.71-r1",
	"base-files-1657~7f6b4a3-r1",
	"malformed package line",
}, "\n"))
assert(apk.available == true and apk.manager == "apk")
assert(apk.count == 3 and #apk.packages == 3, "APK package listing should be parsed and deduplicated")
assert(apk.packages[1].name == "base-files")
assert(apk.packages[1].version == "1657~7f6b4a3-r1")
assert(apk.packages[2].name == "kmod-ath11k")
assert(apk.packages[3].name == "luci-base")

local opkg = packages.parse("opkg", table.concat({
	"base-files - 1657-r1",
	"luci-base - git-25.123.45678",
	"base-files - 1657-r1"
}, "\n"))
assert(opkg.available == true and opkg.count == 2)
assert(opkg.packages[1].name == "base-files")
assert(opkg.packages[2].version == "git-25.123.45678")

local limited = packages.parse("apk", "alpha-1.0\nbeta-2.0\ngamma-3.0", 2)
assert(limited.count == 3 and #limited.packages == 2 and limited.truncated == true)

local absent = packages.parse("unknown", "one-1.0")
assert(absent.available == false and absent.count == 0)

print("packages-inventory: all parser tests passed")
