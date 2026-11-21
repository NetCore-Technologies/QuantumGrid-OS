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
