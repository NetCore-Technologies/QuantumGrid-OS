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
	local management = require "luci.quantumgrid.management_transport"
	for _, network in ipairs(selected_networks) do
		local memberships = owners[network]
		if type(memberships) ~= "table" or #memberships ~= 1 or memberships[1] ~= zone_name then
			return nil, "A management network is attached to multiple firewall zones; SNMP exposure is ambiguous."
		end
		if management.classify_firewall_zone_name(network) == "external" then
			return nil, "The internal management zone contains a WAN or cellular network; SNMP exposure is unsafe."
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

function legacy_access_configured(uci)
	if type(uci) ~= "table" or type(uci.foreach) ~= "function" then return nil end
	local legacy = false
	local checked = {
		"com2sec", "com2sec6", "access", "access_default",
		"access_HostName", "access_HostIP",
		"trap_HostName", "trap_HostIP", "trapsink", "trap2sink", "informsink",
		"pass", "exec", "extend"
	}
	for _, section_type in ipairs(checked) do
		local ok = pcall(function()
			uci:foreach("snmpd", section_type, function() legacy = true end)
		end)
		if not ok then return nil end
	end
	local groups_ok = pcall(function()
		uci:foreach("snmpd", "group", function(section)
			if type(section) ~= "table" then
				legacy = true
			elseif section.version == "v1" or section.version == "v2c" or
				section.version == "any" then
				legacy = true
			end
		end)
	end)
	if not groups_ok then return nil end
	if type(uci.get_all) ~= "function" then return nil end
	local general_ok, general = pcall(uci.get_all, uci, "snmpd", "general")
	if not general_ok or type(general) ~= "table" or general[".type"] ~= "snmpd" then
		return nil
	end
	for _, option in ipairs({ "trapcommunity", "trapsess", "v1trapaddress" }) do
		local value = general[option]
		if type(value) == "string" and value ~= "" or
			type(value) == "table" and #value > 0 then
			legacy = true
		end
	end
	return legacy
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

function private_root_regular_file(stat)
	if not private_root_file(stat) then return false end
	if stat.type ~= nil then return stat.type == "reg" end
	local mode = tonumber(stat.modedec or stat.mode)
	return mode ~= nil and math.floor(mode / 4096) % 16 == 8
end

function private_root_directory(stat)
	if type(stat) ~= "table" or tonumber(stat.uid) ~= 0 then return false end
	local mode = tonumber(stat.modedec or stat.mode)
	if not mode then return false end
	if stat.type ~= nil then
		if stat.type ~= "dir" then return false end
	elseif math.floor(mode / 4096) % 16 ~= 4 then
		return false
	end
	local permissions = mode % 512
	local group_writable = math.floor(permissions / 16) % 2 == 1
	local world_writable = math.floor(permissions / 2) % 2 == 1
	return not group_writable and not world_writable
end

local function persistent_octet_string(value)
	if type(value) ~= "string" then return nil end
	if value:match("^[A-Za-z0-9 ]+$") then return '"' .. value .. '"' end
	local hex = {}
	for index = 1, #value do
		hex[index] = string.format("%02x", value:byte(index))
	end
	return "0x" .. table.concat(hex)
end

local function persistent_line_tokens(line)
	local tokens = {}
	for token in line:gmatch("%S+") do table.insert(tokens, token) end
	return tokens
end

function inspect_persistent_usm_users(content)
	if type(content) ~= "string" or #content > 4 * 1024 * 1024 then
		return nil, "The Net-SNMP persistent user database is missing, unreadable or too large to inspect safely."
	end
	local total = 0
	local records = {}
	for line in (content .. "\n"):gmatch("(.-)\n") do
		local tokens = persistent_line_tokens(line)
		if tokens[1] == "usmUser" then
			if #tokens < 12 then
				return nil, "The Net-SNMP persistent user database contains a malformed usmUser record."
			end
			total = total + 1
			table.insert(records, {
				username_token = tokens[5],
				security_name_token = tokens[6]
			})
		end
	end
	return { total = total, records = records }
end

function strip_persistent_usm_users(content, usernames)
	local inventory, inventory_error = inspect_persistent_usm_users(content)
	if not inventory then return nil, 0, inventory_error end
	if type(usernames) ~= "table" then return nil, 0, "A username list is required." end
	local encoded = {}
	for _, username in ipairs(usernames) do
		if not valid_username(username) then return nil, 0, "A managed SNMP username is invalid." end
		encoded[persistent_octet_string(username)] = true
	end
	local output = {}
	local removed = 0
	local offset = 1
	while offset <= #content do
		local newline = content:find("\n", offset, true)
		local line, ending
		if newline then
			line = content:sub(offset, newline - 1)
			ending = "\n"
			offset = newline + 1
		else
			line = content:sub(offset)
			ending = ""
			offset = #content + 1
		end
		local tokens = persistent_line_tokens(line)
		local remove = tokens[1] == "usmUser" and
			(encoded[tokens[5]] == true or encoded[tokens[6]] == true)
		if remove then
			removed = removed + 1
		else
			table.insert(output, line .. ending)
		end
	end
	return table.concat(output), removed
end

function inspect_persistent_usm_file(fs, path, username, read_fn)
	if type(fs) ~= "table" or type(fs.lstat) ~= "function" or
		type(path) ~= "string" or path == "" then
		return nil, "The Net-SNMP persistent user database cannot be inspected safely."
	end
	if username ~= nil and username ~= "" and not valid_username(username) then
		return nil, "The managed SNMP username is invalid."
	end
	local directory = path:match("^(.*)/[^/]+$")
	if type(directory) ~= "string" or directory == "" then
		return nil, "The Net-SNMP persistent database path has no verifiable parent directory."
	end
	local directory_ok, directory_stat = pcall(fs.lstat, directory)
	if not directory_ok then
		return nil, "The Net-SNMP persistent directory metadata could not be read."
	end
	if directory_stat == nil then
		return { available = true, present = false, total = 0, matches = 0, user_present = false }
	end
	if not private_root_directory(directory_stat) then
		return nil, "The Net-SNMP persistent directory must be root-owned and not writable by group or other users."
	end
	local stat_ok, stat = pcall(fs.lstat, path)
	if not stat_ok then
		return nil, "The Net-SNMP persistent user database metadata could not be read."
	end
	if stat == nil then
		return { available = true, present = false, total = 0, matches = 0, user_present = false }
	end
	if not private_root_regular_file(stat) then
		return nil, "The Net-SNMP persistent user database must be a root-owned regular file with mode 0600."
	end
	local size = tonumber(stat.size)
	if not size or size < 0 or size > 4 * 1024 * 1024 then
		return nil, "The Net-SNMP persistent user database is too large or has invalid metadata."
	end
	if type(read_fn) ~= "function" then
		read_fn = function(file_path)
			local file = io.open(file_path, "r")
			if not file then return nil end
			local content = file:read(4 * 1024 * 1024 + 1)
			local closed = file:close()
			if closed == nil then return nil end
			return content
		end
	end
	local read_ok, content = pcall(read_fn, path)
	if not read_ok or type(content) ~= "string" or #content > 4 * 1024 * 1024 then
		return nil, "The Net-SNMP persistent user database could not be read safely."
	end
	local inventory, inventory_error = inspect_persistent_usm_users(content)
	if not inventory then return nil, inventory_error end
	local matches = 0
	if username == nil or username == "" then
		matches = inventory.total
	else
		local encoded = persistent_octet_string(username)
		for _, record in ipairs(inventory.records) do
			if record.username_token == encoded or record.security_name_token == encoded then
				matches = matches + 1
			end
		end
	end
	return {
		available = true,
		present = true,
		total = inventory.total,
		matches = matches,
		user_present = matches > 0
	}
end

function persistent_user_matches(content, username)
	local inventory, inventory_error = inspect_persistent_usm_users(content)
	if not inventory then return nil, inventory_error end
	if username == nil or username == "" then return inventory.total > 0, inventory.total end
	if not valid_username(username) then return nil, "The managed SNMP username is invalid." end
	local encoded = persistent_octet_string(username)
	local matches = 0
	for _, record in ipairs(inventory.records) do
		if record.username_token == encoded or record.security_name_token == encoded then
			matches = matches + 1
		end
	end
	return matches > 0, matches, inventory.total
end

function snmpd_process_running(pid_contents, comm_contents, cmdline_contents)
	if type(pid_contents) ~= "string" then return false end
	local pid_text = pid_contents:match("^%s*(%d+)%s*$")
	local pid = pid_text and tonumber(pid_text) or nil
	if not pid or pid <= 1 or pid ~= math.floor(pid) then return false end
	if type(comm_contents) ~= "string" or
		comm_contents:match("^%s*(.-)%s*$") ~= "snmpd" then return false end
	if type(cmdline_contents) ~= "string" or #cmdline_contents > 4096 then return false end

	local args = {}
	for argument in cmdline_contents:gmatch("([^%z]+)") do
		table.insert(args, argument)
	end
	local required = {
		"/usr/sbin/snmpd", "-f", "-r", "-p", "/var/run/snmpd.pid",
		"-C", "-c", "/var/run/snmpd.conf"
	}
	if #args < #required then return false end
	for index, expected in ipairs(required) do
		if args[index] ~= expected then return false end
	end

	local index = #required + 1
	while index <= #args do
		local option = args[index]
		local value = args[index + 1]
		if value == nil then return false end
		if option == "-Ls" then
			if not value:match("^[du0-7]$") then return false end
		elseif option == "-LF" then
			if #value < 3 or #value > 512 or value:find("[%z\r\n]") then return false end
		elseif option == "-Lf" then
			if value ~= "/dev/null" then return false end
		else
			return false
		end
		index = index + 2
	end
	return true
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
			snapshot.firewall_inventory_available ~= true or
			snapshot.persistent_inventory_available ~= true or
			(tonumber(snapshot.persistent_usm_user_count) or 0) > 0 then
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
		snapshot.persistent_inventory_available ~= true or
		snapshot.persistent_user_present ~= true or
		snapshot.persistent_user_matches ~= 1 or
		snapshot.persistent_usm_user_count ~= 1 or
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
				if state.enabled == false and state.process_running == false and
					state.runtime_credentials_present == false and
					state.persistent_inventory_available == true and
					state.persistent_user_present == false and
					(tonumber(state.persistent_user_matches) or 0) == 0 then
					return state, true
				end
			end
		end
		if attempt < limit then pcall(sleep_fn) end
	end
	return last, false
end

return _M
