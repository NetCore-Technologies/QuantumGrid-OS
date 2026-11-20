package.path = "files/usr/lib/lua/?.lua;" .. package.path
local mwan3 = require "luci.quantumgrid.mwan3"

local empty = mwan3.normalize_status(nil)
assert(empty.available == false and #empty.interfaces == 0, "missing telemetry must remain unavailable")

local status = mwan3.normalize_status({
	interfaces = {
		wan = {
			enabled = true,
			running = true,
			up = true,
			status = "online",
			tracking = "active",
			age = 120,
			online = 900,
			offline = 0,
			uptime = 3600,
			score = 4,
			lost = 2,
			turn = 7,
			track_ip = {
				{ ip = "1.1.1.1", status = "up", latency = 18, packetloss = 0 },
				{ ip = "9.9.9.9", status = "down", latency = 900, packetloss = 25 }
			}
		},
		wwan = {
			enabled = true,
			running = false,
			up = false,
			status = "offline",
			tracking = "down",
			track_ip = {}
		}
	}
})
assert(status.available == true, "mwan3 telemetry is available")
assert(status.count == 2 and #status.interfaces == 2, "interface count")
assert(status.interfaces[1].name == "wan", "interfaces sort by name")
assert(status.interfaces[1].status == "online" and status.interfaces[1].up == true, "interface state")
assert(status.interfaces[1].tracking == "active" and status.interfaces[1].running == true, "tracking state")
assert(status.interfaces[1].online_seconds == 900 and status.interfaces[1].age_seconds == 120, "duration fields")
assert(#status.interfaces[1].track_targets == 2, "track target count")
assert(status.interfaces[1].track_targets[1].ip == "1.1.1.1", "track targets sort by address")
assert(status.interfaces[1].track_targets[1].latency_ms == 18, "latency conversion")
assert(status.interfaces[1].track_targets[2].packet_loss_percent == 25, "packet loss conversion")
assert(status.interfaces[2].status == "offline" and status.interfaces[2].up == false, "offline state is independent")

local unsafe = mwan3.normalize_status({
	interfaces = {
		["wan;touch /tmp/pwned"] = { status = "online" },
		wan = {
			status = "bad status",
			track_ip = {
				{ ip = "1.1.1.1;bad", status = "online", latency = -1, packetloss = 101 },
				{ ip = "2001:db8::1", status = "skipped", latency = 0, packetloss = 0 }
			}
		}
	}
})
assert(unsafe.count == 1 and #unsafe.interfaces == 1, "unsafe interface names are rejected")
assert(unsafe.interfaces[1].status == "unknown", "unsafe state text is not passed through")
assert(#unsafe.interfaces[1].track_targets == 1, "unsafe target addresses are rejected")
assert(unsafe.interfaces[1].track_targets[1].ip == "2001:db8::1", "IPv6 targets are accepted")
assert(unsafe.interfaces[1].track_targets[1].status == "skipped", "tracking target state")

local many = {}
for index = 1, 20 do
	many["wan" .. tostring(index)] = { status = "online", track_ip = {} }
end
local bounded = mwan3.normalize_status({ interfaces = many })
assert(bounded.count == 20 and #bounded.interfaces == 16, "interface inventory is bounded")
assert(bounded.truncated == true, "truncation is reported")

local too_many_targets = {}
for index = 1, 12 do
	table.insert(too_many_targets, {
		ip = "192.0.2." .. tostring(index),
		status = "up",
		latency = index,
		packetloss = 0
	})
end
local target_limited = mwan3.normalize_status({
	interfaces = { wan = { track_ip = too_many_targets } }
})
assert(#target_limited.interfaces[1].track_targets == 8, "track target inventory is bounded")
assert(target_limited.truncated == true, "target truncation is reported")


local policy_status = mwan3.normalize_status(nil, {
	policies = {
		ipv4 = {
			balanced = {
				{ interface = "wan", percent = 60 },
				{ interface = "wwan", percent = 40 }
			},
			["bad;policy"] = { { interface = "wan", percent = 100 } }
		},
		ipv6 = {
			backup = {
				{ interface = "wwan", percent = 100 }
			}
		}
	}
}, {
	connected = {
		ipv4 = { "192.0.2.0/24", "198.51.100.0/24", "bad network;command" },
		ipv6 = { "2001:db8::/32" }
	}
})
assert(policy_status.available == false, "interface status remains independently unavailable")
assert(policy_status.policies_available == true and policy_status.policy_count == 2, "policy inventory availability and count")
assert(#policy_status.policies == 2, "valid IPv4 and IPv6 policies retained")
assert(policy_status.policies[1].family == "IPv4" and policy_status.policies[1].name == "balanced", "policy family and name")
assert(policy_status.policies[1].members[1].interface == "wan" and policy_status.policies[1].members[1].percent == 60, "policy weights retained")
assert(policy_status.policies[2].family == "IPv6" and policy_status.policies[2].name == "backup", "IPv6 policy retained")
assert(policy_status.connected_available == true, "connected-network telemetry available")
assert(#policy_status.connected_ipv4 == 2 and policy_status.connected_ipv4[1] == "192.0.2.0/24", "IPv4 networks sanitized and sorted")
assert(#policy_status.connected_ipv6 == 1 and policy_status.connected_ipv6[1] == "2001:db8::/32", "IPv6 connected network retained")

local policy_many = {}
for index = 1, 20 do
	policy_many["policy" .. tostring(index)] = {
		{ interface = "wan", percent = 100 }
	}
end
local many_policies = mwan3.normalize_status(nil, { policies = { ipv4 = policy_many } })
assert(many_policies.policy_count == 20 and #many_policies.policies == 16, "policy inventory bound")
assert(many_policies.truncated == true, "policy truncation reported")

local too_many_members = {}
for index = 1, 20 do
	table.insert(too_many_members, { interface = "wan" .. tostring(index), percent = 5 })
end
local members_limited = mwan3.normalize_status(nil, {
	policies = { ipv4 = { balanced = too_many_members } }
})
assert(#members_limited.policies[1].members == 16, "policy members bounded")
assert(members_limited.truncated == true, "member truncation reported")

local many_networks = {}
for index = 1, 70 do
	table.insert(many_networks, "192.0.2." .. tostring(index) .. "/32")
end
local network_limited = mwan3.normalize_status(nil, nil, { connected = { ipv4 = many_networks } })
assert(#network_limited.connected_ipv4 == 64, "connected networks bounded")
assert(network_limited.truncated == true, "connected network truncation reported")

print("mwan3-status: all telemetry normalization tests passed")
