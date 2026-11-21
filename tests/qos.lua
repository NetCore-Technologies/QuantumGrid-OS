package.path = "files/usr/lib/lua/?.lua;" .. package.path
local qos = require "luci.quantumgrid.qos"

local zones = {
	{ name = "corp", networks = { "corp" } },
	{ name = "guest", networks = "guest" },
	{ name = "wan", networks = { "wan" } },
	{ name = "uplink", networks = { "wwan" } }
}

local update = qos.validate_client_policy("02:11:22:33:44:55", "corp", "wan", "AF41", zones)
assert(update and update.mac == "02:11:22:33:44:55" and update.source_zone == "corp")
assert(update.destination_zone == "wan" and update.dscp_class == "AF41")
assert(update.name == "QuantumGrid client QoS: 02:11:22:33:44:55")
assert(qos.validate_client_policy("01:11:22:33:44:55", "corp", "wan", "AF41", zones) == nil,
	"multicast MAC addresses must be rejected")
assert(qos.validate_client_policy("00:00:00:00:00:00", "corp", "wan", "AF41", zones) == nil,
	"zero MAC addresses must be rejected")
assert(qos.validate_client_policy("02:11:22:33:44:5g", "corp", "wan", "AF41", zones) == nil,
	"malformed MAC addresses must be rejected")
assert(qos.validate_client_policy("02:11:22:33:44:55", "wan", "corp", "AF41", zones) == nil,
	"upload classification cannot originate from a WAN zone")
assert(qos.validate_client_policy("02:11:22:33:44:55", "corp", "guest", "AF41", zones) == nil,
	"destination must be an existing WAN zone")
assert(qos.validate_client_policy("02:11:22:33:44:55", "corp", "wan", "DSCP 46; flush", zones) == nil,
	"arbitrary DSCP values or command-like strings must be rejected")
assert(qos.validate_client_policy("02:11:22:33:44:55", "corp", "wan", "EF", zones))
assert(qos.validate_client_policy("02:11:22:33:44:55", "corp", "wan", "CS1", zones))
assert(qos.validate_client_policy("02:11:22:33:44:55", "corp", "uplink", "BE", zones),
	"WWAN networks attached to an external zone must be allowed as destinations")

local summary = qos.summarize_client_policy({
	[".name"] = "cfg_client_1", [".type"] = "rule",
	name = "QuantumGrid client QoS: 02:11:22:33:44:55",
	src = "corp", dest = "wan", src_mac = "02:11:22:33:44:55",
	target = "dscp", set_dscp = "AF41", enabled = "1"
})
assert(summary and summary.section == "cfg_client_1" and summary.enabled)
assert(summary.mac == "02:11:22:33:44:55" and summary.dscp_class == "AF41")
assert(qos.summarize_client_policy({
	[".name"] = "user_rule", [".type"] = "rule", name = "User firewall rule",
	src = "corp", dest = "wan", src_mac = "02:11:22:33:44:55",
	target = "dscp", set_dscp = "AF41"
}) == nil, "unowned firewall rules must not appear as QuantumGrid policies")
assert(qos.summarize_client_policy({
	[".name"] = "cfg_client_2", [".type"] = "rule",
	name = "QuantumGrid client QoS: 02:11:22:33:44:55",
	src = "corp", dest = "wan", src_mac = "02:11:22:33:44:55",
	target = "dscp", set_dscp = "EF; delete"
}) == nil, "unsupported DSCP values must not be exposed")

local duplicate = qos.validate_client_policy("02:11:22:33:44:55", "corp", "wan", "EF", zones)
assert(duplicate and qos.has_duplicate_client_policy({ summary }, update))
assert(qos.has_duplicate_client_policy({ summary }, duplicate),
	"only one policy per client/zone pair is allowed")
assert(not qos.has_duplicate_client_policy({}, update))

local snap = qos.snapshot_client_policy_section({
	[".name"] = "cfg_client_1", [".type"] = "rule",
	name = "QuantumGrid client QoS: 02:11:22:33:44:55",
	src = "corp", dest = "wan", src_mac = "02:11:22:33:44:55",
	target = "dscp", set_dscp = "AF41", extra = { "preserve", "both" }
})
assert(snap and snap.values.extra[2] == "both")
assert(qos.snapshot_client_policy_section({
	[".name"] = "user_rule", [".type"] = "rule", name = "unowned"
}) == nil)

local fake = { rules = {
	{ [".name"] = "cfg_client_1", [".type"] = "rule", name = "QuantumGrid client QoS: 02:11:22:33:44:55", src = "corp", dest = "wan", src_mac = "02:11:22:33:44:55", target = "dscp", set_dscp = "AF41" },
	{ [".name"] = "user_rule", [".type"] = "rule", name = "User rule", src = "corp", dest = "wan", src_mac = "02:11:22:33:44:55", target = "dscp", set_dscp = "EF" },
	{ [".name"] = "cfg_client_2", [".type"] = "rule", name = "QuantumGrid client QoS: 02:aa:bb:cc:dd:ee", src = "guest", dest = "wan", src_mac = "02:aa:bb:cc:dd:ee", target = "dscp", set_dscp = "CS1" }
} }
function fake:foreach(config, section_type, callback)
	assert(config == "firewall" and section_type == "rule")
	for _, rule in ipairs(self.rules) do callback(rule) end
	return true
end
local policies, truncated = qos.read_client_policies(fake, 2)
assert(policies and #policies == 2 and not truncated)
assert(policies[1].section == "cfg_client_1" and policies[2].section == "cfg_client_2")
local capped, is_truncated = qos.read_client_policies(fake, 1)
assert(capped and #capped == 1 and is_truncated)
assert(qos.read_client_policies(fake, 65) == nil, "policy inventory limits must be bounded")
assert(qos.validate_client_policy_section("cfg_client_1") == "cfg_client_1")
assert(qos.validate_client_policy_section("../firewall") == nil)

print("qos: DSCP client policy validation, owned-rule inventory, duplicate rejection and snapshots passed")
