package.path = "files/usr/lib/lua/?.lua;" .. package.path
local acceleration = require "luci.quantumgrid.acceleration"

local none = acceleration.summarize({})
assert(none.status == "not-detected")
assert(none.present_components == 0 and none.required_components == 12)
assert(none.offload_verified == false)
assert(#none.components == 0)

local partial = acceleration.summarize({
	{ name = "EDMA device-tree node", kind = "device-tree", present = true, detail = "present" },
	{ name = "NSS core driver", kind = "kernel-module", present = true, detail = "loaded" },
	{ name = "NSS firmware core 0", kind = "firmware", present = true, detail = "present" },
	{ name = "NSS firmware core 1", kind = "firmware", present = false, detail = "missing" }
})
assert(partial.status == "partial")
assert(partial.present_components == 3 and partial.required_components == 12)
assert(partial.offload_verified == false)
assert(#partial.components == 4)

local complete = {}
local names = {
	{ "EDMA device-tree node", "device-tree" },
	{ "ESS / PPE switch device-tree node", "device-tree" },
	{ "NSS core 0 device-tree node", "device-tree" },
	{ "NSS core 1 device-tree node", "device-tree" },
	{ "NSS core driver", "kernel-module" },
	{ "NSS datapath / EDMA driver", "kernel-module" },
	{ "Qualcomm SSDK", "kernel-module" },
	{ "NSS Enhanced Connection Manager", "kernel-module" },
	{ "NSS firmware core 0", "firmware" },
	{ "NSS firmware core 1", "firmware" },
	{ "Wi-Fi driver", "kernel-module" },
	{ "ath11k NSS offload parameter", "kernel-module" }
}
for _, item in ipairs(names) do
	table.insert(complete, { name = item[1], kind = item[2], present = true, detail = "present" })
end
local ready = acceleration.summarize(complete)
assert(ready.status == "components-present-unverified")
assert(ready.present_components == 12 and ready.required_components == 12)
assert(ready.offload_verified == false, "component presence must never be reported as verified traffic offload")

local untrusted = acceleration.summarize({
	{ name = "bad\nname", kind = "kernel-module", present = true, detail = "line one\nline two" },
	{ name = "arbitrary", kind = "shell-command", present = true, detail = "not an allowed component kind" },
	{ name = "NSS core driver", kind = "kernel-module", present = "yes", detail = "untrusted truthy value" },
	{ name = "NSS core driver", kind = "kernel-module", present = true, detail = "duplicate" }
})
assert(untrusted.present_components == 0, "unknown names and truthy non-booleans must not count as required components")
assert(#untrusted.components == 2, "duplicate names are removed and invalid kinds are rejected")
assert(not untrusted.components[1].detail:find("[\r\n]"), "control characters are removed")

print("acceleration-status: all readiness tests passed")
