module("luci.quantumgrid.wireguard", package.seeall)

local MAX_PEERS = 64
local MAX_ALLOWED_IPS = 16
local MAX_COUNTER = 9007199254740991

local function safe_token(value, limit)
	if type(value) ~= "string" or #value == 0 or #value > (limit or 64) then
		return nil
	end
	if not value:match("^[%w_.:%-]+$") then return nil end
	return value
end

local function safe_network(value)
	if type(value) ~= "string" or #value == 0 or #value > 96 then return nil end
	if not value:match("^[%w_.:%-/%+]+$") then return nil end
	return value
end

local function bounded_integer(value, maximum)
	local number = tonumber(value)
	if not number or number < 0 or number > (maximum or MAX_COUNTER) then
		return nil
	end
	if number ~= math.floor(number) then return nil end
	return number
end

local function split_tabs(line)
	local fields = {}
	local start = 1
	while true do
		local position = line:find("\t", start, true)
		if not position then
			table.insert(fields, line:sub(start))
			break
		end
		table.insert(fields, line:sub(start, position - 1))
		start = position + 1
	end
	return fields
end

local function parse_allowed_ips(value)
	local result = {}
	for item in (type(value) == "string" and value or ""):gmatch("[^,]+") do
		if #result >= MAX_ALLOWED_IPS then break end
		local network = safe_network(item)
		if network then table.insert(result, network) end
	end
	table.sort(result)
	return result
end

function parse_dump(output, now)
	local result = { available = false, count = 0, truncated = false, peers = {} }
	if type(output) ~= "string" then return result end
	result.available = true
	now = bounded_integer(now, MAX_COUNTER) or os.time()

	for line in output:gmatch("[^\\r\\n]+") do
		local fields = split_tabs(line)
		-- wg(8) emits five fields for an interface header and nine for each peer.
		-- The private and preshared key columns are intentionally discarded.
		if #fields >= 9 then
			local interface = safe_token(fields[1], 32)
			local handshake = bounded_integer(fields[6], MAX_COUNTER)
			local rx_bytes = bounded_integer(fields[7], MAX_COUNTER)
			local tx_bytes = bounded_integer(fields[8], MAX_COUNTER)
			local peer = nil
			if interface and rx_bytes and tx_bytes then
				local handshake_age = nil
				if handshake and handshake > 0 and handshake <= now then
					handshake_age = now - handshake
				end
				peer = {
					interface = interface,
					handshake_age_seconds = handshake_age,
					handshake_seen = handshake ~= nil and handshake > 0 and handshake <= now,
					receive_bytes = rx_bytes,
					transmit_bytes = tx_bytes,
					allowed_ips = parse_allowed_ips(fields[5])
				}
			end
			if peer then
				result.count = result.count + 1
				if #result.peers < MAX_PEERS then
					table.insert(result.peers, peer)
				else
					result.truncated = true
				end
			end
		end
	end

	table.sort(result.peers, function(left, right)
		if left.interface ~= right.interface then return left.interface < right.interface end
		if left.handshake_age_seconds == nil then return false end
		if right.handshake_age_seconds == nil then return true end
		return left.handshake_age_seconds < right.handshake_age_seconds
	end)
	return result
end

