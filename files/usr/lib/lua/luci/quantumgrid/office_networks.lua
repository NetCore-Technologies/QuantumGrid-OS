module("luci.quantumgrid.office_networks", package.seeall)

local MAX_INTERFACES = 64
local MAX_BRIDGES = 32
local MAX_VLANS = 64
local MAX_ZONES = 32
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
		return { name = bare, mode = "unspecified", pvid = false }
	end
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

	local source_scopes = type(source.dhcp_scopes) == "table" and source.dhcp_scopes or {}
	for _, item in ipairs(source_scopes) do
		if type(item) == "table" and #result.dhcp_scopes < 64 then
			local name = token(item.name, 64)
			local interface = token(item.interface, 64)
			if name and interface then
				local limit = tonumber(item.limit)
				if limit and (limit ~= math.floor(limit) or limit < 1 or limit > 65535) then limit = nil end
				table.insert(result.dhcp_scopes, {
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

	local bridge_names = {}
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
				bridge_names[name] = true
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

	return result
end

return _M
