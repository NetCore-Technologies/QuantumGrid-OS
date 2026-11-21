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
assert(sqm.validate_queue_update("wan", "1", "1000000", "64") ~= nil, "rate boundaries should pass")
assert(sqm.validate_queue_update("wan", "1", "1000001", "64") == nil, "rates above the upper boundary should fail")
local calibrated = sqm.validate_queue_update("wan_main", "1", "95000", "18000", "ethernet", "42", "84")
assert(calibrated ~= nil and calibrated.overhead == "42" and calibrated.tc_mpu == "84", "Ethernet calibration should pass")
local dsl = sqm.validate_queue_update("wan_main", "1", "95000", "18000", "atm", "44", "96")
assert(dsl ~= nil and dsl.linklayer == "atm", "ATM calibration should pass")
assert(sqm.validate_queue_update("wan", "1", "64", "64", "ptm", "-64", "0") ~= nil, "lower calibration bounds should pass")
assert(sqm.validate_queue_update("wan", "1", "64", "64", "ethernet", "256", "256") ~= nil, "upper calibration bounds should pass")
local function expect_invalid_tuning(linklayer, overhead, mpu, label)
	local result, err = sqm.validate_queue_update("wan", "1", "95000", "18000", linklayer, overhead, mpu)
	assert(result == nil and type(err) == "string" and #err > 0, label .. " should be rejected with an explanation")
end
expect_invalid_tuning("wifi", "42", "84", "unsupported link layer")
expect_invalid_tuning("ethernet", "-65", "84", "overhead too low")
expect_invalid_tuning("ethernet", "257", "84", "overhead too high")
expect_invalid_tuning("ethernet", "42.5", "84", "fractional overhead")
expect_invalid_tuning("ethernet", "42", "-1", "negative MPU")
expect_invalid_tuning("ethernet", "42", "257", "MPU too high")
expect_invalid_tuning("ethernet", "42", "84.5", "fractional MPU")
expect_invalid_tuning(nil, "42", "84", "missing link layer")

expect_invalid("../network", "1", "95000", "18000", "path-like section")
expect_invalid("wan;uci", "1", "95000", "18000", "command-like section")
expect_invalid("wan", "true", "95000", "18000", "non-canonical enabled flag")
expect_invalid("wan", "1", "0", "18000", "zero download rate")
expect_invalid("wan", "1", "1000001", "18000", "out-of-range download rate")
expect_invalid("wan", "1", "12.5", "18000", "fractional download rate")
expect_invalid("wan", "1", "95000", "", "empty upload rate")
expect_invalid(string.rep("a", 33), "1", "95000", "18000", "long section name")

print("sqm-controls: all validation tests passed")

local function queue_state(queue, qdiscs, available, truncated)
	return sqm.queue_runtime_state(queue, qdiscs, available, truncated)
end
local expected_queue = { enabled = true, qdisc = "cake", interface = "wan" }
assert(queue_state(expected_queue, {
	{ kind = "cake", handle = "8001:", device = "wan", root = true }
}, true, false) == "observed", "matching live root CAKE qdisc should be observed")
assert(queue_state(expected_queue, {
	{ kind = "fq_codel", handle = "8001:", device = "wan", root = true }
}, true, false) == "not_observed", "a different root qdisc must not be reported as the configured discipline")
assert(queue_state(expected_queue, {
	{ kind = "cake", handle = "8001:", device = "ifb-wan", root = true }
}, true, false) == "not_observed", "a qdisc on another device must not be attributed to this queue")
assert(queue_state(expected_queue, {
	{ kind = "cake", handle = "8001:", device = "wan", root = false }
}, true, false) == "not_observed", "a child qdisc must not satisfy the root discipline check")
assert(queue_state(expected_queue, {}, false, false) == "unavailable", "missing runtime telemetry must remain unavailable")
assert(queue_state(expected_queue, {}, true, true) == "inventory_truncated", "truncated qdisc inventories must not be treated as definitive absence")
assert(queue_state({ enabled = false, qdisc = "cake", interface = "wan" }, {}, true, false) == "disabled",
	"disabled queues must not be reported as missing runtime qdiscs")
assert(queue_state({ enabled = true, qdisc = "", interface = "wan" }, {}, true, false) == "unconfigured",
	"queues without a configured qdisc must remain unconfigured")

print("sqm-controls: runtime qdisc attribution and validation tests passed")
