package.path = "files/usr/lib/lua/?.lua;" .. package.path
local sqm = require "luci.quantumgrid.sqm"

local function expect_invalid(section, enabled, download, upload, label)
	local result, err = sqm.validate_queue_update(section, enabled, download, upload)
	assert(result == nil, label .. " should be rejected")
	assert(type(err) == "string" and #err > 0, label .. " should explain the rejection")
end

local valid = sqm.validate_queue_update("wan_main", "1", "95000", "18000")
assert(valid ~= nil, "valid queue update should pass")
assert(valid.section == "wan_main")
assert(valid.enabled == "1")
assert(valid.download == "95000")
assert(valid.upload == "18000")

local disabled = sqm.validate_queue_update("cfg012345", "0", "64", "64")
assert(disabled ~= nil and disabled.enabled == "0", "existing anonymous queue names are allowed")
assert(sqm.MIN_RATE_KBPS == 64 and sqm.MAX_RATE_KBPS == 1000000)

expect_invalid("../network", "1", "95000", "18000", "path-like section")
expect_invalid("wan;uci", "1", "95000", "18000", "command-like section")
expect_invalid("wan", "true", "95000", "18000", "non-canonical enabled flag")
expect_invalid("wan", "1", "0", "18000", "zero download rate")
expect_invalid("wan", "1", "1000001", "18000", "out-of-range download rate")
expect_invalid("wan", "1", "12.5", "18000", "fractional download rate")
expect_invalid("wan", "1", "95000", "", "empty upload rate")
expect_invalid(string.rep("a", 33), "1", "95000", "18000", "long section name")

print("sqm-controls: all validation tests passed")
