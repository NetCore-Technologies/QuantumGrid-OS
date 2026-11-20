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

function snapshot_dhcp_scope_options(snapshot)
	if type(snapshot) ~= "table" or snapshot[".type"] ~= "dhcp" then
		return nil, "A DHCP scope snapshot is required."
	end
	local result = {}
	for _, name in ipairs({ "start", "limit", "leasetime" }) do
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
				local zone = {
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

	local source_forwardings = type(source.forwardings) == "table" and source.forwardings or {}
	for _, item in ipairs(source_forwardings) do
		if type(item) == "table" and #result.forwardings < MAX_FORWARDINGS then
			local name = token(item.name, 64)
			local source_zone = token(item.source, 64)
			local destination_zone = token(item.destination, 64)
			if name and source_zone and destination_zone then
				table.insert(result.forwardings, {
					name = name,
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
					ra = clean(item.ra, 16)
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
				table.insert(result.interfaces, {
					name = name,
					protocol = clean(item.protocol, 24),
					device = device,
					up = item.up == true,
					ipv4 = values(item.ipv4, 8),
					netmask = clean(item.netmask, 32),
					ip6assign = clean(item.ip6assign, 16),
					ipv6 = values(item.ipv6, 8),
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
