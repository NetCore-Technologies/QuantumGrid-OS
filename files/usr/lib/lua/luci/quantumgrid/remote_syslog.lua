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
	return true
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
	if type(host) ~= "string" or #host > 253
		or (not valid_ipv4(host) and not valid_hostname(host)) then
		return nil, "Enter a valid IPv4 address or DNS host name for the remote syslog server."
	end
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
		if valid_ipv4(host) then server_ip = host else server_name = host end
		result.tls = {
			section = "quantumgrid_syslog",
			local_host = "127.0.0.1",
			local_port = "5514",
			ca_file = "/etc/ssl/certs/ca-certificates.crt",
			connect = host .. ":" .. tostring(port),
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
		non_root_identity(globals.setuid) and non_root_identity(globals.setgid)
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

function inspect_status(uci, fs, sampled_at)
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
	if not tunnel_ok or type(tunnel) ~= "table" or tunnel[".type"] ~= "service" then
		result.tls_status = result.tls_available and "review" or "unavailable"
		result.enabled = false
		result.tls_error = "The managed TLS tunnel section is missing or invalid."
		return result
	end

	local connect = only_entry(tunnel.connect)
	local remote_host, remote_port_text = nil, nil
	if connect then remote_host, remote_port_text = connect:match("^([^:]+):([1-9]%d*)$") end
	local remote_port = tonumber(remote_port_text)
	local valid_remote_host = remote_host ~= nil and
		(valid_ipv4(remote_host) or valid_hostname(remote_host))
	if valid_remote_host and remote_port and remote_port <= 65535 then
		result.host = remote_host
		result.port = remote_port
	else
		remote_host = nil
		remote_port = nil
	end

	local is_ipv4 = remote_host ~= nil and valid_ipv4(remote_host)
	local identity_ok = false
	if is_ipv4 then
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
	elseif not result.tls_enabled then
		result.tls_status = "disabled"
	else
		result.tls_status = "ready"
	end
	result.enabled = result.enabled and result.tls_enabled and tls_configured and result.tls_available
	if not result.tls_available then
		result.tls_error = "The stunnel service, UCI configuration or trusted CA bundle is unavailable."
	elseif not result.tls_privilege_drop_configured then
		result.tls_error = "The stunnel global configuration must drop privileges to a non-root user and group."
	elseif not tls_configured then
		result.tls_error = "TLS 1.2, chain verification, local listener or exact remote certificate identity configuration is incomplete."
	end
	return result
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
