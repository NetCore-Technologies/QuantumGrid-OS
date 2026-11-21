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

local duplicate_zone_names = {
  { name = "corp", networks = { "corp" } },
  { name = "corp", networks = { "corp2" } },
  { name = "wan", networks = { "wan" } },
}
assert(qos.validate_client_policy(
  "02:11:22:33:44:55", "corp", "wan", "AF41", duplicate_zone_names) == nil,
  "duplicate firewall zone names must not be resolved arbitrarily")
assert(qos.validate_client_download_policy(
  "02:11:22:33:44:55", "192.168.20.40", "wan", "corp", "AF41",
  duplicate_zone_names, {}, {}) == nil,
  "duplicate firewall zone names must fail closed for download marking")

local download_interfaces = {
  {
    name = "corp", ipv4 = { "192.168.20.1" }, netmask = "255.255.255.0",
    firewall_zones = { "corp" },
  },
  {
    name = "guest", ipv4 = { "192.168.30.1" }, netmask = "255.255.255.0",
    firewall_zones = { "guest" },
  },
}
local download_leases = {
  { section = "cfg_host_1", name = "desktop", mac = "02:11:22:33:44:55", ipv4 = "192.168.20.40" },
}
local custom_masquerade_zones = {
  { name = "internet-edge", networks = { "uplink0" }, masquerade = true },
  { name = "corp", networks = { "corp" }, masquerade = false },
}
local custom_external = qos.validate_client_download_policy(
  "02:11:22:33:44:55", "192.168.20.40", "internet-edge", "corp", "AF41",
  custom_masquerade_zones, download_interfaces, download_leases)
assert(custom_external and custom_external.direction == "download",
  "a custom masquerading WAN zone must be classified as external")

local download = qos.validate_client_download_policy(
  "02:11:22:33:44:55", "192.168.20.40", "wan", "corp", "AF41",
  zones, download_interfaces, download_leases)
assert(download and download.direction == "download")
assert(download.mac == "02:11:22:33:44:55" and download.destination_ip == "192.168.20.40")
assert(download.source_zone == "wan" and download.destination_zone == "corp")
assert(download.dscp_class == "AF41")
assert(download.name == "QuantumGrid client QoS download: 02:11:22:33:44:55")

local invalid_downloads = {
  { "01:11:22:33:44:55", "192.168.20.40", "wan", "corp", "AF41", zones, download_interfaces, download_leases },
  { "02:11:22:33:44:55", "192.168.20.0", "wan", "corp", "AF41", zones, download_interfaces, download_leases },
  { "02:11:22:33:44:55", "192.168.20.255", "wan", "corp", "AF41", zones, download_interfaces, download_leases },
  { "02:11:22:33:44:55", "192.168.30.40", "wan", "corp", "AF41", zones, download_interfaces, download_leases },
  { "02:11:22:33:44:55", "192.168.20.40", "corp", "wan", "AF41", zones, download_interfaces, download_leases },
  { "02:11:22:33:44:55", "192.168.20.40", "wan", "guest", "AF41", zones, download_interfaces, download_leases },
  { "02:11:22:33:44:55", "192.168.20.40", "wan", "corp", "CS1; flush", zones, download_interfaces, download_leases },
}
for _, input in ipairs(invalid_downloads) do
  assert(qos.validate_client_download_policy(unpack(input)) == nil,
    "invalid direction, address, subnet, DSCP or zone must be rejected for download marking")
end
assert(qos.validate_client_download_policy(
  "02:11:22:33:44:55", "192.168.20.40", "wan", "corp", "AF41",
  zones, download_interfaces, {}) == nil, "a dynamic lease is not a stable downlink match")
assert(qos.validate_client_download_policy(
  "02:11:22:33:44:56", "192.168.20.40", "wan", "corp", "AF41",
  zones, download_interfaces, download_leases) == nil, "the reserved MAC must match")
assert(qos.validate_client_download_policy(
  "02:11:22:33:44:55", "192.168.20.40", "wan", "corp", "AF41",
  zones, download_interfaces, {
    download_leases[1], { mac = "02:aa:bb:cc:dd:ee", ipv4 = "192.168.20.40" },
  }) == nil, "the reserved IPv4 address must not be duplicated")
assert(qos.validate_client_download_policy(
  "02:11:22:33:44:55", "192.168.20.40", "wan", "corp", "AF41",
  zones, {
    download_interfaces[1],
    { name = "corp2", ipv4 = { "192.168.20.2" }, netmask = "255.255.255.0", firewall_zones = { "corp" } },
  }, download_leases) == nil, "overlapping internal interfaces must be treated as ambiguous")
assert(qos.validate_client_download_policy(
  "02:11:22:33:44:55", "192.168.20.40", "wan", "corp", "AF41",
  zones, {
    { name = "corp", ipv4 = { "192.168.20.1", "192.168.20.2" }, netmask = "255.255.255.0", firewall_zones = { "corp" } },
  }, download_leases) ~= nil,
  "multiple router addresses on one routed interface must be counted as one interface match")
assert(qos.validate_client_download_policy(
  "02:11:22:33:44:55", "192.168.20.40", "wan", "corp", "AF41",
  zones, {
    { name = "corp", ipv4 = { "192.168.20.1" }, netmask = "255.255.255.0", firewall_zones = { "corp", "guest" } },
  }, download_leases) == nil,
  "an interface attached to multiple firewall zones must fail closed")
assert(qos.validate_client_download_policy(
  "02:11:22:33:44:55", "192.168.20.40", "wan", "corp", "AF41",
  zones, {
    { name = "corp", ipv4 = { "192.168.20.1" }, netmask = "255.255.255.0", firewall_zones = { "guest" } },
  }, download_leases) == nil, "the target subnet must be attached to the selected internal firewall zone")

local download_summary = qos.summarize_client_policy({
  [".name"] = "cfg_client_download_1", [".type"] = "rule",
  name = "QuantumGrid client QoS download: 02:11:22:33:44:55",
  src = "wan", dest = "corp", dest_ip = "192.168.20.40",
  target = "dscp", set_dscp = "AF41", enabled = "1",
})
assert(download_summary and download_summary.direction == "download")
assert(download_summary.protocol == "tcpudp")
assert(download_summary.destination_ip == "192.168.20.40")
assert(download_summary.mac == "02:11:22:33:44:55" and download_summary.enabled)
assert(qos.summarize_client_policy({
  [".name"] = "cfg_client_download_bad", [".type"] = "rule",
  name = "QuantumGrid client QoS download: 02:11:22:33:44:55",
  src = "wan", dest = "corp", dest_ip = "192.168.20.40",
  src_mac = "02:11:22:33:44:55", target = "dscp", set_dscp = "AF41",
}) == nil, "download policy must not rely on unsupported destination MAC matching")
assert(qos.summarize_client_policy({
  [".name"] = "cfg_client_download_bad", [".type"] = "rule",
  name = "QuantumGrid client QoS download: 02:11:22:33:44:55",
  src = "wan", dest = "corp", dest_ip = "not-an-ip", target = "dscp", set_dscp = "AF41",
}) == nil, "malformed downlink destination addresses must not be inventoried")
assert(qos.summarize_client_policy({
  [".name"] = "cfg_client_download_srcmac", [".type"] = "rule",
  name = "QuantumGrid client QoS download: 02:11:22:33:44:55",
  src = "wan", dest = "corp", dest_ip = "192.168.20.40",
  src_mac = "invalid", proto = "all", target = "dscp", set_dscp = "AF41",
}) == nil, "downlink rules with a source-MAC condition must not be inventoried as destination-IP-only rules")
assert(qos.summarize_client_policy({
  [".name"] = "cfg_client_download_port", [".type"] = "rule",
  name = "QuantumGrid client QoS download: 02:11:22:33:44:55",
  src = "wan", dest = "corp", dest_ip = "192.168.20.40",
  dest_port = "443", proto = "all", target = "dscp", set_dscp = "AF41",
}) == nil, "downlink rules with extra port restrictions must not be inventoried as general traffic policies")
assert(qos.summarize_client_policy({
  [".name"] = "cfg_client_upload_port", [".type"] = "rule",
  name = "QuantumGrid client QoS: 02:11:22:33:44:55",
  src = "corp", dest = "wan", src_mac = "02:11:22:33:44:55",
  src_port = "443", proto = "all", target = "dscp", set_dscp = "AF41",
}) == nil, "upload rules with extra port restrictions must not be inventoried as general traffic policies")

local all_protocol_upload = qos.summarize_client_policy({
  [".name"] = "cfg_client_all_upload", [".type"] = "rule",
  name = "QuantumGrid client QoS: 02:11:22:33:44:55",
  src = "corp", dest = "wan", src_mac = "02:11:22:33:44:55",
  proto = "all", target = "dscp", set_dscp = "AF41",
})
assert(all_protocol_upload and all_protocol_upload.protocol == "all")
local all_protocol_download = qos.summarize_client_policy({
  [".name"] = "cfg_client_all_download", [".type"] = "rule",
  name = "QuantumGrid client QoS download: 02:11:22:33:44:55",
  src = "wan", dest = "corp", dest_ip = "192.168.20.40",
  proto = "all", target = "dscp", set_dscp = "AF41",
})
assert(all_protocol_download and all_protocol_download.protocol == "all")
assert(qos.summarize_client_policy({
  [".name"] = "cfg_client_bad_proto", [".type"] = "rule",
  name = "QuantumGrid client QoS download: 02:11:22:33:44:55",
  src = "wan", dest = "corp", dest_ip = "192.168.20.40",
  proto = "sctp", target = "dscp", set_dscp = "AF41",
}) == nil, "unrecognized protocol restrictions must not be reported as complete traffic marking")

local summary = qos.summarize_client_policy({
	[".name"] = "cfg_client_1", [".type"] = "rule",
	name = "QuantumGrid client QoS: 02:11:22:33:44:55",
	src = "corp", dest = "wan", src_mac = "02:11:22:33:44:55",
	target = "dscp", set_dscp = "AF41", enabled = "1"
})
assert(summary and summary.section == "cfg_client_1" and summary.enabled)
assert(summary.protocol == "tcpudp", "legacy policies without an explicit protocol retain firewall4's TCP/UDP default")
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
	target = "dscp", set_dscp = "AF41"
})
assert(snap and snap.values.src_mac == "02:11:22:33:44:55")
assert(qos.snapshot_client_policy_section({
	[".name"] = "cfg_client_extra_port", [".type"] = "rule",
	name = "QuantumGrid client QoS: 02:11:22:33:44:55",
	src = "corp", dest = "wan", src_mac = "02:11:22:33:44:55",
	target = "dscp", set_dscp = "AF41", dest_port = "443"
}) == nil, "a policy modified with extra port matches must not be treated as a managed full-traffic rule")
assert(qos.snapshot_client_policy_section({
	[".name"] = "user_rule", [".type"] = "rule", name = "unowned"
}) == nil)

local dependency_policies = {
  {
    direction = "download",
    mac = "02:11:22:33:44:55",
    destination_ip = "192.168.20.40",
    source_zone = "wan",
    destination_zone = "corp",
  },
  {
    direction = "upload",
    mac = "02:aa:bb:cc:dd:ee",
    source_zone = "corp",
    destination_zone = "wan",
  },
}
local dependency = qos.find_download_reservation_policy(
  dependency_policies, "02:11:22:33:44:55", "192.168.20.40")
assert(dependency and dependency.direction == "download",
  "a matching downlink rule must be tied to its static reservation")
assert(qos.find_download_reservation_policy(
  dependency_policies, "02:11:22:33:44:56", "192.168.20.40") ~= nil,
  "a reused reserved IP must be treated as a dependency even when the MAC differs")
assert(qos.find_download_reservation_policy(
  dependency_policies, "02:11:22:33:44:55", "192.168.20.41") ~= nil,
  "a client MAC remains a dependency if its reserved IP changes")
assert(qos.find_download_reservation_policy(dependency_policies, "bad-mac", "192.168.20.40") == nil)

assert(qos.find_download_policy_conflict(
  dependency_policies, "02:11:22:33:44:55", "192.168.20.41") ~= nil,
  "changing a reserved IP for a client with a downlink policy must be blocked")
assert(qos.find_download_policy_conflict(
  dependency_policies, "02:aa:bb:cc:dd:ef", "192.168.20.40") ~= nil,
  "reusing a destination IP referenced by another downlink policy must be blocked")
assert(qos.find_download_policy_conflict(
  dependency_policies, "02:aa:bb:cc:dd:ef", "192.168.20.41") == nil,
  "unrelated reservations must not be blocked")
assert(qos.find_download_reservation_policy(
  dependency_policies, "02:11:22:33:44:55", "192.168.20.41") ~= nil,
  "changing a reserved IP for a client with a downlink policy must be blocked by the client identity")
assert(qos.find_download_reservation_policy(
  { { direction = "download", mac = "02:aa:bb:cc:dd:ee", destination_ip = "192.168.20.40" } },
  "02:11:22:33:44:55", "192.168.20.40") ~= nil,
  "reusing a reserved IP referenced by a different downlink identity must also be blocked")
assert(qos.find_download_policy_conflict({}, "02:11:22:33:44:55", "192.168.20.40") == nil)

local download_snapshot = qos.snapshot_client_policy_section({
  [".name"] = "cfg_client_download_1", [".type"] = "rule",
  name = "QuantumGrid client QoS download: 02:11:22:33:44:55",
  src = "wan", dest = "corp", dest_ip = "192.168.20.40",
  target = "dscp", set_dscp = "AF41",
})
assert(download_snapshot and download_snapshot.values.dest_ip == "192.168.20.40")

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
