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


local runtime_available, parsed_qdiscs, parsed_truncated = sqm.parse_qdisc_inventory(table.concat({
	"qdisc cake 8001: dev wan root refcnt 2",
	" Sent 12345 bytes 67 pkt (dropped 3, overlimits 4 requeues 0)",
	" backlog 128b 2p requeues 0",
	"qdisc fq_codel 0: dev lan parent 1:10",
	" Sent 900 bytes 9 pkt (dropped 0, overlimits 1 requeues 0)",
}, "\n"))
assert(runtime_available and not parsed_truncated and #parsed_qdiscs == 2,
	"recognised tc qdisc output should produce a complete inventory")
assert(parsed_qdiscs[1].kind == "cake" and parsed_qdiscs[1].handle == "8001:" and
	parsed_qdiscs[1].device == "wan" and parsed_qdiscs[1].root,
	"root CAKE header fields should be parsed")
assert(parsed_qdiscs[1].bytes == 12345 and parsed_qdiscs[1].packets == 67 and
	parsed_qdiscs[1].dropped == 3 and parsed_qdiscs[1].overlimits == 4 and
	parsed_qdiscs[1].requeues == 0,
	"qdisc traffic counters should be parsed as numbers")
assert(parsed_qdiscs[1].backlog_bytes == 128 and parsed_qdiscs[1].backlog_packets == 2,
	"qdisc backlog counters should be parsed")
assert(parsed_qdiscs[2].kind == "fq_codel" and not parsed_qdiscs[2].root and
	parsed_qdiscs[2].parent == "1:10", "child qdisc parent details should be parsed")
local empty_available, empty_qdiscs, empty_truncated = sqm.parse_qdisc_inventory("")
assert(not empty_available and #empty_qdiscs == 0 and not empty_truncated,
	"empty tc output must not be reported as a successful runtime inventory")
local invalid_available = sqm.parse_qdisc_inventory("tc: command not found")
assert(not invalid_available, "unrecognised tc output must remain unavailable")
local many_headers = {}
for index = 1, 65 do
	table.insert(many_headers, "qdisc cake " .. tostring(index) .. ": dev wan root")
end
local capped_available, capped_qdiscs, capped_truncated = sqm.parse_qdisc_inventory(table.concat(many_headers, "\n"))
assert(capped_available and #capped_qdiscs == 64 and capped_truncated,
	"runtime qdisc parsing must cap memory and explicitly report truncation")


local profile_update = sqm.validate_cake_profile_update("wan_main", "diffserv4")
assert(profile_update and profile_update.section == "wan_main" and profile_update.profile == "diffserv4")
assert(sqm.validate_cake_profile_update("../wan", "diffserv4") == nil)
assert(sqm.validate_cake_profile_update("wan", "custom") == nil)
assert(sqm.validate_cake_profile_update("wan", "diffserv9") == nil)
local preserved_options = sqm.build_cake_profile_options(
	"overhead 18 rtt 100ms diffserv8 dual-dsthost nat wash", "besteffort")
assert(preserved_options == "overhead 18 rtt 100ms wash besteffort triple-isolate nat ack-filter")
assert(sqm.detect_cake_profile(preserved_options) == "besteffort")
assert(sqm.detect_cake_profile("diffserv4 dual-dsthost nat wash") == "custom")
assert(sqm.detect_cake_profile("overhead 18 rtt 100ms") == "default")
assert(sqm.detect_cake_profile(nil) == "default")
assert(sqm.build_cake_profile_options("overhead 18 rtt 100ms diffserv8 nat", "default") == "overhead 18 rtt 100ms")
assert(sqm.build_cake_profile_options(string.rep("x", 1025), "diffserv4") == nil)
assert(sqm.build_cake_profile_options({}, "diffserv4") == nil)

print("sqm-controls: runtime qdisc parsing, attribution, CAKE profiles and validation tests passed")
