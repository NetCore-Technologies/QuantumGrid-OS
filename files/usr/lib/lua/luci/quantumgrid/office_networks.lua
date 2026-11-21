module("luci.quantumgrid.office_networks", package.seeall)

local MAX_INTERFACES = 64
local MAX_BRIDGES = 32
local MAX_VLANS = 64
local MAX_ZONES = 32
local MAX_FORWARDINGS = 64
local MAX_APS = 32

local function clean(value, limit)
	if type(value) ~= "string" then return "" end
	return value:gsub("[%c]", " "):sub(1, limit or 128)
end

local function token(value, limit)
	local result = clean(value, limit or 64)
	if result == "" or not result:match("^[%w_.:%-]+$") then return nil end
	return result
end

local function values(value, limit)
	local result, seen = {}, {}
	local function add(item)
		local text = clean(item, 128)
		if text ~= "" and not seen[text] and #result < (limit or 16) then
			seen[text] = true
			table.insert(result, text)
		end
	end
	if type(value) == "string" then
		add(value)
	elseif type(value) == "table" then
		for _, item in ipairs(value) do
			if type(item) == "string" then add(item) end
		end
	end
	return result
end

local function contains(list, wanted)
	for _, value in ipairs(list or {}) do
		if value == wanted then return true end
	end
	return false
end

local function parse_port(value)
	if type(value) ~= "string" then return nil end
	local bare = value:match("^([%w_.%-]+)$")
	if bare then
		-- A mode suffix attached directly to a numbered switch port is malformed;
		-- require "lan3:u" / "lan3:t", never "lan3u" / "lan3t".
		if bare:match("%d[ut]$") then return nil end
		return { name = bare, mode = "unspecified", pvid = false }
	end
	-- A tagged member cannot carry the untagged/PVID marker. Reject it
	-- explicitly before parsing the normal tagged/untagged forms.
	if value:match("^[%w_.%-]+:t%*$") then return nil end
	local name, mode, primary = value:match("^([%w_.%-]+):([ut])(%*?)$")
	if not name or (mode == "t" and primary == "*") then return nil end
	return {
		name = name,
		mode = mode == "t" and "tagged" or "untagged",
		pvid = mode == "u" and primary == "*"
	}
end

local function parse_ipv6_address(value, allow_prefix)
	if type(value) ~= "string" or #value == 0 or #value > 64 then return nil end
	local address = value
	if allow_prefix then
		local raw, prefix = value:match("^([^/]+)/(%d+)$")
		if raw then
			local number = tonumber(prefix)
			if not number or number < 1 or number > 128 then return nil end
			address = raw
		elseif value:find("/", 1, true) then
			return nil
		end
	elseif value:find("/", 1, true) then
		return nil
	end
	if address:find("[^%x:]") or address:find("::: ", 1, true) or address:find(":::", 1, true) then
		return nil
	end
	local compression = address:find("::", 1, true)
	if compression and address:find("::", compression + 2, true) then return nil end
	local function parse_side(side)
		local groups = {}
		if side == "" then return groups end
		if side:sub(1, 1) == ":" or side:sub(-1) == ":" then return nil end
		for part in side:gmatch("[^:]+") do
			if #part < 1 or #part > 4 or not part:match("^%x+$") then return nil end
			groups[#groups + 1] = tonumber(part, 16)
		end
		return groups
	end
	local groups = {}
	if compression then
		local left = parse_side(address:sub(1, compression - 1))
		local right = parse_side(address:sub(compression + 2))
		if not left or not right or (#left + #right) >= 8 then return nil end
		for _, part in ipairs(left) do groups[#groups + 1] = part end
		for _ = 1, 8 - #left - #right do groups[#groups + 1] = 0 end
		for _, part in ipairs(right) do groups[#groups + 1] = part end
	else
		if address:sub(1, 1) == ":" or address:sub(-1) == ":" then return nil end
		local parsed = parse_side(address)
		if not parsed or #parsed ~= 8 then return nil end
		groups = parsed
	end
	if #groups ~= 8 then return nil end
	local canonical_parts = {}
	for _, part in ipairs(groups) do
		canonical_parts[#canonical_parts + 1] = string.format("%04x", part)
	end
	return { groups = groups, canonical = table.concat(canonical_parts, ":") }
end

local function global_unicast_ipv6(value, allow_prefix)
	local parsed = parse_ipv6_address(value, allow_prefix)
	if not parsed then return nil end
	local first, second = parsed.groups[1], parsed.groups[2]
	if first < 0x2000 or first > 0x3fff then return nil end
	-- Reject IANA special-purpose prefixes inside 2000::/3: 2001::/23 (including
	-- Teredo/benchmarking/ORCHID/documentation) and the 3fff::/20 documentation block.
	if first == 0x2001 and (second < 0x0200 or second == 0x0db8) then return nil end
	if first == 0x2002 then return nil end -- Deprecated 6to4 transition prefix.
	if first == 0x3fff and second < 0x1000 then return nil end
	return parsed.canonical
end

local function valid_unicast_neighbor_mac(value)
	if type(value) ~= "string"
		or not value:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") then
		return false
	end
	local first = tonumber(value:sub(1, 2), 16)
	return first ~= nil and first % 2 == 0 and value:lower() ~= "00:00:00:00:00:00"
end

function parse_ipv6_neighbor_inventory(contents, device)
	if type(contents) ~= "string" or #contents > 65536
		or type(device) ~= "string" or #device < 1 or #device > 64
		or not device:match("^[%w][%w_.%-]*$") then
		return {}
	end
	local allowed_states = {
		REACHABLE = true, STALE = true, DELAY = true,
		PROBE = true, PERMANENT = true
	}
	local result, seen = {}, {}
	for line in contents:gmatch("[^\r\n]+") do
		if #line <= 512 and #result < 64 then
			local raw_address, rest = line:match("^(%S+)%s+dev%s+(.+)$")
			local observed_device = rest and rest:match("^(%S+)")
			local mac = rest and rest:match("%slladdr%s+(%S+)")
			local state = rest and rest:match("%s(%u+)%s*$")
			local address = raw_address and global_unicast_ipv6(raw_address, false)
			if observed_device == device and address and mac
				and valid_unicast_neighbor_mac(mac) and allowed_states[state]
				and not seen[address] then
				seen[address] = true
				table.insert(result, {
					address = address,
					mac = mac:lower(),
					state = state
				})
			end
		end
	end
	table.sort(result, function(left, right) return left.address < right.address end)
	return result
end

local function valid_ipv4(value)
	if type(value) ~= "string" then return false end
	local a, b, c, d = value:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	if not a then return false end
	for _, part in ipairs({ a, b, c, d }) do
		local octet = tonumber(part)
		if not octet or octet < 0 or octet > 255 or octet ~= math.floor(octet) then
			return false
		end
	end
	return true
end

local function valid_mac(value)
	return type(value) == "string"
		and value:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") ~= nil
end

local function ipv4_number(value)
	if type(value) ~= "string" then return nil end
	local a, b, c, d = value:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	if not a then return nil end
	local octets = { tonumber(a), tonumber(b), tonumber(c), tonumber(d) }
	local parts = { a, b, c, d }
	for index, octet in ipairs(octets) do
		if not octet or octet < 0 or octet > 255 or octet ~= math.floor(octet)
			or tostring(octet) ~= parts[index] then
			return nil
		end
	end
	return octets[1] * 16777216 + octets[2] * 65536 + octets[3] * 256 + octets[4]
end

local function usable_ipv4_host(value)
	local address = ipv4_number(value)
	if not address then return false end
	local first = math.floor(address / 16777216)
	local second = math.floor(address / 65536) % 256
	if first == 0 or first == 127 or (first == 169 and second == 254) or first >= 224 then
		return false
	end
	return true
end

local function ipv4_text(address)
	if type(address) ~= "number" or address < 0 or address > 4294967295 then return nil end
	local a = math.floor(address / 16777216) % 256
	local b = math.floor(address / 65536) % 256
	local c = math.floor(address / 256) % 256
	local d = address % 256
	return table.concat({ a, b, c, d }, ".")
end

local function ipv4_prefix(netmask)
	local address = ipv4_number(netmask)
	if not address then return nil end
	local prefix, zero_seen = 0, false
	local octets = {
		math.floor(address / 16777216) % 256,
		math.floor(address / 65536) % 256,
		math.floor(address / 256) % 256,
		address % 256
	}
	local bit_counts = { [255] = 8, [254] = 7, [252] = 6, [248] = 5, [240] = 4, [224] = 3, [192] = 2, [128] = 1, [0] = 0 }
	for _, octet in ipairs(octets) do
		local count = bit_counts[octet]
		if count == nil or (zero_seen and count ~= 0) then return nil end
		if count < 8 then zero_seen = true end
		prefix = prefix + count
	end
	if prefix < 1 or prefix > 30 then return nil end
	return prefix
end

function validate_reservation_section(section)
	if type(section) ~= "string" or #section < 1 or #section > 64
		or not section:match("^[A-Za-z0-9_.%-]+$") or section == "." or section == ".." then
		return nil, "The DHCP reservation section identifier is invalid."
	end
	return section
end

function validate_reservation_confirmation(value)
	if value ~= "1" then
		return nil, "Explicit confirmation is required before changing DHCP configuration."
	end
	return true
end

function validate_reservation(name, mac, ipv4)
	if type(name) ~= "string" or #name < 1 or #name > 63
		or not name:match("^[A-Za-z0-9][A-Za-z0-9%-]*$") then
		return nil, "Host name must be 1–63 letters, digits or hyphens and start with a letter or digit."
	end
	if not valid_mac(mac) then
		return nil, "A six-octet MAC address is required."
	end
	local normalized_mac = mac:lower()
	local first_octet = tonumber(normalized_mac:sub(1, 2), 16)
	if first_octet % 2 ~= 0 or normalized_mac == "00:00:00:00:00:00"
		or normalized_mac == "ff:ff:ff:ff:ff:ff" then
		return nil, "A unicast, non-zero MAC address is required."
	end
	local ip_number = ipv4_number(ipv4)
	if not ip_number then
		return nil, "A valid dotted-decimal IPv4 address is required."
	end
	local first_octet_ip = math.floor(ip_number / 16777216)
	if first_octet_ip == 0 or first_octet_ip == 127 or first_octet_ip == 169 and math.floor(ip_number / 65536) % 256 == 254
		or first_octet_ip == 255 or first_octet_ip >= 224 then
		return nil, "The IPv4 address must be a usable unicast host address."
	end
	return { name = name, mac = normalized_mac, ipv4 = ipv4, ipv4_number = ip_number }
end

function snapshot_dhcp_scope_section(snapshot)
	if type(snapshot) ~= "table" or snapshot[".type"] ~= "dhcp"
		or type(snapshot[".name"]) ~= "string" then
		return nil, "A named DHCP server section is required."
	end
	local values = {}
	for key, value in pairs(snapshot) do
		if type(key) == "string" and key:sub(1, 1) ~= "." then
			values[key] = value
		end
	end
	return {
		name = snapshot[".name"],
		values = values
	}
end

function snapshot_dhcp_scope_enabled(snapshot)
	if type(snapshot) ~= "table" or snapshot[".type"] ~= "dhcp" then
		return nil, "A DHCP scope snapshot is required."
	end
	return {
		ignore_present = snapshot.ignore ~= nil,
		ignore_value = snapshot.ignore,
		enabled = snapshot.ignore ~= "1"
	}
end

function validate_dhcp_scope_ipv6_modes(dhcpv6, ra, ndp)
	local dhcpv6_modes = { UNCHANGED = true, disabled = true, server = true }
	local ra_modes = { UNCHANGED = true, disabled = true, server = true }
	local ndp_modes = { UNCHANGED = true, disabled = true }
	if type(dhcpv6) ~= "string" or not dhcpv6_modes[dhcpv6] then
		return nil, "DHCPv6 mode must be unchanged, disabled or server. Relay/hybrid requires an odhcpd master topology configured in native LuCI."
	end
	if type(ra) ~= "string" or not ra_modes[ra] then
		return nil, "Router Advertisement mode must be unchanged, disabled or server. Relay/hybrid requires an odhcpd master topology configured in native LuCI."
	end
	if type(ndp) ~= "string" or not ndp_modes[ndp] then
		return nil, "NDP mode must be unchanged or disabled. Relay/hybrid requires an odhcpd master topology configured in native LuCI."
	end
	return { dhcpv6 = dhcpv6, ra = ra, ndp = ndp }
end

function validate_dhcp_scope_ipv6_advanced(
	ra_flags, ra_slaac, ra_dns, ra_preference, ra_lifetime,
	dhcpv6_na, dhcpv6_pd, dhcpv6_assignall, dhcpv6_pd_min_len)
	local valid_flags = {
		UNCHANGED = true,
		none = true,
		["other-config"] = true,
		["managed-config"] = true,
		["managed-config+other-config"] = true
	}
	if type(ra_flags) ~= "string" or not valid_flags[ra_flags] then
		return nil, "RA flags must be unchanged, none, other-config, managed-config or managed-config+other-config."
	end
	local function valid_toggle(value, name)
		if value ~= "UNCHANGED" and value ~= "0" and value ~= "1" then
			return nil, name .. " must be unchanged, enabled or disabled."
		end
		return value
	end
	local toggles = {
		{ ra_slaac, "RA SLAAC" },
		{ ra_dns, "RA DNS" },
		{ dhcpv6_na, "DHCPv6 IA_NA" },
		{ dhcpv6_pd, "DHCPv6 prefix delegation" },
		{ dhcpv6_assignall, "DHCPv6 assign-all" }
	}
	for _, entry in ipairs(toggles) do
		local value, err = valid_toggle(entry[1], entry[2])
		if not value then return nil, err end
	end
	local preferences = { UNCHANGED = true, low = true, medium = true, high = true }
	if type(ra_preference) ~= "string" or not preferences[ra_preference] then
		return nil, "RA route preference must be unchanged, low, medium or high."
	end
	if type(ra_lifetime) ~= "string" then
		return nil, "RA lifetime must be a whole number from 0 to 2700 seconds or unchanged."
	end
	if ra_lifetime ~= "UNCHANGED" then
		if #ra_lifetime > 4 or not ra_lifetime:match("^%d+$") then
			return nil, "RA lifetime must be a whole number from 0 to 2700 seconds or unchanged."
		end
		local lifetime = tonumber(ra_lifetime)
		if not lifetime or lifetime < 0 or lifetime > 2700 then
			return nil, "RA lifetime must be a whole number from 0 to 2700 seconds or unchanged."
		end
	end
	if type(dhcpv6_pd_min_len) ~= "string" then
		return nil, "Minimum delegated IPv6 prefix length must be unchanged or a whole number from 1 to 64."
	end
	if dhcpv6_pd_min_len ~= "UNCHANGED" then
		if #dhcpv6_pd_min_len > 2 or not dhcpv6_pd_min_len:match("^[1-9]%d?$") then
			return nil, "Minimum delegated IPv6 prefix length must be unchanged or a whole number from 1 to 64."
		end
		local prefix_length = tonumber(dhcpv6_pd_min_len)
		if not prefix_length or prefix_length < 1 or prefix_length > 64 then
			return nil, "Minimum delegated IPv6 prefix length must be unchanged or a whole number from 1 to 64."
		end
	end
	return {
		ra_flags = ra_flags,
		ra_slaac = ra_slaac,
		ra_dns = ra_dns,
		ra_preference = ra_preference,
		ra_lifetime = ra_lifetime,
		dhcpv6_na = dhcpv6_na,
		dhcpv6_pd = dhcpv6_pd,
		dhcpv6_assignall = dhcpv6_assignall,
		dhcpv6_pd_min_len = dhcpv6_pd_min_len
	}
end

function snapshot_dhcp_scope_options(snapshot)
	if type(snapshot) ~= "table" or snapshot[".type"] ~= "dhcp" then
		return nil, "A DHCP scope snapshot is required."
	end
	local result = {}
	for _, name in ipairs({ "start", "limit", "leasetime", "dhcpv6", "ra", "ndp", "ra_flags", "ra_slaac", "ra_dns", "ra_preference", "ra_lifetime", "dhcpv6_na", "dhcpv6_pd", "dhcpv6_assignall", "dhcpv6_pd_min_len" }) do
		local value = snapshot[name]
		table.insert(result, {
			name = name,
			present = value ~= nil,
			value = value
		})
	end
	return result
end

function snapshot_dhcp_host_options(snapshot)
	if type(snapshot) ~= "table" or snapshot[".type"] ~= "host" then
		return nil, "A static DHCP host snapshot is required."
	end
	local result = {}
	for _, name in ipairs({ "name", "mac", "ip" }) do
		local value = snapshot[name]
		table.insert(result, {
			name = name,
			present = value ~= nil,
			value = value
		})
	end
	return result
end

function validate_dhcp_pool_range(start_value, limit_value, interface_address, netmask, other_ranges)
	if type(start_value) ~= "string" or #start_value > 10
		or not start_value:match("^[1-9]%d*$") then
		return nil, "DHCP start must be a positive whole-number offset."
	end
	if type(limit_value) ~= "string" or #limit_value > 10
		or not limit_value:match("^[1-9]%d*$") then
		return nil, "DHCP limit must be a positive whole-number pool size."
	end
	local start = tonumber(start_value)
	local limit = tonumber(limit_value)
	if not start or not limit or start > 4294967294 or limit > 4294967294 then
		return nil, "DHCP offset or pool size exceeds the supported IPv4 range."
	end

	local router = ipv4_number(interface_address)
	local prefix = ipv4_prefix(netmask)
	if not router or not prefix then
		return nil, "A valid static IPv4 address and contiguous subnet mask are required."
	end
	local size = 2 ^ (32 - prefix)
	local network = math.floor(router / size) * size
	local broadcast = network + size - 1
	local first = network + start
	local last = first + limit - 1
	if first <= network or last >= broadcast then
		return nil, "The new DHCP pool would extend outside usable host addresses in the subnet."
	end
	if router >= first and router <= last then
		return nil, "The new DHCP pool would include the router interface address."
	end

	if type(other_ranges) == "table" then
		for _, range in ipairs(other_ranges) do
			if type(range) == "table" then
				local other_first = ipv4_number(range.start)
				local other_last = ipv4_number(range.finish)
				if other_first and other_last and first <= other_last and other_first <= last then
					return nil, "The new DHCP pool overlaps another enabled DHCP scope."
				end
			end
		end
	end

	return {
		start = tostring(start),
		limit = tostring(limit),
		pool_start_ip = ipv4_text(first),
		pool_end_ip = ipv4_text(last),
		first = first,
		last = last
	}
end

function validate_dhcp_scope_update(start_value, limit_value, lease_time, interface_address, netmask, other_ranges)
	if type(lease_time) ~= "string" or #lease_time > 16 then
		return nil, "DHCP lease time must be between 60 seconds and 365 days."
	end
	local amount, unit = lease_time:match("^([1-9]%d*)([smhdw]?)$")
	amount = tonumber(amount)
	local multiplier = ({ [""] = 1, s = 1, m = 60, h = 3600, d = 86400, w = 604800 })[unit or ""]
	if not amount or not multiplier then
		return nil, "Lease time must use seconds, minutes, hours, days or weeks (for example 12h)."
	end
	local seconds = amount * multiplier
	if seconds < 60 or seconds > 31536000 then
		return nil, "DHCP lease time must be between 60 seconds and 365 days."
	end

	local pool, pool_error = validate_dhcp_pool_range(
		start_value, limit_value, interface_address, netmask, other_ranges)
	if not pool then return nil, pool_error end
	pool.lease_time = lease_time
	pool.lease_seconds = seconds
	return pool
end

function live_lease_conflict(contents, address, mac)
	if type(contents) ~= "string" or type(address) ~= "string" or type(mac) ~= "string" then
		return false
	end
	local wanted_mac = mac:lower()
	for line in contents:gmatch("[^\r\n]+") do
		local _, lease_mac, lease_ip = line:match("^(%S+)%s+(%x%x:%x%x:%x%x:%x%x:%x%x:%x%x)%s+(%d+%.%d+%.%d+%.%d+)%s")
		if lease_ip == address and lease_mac and lease_mac:lower() ~= wanted_mac then
			return true
		end
	end
	return false
end

function ipv4_in_subnet(address, interface_address, netmask)
	local host = ipv4_number(address)
	local router = ipv4_number(interface_address)
	local prefix = ipv4_prefix(netmask)
	if not host or not router or not prefix then return false end
	local size = 2 ^ (32 - prefix)
	local host_network = math.floor(host / size) * size
	local router_network = math.floor(router / size) * size
	return host_network == router_network and host ~= router
		and host > host_network and host < host_network + size - 1
end

local function parse_vlan_id(value)
	local id = tonumber(value)
	if not id or id ~= math.floor(id) or id < 1 or id > 4094 then return nil end
	return id
end

local function network_device_vlan(device)
	if type(device) ~= "string" then return nil, nil end
	local bridge, vlan = device:match("^([%w_.%-]+)%.(%d+)$")
	local id = parse_vlan_id(vlan)
	if bridge and id then return bridge, id end
	return nil, nil
end

local function parse_bridge_ports(value)
	local result = {}
	if type(value) == "string" then
		for item in value:gmatch("%S+") do table.insert(result, item) end
	elseif type(value) == "table" then
		for _, item in ipairs(value) do
			if type(item) ~= "string" then return nil, "Bridge port membership entries must be strings." end
			table.insert(result, item)
		end
	else
		return nil, "At least one explicit bridge port membership is required."
	end
	if #result < 1 or #result > 32 then
		return nil, "A bridge VLAN must contain between 1 and 32 explicit port memberships."
	end
	return result
end

local EXTERNAL_ZONE_NAMES = {
	wan = true,
	wan6 = true,
	wwan = true,
	cellular = true,
}

local function zone_networks(value)
	local result = {}
	if type(value) == "string" then
		result[1] = value
	elseif type(value) == "table" then
		for _, item in ipairs(value) do
			if type(item) == "string" then table.insert(result, item) end
		end
	end
	return result
end

local function is_external_zone(zone)
	if type(zone) ~= "table" then return false end
	local name = type(zone.name) == "string" and zone.name:lower() or ""
	if EXTERNAL_ZONE_NAMES[name] then return true end
	for _, network in ipairs(zone_networks(zone.networks)) do
		if EXTERNAL_ZONE_NAMES[network:lower()] then return true end
	end
	return false
end

function validate_radius_dynamic_vlan_mappings(mappings, interfaces, bridges, vlans, zones)
	if type(mappings) ~= "table" or #mappings < 1 or #mappings > 16 then
		return nil, "RADIUS dynamic VLAN requires between 1 and 16 explicit VLAN-to-network mappings."
	end

	local result, seen_vids, seen_networks = {}, {}, {}
	for index, mapping in ipairs(mappings) do
		if type(mapping) ~= "table" then
			return nil, "RADIUS VLAN mapping " .. tostring(index) .. " must be an object."
		end
		local vid = mapping.vid
		if type(vid) == "number" then vid = tostring(vid) end
		if type(vid) ~= "string" or #vid > 4 or not vid:match("^[1-9]%d*$") then
			return nil, "Every RADIUS VLAN ID must be a whole number from 1 to 4094."
		end
		local numeric_vid = tonumber(vid)
		if not numeric_vid or numeric_vid < 1 or numeric_vid > 4094 then
			return nil, "Every RADIUS VLAN ID must be a whole number from 1 to 4094."
		end
		if seen_vids[numeric_vid] then
			return nil, "Each RADIUS VLAN ID may be mapped only once per SSID."
		end
		seen_vids[numeric_vid] = true

		local network = mapping.network
		if type(network) ~= "string" or #network < 1 or #network > 64
			or not network:match("^[%w_.%-]+$") or network == "." or network == ".." then
			return nil, "Each RADIUS VLAN must map to one existing office network interface."
		end
		if seen_networks[network] then
			return nil, "Each RADIUS VLAN must map to a different routed network interface."
		end
		seen_networks[network] = true

		local binding, binding_error = validate_wireless_network_binding(network, interfaces, zones)
		if not binding then return nil, binding_error end
		local gateway_available = false
		for _, gateway in ipairs(type(binding.ipv4) == "table" and binding.ipv4 or {}) do
			if usable_ipv4_host(gateway) then
				gateway_available = true
				break
			end
		end
		if not gateway_available then
			return nil, "RADIUS VLAN " .. tostring(numeric_vid) ..
				" must map to an existing routed IPv4 office segment with a valid unicast gateway address."
		end
		local parent_bridge, device_vid = binding.device:match("^(.-)%.(%d+)$")
		if not parent_bridge or tonumber(device_vid) ~= numeric_vid then
			return nil, "RADIUS VLAN " .. tostring(numeric_vid) ..
				" must map to an existing routed interface whose device is <bridge>." .. tostring(numeric_vid) .. "."
		end
		local bridge_found = false
		for _, bridge in ipairs(type(bridges) == "table" and bridges or {}) do
			if type(bridge) == "table" and bridge.name == parent_bridge and bridge.vlan_filtering == true then
				bridge_found = true
				break
			end
		end
		if not bridge_found then
			return nil, "RADIUS VLAN " .. tostring(numeric_vid) ..
				" must use an existing bridge with VLAN filtering enabled."
		end
		local vlan_found = false
		for _, vlan in ipairs(type(vlans) == "table" and vlans or {}) do
			if type(vlan) == "table" and vlan.device == parent_bridge
				and tonumber(vlan.vlan_id) == numeric_vid
				and type(vlan.ports) == "table" and #vlan.ports > 0 then
				vlan_found = true
				break
			end
		end
		if not vlan_found then
			return nil, "RADIUS VLAN " .. tostring(numeric_vid) ..
				" has no existing bridge-VLAN section with explicit switch-port membership."
		end
		local zone = nil
		for _, candidate in ipairs(type(zones) == "table" and zones or {}) do
			if type(candidate) == "table" and candidate.section == binding.zone_section then
				zone = candidate
				break
			end
		end
		if not zone or (zone.input ~= "REJECT" and zone.input ~= "DROP")
			or (zone.forward ~= "REJECT" and zone.forward ~= "DROP") then
			return nil, "RADIUS VLAN " .. tostring(numeric_vid) ..
				" must use an internal firewall zone with router INPUT and inter-zone FORWARD default-deny."
		end

		result[#result + 1] = {
			vid = tostring(numeric_vid),
			network = network,
			device = binding.device,
			bridge = parent_bridge,
			zone = binding.zone_name,
			name = "qg" .. tostring(numeric_vid)
		}
	end

	table.sort(result, function(left, right) return tonumber(left.vid) < tonumber(right.vid) end)
	return result
end

function validate_wireless_network_binding(network_name, interfaces, zones)
	if type(network_name) ~= "string" or #network_name < 1 or #network_name > 64
		or not network_name:match("^[%w_.%-]+$") or network_name == "." or network_name == ".." then
		return nil, "Select one existing routed network interface."
	end

	local selected_interface = nil
	for _, iface in ipairs(type(interfaces) == "table" and interfaces or {}) do
		if type(iface) == "table" and iface.name == network_name then
			if selected_interface then
				return nil, "The selected network interface is ambiguous in the current inventory."
			end
			selected_interface = iface
		end
	end
	if not selected_interface then
		return nil, "The selected network interface does not exist."
	end
	if selected_interface.protocol ~= "static" or type(selected_interface.device) ~= "string"
		or not selected_interface.device:match("^[%w_.%-]+$") then
		return nil, "SSID VLAN binding requires an existing static L3 network with a validated device."
	end

	local selected_zone = nil
	for _, zone in ipairs(type(zones) == "table" and zones or {}) do
		if type(zone) == "table" then
			local attached = false
			for _, item in ipairs(zone_networks(zone.networks)) do
				if item == network_name then attached = true break end
			end
			if attached then
				if selected_zone then
					return nil, "The network belongs to multiple firewall zones; resolve the ambiguous zone mapping before binding an SSID."
				end
				selected_zone = zone
			end
		end
	end
	if not selected_zone then
		return nil, "The selected network must belong to an existing firewall zone before an SSID can be bound to it."
	end
	if is_external_zone(selected_zone) then
		return nil, "An AP SSID cannot be bridged directly into an external WAN/WWAN firewall zone."
	end
	if type(selected_zone.section) ~= "string" or selected_zone.section == ""
		or type(selected_zone.name) ~= "string" or selected_zone.name == "" then
		return nil, "The selected network's firewall-zone mapping is incomplete."
	end

	return {
		network = network_name,
		device = selected_interface.device,
		ipv4 = zone_networks(selected_interface.ipv4),
		zone_section = selected_zone.section,
		zone_name = selected_zone.name
	}
end

local ALLOWED_ZONE_POLICIES = {
	ACCEPT = true,
	REJECT = true,
	DROP = true,
}

local function valid_zone_policy_choice(value)
	return value == "UNCHANGED" or value == "INHERIT" or ALLOWED_ZONE_POLICIES[value] == true
end

local function port_number(value, label)
	if type(value) ~= "string" or #value > 5 or not value:match("^%d+$") then
		return nil, label .. " must be a whole number from 1 to 65535."
	end
	local port = tonumber(value)
	if not port or port < 1 or port > 65535 then
		return nil, label .. " must be a whole number from 1 to 65535."
	end
	return tostring(port)
end

local function protocol_set(value)
	if value == "tcp" then return { tcp = true } end
	if value == "udp" then return { udp = true } end
	if value == "tcp udp" then return { tcp = true, udp = true } end
	return nil
end

function validate_office_vlan_segment(
	section, zone_name, bridge_name, vlan_id, address, netmask,
	dhcp_start, dhcp_limit, lease_time, interfaces, bridges, vlans, zones, dhcp_ranges)
	local function valid_section(value, label)
		if type(value) ~= "string" or #value < 1 or #value > 32
			or not value:match("^[A-Za-z][A-Za-z0-9_%-]*$") then
				return nil, label .. " must start with a letter and contain only letters, digits, underscores or hyphens."
		end
		return value
	end
	local valid_name, name_error = valid_section(section, "Network section name")
	if not valid_name then return nil, name_error end
	local valid_zone, zone_error = valid_section(zone_name, "Firewall zone name")
	if not valid_zone then return nil, zone_error end
	local vid = tonumber(vlan_id)
	if type(vlan_id) ~= "string" or not vlan_id:match("^%d+$")
		or not vid or vid < 1 or vid > 4094 then
		return nil, "A VLAN ID from 1 to 4094 is required."
	end
	if type(bridge_name) ~= "string" or #bridge_name < 1 or #bridge_name > 64
		or not bridge_name:match("^[%w_.%-]+$") then
		return nil, "Select an existing VLAN-filtered bridge."
	end
	local filtering = false
	for _, bridge in ipairs(type(bridges) == "table" and bridges or {}) do
		if type(bridge) == "table" and bridge.name == bridge_name then
			filtering = bridge.vlan_filtering == true
			break
		end
	end
	if not filtering then
		return nil, "The selected bridge must already have VLAN filtering enabled."
	end
	local vlan_found = false
	for _, vlan in ipairs(type(vlans) == "table" and vlans or {}) do
		if type(vlan) == "table" and vlan.device == bridge_name and tonumber(vlan.vlan_id) == vid then
			vlan_found = true
			break
		end
	end
	if not vlan_found then
		return nil, "The selected bridge VLAN must already exist before a Layer-3 interface can be created."
	end
	for _, iface in ipairs(type(interfaces) == "table" and interfaces or {}) do
		if type(iface) == "table" and iface.name == valid_name then
			return nil, "A network interface with this section name already exists."
		end
	end
	for _, zone in ipairs(type(zones) == "table" and zones or {}) do
		if type(zone) == "table" and zone.name == valid_zone then
			return nil, "A firewall zone with this name already exists."
		end
	end
	if not valid_ipv4(address) then
		return nil, "A valid static IPv4 gateway address is required."
	end
	local router = ipv4_number(address)
	local prefix = ipv4_prefix(netmask)
	if not router or not prefix then
		return nil, "The subnet mask must be contiguous and between /1 and /30."
	end
	local size = 2 ^ (32 - prefix)
	local network_address = math.floor(router / size) * size
	local broadcast = network_address + size - 1
	if router <= network_address or router >= broadcast then
		return nil, "The router IPv4 address must be a usable host address, not the subnet or broadcast address."
	end
	for _, iface in ipairs(type(interfaces) == "table" and interfaces or {}) do
		local other_addresses = values(iface.ipv4, 8)
		for _, other_address in ipairs(other_addresses) do
			local other_router = ipv4_number(other_address)
			local other_prefix = ipv4_prefix(iface.netmask)
			if other_router and other_prefix then
				local other_size = 2 ^ (32 - other_prefix)
				local other_first = math.floor(other_router / other_size) * other_size
				local other_last = other_first + other_size - 1
				if network_address <= other_last and other_first <= broadcast then
					return nil, "The new office subnet overlaps an existing interface subnet."
				end
			end
		end
	end
	local pool, pool_error = validate_dhcp_scope_update(
		dhcp_start, dhcp_limit, lease_time, address, netmask, dhcp_ranges)
	if not pool then return nil, pool_error end
	return {
		section = valid_name,
		zone_name = valid_zone,
		bridge = bridge_name,
		vlan_id = tostring(vid),
		device = bridge_name .. "." .. tostring(vid),
		address = address,
		netmask = netmask,
		start = pool.start,
		limit = pool.limit,
		lease_time = pool.lease_time,
		pool_start_ip = pool.pool_start_ip,
		pool_end_ip = pool.pool_end_ip
	}
end

function validate_office_port_forward(
	name, source, destination, protocol, source_port, destination_ip, destination_port,
	zones, interfaces, existing)
	if type(name) ~= "string" or #name < 1 or #name > 64
		or not name:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$") then
		return nil, "Rule name must be 1–64 letters, digits, dots, underscores or hyphens and start with a letter or digit."
	end
	if type(source) ~= "string" or #source > 64 or not source:match("^[%w_.%-]+$") then
		return nil, "Select an existing external source firewall zone."
	end
	if type(destination) ~= "string" or #destination > 64 or not destination:match("^[%w_.%-]+$") then
		return nil, "Select an existing internal destination firewall zone."
	end
	if source == destination then return nil, "Source and destination zones must be different." end
	local source_zone, destination_zone
	for _, zone in ipairs(type(zones) == "table" and zones or {}) do
		if type(zone) == "table" then
			if zone.name == source then source_zone = zone end
			if zone.name == destination then destination_zone = zone end
		end
	end
	if not source_zone or not destination_zone then
		return nil, "Both firewall zones must already exist in the current configuration."
	end
	if not is_external_zone(source_zone) then
		return nil, "Port forwarding must originate from an external WAN/WWAN firewall zone."
	end
	if is_external_zone(destination_zone) then
		return nil, "The port-forward destination must be an internal LAN/office firewall zone."
	end
	local protocols = protocol_set(protocol)
	if not protocols then return nil, "Protocol must be TCP, UDP or TCP + UDP." end
	local external_port, external_error = port_number(source_port, "External port")
	if not external_port then return nil, external_error end
	local internal_port, internal_error = port_number(destination_port, "Destination port")
	if not internal_port then return nil, internal_error end
	if not valid_ipv4(destination_ip) then
		return nil, "Destination must be a valid IPv4 address inside the selected LAN/VLAN subnet."
	end
	local in_destination_subnet = false
	for _, iface in ipairs(type(interfaces) == "table" and interfaces or {}) do
		if type(iface) == "table" and contains(zone_networks(destination_zone.networks), iface.name) then
			for _, address in ipairs(values(iface.ipv4, 8)) do
				if ipv4_in_subnet(destination_ip, address, iface.netmask) then
					in_destination_subnet = true
					break
				end
			end
		end
		if in_destination_subnet then break end
	end
	if not in_destination_subnet then
		return nil, "Destination IPv4 address must be a usable host inside a static subnet attached to the selected destination firewall zone."
	end
	for _, redirect in ipairs(type(existing) == "table" and existing or {}) do
		if type(redirect) == "table" and redirect.source == source
			and redirect.source_port == external_port then
			local existing_protocols = protocol_set(redirect.protocol)
			if existing_protocols and
				((protocols.tcp and existing_protocols.tcp) or (protocols.udp and existing_protocols.udp)) then
				return nil, "An existing port-forward rule already uses this external port/protocol on the selected WAN zone."
			end
		end
		if type(redirect) == "table" and redirect.name == name then
			return nil, "A port-forward rule with this name already exists."
		end
	end
	return {
		name = name,
		source = source,
		destination = destination,
		protocol = protocol,
		source_port = external_port,
		destination_ip = destination_ip,
		destination_port = internal_port
	}
end

function validate_office_ipv6_pinhole(
	name, source, destination, protocol, destination_ip, destination_port,
	zones, interfaces, existing)
	if type(name) ~= "string" or #name < 1 or #name > 64
		or not name:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$") then
		return nil, "Rule name must be 1–64 letters, digits, dots, underscores or hyphens and start with a letter or digit."
	end
	if type(source) ~= "string" or #source > 64 or not source:match("^[%w_.%-]+$") then
		return nil, "Select an existing external source firewall zone."
	end
	if type(destination) ~= "string" or #destination > 64 or not destination:match("^[%w_.%-]+$") then
		return nil, "Select an existing internal destination firewall zone."
	end
	if source == destination then return nil, "Source and destination zones must be different." end
	local source_zone, destination_zone
	for _, zone in ipairs(type(zones) == "table" and zones or {}) do
		if type(zone) == "table" then
			if zone.name == source then source_zone = zone end
			if zone.name == destination then destination_zone = zone end
		end
	end
	if not source_zone or not destination_zone then
		return nil, "Both firewall zones must already exist in the current configuration."
	end
	if not is_external_zone(source_zone) then
		return nil, "An IPv6 pinhole must originate from an external WAN/WWAN zone."
	end
	if is_external_zone(destination_zone) then
		return nil, "The IPv6 pinhole destination must be an internal LAN/office firewall zone."
	end
	local protocols = protocol_set(protocol)
	if not protocols then return nil, "Protocol must be TCP, UDP or TCP + UDP." end
	local port, port_error = port_number(destination_port, "Destination port")
	if not port then return nil, port_error end
	local canonical_ip = global_unicast_ipv6(destination_ip, false)
	if not canonical_ip then
		return nil, "Destination must be a global-unicast IPv6 address (2000::/3), not a private, link-local, multicast, documentation or unspecified address."
	end
	local observed = false
	local destination_networks = zone_networks(destination_zone.networks)
	for _, iface in ipairs(type(interfaces) == "table" and interfaces or {}) do
		-- A neighbour retained on a down interface (or attached to an invalid
		-- device identifier) must never authorize an Internet-facing pinhole.
		-- The controller only collects NDP data for an active kernel L3 device;
		-- enforce that invariant again at the policy boundary.
		local live_device = type(iface) == "table" and iface.up == true
			and type(iface.device) == "string" and #iface.device <= 64
			and iface.device:match("^[%w][%w_.%-]*$") ~= nil
		if live_device and contains(destination_networks, iface.name) then
			for _, neighbor in ipairs(type(iface.ipv6_neighbors) == "table" and iface.ipv6_neighbors or {}) do
				if type(neighbor) == "table"
					and global_unicast_ipv6(neighbor.address, false) == canonical_ip
					and valid_unicast_neighbor_mac(neighbor.mac)
					and ({ REACHABLE = true, STALE = true, DELAY = true, PROBE = true, PERMANENT = true })[neighbor.state] then
					observed = true
					break
				end
			end
		end
		if observed then break end
	end
	if not observed then
		return nil, "Destination must be a currently observed global-unicast NDP neighbour with a valid unicast MAC on an interface attached to the selected internal zone."
	end
	for _, pinhole in ipairs(type(existing) == "table" and existing or {}) do
		if type(pinhole) == "table" and pinhole.source == source
			and pinhole.destination_ip and global_unicast_ipv6(pinhole.destination_ip, false) == canonical_ip
			and tonumber(pinhole.destination_port) == tonumber(port) then
			local existing_protocols = protocol_set(pinhole.protocol)
			if existing_protocols and
				((protocols.tcp and existing_protocols.tcp) or (protocols.udp and existing_protocols.udp)) then
				return nil, "An existing IPv6 pinhole already allows this WAN zone, address, port and protocol."
			end
		end
		if type(pinhole) == "table" and pinhole.name == name then
			return nil, "An IPv6 pinhole with this name already exists."
		end
	end
	return {
		name = name,
		source = source,
		destination = destination,
		protocol = protocol,
		destination_ip = canonical_ip,
		destination_port = port
	}
end

function snapshot_office_ipv6_pinhole(snapshot)
	if type(snapshot) ~= "table" or snapshot[".type"] ~= "rule"
		or type(snapshot[".name"]) ~= "string" or snapshot[".name"] == "" then
		return nil, "A named firewall rule section is required."
	end
	local name = type(snapshot.name) == "string" and snapshot.name or ""
	if not name:match("^QuantumGrid IPv6 pinhole: [A-Za-z0-9][A-Za-z0-9_.%-]*$") then
		return nil, "The selected firewall rule is not a QuantumGrid-managed IPv6 pinhole."
	end
	if (snapshot.enabled ~= nil and snapshot.enabled ~= "0" and snapshot.enabled ~= "1")
		or snapshot.family ~= "ipv6" or snapshot.target ~= "ACCEPT"
		or type(snapshot.src) ~= "string" or type(snapshot.dest) ~= "string"
		or type(snapshot.dest_ip) ~= "string"
		or not global_unicast_ipv6(snapshot.dest_ip, false)
		or not port_number(tostring(snapshot.dest_port or ""), "Destination port") then
		return nil, "The IPv6 pinhole rule does not match the managed firewall rule format."
	end
	local protocol = snapshot.proto
	if type(protocol) == "table" then protocol = table.concat(protocol, " ") end
	if protocol ~= "tcp" and protocol ~= "udp" and protocol ~= "tcp udp" then
		return nil, "The IPv6 pinhole rule protocol is invalid."
	end
	local values_copy = {}
	for key, value in pairs(snapshot) do
		if type(key) == "string" and key:sub(1, 1) ~= "." then values_copy[key] = value end
	end
	return { name = snapshot[".name"], values = values_copy }
end

function snapshot_firewall_redirect_section(snapshot)
	if type(snapshot) ~= "table" or snapshot[".type"] ~= "redirect"
		or type(snapshot[".name"]) ~= "string" or snapshot[".name"] == "" then
		return nil, "A named firewall redirect section is required."
	end
	local values = {}
	for key, value in pairs(snapshot) do
		if type(key) == "string" and key:sub(1, 1) ~= "." then values[key] = value end
	end
	return { name = snapshot[".name"], values = values }
end

function validate_office_wifi_ap_network(section, network, aps, interfaces, zones)
	if type(section) ~= "string" or #section < 1 or #section > 64
		or not section:match("^[%w_.%-]+$") or section == "." or section == ".." then
		return nil, "The wireless AP section identifier is invalid."
	end
	if type(network) ~= "string" or #network < 1 or #network > 64
		or not network:match("^[%w_.%-]+$") then
		return nil, "Select an existing office LAN/VLAN network."
	end
	local ap_found = false
	for _, ap in ipairs(type(aps) == "table" and aps or {}) do
		if type(ap) == "table" and ap.section == section then ap_found = true break end
	end
	if not ap_found then
		return nil, "The selected wireless AP section no longer exists."
	end
	local interface_found = false
	for _, iface in ipairs(type(interfaces) == "table" and interfaces or {}) do
		if type(iface) == "table" and iface.name == network then
			interface_found = true
			break
		end
	end
	if not interface_found then
		return nil, "The selected network interface is not present in the current office network inventory."
	end
	if EXTERNAL_ZONE_NAMES[network:lower()] then
		return nil, "A WAN/WWAN interface cannot be assigned as a wireless client network."
	end
	for _, zone in ipairs(type(zones) == "table" and zones or {}) do
		if is_external_zone(zone) then
			for _, attached in ipairs(zone_networks(zone.networks)) do
				if attached == network then
					return nil, "A network attached to an external WAN/WWAN firewall zone cannot be assigned to a wireless AP."
				end
			end
		end
	end
	return { section = section, network = network }
end

function snapshot_wifi_ap_network(snapshot)
	if type(snapshot) ~= "table" or snapshot[".type"] ~= "wifi-iface"
		or snapshot.mode ~= "ap" or type(snapshot[".name"]) ~= "string"
		or snapshot[".name"] == "" then
		return nil, "A named wireless AP section is required."
	end
	local raw = snapshot.network
	if raw == nil then
		return { section = snapshot[".name"], present = false, value = {} }
	end
	local value = {}
	if type(raw) == "string" then
		value[1] = raw
	elseif type(raw) == "table" then
		for _, item in ipairs(raw) do
			if type(item) ~= "string" or not item:match("^[%w_.%-]+$") then
				return nil, "The original AP network binding contains an invalid value."
			end
			table.insert(value, item)
		end
	else
		return nil, "The original AP network binding could not be snapshotted safely."
	end
	return { section = snapshot[".name"], present = true, value = value }
end

function validate_office_zone_policy(section, output, forward, masquerade, zones)
	if type(section) ~= "string" or #section < 1 or #section > 64
		or not section:match("^[%w_.%-]+$") or section == "." or section == ".." then
		return nil, "The firewall zone section identifier is invalid."
	end
	if type(output) ~= "string" or not valid_zone_policy_choice(output) then
		return nil, "Zone output policy must be unchanged, inherited, ACCEPT, REJECT or DROP."
	end
	if type(forward) ~= "string" or not valid_zone_policy_choice(forward) then
		return nil, "Zone forward policy must be unchanged, inherited, ACCEPT, REJECT or DROP."
	end
	if masquerade ~= "0" and masquerade ~= "1" then
		return nil, "Masquerading must be explicitly enabled or disabled."
	end
	local found = false
	for _, zone in ipairs(type(zones) == "table" and zones or {}) do
		if type(zone) == "table" and zone.section == section then found = true break end
	end
	if not found then
		return nil, "The selected firewall zone no longer exists in the current inventory."
	end
	return {
		section = section,
		output = output,
		output_write = output ~= "UNCHANGED",
		forward = forward,
		forward_write = forward ~= "UNCHANGED",
		masquerade = masquerade == "1",
		masq_value = masquerade
	}
end

function snapshot_firewall_zone_policy_options(snapshot)
	if type(snapshot) ~= "table" or snapshot[".type"] ~= "zone"
		or type(snapshot[".name"]) ~= "string" or snapshot[".name"] == "" then
		return nil, "A named firewall zone section is required."
	end
	local result = {}
	for _, option in ipairs({ "output", "forward", "masq" }) do
		local value = snapshot[option]
		result[option] = {
			present = value ~= nil,
			value = value
		}
	end
	return { section = snapshot[".name"], options = result }
end

local RESERVED_INTERFACE_NAMES = {
	lan = true, wan = true, wan6 = true, loopback = true,
	wwan = true, cellular = true
}

local function private_ipv4(value)
	local address = ipv4_number(value)
	if not address then return false end
	local first = math.floor(address / 16777216)
	local second = math.floor(address / 65536) % 256
	return first == 10 or
		(first == 172 and second >= 16 and second <= 31) or
		(first == 192 and second == 168)
end

local function ipv4_subnet_bounds(address, netmask)
	local host = ipv4_number(address)
	local prefix = ipv4_prefix(netmask)
	if not host or not prefix then return nil end
	local size = 2 ^ (32 - prefix)
	local network = math.floor(host / size) * size
	local broadcast = network + size - 1
	if host <= network or host >= broadcast then return nil end
	return { first = network, last = broadcast, prefix = prefix }
end

local function ipv4_overlaps(left, right)
	return left and right and left.first <= right.last and right.first <= left.last
end

function validate_office_segment_ipv6(enabled)
	if enabled == nil then enabled = "0" end
	if enabled ~= "0" and enabled ~= "1" then
		return nil, "IPv6 must be explicitly disabled or enabled."
	end

	if enabled == "0" then
		return {
			enabled = false,
			ip6assign = "",
			dhcpv6 = "disabled",
			ra = "disabled",
			ndp = "disabled"
		}
	end

	local modes, mode_error = validate_dhcp_scope_ipv6_modes("server", "server", "disabled")
	if not modes then return nil, mode_error end
	local advanced, advanced_error = validate_dhcp_scope_ipv6_advanced(
		"managed-config+other-config", "1", "1", "medium", "2700",
		"1", "0", "0", "UNCHANGED")
	if not advanced then return nil, advanced_error end
	return {
		enabled = true,
		ip6assign = "64",
		dhcpv6 = modes.dhcpv6,
		ra = modes.ra,
		ra_flags = { "managed-config", "other-config" },
		ra_slaac = advanced.ra_slaac,
		ra_dns = advanced.ra_dns,
		ra_preference = advanced.ra_preference,
		ra_lifetime = advanced.ra_lifetime,
		dhcpv6_na = advanced.dhcpv6_na,
		dhcpv6_pd = advanced.dhcpv6_pd,
		dhcpv6_assignall = advanced.dhcpv6_assignall,
		ndp = modes.ndp
	}
end

function validate_office_segment(name, bridge_name, vlan_id, address, netmask,
	start_value, limit_value, lease_time, interfaces, bridges, vlans, zones, scopes)
	if type(name) ~= "string" or #name < 1 or #name > 32
		or not name:match("^[A-Za-z][A-Za-z0-9_%-]*$") or RESERVED_INTERFACE_NAMES[name] then
		return nil, "Network name must be 1–32 letters, digits, underscores or hyphens and must not use a reserved interface name."
	end
	if type(bridge_name) ~= "string" or #bridge_name < 1 or #bridge_name > 64
		or not bridge_name:match("^[%w_.%-]+$") then
		return nil, "Select an existing VLAN-filtered bridge."
	end
	if type(vlan_id) ~= "string" or #vlan_id > 4 or not vlan_id:match("^[1-9]%d*$") then
		return nil, "Select an existing VLAN ID from 1 to 4094."
	end
	local numeric_vlan = tonumber(vlan_id)
	if not numeric_vlan or numeric_vlan < 1 or numeric_vlan > 4094 then
		return nil, "Select an existing VLAN ID from 1 to 4094."
	end

	local selected_bridge = nil
	for _, bridge in ipairs(type(bridges) == "table" and bridges or {}) do
		if type(bridge) == "table" and bridge.name == bridge_name then
			selected_bridge = bridge
			break
		end
	end
	if not selected_bridge or selected_bridge.vlan_filtering ~= true then
		return nil, "The selected bridge must already exist with VLAN filtering enabled."
	end

	local selected_vlan = nil
	for _, vlan in ipairs(type(vlans) == "table" and vlans or {}) do
		if type(vlan) == "table" and vlan.device == bridge_name and tonumber(vlan.vlan_id) == numeric_vlan then
			selected_vlan = vlan
			break
		end
	end
	if not selected_vlan or type(selected_vlan.name) ~= "string" or selected_vlan.name == "" then
		return nil, "The selected bridge VLAN must already exist before an L3 network can be provisioned."
	end
	if type(selected_vlan.ports) ~= "table" or #selected_vlan.ports == 0 then
		return nil, "The selected bridge VLAN has no validated switch-port membership."
	end
	local device = bridge_name .. "." .. tostring(numeric_vlan)
	if #device > 64 then return nil, "The generated VLAN device name is too long." end

	for _, iface in ipairs(type(interfaces) == "table" and interfaces or {}) do
		if type(iface) == "table" then
			if iface.name == name then
				return nil, "A network interface with this name already exists."
			end
			if iface.device == device then
				return nil, "This bridge VLAN device is already assigned to another network interface."
			end
		end
	end

	if not private_ipv4(address) then
		return nil, "Use a canonical RFC1918 private IPv4 address for the new office gateway."
	end
	local subnet = ipv4_subnet_bounds(address, netmask)
	if not subnet then
		return nil, "The gateway must be a usable host address with a contiguous IPv4 netmask from /1 through /30."
	end

	for _, iface in ipairs(type(interfaces) == "table" and interfaces or {}) do
		if type(iface) == "table" then
			local existing_addresses = values(iface.ipv4, 16)
			for _, existing_address in ipairs(existing_addresses) do
				local existing_host = ipv4_number(existing_address)
				if existing_host == ipv4_number(address) then
					return nil, "The new gateway address is already assigned to another interface."
				end
				local existing_subnet = ipv4_subnet_bounds(existing_address, iface.netmask)
				if iface.protocol == "static" and not existing_subnet then
					return nil, "An existing static IPv4 interface has an address or netmask that cannot be parsed safely. Resolve it before creating another subnet."
				end
				if existing_subnet and ipv4_overlaps(subnet, existing_subnet) then
					return nil, "The new office subnet overlaps an existing static IPv4 interface subnet."
				end
			end
		end
	end

	local selected_zone = nil
	if type(zones) == "table" then
		for _, candidate in ipairs(zones) do
			if type(candidate) == "table" and candidate.selected == true then
				if selected_zone then return nil, "Select exactly one existing firewall zone." end
				selected_zone = candidate
			end
		end
	end
	if not selected_zone or type(selected_zone.section) ~= "string" or selected_zone.section == ""
		or is_external_zone(selected_zone) then
		return nil, "Choose an existing internal firewall zone. External WAN/WWAN zones cannot host an office LAN."
	end
	if selected_zone.input ~= "REJECT" and selected_zone.input ~= "DROP" then
		return nil, "The selected zone must already default router input to REJECT or DROP. QuantumGrid adds only narrow DHCP and DNS access rules for the new segment."
	end
	if selected_zone.forward ~= "REJECT" and selected_zone.forward ~= "DROP" then
		return nil, "The selected zone must already default inter-zone forwarding to REJECT or DROP. Add explicit inter-zone forwarding only after the segment is provisioned."
	end

	local other_ranges = {}
	for _, scope in ipairs(type(scopes) == "table" and scopes or {}) do
		if type(scope) == "table" and not scope.ignore then
			if scope.range_valid then
				table.insert(other_ranges, { start = scope.pool_start_ip, finish = scope.pool_end_ip })
			else
				return nil, "An existing enabled DHCP pool has an invalid or unknown range. Resolve it before creating another office network."
			end
		end
	end
	local pool, pool_error = validate_dhcp_scope_update(
		start_value, limit_value, lease_time, address, netmask, other_ranges)
	if not pool then return nil, pool_error end

	return {
		name = name,
		bridge = bridge_name,
		vlan_id = numeric_vlan,
		device = device,
		address = address,
		netmask = netmask,
		subnet_cidr = ipv4_text(subnet.first) .. "/" .. tostring(subnet.prefix),
		zone_section = selected_zone.section,
		zone_name = selected_zone.name,
		zone_input = selected_zone.input,
		zone_output = selected_zone.output,
		zone_forward = selected_zone.forward,
		dhcp_start = pool.start,
		dhcp_limit = pool.limit,
		lease_time = pool.lease_time,
		pool_start_ip = pool.pool_start_ip,
		pool_end_ip = pool.pool_end_ip
	}
end

function validate_office_forwarding(source, destination, zones, existing)
	if type(source) ~= "string" or not source:match("^[%w_.%-]+$") or #source > 64 then
		return nil, "Select an existing source firewall zone."
	end
	if type(destination) ~= "string" or not destination:match("^[%w_.%-]+$") or #destination > 64 then
		return nil, "Select an existing destination firewall zone."
	end
	if source == destination then
		return nil, "Source and destination firewall zones must be different."
	end

	local source_zone, destination_zone = nil, nil
	for _, zone in ipairs(type(zones) == "table" and zones or {}) do
		if type(zone) == "table" then
			if zone.name == source then source_zone = zone end
			if zone.name == destination then destination_zone = zone end
		end
	end
	if not source_zone or not destination_zone then
		return nil, "Both firewall zones must already exist in the router configuration."
	end
	if is_external_zone(source_zone) then
		return nil, "An external WAN/WWAN zone cannot be used as the source of a new forwarding."
	end

	for _, forwarding in ipairs(type(existing) == "table" and existing or {}) do
		if type(forwarding) == "table" and forwarding.source == source
			and forwarding.destination == destination then
			return nil, "This source-to-destination forwarding already exists."
		end
	end

	return { source = source, destination = destination }
end

function snapshot_firewall_forwarding_section(snapshot)
	if type(snapshot) ~= "table" or snapshot[".type"] ~= "forwarding"
		or type(snapshot[".name"]) ~= "string" or snapshot[".name"] == "" then
		return nil, "A named firewall forwarding section is required."
	end
	local values = {}
	for key, value in pairs(snapshot) do
		if type(key) == "string" and key:sub(1, 1) ~= "." then
			values[key] = value
		end
	end
	return { name = snapshot[".name"], values = values }
end

function validate_bridge_vlan(device, vlan_id, requested_ports, bridge_ports, existing_vlans, current_section)
	if type(device) ~= "string" or #device < 1 or #device > 64
		or not device:match("^[%w_.%-]+$") then
		return nil, "Select an existing bridge device."
	end
	if type(vlan_id) ~= "string" or #vlan_id > 4 or not vlan_id:match("^[1-9]%d*$") then
		return nil, "VLAN ID must be a whole number from 1 to 4094."
	end
	local numeric_vlan = tonumber(vlan_id)
	if not numeric_vlan or numeric_vlan < 1 or numeric_vlan > 4094 then
		return nil, "VLAN ID must be a whole number from 1 to 4094."
	end

	local allowed_ports = {}
	for _, raw_port in ipairs(type(bridge_ports) == "table" and bridge_ports or {}) do
		if type(raw_port) == "string" and raw_port:match("^[%w_.%-]+$") then
			allowed_ports[raw_port] = true
		end
	end
	if not next(allowed_ports) then
		return nil, "The bridge has no validated member ports to configure."
	end

	local requested, parse_error = parse_bridge_ports(requested_ports)
	if not requested then return nil, parse_error end
	local normalized, seen = {}, {}
	local pvid_ports = {}
	for _, raw in ipairs(requested) do
		local port = parse_port(raw)
		if not port or port.mode == "unspecified" then
			return nil, "Every selected port must explicitly be tagged (:t), untagged (:u) or untagged PVID (:u*)."
		end
		if not allowed_ports[port.name] then
			return nil, "A selected port is not a member of the chosen bridge."
		end
		if seen[port.name] then
			return nil, "A bridge port may appear only once in a VLAN membership list."
		end
		seen[port.name] = true
		if port.pvid then pvid_ports[port.name] = true end
		normalized[#normalized + 1] = port.name .. (port.mode == "tagged" and ":t" or port.pvid and ":u*" or ":u")
	end

	for _, existing in ipairs(type(existing_vlans) == "table" and existing_vlans or {}) do
		if type(existing) == "table" and existing.section ~= current_section then
			if existing.device == device and tonumber(existing.vlan) == numeric_vlan then
				return nil, "This VLAN ID already exists on the selected bridge."
			end
			if existing.device == device then
				local existing_ports = parse_bridge_ports(existing.ports) or {}
				for _, raw in ipairs(existing_ports) do
					local old_port = parse_port(raw)
					if old_port and old_port.mode == "untagged" then
						for _, new_raw in ipairs(normalized) do
							local new_port = parse_port(new_raw)
							if new_port and new_port.name == old_port.name and new_port.mode == "untagged" then
								return nil, "A switch port can have only one untagged VLAN membership across the bridge."
							end
						end
						if old_port.pvid and pvid_ports[old_port.name] then
							return nil, "A switch port can have only one untagged PVID across the bridge."
						end
					end
				end
			end
		end
	end

	return {
		device = device,
		vlan_id = numeric_vlan,
		ports = normalized,
		port_count = #normalized,
		section = current_section
	}
end

function build_inventory(source)
	source = type(source) == "table" and source or {}
	local result = {
		available = source.available == true,
		firewall_available = source.firewall_available == true,
		wireless_available = source.wireless_available == true,
		truncated = source.truncated == true,
		interfaces = {},
		bridges = {},
		vlans = {},
		zones = {},
		forwardings = {},
		forwarding_count = 0,
		redirects = {},
		redirect_count = 0,
		ipv6_pinholes = {},
		ipv6_pinhole_count = 0,
		dhcp_available = source.dhcp_available == true,
		dhcp_scopes = {},
		static_leases = {},
		dhcp_scope_count = 0,
		static_lease_count = 0,
		interface_count = 0,
		bridge_count = 0,
		vlan_count = 0,
		zone_count = 0,
		wifi_ap_count = 0,
		vlan_filtering_bridge_count = 0,
		segmented_interface_count = 0,
		sampled_at = tonumber(source.sampled_at) or os.time()
	}

	local source_interfaces = type(source.interfaces) == "table" and source.interfaces or {}
	local source_bridges = type(source.bridges) == "table" and source.bridges or {}
	local source_vlans = type(source.vlans) == "table" and source.vlans or {}
	local source_zones = type(source.zones) == "table" and source.zones or {}
	local source_aps = type(source.wifi_aps) == "table" and source.wifi_aps or {}

	local zones = {}
	for _, item in ipairs(source_zones) do
		if type(item) == "table" and #result.zones < MAX_ZONES then
			local name = token(item.name, 64)
			if name then
				local networks = values(item.networks, 16)
				local section = token(item.section, 64) or name
				local zone = {
					section = section,
					name = name,
					networks = networks,
					input = clean(item.input, 24),
					output = clean(item.output, 24),
					forward = clean(item.forward, 24),
					masquerade = item.masquerade == true
				}
				table.insert(result.zones, zone)
				zones[#zones + 1] = zone
			end
		else
			result.truncated = true
		end
	end
	result.zone_count = #result.zones

	local source_redirects = type(source.redirects) == "table" and source.redirects or {}
	for _, item in ipairs(source_redirects) do
		if type(item) == "table" and #result.redirects < 64 then
			local section = token(item.section, 64)
			local name = token(item.name, 64)
			local source_zone = token(item.source, 64)
			local destination_zone = token(item.destination, 64)
			local protocol = item.protocol == "tcp" or item.protocol == "udp" or item.protocol == "tcp udp"
			local source_port = tonumber(item.source_port)
			local destination_port = tonumber(item.destination_port)
			local destination_ip = type(item.destination_ip) == "string" and item.destination_ip or ""
			if section and name and source_zone and destination_zone and protocol
				and source_port and source_port >= 1 and source_port <= 65535
				and destination_port and destination_port >= 1 and destination_port <= 65535
				and valid_ipv4(destination_ip) then
				table.insert(result.redirects, {
					section = section,
					name = name,
					source = source_zone,
					destination = destination_zone,
					protocol = item.protocol,
					source_port = source_port,
					destination_ip = destination_ip,
					destination_port = destination_port
				})
			end
		end
	end
	result.redirect_count = #result.redirects
	if #source_redirects > #result.redirects then result.truncated = true end

	local source_pinholes = type(source.ipv6_pinholes) == "table" and source.ipv6_pinholes or {}
	for _, item in ipairs(source_pinholes) do
		if type(item) == "table" and #result.ipv6_pinholes < 64 then
			local section = token(item.section, 64)
			local name = clean(item.name, 64)
			local source_zone = token(item.source, 64)
			local destination_zone = token(item.destination, 64)
			local protocol = item.protocol == "tcp" or item.protocol == "udp" or item.protocol == "tcp udp"
			local destination_ip = global_unicast_ipv6(item.destination_ip, false)
			local destination_port = tonumber(item.destination_port)
			if section and name ~= "" and source_zone and destination_zone and protocol
				and destination_ip and destination_port and destination_port >= 1
				and destination_port <= 65535 and destination_port == math.floor(destination_port) then
				table.insert(result.ipv6_pinholes, {
					section = section,
					name = name,
					source = source_zone,
					destination = destination_zone,
					protocol = item.protocol,
					destination_ip = destination_ip,
					destination_port = destination_port,
					enabled = item.enabled ~= false
				})
			end
		end
	end
	result.ipv6_pinhole_count = #result.ipv6_pinholes
	if #source_pinholes > #result.ipv6_pinholes then result.truncated = true end

	local source_forwardings = type(source.forwardings) == "table" and source.forwardings or {}
	for _, item in ipairs(source_forwardings) do
		if type(item) == "table" and #result.forwardings < MAX_FORWARDINGS then
			local name = token(item.name, 64)
			local section = token(item.section, 64)
			local source_zone = token(item.source, 64)
			local destination_zone = token(item.destination, 64)
			if name and section and source_zone and destination_zone then
				table.insert(result.forwardings, {
					name = name,
					section = section,
					source = source_zone,
					destination = destination_zone
				})
			end
		end
	end
	result.forwarding_count = #result.forwardings
	if #source_forwardings > #result.forwardings then result.truncated = true end

	local source_scopes = type(source.dhcp_scopes) == "table" and source.dhcp_scopes or {}
	for _, item in ipairs(source_scopes) do
		if type(item) == "table" and #result.dhcp_scopes < 64 then
			local name = token(item.name, 64)
			local interface = token(item.interface, 64)
			if name and interface then
				local limit = tonumber(item.limit)
				if limit and (limit ~= math.floor(limit) or limit < 1 or limit > 4294967294) then limit = nil end
				table.insert(result.dhcp_scopes, {
					section = token(item.section, 64) or name,
					name = name,
					interface = interface,
					start = clean(item.start, 32),
					limit = limit,
					lease_time = clean(item.lease_time, 32),
					ignore = item.ignore == true,
					dhcpv6 = clean(item.dhcpv6, 16),
					ra = clean(item.ra, 16),
					ndp = clean(item.ndp, 16),
					ra_flags = values(item.ra_flags, 8),
					ra_slaac = item.ra_slaac ~= false,
					ra_dns = item.ra_dns ~= false,
					ra_preference = clean(item.ra_preference, 8),
					ra_lifetime = tonumber(item.ra_lifetime) or 2700,
					dhcpv6_na = item.dhcpv6_na ~= false,
					dhcpv6_pd = item.dhcpv6_pd ~= false,
					dhcpv6_assignall = item.dhcpv6_assignall ~= false,
					dhcpv6_pd_min_len = tonumber(item.dhcpv6_pd_min_len) or 62
				})
			end
		end
	end
	result.dhcp_scope_count = #result.dhcp_scopes
	if #source_scopes > #result.dhcp_scopes then result.truncated = true end

	local source_leases = type(source.static_leases) == "table" and source.static_leases or {}
	for _, item in ipairs(source_leases) do
		if type(item) == "table" and #result.static_leases < 256 then
			local name = clean(item.name, 64)
			local mac = type(item.mac) == "string" and item.mac:lower() or ""
			local address = type(item.ipv4) == "string" and item.ipv4 or ""
			if valid_mac(mac) and valid_ipv4(address) then
				table.insert(result.static_leases, {
					section = token(item.section, 64) or "",
					name = name ~= "" and name or "Unnamed host",
					mac = mac,
					ipv4 = address
				})
			end
		end
	end
	result.static_lease_count = #result.static_leases
	if #source_leases > 256 then result.truncated = true end
	if #source_zones > #result.zones then result.truncated = true end

	for _, item in ipairs(source_bridges) do
		if type(item) == "table" then
			local name = token(item.name, 64)
			if name and #result.bridges < MAX_BRIDGES then
				local ports = values(item.ports, 32)
				table.insert(result.bridges, {
					name = name,
					type = clean(item.type, 24),
					ports = ports,
					vlan_filtering = item.vlan_filtering == true
				})
			end
		end
	end
	result.bridge_count = #result.bridges
	for _, bridge in ipairs(result.bridges) do
		if bridge.vlan_filtering then
			result.vlan_filtering_bridge_count = result.vlan_filtering_bridge_count + 1
		end
	end
	if #source_bridges > #result.bridges then result.truncated = true end

	for _, item in ipairs(source_vlans) do
		if type(item) == "table" then
			local device = token(item.device, 64)
			local vlan_id = parse_vlan_id(item.vlan)
			if device and vlan_id and #result.vlans < MAX_VLANS then
				local ports, seen_ports = {}, {}
				for _, raw_port in ipairs(values(item.ports, 32)) do
					local port = parse_port(raw_port)
					if port and not seen_ports[port.name] then
						seen_ports[port.name] = true
						table.insert(ports, port)
					end
				end
				table.insert(result.vlans, {
					name = token(item.name, 64) or ("vlan_" .. tostring(vlan_id)),
					device = device,
					vlan_id = vlan_id,
					ports = ports
				})
			end
		end
	end
	result.vlan_count = #result.vlans
	if #source_vlans > #result.vlans then result.truncated = true end

	local aps = {}
	for _, item in ipairs(source_aps) do
		if type(item) == "table" then
			local section = token(item.section, 64)
			if section and #aps < MAX_APS and item.mode == "ap" then
				local network_names = values(item.networks, 8)
				local ap = {
					section = section,
					ssid = clean(item.ssid, 32),
					device = token(item.device, 64) or "",
					networks = network_names,
					disabled = item.disabled == true
				}
				table.insert(aps, ap)
			end
		end
	end
	result.wifi_ap_count = #aps
	if #source_aps > #aps then result.truncated = true end

	for _, item in ipairs(source_interfaces) do
		if type(item) == "table" then
			local name = token(item.name, 64)
			if name and #result.interfaces < MAX_INTERFACES then
				local device = token(item.device, 64) or ""
				local bridge_name, suffix_vlan = network_device_vlan(device)
				local vlan_ids, attached_zones, ssids = {}, {}, {}
				for _, vlan in ipairs(result.vlans) do
					if (bridge_name and vlan.device == bridge_name and vlan.vlan_id == suffix_vlan)
						or (device ~= "" and device == vlan.device .. "." .. tostring(vlan.vlan_id)) then
						table.insert(vlan_ids, vlan.vlan_id)
					end
				end
				for _, zone in ipairs(zones) do
					if contains(zone.networks, name) then table.insert(attached_zones, zone.name) end
				end
				for _, ap in ipairs(aps) do
					if contains(ap.networks, name) then
						table.insert(ssids, {
							ssid = ap.ssid,
							section = ap.section,
							device = ap.device,
							disabled = ap.disabled
						})
					end
				end
				local ipv6_neighbors, neighbor_seen = {}, {}
				local live_device = item.up == true and type(item.device) == "string"
					and #item.device <= 64 and item.device:match("^[%w][%w_.%-]*$") ~= nil
				local source_neighbors = live_device and type(item.ipv6_neighbors) == "table"
					and item.ipv6_neighbors or {}
				for _, neighbor in ipairs(source_neighbors) do
					if type(neighbor) == "table" and #ipv6_neighbors < 64 then
						local address = global_unicast_ipv6(neighbor.address, false)
						local mac = type(neighbor.mac) == "string" and neighbor.mac:lower() or ""
						local state = neighbor.state
						if address and not neighbor_seen[address] and valid_unicast_neighbor_mac(mac)
							and ({ REACHABLE = true, STALE = true, DELAY = true, PROBE = true, PERMANENT = true })[state] then
							neighbor_seen[address] = true
							table.insert(ipv6_neighbors, {
								address = address,
								mac = mac,
								state = state
							})
						end
					end
				end
				table.sort(ipv6_neighbors, function(left, right) return left.address < right.address end)
				table.insert(result.interfaces, {
					name = name,
					protocol = clean(item.protocol, 24),
					device = device,
					up = item.up == true,
					ipv4 = values(item.ipv4, 8),
					netmask = clean(item.netmask, 32),
					ip6assign = clean(item.ip6assign, 16),
					ipv6 = values(item.ipv6, 8),
					ipv6_neighbors = ipv6_neighbors,
					vlan_ids = vlan_ids,
					firewall_zones = attached_zones,
					wifi_aps = ssids
				})
				if #vlan_ids > 0 then result.segmented_interface_count = result.segmented_interface_count + 1 end
			end
		end
	end
	result.interface_count = #result.interfaces
	if #source_interfaces > #result.interfaces then result.truncated = true end

	local pool_ranges = {}
	for _, scope in ipairs(result.dhcp_scopes) do
		scope.range_valid = false
		scope.pool_start_ip = ""
		scope.pool_end_ip = ""
		scope.range_error = ""
		scope.overlap = false
		if scope.ignore then
			scope.range_error = "DHCP scope is disabled."
		else
			local iface = nil
			for _, candidate in ipairs(result.interfaces) do
				if candidate.name == scope.interface then iface = candidate break end
			end
			local interface_address = iface and iface.ipv4[1] or nil
			local router_number = ipv4_number(interface_address)
			local prefix = iface and ipv4_prefix(iface.netmask) or nil
			local start = tonumber(scope.start)
			local limit = tonumber(scope.limit)
			if not iface or not router_number or not prefix then
				scope.range_error = "A static IPv4 address and contiguous netmask are required to calculate this pool."
			elseif not start or start ~= math.floor(start) or start < 1
				or not limit or limit ~= math.floor(limit) or limit < 1
				or start > 4294967294 or limit > 4294967294 then
				scope.range_error = "DHCP start offset or pool size is invalid."
			else
				local size = 2 ^ (32 - prefix)
				local network = math.floor(router_number / size) * size
				local broadcast = network + size - 1
				local first = network + start
				local last = first + limit - 1
				if first <= network or last >= broadcast then
					scope.range_error = "The configured pool extends outside usable host addresses in the subnet."
				elseif router_number >= first and router_number <= last then
					scope.range_error = "The configured pool includes the router interface address."
				else
					scope.range_valid = true
					scope.pool_start_ip = ipv4_text(first) or ""
					scope.pool_end_ip = ipv4_text(last) or ""
					pool_ranges[#pool_ranges + 1] = {
						scope = scope,
						first = first,
						last = last
					}
				end
			end
		end
	end
	for left = 1, #pool_ranges do
		for right = left + 1, #pool_ranges do
			local first, second = pool_ranges[left], pool_ranges[right]
			if first.first <= second.last and second.first <= first.last then
				first.scope.overlap = true
				second.scope.overlap = true
			end
		end
	end

	return result
end

return _M
