module("luci.quantumgrid.routing", package.seeall)

local MAX_POLICY_RULES = 64

local function safe_token(value)
	if type(value) ~= "string" or #value == 0 or #value > 96 then
		return nil
	end
	if not value:match("^[%w_.:%-/%+]+$") then
		return nil
	end
	return value
end

local function selector_value(selectors, name, fallback)
	local value
	if name == "from" and selectors:match("^from%s+") then
		value = selectors:match("^from%s+(%S+)")
	else
		value = selectors:match("%s" .. name .. "%s+(%S+)")
	end
	return safe_token(value) or fallback
end

local function clean_selectors(value)
	return value:gsub("[%c]", " "):gsub("%s+", " "):sub(1, 192)
end

function parse_policy_rules(output, family)
	local rules = {}
	local count = 0
	local truncated = false
	if type(output) ~= "string" or (family ~= "IPv4" and family ~= "IPv6") then
		return rules, count, truncated
	end

	for line in output:gmatch("[^\r\n]+") do
		local priority_text, selectors = line:match("^%s*(%d+):%s*(.-)%s*$")
		local priority = tonumber(priority_text)
		if priority and priority >= 0 and priority <= 4294967295 and priority == math.floor(priority) then
			count = count + 1
			if #rules < MAX_POLICY_RULES then
				local table_name = selectors:match("%slookup%s+(%S+)") or selectors:match("%stable%s+(%S+)")
				table_name = safe_token(table_name) or ""
				local action = "lookup"
				if table_name == "" then
					action = selectors:match("%s(blackhole)%s*$")
						or selectors:match("%s(unreachable)%s*$")
						or selectors:match("%s(prohibit)%s*$")
						or selectors:match("%s(goto)%s+[%d]+%s*$")
						or "other"
				end

				table.insert(rules, {
					family = family,
					priority = priority,
					source = selector_value(selectors, "from", "all"),
					destination = selector_value(selectors, "to", "all"),
					fwmark = selector_value(selectors, "fwmark", ""),
					input_interface = selector_value(selectors, "iif", ""),
					output_interface = selector_value(selectors, "oif", ""),
					protocol = selector_value(selectors, "ipproto", ""),
					uid_range = selector_value(selectors, "uidrange", ""),
					table = table_name,
					action = action,
					selectors = clean_selectors(selectors)
				})
			else
				truncated = true
			end
		end
	end

	table.sort(rules, function(left, right)
		if left.priority ~= right.priority then
			return left.priority < right.priority
		end
		return left.selectors < right.selectors
	end)
	return rules, count, truncated
end

local function parse_ipv4(value)
	if type(value) ~= "string" or #value > 15 then return nil end
	local parts = {}
	for part in (value .. "."):gmatch("(.-)%.") do
		if #part < 1 or #part > 3 or not part:match("^%d+$") then return nil end
		if #part > 1 and part:sub(1, 1) == "0" then return nil end
		local octet = tonumber(part)
		if not octet or octet > 255 then return nil end
		table.insert(parts, octet)
	end
	if #parts ~= 4 then return nil end
	return parts[1] * 16777216 + parts[2] * 65536 + parts[3] * 256 + parts[4], parts
end

local function parse_ipv6(value)
	if type(value) ~= "string" or #value < 2 or #value > 39
		or not value:find(":", 1, true) or value:find("%", 1, true) then
		return nil
	end
	local compression = value:find("::", 1, true)
	local groups = {}
	local function append_side(side)
		if side == "" then return true end
		for group in (side .. ":"):gmatch("(.-):") do
			if #group < 1 or #group > 4 or not group:match("^[%x]+$") then
				return false
			end
			groups[#groups + 1] = tonumber(group, 16)
		end
		return true
	end
	if compression then
		if value:find("::", compression + 2, true) then return nil end
		local left = value:sub(1, compression - 1)
		local right = value:sub(compression + 2)
		if not append_side(left) then return nil end
		local left_groups = groups
		groups = {}
		if not append_side(right) then return nil end
		local right_groups = groups
		local zeros = 8 - #left_groups - #right_groups
		if zeros < 1 then return nil end
		local combined = {}
		for _, item in ipairs(left_groups) do combined[#combined + 1] = item end
		for _ = 1, zeros do combined[#combined + 1] = 0 end
		for _, item in ipairs(right_groups) do combined[#combined + 1] = item end
		groups = combined
	else
		if not append_side(value) or #groups ~= 8 then return nil end
	end
	if #groups ~= 8 then return nil end
	return groups
end

local function format_ipv6(groups)
	local result = {}
	for _, group in ipairs(groups) do result[#result + 1] = string.format("%x", group) end
	return table.concat(result, ":")
end

local function valid_ipv6_gateway(groups)
	if not groups then return false end
	local all_zero = true
	for _, group in ipairs(groups) do
		if group ~= 0 then all_zero = false break end
	end
	if all_zero or (groups[1] == 0 and groups[2] == 0 and groups[3] == 0
		and groups[4] == 0 and groups[5] == 0 and groups[6] == 0
		and groups[7] == 0 and groups[8] == 1) then
		return false
	end
	return groups[1] < 0xff00
end

local function parse_target(family, target)
	if type(target) ~= "string" or #target > 64 then return nil, "Route target must be a destination CIDR." end
	local address, prefix_text = target:match("^([^/]+)/(%d+)$")
	if not address or #prefix_text > 3 then return nil, "Route target must include an explicit network prefix." end
	local prefix = tonumber(prefix_text)
	if not prefix or prefix < 1 or prefix > (family == "IPv4" and 32 or 128) then
		return nil, "Route prefix must be between /1 and /" .. (family == "IPv4" and "32" or "128") .. "; default routes are managed separately."
	end
	if family == "IPv4" then
		local number, parts = parse_ipv4(address)
		if not number then return nil, "IPv4 route target must use canonical dotted-decimal notation." end
		if parts[1] == 0 or parts[1] == 127 or parts[1] >= 224 or
			(parts[1] == 169 and parts[2] == 254) then
			return nil, "IPv4 route target cannot be unspecified, loopback, link-local, multicast or reserved space."
		end
		local block = 2 ^ (32 - prefix)
		local first = math.floor(number / block) * block
		if first ~= number then return nil, "IPv4 route target must be the canonical network address for its prefix." end
		return { normalized = address .. "/" .. tostring(prefix), family = family, number = number, prefix = prefix }
	end
	if family ~= "IPv6" then return nil, "Route address family must be IPv4 or IPv6." end
	local groups = parse_ipv6(address)
	if not groups then return nil, "IPv6 route target must be a valid hexadecimal IPv6 address without a zone suffix." end
	if groups[1] == 0 or (groups[1] >= 0xfe80 and groups[1] <= 0xfebf) then
		return nil, "IPv6 route target cannot be unspecified, loopback or link-local space."
	end
	if groups[1] >= 0xff00 then return nil, "IPv6 multicast route targets are not supported." end
	local whole = math.floor(prefix / 16)
	local remainder = prefix % 16
	if remainder > 0 then
		local block = 2 ^ (16 - remainder)
		if groups[whole + 1] % block ~= 0 then
			return nil, "IPv6 route target must be the canonical network address for its prefix."
		end
	end
	local first_host = whole + (remainder > 0 and 2 or 1)
	for index = first_host, 8 do
		if groups[index] ~= 0 then return nil, "IPv6 route target must be the canonical network address for its prefix." end
	end
	return { normalized = format_ipv6(groups) .. "/" .. tostring(prefix), family = family, groups = groups, prefix = prefix }
end

function validate_static_route(family, interface, target, gateway, metric, table_id, interfaces, existing)
	if family ~= "IPv4" and family ~= "IPv6" then return nil, "Select IPv4 or IPv6 for the static route." end
	if type(interface) ~= "string" or #interface < 1 or #interface > 64
		or not interface:match("^[%w_.%-]+$") then
		return nil, "Select an existing network interface."
	end
	local interface_found = false
	for _, item in ipairs(type(interfaces) == "table" and interfaces or {}) do
		local name = type(item) == "table" and item.name or item
		if name == interface then interface_found = true break end
	end
	if not interface_found then return nil, "The selected network interface no longer exists." end

	local parsed_target, target_error = parse_target(family, target)
	if not parsed_target then return nil, target_error end
	if gateway == nil then gateway = "" end
	if type(gateway) ~= "string" or #gateway > 64 then return nil, "Route gateway is invalid." end
	if gateway ~= "" then
		if family == "IPv4" then
			local number, parts = parse_ipv4(gateway)
			if not number or parts[1] == 0 or parts[1] == 127 or
				(parts[1] == 169 and parts[2] == 254) or parts[1] >= 224 then
				return nil, "IPv4 gateway must be a canonical unicast address."
			end
		else
			local groups = parse_ipv6(gateway)
			if not valid_ipv6_gateway(groups) then return nil, "IPv6 gateway must be a valid unicast address." end
			gateway = format_ipv6(groups)
		end
	end

	local metric_number = nil
	if metric ~= nil and metric ~= "" then
		if type(metric) ~= "string" or #metric > 5 or not metric:match("^%d+$") then
			return nil, "Route metric must be a whole number from 0 to 65535."
		end
		metric_number = tonumber(metric)
		if not metric_number or metric_number > 65535 or tostring(metric_number) ~= metric then
			return nil, "Route metric must be a canonical whole number from 0 to 65535."
		end
	end

	local table_number = nil
	if table_id ~= nil and table_id ~= "" then
		if type(table_id) ~= "string" or #table_id > 5 or not table_id:match("^[1-9]%d*$") then
			return nil, "Custom route table must be a numeric ID from 1 to 252 or 254 (main)."
		end
		table_number = tonumber(table_id)
		if not table_number or (table_number > 252 and table_number ~= 254) then
			return nil, "Custom route table must be a numeric ID from 1 to 252 or 254 (main)."
		end
	end

	for _, route in ipairs(type(existing) == "table" and existing or {}) do
		if type(route) == "table" and route.family == family and
			tostring(route.table or "") == tostring(table_number or "") then
			local existing_target = parse_target(family, route.target)
			if existing_target and existing_target.normalized == parsed_target.normalized then
				return nil, "A route for this destination already exists in the selected routing table."
			end
		end
	end

	return {
		family = family,
		interface = interface,
		target = parsed_target.normalized,
		gateway = gateway,
		metric = metric_number,
		table = table_number and tostring(table_number) or "",
		route_type = family == "IPv4" and "route" or "route6"
	}
end

function static_route_contains_address(route, address)
	if type(route) ~= "table" or type(address) ~= "string" then return false end
	local parsed, err = parse_target(route.family, route.target)
	if not parsed then return false end
	if route.family == "IPv4" then
		local number = parse_ipv4(address)
		if not number then return false end
		local block = 2 ^ (32 - parsed.prefix)
		return math.floor(number / block) == math.floor(parsed.number / block)
	end
	local groups = parse_ipv6(address)
	if not groups then return false end
	local whole = math.floor(parsed.prefix / 16)
	for index = 1, whole do
		if groups[index] ~= parsed.groups[index] then return false end
	end
	local remainder = parsed.prefix % 16
	if remainder > 0 then
		local block = 2 ^ (16 - remainder)
		if math.floor(groups[whole + 1] / block) ~= math.floor(parsed.groups[whole + 1] / block) then
			return false
		end
	end
	return true
end

function snapshot_static_route_section(snapshot, expected_type)
	if type(snapshot) ~= "table" or (expected_type ~= "route" and expected_type ~= "route6")
		or snapshot[".type"] ~= expected_type or type(snapshot[".name"]) ~= "string"
		or snapshot[".name"] == "" then
		return nil, "A named static route section is required."
	end
	local values = {}
	for key, value in pairs(snapshot) do
		if type(key) == "string" and key:sub(1, 1) ~= "." then values[key] = value end
	end
	return { name = snapshot[".name"], values = values }
end
