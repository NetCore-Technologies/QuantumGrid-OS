module("luci.quantumgrid.remote_syslog", package.seeall)

local function valid_ipv4(value)
	if type(value) ~= "string" then return false end
	local a, b, c, d = value:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	if not a then return false end
	local octets = { a, b, c, d }
	for _, part in ipairs(octets) do
		local number = tonumber(part)
		if not number or number < 0 or number > 255 or number ~= math.floor(number)
			or tostring(number) ~= part then
			return false
		end
	end
	local first, second, third = tonumber(a), tonumber(b), tonumber(c)
	if first == 0 or first == 127 or first >= 224 or
		(first == 169 and second == 254) or
		(first == 192 and second == 0 and third == 2) or
		(first == 198 and (second == 18 or second == 19 or (second == 51 and third == 100))) or
		(first == 203 and second == 0 and third == 113) then
		return false
	end
	return true
end

local function normalize_ipv6(value)
	if type(value) ~= "string" or #value < 2 or #value > 39 or
		value:find("[^%x:]") or value:find(":::") or value:find("%%", 1, true) then
		return nil
	end
	local compression = value:find("::", 1, true)
	if compression and value:find("::", compression + 2, true) then return nil end
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
		local left = parse_side(value:sub(1, compression - 1))
		local right = parse_side(value:sub(compression + 2))
		if not left or not right or #left + #right >= 8 then return nil end
		for _, part in ipairs(left) do groups[#groups + 1] = part end
		for _ = 1, 8 - #left - #right do groups[#groups + 1] = 0 end
		for _, part in ipairs(right) do groups[#groups + 1] = part end
	else
		local parsed = parse_side(value)
		if not parsed or #parsed ~= 8 then return nil end
		groups = parsed
	end
	if #groups ~= 8 then return nil end
	local all_zero = true
	for _, part in ipairs(groups) do if part ~= 0 then all_zero = false break end end
	if all_zero or (groups[1] == 0 and groups[2] == 0 and groups[3] == 0 and
		groups[4] == 0 and groups[5] == 0 and groups[6] == 0 and
		groups[7] == 0 and groups[8] == 1) then return nil end
	local first = groups[1]
	local unicast_global = first >= 0x2000 and first <= 0x3fff
	local unique_local = first >= 0xfc00 and first <= 0xfdff
	if not unicast_global and not unique_local then return nil end
	if first == 0x2001 and (groups[2] < 0x0200 or groups[2] == 0x0db8) then return nil end
	if first == 0x2002 or (first == 0x3fff and groups[2] < 0x1000) then return nil end
	if groups[1] == 0 and groups[2] == 0 and groups[3] == 0 and
		groups[4] == 0 and groups[5] == 0 and groups[6] == 0xffff then return nil end
	local canonical = {}
	for _, part in ipairs(groups) do canonical[#canonical + 1] = string.format("%04x", part) end
	return table.concat(canonical, ":")
end

local function valid_hostname(value)
	if type(value) ~= "string" or #value < 1 or #value > 253
		or value:sub(1, 1) == "." or value:sub(-1) == "." then
		return false
	end
	if value:match("^[%d%.]+$") then return false end
	for label in value:gmatch("[^.]+") do
		if #label < 1 or #label > 63
			or not label:match("^[A-Za-z0-9][A-Za-z0-9%-]*[A-Za-z0-9]$")
			and not label:match("^[A-Za-z0-9]$") then
			return false
		end
	end
	return not value:find("..", 1, true)
end

function validate(input)
	if type(input) ~= "table" then return nil, "Remote syslog settings must be provided." end
	if input.confirmed ~= "1" then return nil, "Explicit confirmation is required before changing remote syslog settings." end
	local enabled = input.enabled
	if enabled ~= "1" and enabled ~= "0" then
		return nil, "Remote syslog enabled state must be 1 or 0."
	end
	if enabled == "0" then
		return { enabled = false }
	end

	local host = input.host
	local ipv6_host = normalize_ipv6(host)
	if type(host) ~= "string" or #host > 253 or
		(not valid_ipv4(host) and not ipv6_host and not valid_hostname(host)) then
		return nil, "Enter a valid IPv4 address, unicast IPv6 address or DNS host name for the remote syslog server."
	end
	if ipv6_host then host = ipv6_host end
	local port_text = input.port
	if type(port_text) ~= "string" or #port_text > 5
		or not port_text:match("^[1-9]%d*$") then
		return nil, "Remote syslog port must be a whole number from 1 to 65,535."
	end
	local port = tonumber(port_text)
	if not port or port < 1 or port > 65535 then
		return nil, "Remote syslog port must be a whole number from 1 to 65,535."
	end
	local protocol = input.protocol
	if protocol ~= "tcp" and protocol ~= "udp" and protocol ~= "tls" then
		return nil, "Remote syslog transport must be UDP, TCP or authenticated TLS."
	end
	local hostname = input.hostname or ""
	if type(hostname) ~= "string" or (hostname ~= "" and not valid_hostname(hostname)) then
		return nil, "The syslog sender hostname must be a valid DNS host name."
	end
	local prefix = input.prefix or ""
	if type(prefix) ~= "string" or #prefix > 32
		or (prefix ~= "" and not prefix:match("^[A-Za-z0-9][A-Za-z0-9_.%-]*$")) then
		return nil, "The optional syslog prefix may contain only letters, digits, dots, underscores and hyphens (maximum 32 characters)."
	end
	local result = {
		enabled = true,
		host = host,
		port = tostring(port),
		protocol = protocol,
		hostname = hostname,
		prefix = prefix
	}
	if protocol == "tls" then
		local server_name = nil
		local server_ip = nil
		local connect_host = host
		if valid_ipv4(host) then
			server_ip = host
		elseif ipv6_host then
			server_ip = host
			connect_host = "[" .. host .. "]"
		else
			server_name = host
		end
		result.tls = {
			section = "quantumgrid_syslog",
			local_host = "127.0.0.1",
			local_port = "5514",
			ca_file = "/etc/ssl/certs/ca-certificates.crt",
			connect = connect_host .. ":" .. tostring(port),
			verify_chain = true,
			check_host = server_name,
			check_ip = server_ip,
			sni = server_name
		}
	end
	return result
end

local function non_root_identity(value)
	if type(value) ~= "string" or #value > 32 then return false end
	local normalized = value:lower():match("^%s*(.-)%s*$")
	if not normalized or normalized == "" or normalized == "root" then return false end
	if normalized:match("^[1-9]%d*$") then return tonumber(normalized) ~= nil end
	return normalized:match("^[a-z_][a-z0-9_-]*$") ~= nil
end

function has_non_root_privilege_drop(globals)
	return type(globals) == "table" and globals[".type"] == "globals" and
		(globals.alt_config_file == nil or globals.alt_config_file == "") and
		non_root_identity(globals.setuid) and non_root_identity(globals.setgid)
end

local managed_service_options = {
	enabled = true, client = true, accept_host = true, accept_port = true,
	CAfile = true, verifyChain = true, sslVersion = true, TIMEOUTconnect = true,
	retry = true, connect = true, checkHost = true, checkIP = true, sni = true
}

function has_only_managed_service_options(section)
	if type(section) ~= "table" or section[".type"] ~= "service" then return false end
	for option in pairs(section) do
		if type(option) ~= "string" then return false end
		if option:sub(1, 1) ~= "." and not managed_service_options[option] then return false end
	end
	return true
end

local function fs_has_access(fs, path)
	if type(fs) ~= "table" or type(fs.access) ~= "function" then return false end
	local ok, value = pcall(fs.access, path)
	return ok and value == true
end

local function only_value(value, wanted)
	if type(value) == "string" then return value == wanted end
	if type(value) ~= "table" or #value ~= 1 then return false end
	return value[1] == wanted
end

local function only_entry(value)
	if type(value) == "string" then return value end
	if type(value) == "table" and #value == 1 and type(value[1]) == "string" then
		return value[1]
	end
	return nil
end

function inspect_status(uci, fs, sampled_at, process)
	local stunnel_installed = fs_has_access(fs, "/etc/init.d/stunnel")
	local stunnel_config_available = fs_has_access(fs, "/etc/config/stunnel")
	local ca_bundle_available = fs_has_access(fs, "/etc/ssl/certs/ca-certificates.crt")
	local result = {
		available = false,
		service_installed = fs_has_access(fs, "/etc/init.d/log"),
		config_available = fs_has_access(fs, "/etc/config/system"),
		stunnel_installed = stunnel_installed,
		stunnel_config_available = stunnel_config_available,
		tls_available = stunnel_installed and stunnel_config_available and ca_bundle_available,
		tls_privilege_drop_configured = false,
		tls_process_running = stunnel_process_running(
			type(process) == "table" and process.pid or nil,
			type(process) == "table" and process.comm or nil,
			type(process) == "table" and process.cmdline or nil
		),
		tls_enabled = false,
		tls_status = "unavailable",
		enabled = false,
		host = "",
		port = 514,
		protocol = "udp",
		hostname = "",
		prefix = "",
		sampled_at = tonumber(sampled_at) or os.time()
	}
	if not result.config_available or type(uci) ~= "table" or type(uci.foreach) ~= "function" then
		return result
	end

	local globals_ok, globals = pcall(uci.get_all, uci, "stunnel", "globals")
	result.tls_privilege_drop_configured = globals_ok and
		has_non_root_privilege_drop(globals)

	local system_section = nil
	local section_count = 0
	local system_ok = pcall(function()
		uci:foreach("system", "system", function(section)
			section_count = section_count + 1
			if section_count == 1 then system_section = section end
		end)
	end)
	result.available = system_ok and section_count == 1 and type(system_section) == "table" and
		system_section[".type"] == "system"
	if not result.available then return result end

	result.host = type(system_section.log_ip) == "string" and system_section.log_ip or ""
	result.port = tonumber(system_section.log_port) or 514
	result.protocol = system_section.log_proto == "tcp" and "tcp" or "udp"
	result.hostname = type(system_section.log_hostname) == "string" and system_section.log_hostname or ""
	result.prefix = type(system_section.log_prefix) == "string" and system_section.log_prefix or ""
	result.enabled = result.host ~= "" and system_section.log_remote == "1"
	local local_tls_forwarder = result.host == "127.0.0.1" and
		result.port == 5514 and result.protocol == "tcp"
	if not local_tls_forwarder then return result end

	result.protocol = "tls"
	local tunnel_ok, tunnel = pcall(uci.get_all, uci, "stunnel", "quantumgrid_syslog")
	if not tunnel_ok or not has_only_managed_service_options(tunnel) then
		result.tls_status = result.tls_available and "review" or "unavailable"
		result.enabled = false
		result.tls_error = "The managed TLS tunnel section is missing or invalid."
		return result
	end

	local connect = only_entry(tunnel.connect)
	local remote_host, remote_port_text = nil, nil
	if connect then
		remote_host, remote_port_text = connect:match("^%[([%x:]+)%]:([1-9]%d*)$")
		if not remote_host then remote_host, remote_port_text = connect:match("^([^:]+):([1-9]%d*)$") end
	end
	local remote_ipv6 = remote_host and normalize_ipv6(remote_host) or nil
	local remote_port = tonumber(remote_port_text)
	local valid_remote_host = remote_host ~= nil and
		(valid_ipv4(remote_host) or remote_ipv6 ~= nil or valid_hostname(remote_host))
	if remote_ipv6 then remote_host = remote_ipv6 end
	if valid_remote_host and remote_port and remote_port <= 65535 then
		result.host = remote_host
		result.port = remote_port
	else
		remote_host = nil
		remote_port = nil
	end

	local is_ip = remote_host ~= nil and (valid_ipv4(remote_host) or remote_ipv6 ~= nil)
	local identity_ok = false
	if is_ip then
		identity_ok = only_value(tunnel.checkIP, remote_host) and
			tunnel.checkHost == nil and tunnel.sni == nil
	elseif remote_host then
		identity_ok = only_value(tunnel.checkHost, remote_host) and
			only_value(tunnel.sni, remote_host) and tunnel.checkIP == nil
	end
	local tls_configured = result.tls_privilege_drop_configured and
		tunnel.client == "1" and tunnel.verifyChain == "1" and
		tunnel.sslVersion == "TLSv1.2" and
		tunnel.CAfile == "/etc/ssl/certs/ca-certificates.crt" and
		tunnel.accept_host == "127.0.0.1" and tonumber(tunnel.accept_port) == 5514 and
		remote_port ~= nil and remote_port >= 1 and remote_port <= 65535 and identity_ok

	result.tls_identity_verified = identity_ok
	result.tls_configured = tls_configured
	result.tls_enabled = tunnel.enabled == "1"
	if not result.tls_available then
		result.tls_status = "unavailable"
	elseif not result.tls_privilege_drop_configured then
		result.tls_status = "review"
	elseif not tls_configured then
		result.tls_status = "review"
	elseif not result.tls_enabled and not result.tls_process_running then
		result.tls_status = "disabled"
	elseif not result.tls_process_running then
		result.tls_status = "review"
	elseif not result.enabled and result.tls_process_running then
		result.tls_status = "review"
	elseif not result.tls_enabled then
		result.tls_status = "review"
	else
		result.tls_status = "ready"
	end
	result.enabled = result.enabled and result.tls_enabled and tls_configured and
		result.tls_available and result.tls_process_running
	if not result.tls_available then
		result.tls_error = "The stunnel service, UCI configuration or trusted CA bundle is unavailable."
	elseif not result.tls_privilege_drop_configured then
		result.tls_error = "The stunnel global configuration must drop privileges to a non-root user and group."
	elseif not tls_configured then
		result.tls_error = "TLS 1.2, chain verification, local listener or exact remote certificate identity configuration is incomplete."
	elseif not result.tls_process_running then
		result.tls_error = "The managed stunnel process is not running with its expected PID, process identity and generated configuration file."
	elseif not result.enabled and result.tls_process_running then
		result.tls_error = "The stunnel process is running while remote logging is disabled; inspect for stale tunnel state."
	elseif not result.tls_enabled then
		result.tls_error = "The stunnel process is running while the managed service is configured as disabled; inspect for stale tunnel state."
	end
	return result
end

function wait_for_ready(sample, wait, host, port, max_attempts)
	if type(sample) ~= "function" or type(host) ~= "string" then return nil, false, 0 end
	local expected_port = tonumber(port)
	local attempts = tonumber(max_attempts) or 1
	if not expected_port or expected_port < 1 or expected_port > 65535 or
		attempts < 1 or attempts > 20 or attempts ~= math.floor(attempts) then
		return nil, false, 0
	end
	local last = nil
	for attempt = 1, attempts do
		local sample_ok, status = pcall(sample)
		if sample_ok and type(status) == "table" then
			last = status
			if status.enabled == true and status.protocol == "tls" and
				status.tls_status == "ready" and status.tls_process_running == true and
				status.host == host and tonumber(status.port) == expected_port then
				return status, true, attempt
			end
		end
		if attempt < attempts and type(wait) == "function" then pcall(wait) end
	end
	return last, false, attempts
end

function stunnel_process_running(pid_contents, comm_contents, cmdline_contents)
	if type(pid_contents) ~= "string" then return false end
	local pid_text = pid_contents:match("^%s*(%d+)%s*$")
	local pid = pid_text and tonumber(pid_text) or nil
	if not pid or pid <= 1 or pid ~= math.floor(pid) then return false end
	if type(comm_contents) ~= "string" or comm_contents:match("^%s*(.-)%s*$") ~= "stunnel" then
		return false
	end
	if type(cmdline_contents) ~= "string" then return false end
	local executable, config_file, trailing = cmdline_contents:match("^([^%z]+)%z([^%z]+)%z(.*)$")
	return executable == "/usr/bin/stunnel" and config_file == "/var/etc/stunnel.conf" and trailing == ""
end

function normalize_ipv6_address(value)
	return normalize_ipv6(value)
end

function requires_tunnel_restart(update, system_snapshot, tunnel_snapshot, service_available)
	if service_available ~= true then return false end
	if type(update) == "table" and type(update.tls) == "table" then return true end
	local configured_enabled = type(tunnel_snapshot) == "table" and tunnel_snapshot.enabled == "1"
	local system_points_to_tunnel = type(system_snapshot) == "table" and
		system_snapshot.log_ip == "127.0.0.1" and
		tostring(system_snapshot.log_port or "") == "5514" and
		system_snapshot.log_proto == "tcp"
	return configured_enabled or system_points_to_tunnel
end

function stunnel_options(update)
	if type(update) ~= "table" or update.enabled ~= true or type(update.tls) ~= "table" then
		return nil
	end
	local tls = update.tls
	local scalars = {
		enabled = "1",
		client = "1",
		accept_host = tls.local_host,
		accept_port = tls.local_port,
		CAfile = tls.ca_file,
		verifyChain = "1",
		sslVersion = "TLSv1.2",
		TIMEOUTconnect = "10",
		retry = "1"
	}
	local lists = { connect = { tls.connect }, checkHost = {}, checkIP = {}, sni = {} }
	if tls.check_host then
		table.insert(lists.checkHost, tls.check_host)
		table.insert(lists.sni, tls.sni)
	end
	if tls.check_ip then table.insert(lists.checkIP, tls.check_ip) end
	return { section = tls.section, scalars = scalars, lists = lists }
end

return _M
