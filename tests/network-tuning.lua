package.path = "files/usr/lib/lua/?.lua;" .. package.path

local tuning = require "luci.quantumgrid.network_tuning"

local algorithms = assert(tuning.parse_algorithms("reno cubic bbr cubic", "bbr"))
assert(#algorithms == 3)
assert(algorithms[1] == "bbr" and algorithms[2] == "cubic" and algorithms[3] == "reno")
assert(tuning.parse_algorithms("reno;reboot", "reno") == nil)
assert(tuning.parse_algorithms(string.rep("a", 1025), "reno") == nil)
assert(tuning.parse_algorithms("", "") == nil)

local reads = {
	["/proc/sys/net/ipv4/tcp_available_congestion_control"] = "reno cubic bbr",
	["/proc/sys/net/ipv4/tcp_congestion_control"] = "bbr",
	["/proc/sys/net/core/default_qdisc"] = "fq_codel",
}
local snapshot = tuning.inspect({
	read = function(path) return reads[path] end,
	access = function(path) return path == "/sys/module/sch_fq" end,
	modules_dep = "kernel/net/sched/sch_cake.ko:\nkernel/net/sched/sch_fq.ko:\n",
})
assert(snapshot.available)
assert(snapshot.current_congestion_control == "bbr")
assert(snapshot.current_default_qdisc == "fq_codel")
assert(#snapshot.congestion_controls == 3)
assert(#snapshot.default_qdiscs == 3)
assert(snapshot.default_qdiscs[1] == "cake")
assert(snapshot.default_qdiscs[2] == "fq")
assert(snapshot.default_qdiscs[3] == "fq_codel")

local valid, err = tuning.validate({
	congestion_control = "cubic",
	default_qdisc = "cake",
	confirmed = "1"
}, snapshot)
assert(valid, err)
assert(valid.previous_congestion_control == "bbr")
assert(valid.previous_default_qdisc == "fq_codel")

local function reject(input, state, label)
	local result, reason = tuning.validate(input, state or snapshot)
	assert(result == nil, label .. " must be rejected")
	assert(type(reason) == "string" and #reason > 0)
end
reject({ congestion_control = "reboot", default_qdisc = "cake", confirmed = "1" }, nil, "unavailable algorithm")
reject({ congestion_control = "cubic", default_qdisc = "unknown", confirmed = "1" }, nil, "unavailable qdisc")
reject({ congestion_control = "cubic", default_qdisc = "cake", confirmed = "0" }, nil, "missing confirmation")
reject({ congestion_control = "cubic; reboot", default_qdisc = "cake", confirmed = "1" }, nil, "command-like algorithm")
reject({ congestion_control = "cubic", default_qdisc = "cake; reboot", confirmed = "1" }, nil, "command-like qdisc")

local malformed = tuning.inspect({
	read = function(path)
		if path == "/proc/sys/net/ipv4/tcp_available_congestion_control" then return "reno cubic" end
		if path == "/proc/sys/net/ipv4/tcp_congestion_control" then return "bbr;bad" end
		return "fq_codel"
	end,
	access = function() return true end,
	modules_dep = ""
})
assert(not malformed.available, "malformed current kernel values fail closed")


local live = {
	["/proc/sys/net/ipv4/tcp_congestion_control"] = "bbr",
	["/proc/sys/net/core/default_qdisc"] = "fq_codel",
}
local function fake_deps(options)
	options = options or {}
	return {
		read = function(path) return live[path] end,
		write = function(path, value)
			if options.fail_path == path and options.fail_once then
				options.fail_once = false
				return false
			end
			if options.fail_path == path and options.fail_always then return false end
			if options.reject_value == value then return true end
			live[path] = value
			return true
		end,
	}
end

-- A successful transaction updates both fixed kernel paths and confirms read-back.
local updated = assert(tuning.apply({
	congestion_control = "cubic", default_qdisc = "cake", confirmed = "1"
}, snapshot, fake_deps()))
assert(updated.changed and live["/proc/sys/net/ipv4/tcp_congestion_control"] == "cubic")
assert(live["/proc/sys/net/core/default_qdisc"] == "cake")

-- A partial write failure restores both old kernel settings.
live["/proc/sys/net/ipv4/tcp_congestion_control"] = "bbr"
live["/proc/sys/net/core/default_qdisc"] = "fq_codel"
local fail_first_qdisc = true
local partial_failure_deps = {
	read = function(path) return live[path] end,
	write = function(path, value)
		if path == "/proc/sys/net/core/default_qdisc" and value == "cake" and fail_first_qdisc then
			fail_first_qdisc = false
			return false
		end
		live[path] = value
		return true
	end
}
local failed, reason, rolled_back = tuning.apply({
	congestion_control = "cubic", default_qdisc = "cake", confirmed = "1"
}, snapshot, partial_failure_deps)
assert(failed == nil and reason and rolled_back,
	"partial qdisc write failure must restore and verify both original kernel values")
assert(live["/proc/sys/net/ipv4/tcp_congestion_control"] == "bbr")
assert(live["/proc/sys/net/core/default_qdisc"] == "fq_codel")

-- Read-back mismatch is not reported as success and still attempts rollback.
live["/proc/sys/net/ipv4/tcp_congestion_control"] = "bbr"
live["/proc/sys/net/core/default_qdisc"] = "fq_codel"
local calls = 0
local mismatched = tuning.apply({
	congestion_control = "cubic", default_qdisc = "cake", confirmed = "1"
}, snapshot, {
	read = function(path)
		calls = calls + 1
		if calls == 1 then return "not-applied" end
		return live[path]
	end,
	write = function(path, value) live[path] = value; return true end
})
assert(mismatched == nil)
assert(live["/proc/sys/net/ipv4/tcp_congestion_control"] == "bbr")
assert(live["/proc/sys/net/core/default_qdisc"] == "fq_codel")

-- Re-applying the current state is a no-op and does not write anything.
local writes = 0
local no_op = assert(tuning.apply({
	congestion_control = "bbr", default_qdisc = "fq_codel", confirmed = "1"
}, snapshot, {
	read = function(path) return live[path] end,
	write = function() writes = writes + 1; return true end
}))
assert(not no_op.changed and writes == 0)

print("network-tuning: bounded allowlists, no-op, runtime write/read-back and rollback tests passed")
