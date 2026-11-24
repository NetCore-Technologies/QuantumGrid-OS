module("luci.quantumgrid.qos", package.seeall)

local POLICY_PREFIX = "QuantumGrid client QoS: "
local DEFAULT_LIMIT = 32
local EXTERNAL_NAMES = {
	wan = true, wan6 = true, wwan = true, cellular = true, lte = true, ["5g"] = true,
	mobile = true, internet = true, upstream = true, public = true, uplink = true
}
local EXTERNAL_PROTOCOLS = {
	dhcp = true, dhcpv6 = true, ppp = true, pppoe = true, qmi = true,
	mbim = true, ncm = true, ["3g"] = true, wwan = true, modem = true
}
local ALLOWED_DSCP = { BE = true, AF41 = true, EF = true, CS1 = true }

local function valid_token(value)
	return type(value) == "string" and #value >= 1 and #value <= 64
		and value:match("^[A-Za-z0-9_.%-]+$") ~= nil and value ~= "." and value ~= ".."
end

local function zone_network_list(value)
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

local function unique_zone(zones, name)
	local found = nil
	local matches = 0
	for _, zone in ipairs(type(zones) == "table" and zones or {}) do
		if type(zone) == "table" and zone.name == name then
			found = zone
			matches = matches + 1
		end
	end
	return matches == 1 and found or nil
end

local function is_external_zone(zone, interfaces)
	if type(zone) ~= "table" then return false end
	local name = type(zone.name) == "string" and zone.name:lower() or ""
	if EXTERNAL_NAMES[name] or zone.masquerade == true then return true end
	local networks = {}
	for _, network in ipairs(zone_network_list(zone.networks)) do
		local normalized = network:lower()
		networks[normalized] = true
		if EXTERNAL_NAMES[normalized] then return true end
	end
	for _, iface in ipairs(type(interfaces) == "table" and interfaces or {}) do
		if type(iface) == "table" and type(iface.name) == "string" and networks[iface.name:lower()] then
			local protocol = type(iface.protocol) == "string" and iface.protocol:lower() or ""
			if EXTERNAL_PROTOCOLS[protocol] then return true end
		end
	end
	return false
end

-- Resolve an external zone to its live L3 devices. Logical network names and
-- kernel device names are deliberately kept separate.
function resolve_external_zone_devices(zone_name, zones, interfaces)
	if not valid_token(zone_name) then return nil, "Choose a valid external firewall zone." end
	local zone = unique_zone(zones, zone_name)
	if not zone then return nil, "The selected external firewall zone is missing or ambiguous." end
	if not is_external_zone(zone, interfaces) then
		return nil, "The selected source zone is not recognised as an existing WAN/WWAN zone."
	end
	local networks, devices = {}, {}
	for _, network in ipairs(zone_network_list(zone.networks)) do
		if valid_token(network) then networks[network] = true end
	end
	for _, iface in ipairs(type(interfaces) == "table" and interfaces or {}) do
		if type(iface) == "table" and type(iface.name) == "string" and networks[iface.name] then
			local device = iface.l3_device
			if type(device) ~= "string" or device == "" then device = iface.device end
			if type(device) == "string" and #device <= 15 and device:match("^[%w_.:%-]+$") then
				devices[device] = true
			end
		end
	end
	local result = {}
	for device in pairs(devices) do result[#result + 1] = device end
	table.sort(result)
	if #result == 0 then return nil, "The selected WAN/WWAN zone has no resolvable Layer-3 device." end
	if #result > 8 then return nil, "The selected WAN/WWAN zone has too many device members." end
	return result
end

local function normalize_unicast_mac(value)
	if type(value) ~= "string" or #value ~= 17
		or not value:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") then return nil end
	local mac = value:lower()
	local first = tonumber(mac:sub(1, 2), 16)
	if not first or first % 2 ~= 0 or mac == "00:00:00:00:00:00"
		or mac == "ff:ff:ff:ff:ff:ff" then return nil end
	return mac
end

function validate_client_policy(mac, source_zone, destination_zone, dscp_class, zones, interfaces)
	local normalized_mac = normalize_unicast_mac(mac)
	if not normalized_mac then
		return nil, "Choose one unicast client MAC address in six-octet notation."
	end
	if not valid_token(source_zone) or not valid_token(destination_zone) then
		return nil, "Choose existing internal and external firewall zones."
	end
	if source_zone == destination_zone then
		return nil, "The client source zone and WAN destination zone must be different."
	end
	if type(dscp_class) ~= "string" or not ALLOWED_DSCP[dscp_class] then
		return nil, "Choose one supported DSCP class: BE, AF41, EF or CS1."
	end

	local source = unique_zone(zones, source_zone)
	local destination = unique_zone(zones, destination_zone)
	if not source or not destination then
		return nil, "Both firewall zones must already exist in the current inventory."
	end
	if is_external_zone(source, interfaces) then
		return nil, "Per-client upload marking must start in an internal LAN/office zone."
	end
	if not is_external_zone(destination, interfaces) then
		return nil, "Per-client upload marking must target an existing WAN/WWAN zone."
	end
	return {
		mac = normalized_mac,
		source_zone = source_zone,
		destination_zone = destination_zone,
		dscp_class = dscp_class,
		name = POLICY_PREFIX .. normalized_mac
	}
end

function validate_client_policy_section(section)
	if not valid_token(section) then
		return nil, "The client QoS firewall rule section identifier is invalid."
	end
	return section
end

local DOWNLOAD_POLICY_PREFIX = "QuantumGrid client QoS download: "

local function normalized_qos_protocol(value)
	if value == nil or value == "" then return "tcpudp" end
	if value == "all" or value == "tcpudp" then return value end
	if type(value) == "table" and #value == 2 and
		((value[1] == "tcp" and value[2] == "udp") or
		(value[1] == "udp" and value[2] == "tcp")) then
		return "tcpudp"
	end
	return nil
end

local function valid_ipv4_host(value)
	if type(value) ~= "string" or #value > 15 then return false end
	local a, b, c, d = value:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	if not a then return false end
	local octets = { a, b, c, d }
	for _, part in ipairs(octets) do
		local number = tonumber(part)
		if not number or number < 0 or number > 255 or number ~= math.floor(number)
			or tostring(number) ~= part then return false end
	end
	local first, second = tonumber(a), tonumber(b)
	return first ~= 0 and first ~= 127 and first < 224 and
		not (first == 169 and second == 254) and not (first == 255)
end

function validate_client_download_policy(mac, destination_ip, source_zone, destination_zone, dscp_class, zones, interfaces, static_leases)
	local normalized_mac = normalize_unicast_mac(mac)
	if not normalized_mac then
		return nil, "Choose one unicast client MAC address in six-octet notation."
	end
	if not valid_ipv4_host(destination_ip) then
		return nil, "Download marking requires one usable static IPv4 host address."
	end
	if not valid_token(source_zone) or not valid_token(destination_zone) or source_zone == destination_zone then
		return nil, "Choose existing external and internal firewall zones."
	end
	if type(dscp_class) ~= "string" or not ALLOWED_DSCP[dscp_class] then
		return nil, "Choose one supported DSCP class: BE, AF41, EF or CS1."
	end
	local source = unique_zone(zones, source_zone)
	local destination = unique_zone(zones, destination_zone)
	if not source or not destination then
		return nil, "Both firewall zones must already exist in the current inventory."
	end
	if not is_external_zone(source, interfaces) or is_external_zone(destination, interfaces) then
		return nil, "Download marking must travel from an existing WAN/WWAN zone to an internal LAN/office zone."
	end

	local matching_leases, mac_conflicts, ip_conflicts = 0, 0, 0
	for _, lease in ipairs(type(static_leases) == "table" and static_leases or {}) do
		if type(lease) == "table" then
			local lease_mac = normalize_unicast_mac(lease.mac)
			if lease_mac == normalized_mac then
				mac_conflicts = mac_conflicts + 1
				if lease.ipv4 == destination_ip then matching_leases = matching_leases + 1 end
			end
			if lease.ipv4 == destination_ip then ip_conflicts = ip_conflicts + 1 end
		end
	end
	if matching_leases ~= 1 or mac_conflicts ~= 1 or ip_conflicts ~= 1 then
		return nil, "The client must have exactly one matching static DHCP reservation for this MAC and IPv4 address."
	end

	local office = require "luci.quantumgrid.office_networks"
	local matching_interfaces = 0
	for _, iface in ipairs(type(interfaces) == "table" and interfaces or {}) do
		if type(iface) == "table" then
			local zone_memberships = type(iface.firewall_zones) == "table" and iface.firewall_zones or {}
			local attached = #zone_memberships == 1 and zone_memberships[1] == destination_zone
			if attached and type(iface.ipv4) == "table" then
				local interface_matches = false
				for _, interface_ip in ipairs(iface.ipv4) do
					if office.ipv4_in_subnet(destination_ip, interface_ip, iface.netmask) then
						interface_matches = true
						break
					end
				end
				if interface_matches then matching_interfaces = matching_interfaces + 1 end
			end
		end
	end
	if matching_interfaces ~= 1 then
		return nil, "The reserved client IP must belong to exactly one routed IPv4 subnet attached to the selected internal zone."
	end

	return {
		mac = normalized_mac,
		destination_ip = destination_ip,
		source_zone = source_zone,
		destination_zone = destination_zone,
		dscp_class = dscp_class,
		direction = "download",
		name = DOWNLOAD_POLICY_PREFIX .. normalized_mac
	}
end

local MANAGED_UPLOAD_OPTIONS = {
	name = true, src = true, dest = true, proto = true, src_mac = true,
	target = true, set_dscp = true, enabled = true
}
local MANAGED_DOWNLOAD_OPTIONS = {
	name = true, src = true, dest = true, proto = true, dest_ip = true,
	target = true, set_dscp = true, enabled = true
}

local function has_only_managed_policy_options(section, allowed)
	for option in pairs(section) do
		if type(option) ~= "string" then return false end
		if option:sub(1, 1) ~= "." and not allowed[option] then return false end
	end
	return true
end

function summarize_client_policy(section)
	if type(section) ~= "table" or type(section.name) ~= "string" or section.target ~= "dscp" then return nil end
	if section[".type"] ~= nil and section[".type"] ~= "rule" then return nil end
	local section_name = type(section[".name"]) == "string" and section[".name"] or ""
	if not valid_token(section_name) then return nil end
	if type(section.set_dscp) ~= "string" or not ALLOWED_DSCP[section.set_dscp] then return nil end
	local protocol = normalized_qos_protocol(section.proto)
	if not protocol then return nil end

	local upload_mac = section.name:sub(1, #POLICY_PREFIX) == POLICY_PREFIX
		and normalize_unicast_mac(section.src_mac) or nil
	if upload_mac and section.name == POLICY_PREFIX .. upload_mac and
		has_only_managed_policy_options(section, MANAGED_UPLOAD_OPTIONS) and
		valid_token(section.src) and valid_token(section.dest) then
		return {
			section = section_name, name = "Client " .. upload_mac, mac = upload_mac,
			source_zone = section.src, destination_zone = section.dest,
			dscp_class = section.set_dscp, direction = "upload", protocol = protocol, enabled = section.enabled ~= "0"
		}
	end

	local download_mac = section.name:sub(1, #DOWNLOAD_POLICY_PREFIX) == DOWNLOAD_POLICY_PREFIX
		and normalize_unicast_mac(section.name:sub(#DOWNLOAD_POLICY_PREFIX + 1)) or nil
	if download_mac and section.name == DOWNLOAD_POLICY_PREFIX .. download_mac and
		section.src_mac == nil and has_only_managed_policy_options(section, MANAGED_DOWNLOAD_OPTIONS) and
		valid_token(section.src) and valid_token(section.dest) and valid_ipv4_host(section.dest_ip) then
		return {
			section = section_name, name = "Client " .. download_mac, mac = download_mac,
			destination_ip = section.dest_ip, source_zone = section.src, destination_zone = section.dest,
			dscp_class = section.set_dscp, direction = "download", protocol = protocol, enabled = section.enabled ~= "0"
		}
	end
	return nil
end

function read_client_policies(uci, limit)
	if type(uci) ~= "table" or type(uci.foreach) ~= "function" then
		return nil, false, "Firewall UCI cursor is unavailable."
	end
	limit = tonumber(limit) or DEFAULT_LIMIT
	if limit < 1 or limit > 64 or limit ~= math.floor(limit) then
		return nil, false, "Client QoS inventory limit is invalid."
	end
	local result, truncated = {}, false
	local ok, err = pcall(uci.foreach, uci, "firewall", "rule", function(section)
		local summary = summarize_client_policy(section)
		if summary then
			if #result < limit then table.insert(result, summary) else truncated = true end
		end
	end)
	if not ok then return nil, false, tostring(err or "Firewall QoS inventory could not be read.") end
	return result, truncated
end

function has_duplicate_client_policy(policies, update)
	if type(policies) ~= "table" or type(update) ~= "table" then return false end
	for _, policy in ipairs(policies) do
		if type(policy) == "table" and policy.mac == update.mac
			and policy.source_zone == update.source_zone
			and policy.destination_zone == update.destination_zone then return true end
	end
	return false
end

function find_download_reservation_policy(policies, mac, ipv4)
	local normalized_mac = normalize_unicast_mac(type(mac) == "string" and mac or "")
	if not normalized_mac or not valid_ipv4_host(ipv4) then return nil end
	for _, policy in ipairs(type(policies) == "table" and policies or {}) do
		if type(policy) == "table" and policy.direction == "download" and
			(policy.mac == normalized_mac or policy.destination_ip == ipv4) then
			return policy
		end
	end
	return nil
end

function find_download_policy_conflict(policies, mac, ipv4)
	local normalized_mac = normalize_unicast_mac(type(mac) == "string" and mac or "")
	if not normalized_mac or not valid_ipv4_host(ipv4) then return nil end
	for _, policy in ipairs(type(policies) == "table" and policies or {}) do
		if type(policy) == "table" and policy.direction == "download" and
			(policy.mac == normalized_mac or policy.destination_ip == ipv4) then
			return policy
		end
	end
	return nil
end

function snapshot_client_policy_section(snapshot)
	if type(snapshot) ~= "table" or snapshot[".type"] ~= "rule"
		or not summarize_client_policy(snapshot) then
		return nil, "A QuantumGrid-owned DSCP client rule is required."
	end
	local values = {}
	for key, value in pairs(snapshot) do
		if type(key) == "string" and key:sub(1, 1) ~= "." then values[key] = value end
	end
	return { section = snapshot[".name"], values = values }
end
