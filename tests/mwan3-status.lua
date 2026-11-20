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

print("mwan3-status: all telemetry normalization tests passed")
