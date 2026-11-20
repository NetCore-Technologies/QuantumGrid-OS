module("luci.quantumgrid.mwan3", package.seeall)

local MAX_INTERFACES = 16
local MAX_TRACK_TARGETS = 8

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

function normalize_status(response)
	local result = { available = false, count = 0, truncated = false, interfaces = {} }
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
