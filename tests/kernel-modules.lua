package.path = "files/usr/lib/lua/?.lua;" .. package.path
local kernel_modules = require "luci.quantumgrid.kernel_modules"

local inventory = kernel_modules.parse(table.concat({
	"kernel/drivers/net/ethernet/qcom/nss-dp.ko:",
	"kernel/net/netfilter/nf_conntrack.ko:",
	"kernel/drivers/net/wireless/ath/ath11k/ath11k.ko:",
	"kernel/drivers/net/ethernet/qcom/nss-dp.ko:",
	"kernel/../bad.ko:",
	"kernel/drivers/net/ethernet/qcom/qca_ssdk.ko.zst:"
}, "\n"), table.concat({
	"nss_dp 12345 1 - Live 0x00000000",
	"ath11k 98765 0 - Live 0x00000000",
	"out_of_tree 100 0 - Live 0x00000000"
}, "\n"))
assert(inventory.available == true)
assert(inventory.count == 4, "module names should be unique and paths validated")
assert(inventory.loaded_count == 3)
local by_name = {}
for _, item in ipairs(inventory.modules) do by_name[item.name] = item end
assert(by_name.nss_dp.loaded == true)
assert(by_name.ath11k.loaded == true)
assert(by_name.nf_conntrack.loaded == false)
assert(by_name.qca_ssdk.path:find("%.ko%.zst$"))
assert(by_name.out_of_tree.loaded == true and by_name.out_of_tree.path == "")

local limited = kernel_modules.parse("kernel/a.ko:\nkernel/b.ko:\nkernel/c.ko:", "", 2)
local duplicates_after_limit = kernel_modules.parse(
	"kernel/a.ko:\nkernel/b.ko:\nkernel/c.ko:\nkernel/c.ko:",
	"", 2
)
assert(duplicates_after_limit.count == 3 and #duplicates_after_limit.modules == 2,
	"duplicate entries after the API cap must not inflate the count")
assert(limited.count == 3 and #limited.modules == 2 and limited.truncated == true)

local absent = kernel_modules.parse(nil, "x 10 0 - Live 0x0")
assert(absent.available == false)
assert(absent.count == 1 and absent.loaded_count == 1)
assert(absent.modules[1].name == "x" and absent.modules[1].loaded == true)

print("kernel-modules: all inventory parser tests passed")
