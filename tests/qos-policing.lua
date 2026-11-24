package.path = "files/usr/lib/lua/?.lua;" .. package.path

local policing = require "luci.quantumgrid.qos_policing"
local limits = policing.get_limits()
assert(limits.max_policies == 32 and limits.min_rate_kbps == 64 and limits.max_rate_kbps == 1000000)
assert(limits.min_burst_bytes == 16384 and limits.max_burst_bytes == 262144)
assert(limits.priority_base == 46000 and limits.reserved_priorities == 64)

local zones = {
	{ name = "fiber-edge", networks = { "uplink0" }, masquerade = true },
	{ name = "corp", networks = { "corp" }, masquerade = false }
}
local interfaces = {
	{ name = "uplink0", protocol = "dhcp", device = "eth1", l3_device = "pppoe-wan", up = true,
		firewall_zones = { "fiber-edge" } },
	{ name = "corp", protocol = "static", device = "br-lan", l3_device = "br-lan", up = true,
		ipv4 = { "192.168.20.1" }, netmask = "255.255.255.0", firewall_zones = { "corp" } }
}
local leases = {
	{ section = "cfg_static_1", name = "desktop", mac = "02:11:22:33:44:55", ipv4 = "192.168.20.40" }
}
local policy, err = policing.validate_policy({
	section = "qg_rate_01", slot = 1, mac = "02:11:22:33:44:55",
	client_ip = "192.168.20.40", source_zone = "fiber-edge", destination_zone = "corp",
	upload_kbps = "25000", download_kbps = "100000"
}, zones, interfaces, leases)
assert(policy, err)
assert(policy.enabled and policy.policing and policy.slot == 1)
assert(policy.mac == "02:11:22:33:44:55" and policy.client_ip == "192.168.20.40")
assert(policy.upload_kbps == 25000 and policy.download_kbps == 100000)
assert(#policy.devices == 1 and policy.devices[1] == "pppoe-wan")
assert(policy.upload_burst_bytes == 31250 and policy.download_burst_bytes == 125000)

local upload_only = assert(policing.validate_policy({
	section = "qg_rate_02", slot = 2, mac = "02:11:22:33:44:55",
	client_ip = "192.168.20.40", source_zone = "fiber-edge", destination_zone = "corp",
	upload_kbps = "64", download_kbps = ""
}, zones, interfaces, leases))
assert(upload_only.upload_kbps == 64 and upload_only.download_kbps == nil)
assert(upload_only.upload_burst_bytes == 16384)

local download_only = assert(policing.validate_policy({
	section = "qg_rate_03", slot = 3, mac = "02:11:22:33:44:55",
	client_ip = "192.168.20.40", source_zone = "fiber-edge", destination_zone = "corp",
	upload_kbps = "", download_kbps = "1000000"
}, zones, interfaces, leases))
assert(download_only.upload_kbps == nil and download_only.download_kbps == 1000000)
assert(download_only.download_burst_bytes == 262144)

for _, bad in ipairs({
	{ upload_kbps = "63", download_kbps = "" },
	{ upload_kbps = "1000001", download_kbps = "" },
	{ upload_kbps = "10.5", download_kbps = "" },
	{ upload_kbps = "1000; reboot", download_kbps = "" },
	{ upload_kbps = "", download_kbps = "" },
	{ upload_kbps = "1000", download_kbps = "0" },
	{ upload_kbps = "1000", download_kbps = "1000001" },
}) do
	local input = {
		section = "qg_rate_01", slot = 1, mac = "02:11:22:33:44:55",
		client_ip = "192.168.20.40", source_zone = "fiber-edge", destination_zone = "corp"
	}
	for key, value in pairs(bad) do input[key] = value end
	assert(policing.validate_policy(input, zones, interfaces, leases) == nil,
		"invalid, fractional, zero or command-injected rates must be rejected")
end

assert(policing.validate_policy({
	section = "../rule", slot = 1, mac = "02:11:22:33:44:55",
	client_ip = "192.168.20.40", source_zone = "fiber-edge", destination_zone = "corp",
	upload_kbps = "1000"
}, zones, interfaces, leases) == nil)
assert(policing.validate_policy({
	section = "qg_rate_01", slot = 0, mac = "02:11:22:33:44:55",
	client_ip = "192.168.20.40", source_zone = "fiber-edge", destination_zone = "corp",
	upload_kbps = "1000"
}, zones, interfaces, leases) == nil)
assert(policing.validate_policy({
	section = "qg_rate_01", slot = 1, mac = "02:11:22:33:44:55",
	client_ip = "192.168.20.41", source_zone = "fiber-edge", destination_zone = "corp",
	upload_kbps = "1000"
}, zones, interfaces, leases) == nil, "the client must retain its exact static reservation")
assert(policing.validate_policy({
	section = "qg_rate_01", slot = 1, mac = "02:11:22:33:44:55",
	client_ip = "192.168.20.40", source_zone = "corp", destination_zone = "fiber-edge",
	upload_kbps = "1000"
}, zones, interfaces, leases) == nil, "the zone direction must be WAN-to-internal")

local multiwan = {
	{ name = "fiber", protocol = "dhcp", device = "eth1", l3_device = "pppoe-wan", up = true,
		firewall_zones = { "internet" } },
	{ name = "cellular", protocol = "qmi", device = "wwan0", l3_device = "wwan0", up = true,
		firewall_zones = { "internet" } },
	{ name = "corp", protocol = "static", device = "br-lan", l3_device = "br-lan", up = true,
		ipv4 = { "192.168.20.1" }, netmask = "255.255.255.0", firewall_zones = { "corp" } }
}
local multiwan_zones = {
	{ name = "internet", networks = { "fiber", "cellular" }, masquerade = true },
	{ name = "corp", networks = { "corp" }, masquerade = false }
}
local multiwan_policy = assert(policing.validate_policy({
	section = "qg_rate_04", slot = 4, mac = "02:11:22:33:44:55",
	client_ip = "192.168.20.40", source_zone = "internet", destination_zone = "corp",
	download_kbps = "8000"
}, multiwan_zones, multiwan, leases))
assert(#multiwan_policy.devices == 2 and multiwan_policy.devices[1] == "pppoe-wan" and multiwan_policy.devices[2] == "wwan0",
	"each configured WAN member must enforce the cap through failover")

local rules, rules_error = policing.build_filter_rules({ policy, upload_only, download_only })
assert(rules, rules_error)
assert(#rules == 4)
assert(rules[1].direction == "upload" and rules[1].parent == "ffff:fff3" and rules[1].match == "src")
assert(rules[2].direction == "download" and rules[2].parent == "ffff:fff2" and rules[2].match == "dst")
assert(rules[1].pref == 46000 and rules[2].pref == 46001)
assert(rules[1].handle == "0x51420002" and rules[2].handle == "0x51420003")

local upload_cmd = assert(policing.build_filter_command(rules[1]))
assert(upload_cmd:find("/sbin/tc filter replace dev pppoe%-wan parent ffff:fff3"))
assert(upload_cmd:find("match ip src 192%.168%.20%.40/32"))
assert(upload_cmd:find("police rate 25000kbit burst 31250b"))
assert(upload_cmd:find("conform%-exceed drop/ok"))
local download_cmd = assert(policing.build_filter_command(rules[2]))
assert(download_cmd:find("parent ffff:fff2") and download_cmd:find("match ip dst 192%.168%.20%.40/32"))

assert(policing.build_filter_command({
	device = "eth; reboot", parent = "ffff:fff3", pref = 46000, handle = "0x51420002",
	match = "src", client_ip = "192.168.20.40", rate_kbps = 1000, burst_bytes = 16384
}) == nil, "TC command builder must reject unsafe device names")
assert(policing.build_filter_command({
	device = "eth1", parent = "ffff:fff3", pref = 46000, handle = "0x51420002",
	match = "src", client_ip = "192.168.20.1;reboot", rate_kbps = 1000, burst_bytes = 16384
}) == nil, "TC command builder must reject unsafe IPv4 match strings")

local delete_cmd = assert(policing.build_delete_command("pppoe-wan", "ffff:fff3", 1, "upload"))
assert(delete_cmd:find("filter del dev pppoe%-wan"))
assert(delete_cmd:find("pref 46000") and delete_cmd:find("handle 0x51420002"))
assert(policing.build_delete_command("eth1", "ffff:fff3", 33, "upload") == nil)

print("qos-policing: static lease binding, WAN resolution, rate bounds, multi-WAN TC rules and command safety passed")