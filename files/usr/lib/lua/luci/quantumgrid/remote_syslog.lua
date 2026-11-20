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
	if protocol ~= "tcp" and protocol ~= "udp" then
		return nil, "Remote syslog transport must be TCP or UDP."
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
	return {
		enabled = true,
		host = host,
		port = tostring(port),
		protocol = protocol,
		hostname = hostname,
		prefix = prefix
	}
end

return _M
