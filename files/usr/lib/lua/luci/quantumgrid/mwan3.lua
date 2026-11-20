module("luci.quantumgrid.mwan3", package.seeall)

local MAX_INTERFACES = 16
local MAX_TRACK_TARGETS = 8
local MAX_POLICIES = 16
local MAX_POLICY_MEMBERS = 16
local MAX_CONNECTED_NETWORKS = 64

local function safe_token(value, limit)
	if type(value) ~= "string" or #value == 0 or #value > (limit or 64) then
		return nil
	end
	if not value:match("^[%w_.:%-]+$") then return nil end
	return value
end

local function bounded_number(value, maximum)
	local number = tonumber(value)
	if not number or number < 0 or number > (maximum or 2147483647) then
		return nil
	end
	return number
end

local function safe_status(value, fallback)
	local status = safe_token(value, 24)
	return status and status:lower() or (fallback or "unknown")
end

local function safe_network(value)
	if type(value) ~= "string" or #value == 0 or #value > 96 then return nil end
	if not value:match("^[%w_.:%-/%+]+$") then return nil end
	return value
end

local function policy_inventory(response)
	local result = { available = false, count = 0, truncated = false, policies = {} }
	if type(response) ~= "table" or type(response.policies) ~= "table" then return result end
	result.available = true
	for _, family in ipairs({ { key = "ipv4", name = "IPv4" }, { key = "ipv6", name = "IPv6" } }) do
		local source = response.policies[family.key]
		if type(source) == "table" then
			local names = {}
			for name, members in pairs(source) do
				if type(name) == "string" and safe_token(name, 48) and type(members) == "table" then
					table.insert(names, name)
				end
			end
			table.sort(names)
			for _, name in ipairs(names) do
				result.count = result.count + 1
				if #result.policies >= MAX_POLICIES then
					result.truncated = true
					break
				end
				local members = {}
				for _, member in ipairs(source[name]) do
					if #members >= MAX_POLICY_MEMBERS then
						result.truncated = true
						break
					end
					if type(member) == "table" then
						local interface = safe_token(member.interface, 32)
						local percent = bounded_number(member.percent, 100)
						if interface and percent then
							table.insert(members, { interface = interface, percent = percent })
						end
					end
				end
				table.sort(members, function(left, right)
					if left.percent ~= right.percent then return left.percent > right.percent end
					return left.interface < right.interface
				end)
				table.insert(result.policies, { family = family.name, name = name, members = members })
			end
		end
	end
	return result
end

local function connected_inventory(response)
	local result = { available = false, ipv4 = {}, ipv6 = {}, truncated = false }
	if type(response) ~= "table" or type(response.connected) ~= "table" then return result end
	result.available = true
	for _, family in ipairs({ { key = "ipv4", target = result.ipv4 }, { key = "ipv6", target = result.ipv6 } }) do
		local source = response.connected[family.key]
		if type(source) == "table" then
			for _, network in ipairs(source) do
				if #family.target >= MAX_CONNECTED_NETWORKS then
					result.truncated = true
					break
				end
				local value = safe_network(network)
				if value then table.insert(family.target, value) end
			end
			table.sort(family.target)
		end
	end
	return result
end

function normalize_status(response, policies_response, connected_response)
	local result = {
		available = false, count = 0, truncated = false, interfaces = {},
		policies_available = false, policy_count = 0, policies = {},
		connected_available = false, connected_ipv4 = {}, connected_ipv6 = {}
	}
	local policy_data = policy_inventory(policies_response)
	local connected_data = connected_inventory(connected_response)
	result.policies_available = policy_data.available
	result.policy_count = policy_data.count
	result.policies = policy_data.policies
	result.connected_available = connected_data.available
	result.connected_ipv4 = connected_data.ipv4
	result.connected_ipv6 = connected_data.ipv6
	result.truncated = policy_data.truncated or connected_data.truncated
	if type(response) ~= "table" or type(response.interfaces) ~= "table" then
		return result
	end

	result.available = true
	for name, entry in pairs(response.interfaces) do
		if type(name) == "string" and safe_token(name, 32) and type(entry) == "table" then
			result.count = result.count + 1
			if #result.interfaces < MAX_INTERFACES then
				local interface = {
					name = name,
					enabled = entry.enabled == true,
					running = entry.running == true,
					up = entry.up == true,
					status = safe_status(entry.status),
					tracking = safe_status(entry.tracking),
					age_seconds = bounded_number(entry.age),
					online_seconds = bounded_number(entry.online),
					offline_seconds = bounded_number(entry.offline),
					interface_uptime_seconds = bounded_number(entry.uptime),
					score = bounded_number(entry.score, 1000000),
					lost = bounded_number(entry.lost, 1000000),
					turn = bounded_number(entry.turn, 1000000),
					track_targets = {}
				}
				local targets = type(entry.track_ip) == "table" and entry.track_ip or {}
				for _, target in ipairs(targets) do
					if #interface.track_targets >= MAX_TRACK_TARGETS then
						result.truncated = true
						break
					end
					if type(target) == "table" then
						local address = safe_token(target.ip, 64)
						if address then
							table.insert(interface.track_targets, {
								ip = address,
								status = safe_status(target.status),
								latency_ms = bounded_number(target.latency, 3600000),
								packet_loss_percent = bounded_number(target.packetloss, 100)
							})
						end
					end
				end
				table.sort(interface.track_targets, function(left, right)
					return left.ip < right.ip
				end)
				table.insert(result.interfaces, interface)
			else
				result.truncated = true
			end
		end
	end

	table.sort(result.interfaces, function(left, right)
		return left.name < right.name
	end)
	return result
end
