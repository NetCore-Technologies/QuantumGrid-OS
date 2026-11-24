package.path = "files/usr/lib/lua/?.lua;" .. package.path

local policing = require "luci.quantumgrid.client_policing"

local inventory = {
	available = true,
	firewall_available = true,
	dhcp_available = true,
	truncated = false,
	zones = {
		{ name = "fiber-edge", networks = { "uplink0" }, masquerade = true },
		{ name = "corp", networks = { "corp" }, masquerade = false },
	},
	interfaces = {
		{ name = "uplink0", protocol = "dhcp", device = "eth1", l3_device = "pppoe-wan", up = true,
			firewall_zones = { "fiber-edge" } },
		{ name = "corp", protocol = "static", device = "br-lan", l3_device = "br-lan", up = true,
			ipv4 = { "192.168.20.1" }, netmask = "255.255.255.0",
			firewall_zones = { "corp" } },
	},
	static_leases = {
		{ section = "cfg_static_1", name = "desktop", mac = "02:11:22:33:44:55", ipv4 = "192.168.20.40" },
	},
}

local function fixture()
	local state = { rules = nil, status = nil, ensures = {}, replaces = {}, deletes = {}, fail_replace = false }
	local deps = {
		ensure_clsact = function(device)
			state.ensures[#state.ensures + 1] = device
			return true
		end,
		device_has_clsact = function(device)
			return device == "pppoe-wan"
		end,
		replace_filter = function(command, rule)
			state.replaces[#state.replaces + 1] = { command = command, rule = rule }
			if state.fail_replace then return false, "simulated tc failure" end
			return true
		end,
		delete_filter = function(device, slot, direction)
			state.deletes[#state.deletes + 1] = { device = device, slot = slot, direction = direction }
			return true
		end,
		write_state = function(value)
			state.rules = value
			return true
		end,
		write_status = function(value)
			state.status = value
			return true
		end,
	}
	return state, deps
end

local function policy(upload, download)
	return {
		section = "qg_rate_01", slot = 1, name = "desktop",
		mac = "02:11:22:33:44:55", client_ip = "192.168.20.40",
		source_zone = "fiber-edge", destination_zone = "corp",
		upload_kbps = upload or "", download_kbps = download or "", enabled = "1",
	}
end

-- First reconciliation creates only clsact-based policers; it never touches
-- the root qdisc and publishes an explicit drop-excess status.
do
	local state, deps = fixture()
	local result, err = policing.reconcile({ policy("25000", "100000") }, inventory, {}, deps, 1790000000)
	assert(result, err)
	assert(result.ready and result.policing_mode == "drop_excess")
	assert(result.policy_count == 1 and result.applied_filter_count == 2)
	assert(state.rules and #state.rules == 2 and state.status == result)
	assert(#state.ensures == 1 and state.ensures[1] == "pppoe-wan")
	assert(#state.replaces == 2 and #state.deletes == 0)
	assert(state.replaces[1].command:find("parent ffff:fff3", 1, true) or state.replaces[2].command:find("parent ffff:fff3", 1, true))
	assert(result.notice:find("does not reserve bandwidth", 1, true))
end

-- Removing one direction deletes only the previously owned filter.
do
	local previous = {
		{ device="pppoe-wan", slot=1, direction="upload" },
		{ device="pppoe-wan", slot=1, direction="download" },
	}
	local state, deps = fixture()
	local result, err = policing.reconcile({ policy("25000", "") }, inventory, previous, deps, 1790000001)
	assert(result, err)
	assert(result.applied_filter_count == 1 and result.removed_filter_count == 1)
	assert(#state.deletes == 1 and state.deletes[1].direction == "download")
end

-- A truncated or unavailable inventory fails closed before any TC operation.
do
	local state, deps = fixture()
	local incomplete = {}
	for k, v in pairs(inventory) do incomplete[k] = v end
	incomplete.truncated = true
	local result = policing.reconcile({ policy("25000", "100000") }, incomplete, {}, deps, 1790000002)
	assert(result == nil)
	assert(#state.ensures == 0 and #state.replaces == 0 and #state.deletes == 0)
end

-- Invalid ownership state is not trusted to delete arbitrary filters.
do
	local state, deps = fixture()
	local result = policing.reconcile({ policy("25000", "") }, inventory, {
		{ device="eth;reboot", slot=1, direction="upload" },
	}, deps, 1790000003)
	assert(result == nil)
	assert(#state.ensures == 0 and #state.replaces == 0 and #state.deletes == 0)
end

-- Failure to persist ownership must never be reported as a ready policy.
do
	local state, deps = fixture()
	deps.write_state = function() return false, "read-only file system" end
	local result = policing.reconcile({ policy("25000", "") }, inventory, {}, deps, 1790000004)
	assert(result == nil)
	assert(state.status == nil)
end

print("client-policing-runtime: fail-closed inventory, filter reconciliation and status tests passed")