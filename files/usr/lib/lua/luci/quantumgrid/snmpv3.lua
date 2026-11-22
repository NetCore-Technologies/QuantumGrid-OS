module("luci.quantumgrid.snmpv3", package.seeall)

local VALID_OID = ".1.3.6.1.2.1.1"
local ALLOWED_SECRET_CHARACTERS =
	"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&()*+,-./:;<=>?@[]^_{|}~"

function valid_username(value)
	if type(value) ~= "string" or #value < 1 or #value > 32 then return false end
	if value == "root" then return false end
	return value:match("^[A-Za-z][A-Za-z0-9_.%-]*$") ~= nil
end

function valid_secret(value)
	if type(value) ~= "string" or #value < 20 or #value > 128 then return false end
	for index = 1, #value do
		if not ALLOWED_SECRET_CHARACTERS:find(value:sub(index, index), 1, true) then
			return false
		end
	end
	return true
end

local function trusted_zone_exists(trusted_zones, name)
	if type(trusted_zones) ~= "table" or type(name) ~= "string" then return false end
	if trusted_zones[name] == true then return true end
	for _, zone in ipairs(trusted_zones) do
		if zone == name then return true end
	end
	return false
end

function validate(input, trusted_zones)
	if type(input) ~= "table" then
		return nil, "SNMPv3 settings must be provided."
	end
	if input.confirmed ~= "1" then
		return nil, "Explicit confirmation is required before changing SNMP service settings."
	end
	if input.enabled ~= "1" and input.enabled ~= "0" then
		return nil, "SNMPv3 enabled state must be 1 or 0."
	end
	if input.enabled == "0" then
		return { enabled = false }
	end

	local username = input.username
	if not valid_username(username) then
		return nil, "SNMPv3 username must be 1-32 safe characters, start with a letter and must not be root."
	end
	local auth_pass = input.auth_pass
	local privacy_pass = input.privacy_pass
	if not valid_secret(auth_pass) then
		return nil, "SNMPv3 authentication passphrase must be 20-128 characters using the supported ASCII character set."
	end
	if not valid_secret(privacy_pass) then
		return nil, "SNMPv3 privacy passphrase must be 20-128 characters using the supported ASCII character set."
	end
	if auth_pass == privacy_pass then
		return nil, "SNMPv3 authentication and privacy passphrases must be different."
	end

	local source_zone = input.source_zone
	if not trusted_zone_exists(trusted_zones, source_zone) then
		return nil, "Choose an existing internal management firewall zone; WAN and unknown zones are not allowed."
	end

	return {
		enabled = true,
		username = username,
		auth_type = "SHA",
		auth_pass = auth_pass,
		privacy_type = "AES",
		privacy_pass = privacy_pass,
		allow_write = "0",
		restricted_oid = VALID_OID,
		source_zone = source_zone,
		security_level = "authPriv"
	}
end

local function safe_network_name(value)
	return type(value) == "string" and #value > 0 and #value <= 64 and
		value:match("^[A-Za-z0-9_.:%-]+$") ~= nil
end

local function zone_network_list(value)
	local result = {}
	local seen = {}
	local function add(item)
		if not safe_network_name(item) then return false end
		if not seen[item] then
			seen[item] = true
			table.insert(result, item)
		end
		return true
	end
	if type(value) == "table" then
		for _, item in ipairs(value) do if not add(item) then return nil end end
	elseif type(value) == "string" then
		for item in value:gmatch("%S+") do if not add(item) then return nil end end
	elseif value ~= nil then
		return nil
	end
	return result
end

function trusted_zone_networks(uci, zone_name)
	if type(uci) ~= "table" or type(uci.foreach) ~= "function" or
		type(zone_name) ~= "string" or
		require("luci.quantumgrid.management_transport").classify_firewall_zone_name(zone_name) ~= "internal" then
		return nil, "The selected firewall zone is not a recognised internal management zone."
	end
	local owners = {}
	local selected_networks = nil
	local selected_count = 0
	local ok = pcall(function()
		uci:foreach("firewall", "zone", function(section)
			if type(section) ~= "table" then error("invalid firewall zone") end
			local name = type(section.name) == "string" and section.name or section[".name"]
			if type(name) ~= "string" or name == "" then error("unnamed firewall zone") end
			local networks = zone_network_list(section.network or section.networks)
			if not networks then error("invalid firewall zone network list") end
			if name == zone_name then
				selected_count = selected_count + 1
				selected_networks = networks
			end
			for _, network in ipairs(networks) do
				owners[network] = owners[network] or {}
				table.insert(owners[network], name)
			end
		end)
	end)
	if not ok or selected_count ~= 1 or type(selected_networks) ~= "table" or #selected_networks == 0 then
		return nil, "The selected management zone has no unique, readable network membership."
	end
	for _, network in ipairs(selected_networks) do
		local memberships = owners[network]
		if type(memberships) ~= "table" or #memberships ~= 1 or memberships[1] ~= zone_name then
			return nil, "A management network is attached to multiple firewall zones; SNMP exposure is ambiguous."
		end
	end
	table.sort(selected_networks)
	return selected_networks
end

local managed_user_options = {
	username = true, auth_type = true, auth_pass = true, privacy_type = true,
	privacy_pass = true, allow_write = true, RestrictedOID = true, source_zone = true
}

function has_only_managed_user_options(section)
	if type(section) ~= "table" or section[".type"] ~= "v3" or
		section[".name"] ~= "quantumgrid" then return false end
	for option in pairs(section) do
		if type(option) ~= "string" then return false end
		if option:sub(1, 1) ~= "." and not managed_user_options[option] then return false end
	end
	return true
end

local managed_firewall_options = {
	name = true, src = true, proto = true, dest_port = true,
	target = true, family = true, enabled = true
}

function has_only_managed_firewall_options(section)
	if type(section) ~= "table" or section[".type"] ~= "rule" or
		section[".name"] ~= "quantumgrid_snmpv3" then return false end
	for option in pairs(section) do
		if type(option) ~= "string" then return false end
		if option:sub(1, 1) ~= "." and not managed_firewall_options[option] then return false end
	end
	return true
end

function has_expected_agent_listener(uci)
	if type(uci) ~= "table" or type(uci.foreach) ~= "function" then return false end
	local count = 0
	local valid = false
	local ok = pcall(function()
		uci:foreach("snmpd", "agent", function(section)
			count = count + 1
			if type(section) ~= "table" or section[".type"] ~= "agent" or
				section[".name"] ~= "agent" then
				valid = false
				return
			end
			for option in pairs(section) do
				if type(option) ~= "string" or
					(option:sub(1, 1) ~= "." and option ~= "agentaddress") then
					valid = false
					return
				end
			end
			valid = section.agentaddress == "UDP:161,UDP6:161"
		end)
	end)
	return ok and count == 1 and valid
end

function private_root_file(stat)
	if type(stat) ~= "table" or tonumber(stat.uid) ~= 0 then return false end
	local mode = tonumber(stat.modedec or stat.mode)
	return mode ~= nil and mode % 512 == 384
end

function snmpd_process_running(pid_contents, comm_contents, cmdline_contents)
	if type(pid_contents) ~= "string" then return false end
	local pid_text = pid_contents:match("^%s*(%d+)%s*$")
	local pid = pid_text and tonumber(pid_text) or nil
	if not pid or pid <= 1 or pid ~= math.floor(pid) then return false end
	if type(comm_contents) ~= "string" or
		comm_contents:match("^%s*(.-)%s*$") ~= "snmpd" then return false end
	if type(cmdline_contents) ~= "string" then return false end
	return cmdline_contents:find("/usr/sbin/snmpd", 1, true) ~= nil and
		cmdline_contents:find("/var/run/snmpd.conf", 1, true) ~= nil
end

local function contains_udp(value)
	if value == nil or value == "" then return true end
	if type(value) == "table" then
		for _, item in ipairs(value) do
			if item == "udp" or item == "all" or item == "any" then return true end
		end
		return false
	end
	if type(value) ~= "string" then return false end
	for token in value:gmatch("[^,%s]+") do
		if token == "udp" or token == "all" or token == "any" then return true end
	end
	return false
end

local function contains_snmp_port(value)
	if value == nil or value == "" then return true end
	local values = type(value) == "table" and value or { value }
	for _, raw in ipairs(values) do
		if type(raw) ~= "string" then return true end
		for token in raw:gmatch("[^,%s]+") do
			local port = tonumber(token)
			if port == 161 then return true end
			local first, last = token:match("^(%d+)%-(%d+)$")
			if first and last and tonumber(first) <= 161 and tonumber(last) >= 161 then
				return true
			end
		end
	end
	return false
end

function has_conflicting_firewall_rule(uci)
	if type(uci) ~= "table" or type(uci.foreach) ~= "function" then return nil end
	local conflict = false
	local ok = pcall(function()
		uci:foreach("firewall", "rule", function(section)
			if section[".name"] == "quantumgrid_snmpv3" then return end
			local target = type(section.target) == "string" and section.target:upper() or "ACCEPT"
			if target == "ACCEPT" and contains_udp(section.proto) and
				contains_snmp_port(section.dest_port) then
				conflict = true
			end
		end)
	end)
	if not ok then return nil end
	return conflict
end

function private_file_mode_secure(mode)
	if type(mode) ~= "number" or mode < 0 or mode ~= math.floor(mode) then return false end
	return mode % 512 == 384
end

function credentials_file_private(stat)
	return private_root_file(stat)
end

function classify_status(snapshot)
	if type(snapshot) ~= "table" or snapshot.available ~= true then
		return "unavailable"
	end
	if snapshot.legacy_community_configured == true then
		return "review"
	end
	if snapshot.enabled ~= true then
		if snapshot.process_running == true or snapshot.firewall_rule_present == true or
			snapshot.runtime_credentials_present == true or snapshot.firewall_conflict == true or
			snapshot.firewall_inventory_available ~= true then
			return "review"
		end
		return "disabled"
	end
	if snapshot.agent_listener_configured ~= true or
		snapshot.snmp_version ~= "v3" or
		not valid_username(snapshot.username) or
		snapshot.auth_type ~= "SHA" or
		snapshot.privacy_type ~= "AES" or
		snapshot.allow_write ~= "0" or
		snapshot.restricted_oid ~= VALID_OID or
		snapshot.managed_user_section ~= true or
		snapshot.source_zone_class ~= "internal" or
		snapshot.user_source_zone ~= snapshot.source_zone or
		snapshot.network_membership_verified ~= true or
		snapshot.legacy_network_firewall == true or
		snapshot.firewall_perimeter_safe ~= true or
		snapshot.firewall_conflict == true or
		snapshot.firewall_rule_configured ~= true or
		snapshot.managed_user_section ~= true or
		snapshot.managed_firewall_rule ~= true or
		snapshot.firewall_inventory_available ~= true or
		snapshot.private_config_permissions ~= true or
		snapshot.runtime_credentials_private ~= true or
		snapshot.runtime_credentials_present ~= true or
		snapshot.process_running ~= true then
		return "review"
	end
	return "ready"
end

function wait_for_state(sample_fn, sleep_fn, expected_enabled, expected_username, expected_zone, attempts)
	if type(sample_fn) ~= "function" or type(sleep_fn) ~= "function" then
		return nil, false
	end
	local limit = tonumber(attempts) or 10
	if limit < 1 or limit > 20 or limit ~= math.floor(limit) then limit = 10 end
	local last = nil
	for attempt = 1, limit do
		local ok, state = pcall(sample_fn)
		if ok and type(state) == "table" then
			last = state
			if expected_enabled == true then
				if state.enabled == true and state.status == "ready" and
					state.username == expected_username and state.source_zone == expected_zone then
					return state, true
				end
			else
				if state.enabled == false and state.process_running == false then
					return state, true
				end
			end
		end
		if attempt < limit then pcall(sleep_fn) end
	end
	return last, false
end

return _M
