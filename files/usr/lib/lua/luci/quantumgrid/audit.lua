module("luci.quantumgrid.audit", package.seeall)

local LOG_DIR = "/etc/quantumgrid"
local LOG_PATH = LOG_DIR .. "/audit.jsonl"
local ROTATED_PATH = LOG_PATH .. ".1"
local MAX_LOG_BYTES = 512 * 1024
local MAX_EVENTS = 200

local ALLOWED_ACTIONS = {
	["admin.password.setup"] = true,
	["wireless.update"] = true,
	["sqm.update"] = true,
	["dhcp.reservation.add"] = true,
	["dhcp.reservation.update"] = true,
	["dhcp.reservation.remove"] = true,
	["dhcp.scope.update"] = true,
	["dhcp.scope.toggle"] = true,
	["dhcp.scope.add"] = true,
	["dhcp.scope.remove"] = true,
	["office.vlan.update"] = true,
	["office.vlan.remove"] = true,
	["office.forwarding.add"] = true,
	["office.forwarding.remove"] = true,
	["package.install"] = true,
	["package.remove"] = true,
	["package.feed.update"] = true,
	["hardware.led.update"] = true,
	["system.config.backup"] = true,
	["system.syslog.update"] = true
}

local function clean(value, limit)
	if type(value) ~= "string" then return "" end
	return value:gsub("[%c]", " "):sub(1, limit or 96)
end

local function quote(value)
	local text = clean(value, 160)
	text = text:gsub("\\", "\\\\"):gsub('"', '\\"')
	text = text:gsub("\n", "\\n"):gsub("\r", "\\r")
	return '"' .. text .. '"'
end

function encode_event(event)
	if type(event) ~= "table" then return nil, "Audit event must be a table." end
	local action = clean(event.action, 64)
	if not ALLOWED_ACTIONS[action] then return nil, "Audit action is not allowlisted." end
	local outcome = event.outcome
	if outcome ~= "success" and outcome ~= "failed" then
		return nil, "Audit outcome must be success or failed."
	end
	local timestamp = tonumber(event.timestamp) or os.time()
	if timestamp < 0 or timestamp ~= math.floor(timestamp) then
		return nil, "Audit timestamp is invalid."
	end
	local target = clean(event.target, 96)
	local remote_ip = clean(event.remote_ip, 64)
	local actor = clean(event.actor, 32)
	if actor == "" then actor = "root" end

	return "{" ..
		'"timestamp":' .. tostring(timestamp) .. "," ..
		'"actor":' .. quote(actor) .. "," ..
		'"remote_ip":' .. quote(remote_ip) .. "," ..
		'"action":' .. quote(action) .. "," ..
		'"target":' .. quote(target) .. "," ..
		'"outcome":' .. quote(outcome) ..
		"}"
end

function append(event)
	local encoded, encode_error = encode_event(event)
	if not encoded then return false, encode_error end

	local fs = require "nixio.fs"
	local mkdir_ok, mkdir_result = pcall(fs.mkdirr, LOG_DIR)
	if not mkdir_ok or (mkdir_result == false) then
		return false, "Audit log directory could not be created."
	end
	pcall(fs.chmod, LOG_DIR, 448)

	local current = io.open(LOG_PATH, "r")
	if current then
		local size = current:seek("end") or 0
		current:close()
		if size > MAX_LOG_BYTES then
			os.remove(ROTATED_PATH)
			local rotate_ok = os.rename(LOG_PATH, ROTATED_PATH)
			if not rotate_ok then return false, "Audit log rotation failed." end
			pcall(fs.chmod, ROTATED_PATH, 384)
		end
	end

	local file = io.open(LOG_PATH, "a")
	if not file then return false, "Audit log file could not be opened." end
	local write_ok, written = pcall(file.write, file, encoded .. "\n")
	local close_ok = pcall(file.close, file)
	if not write_ok or written == nil or not close_ok then
		return false, "Audit event could not be written."
	end
	pcall(fs.chmod, LOG_PATH, 384)
	return true
end

function parse_log(contents, decoder)
	local result = { available = type(contents) == "string", events = {}, count = 0, truncated = false }
	if type(contents) ~= "string" or type(decoder) ~= "function" then
		result.available = false
		return result
	end
	local lines = {}
	for line in contents:gmatch("[^\r\n]+") do
		if #line <= 2048 then table.insert(lines, line) end
	end
	result.count = #lines
	local start = math.max(1, #lines - MAX_EVENTS + 1)
	result.truncated = start > 1
	for index = start, #lines do
		local ok, event = pcall(decoder, lines[index])
		if ok and type(event) == "table"
			and type(event.timestamp) == "number"
			and type(event.action) == "string"
			and ALLOWED_ACTIONS[event.action] == true
			and (event.outcome == "success" or event.outcome == "failed") then
			table.insert(result.events, {
				timestamp = event.timestamp,
				actor = clean(event.actor, 32),
				remote_ip = clean(event.remote_ip, 64),
				action = clean(event.action, 64),
				target = clean(event.target, 96),
				outcome = event.outcome
			})
		end
	end
	local reversed = {}
	for index = #result.events, 1, -1 do
		table.insert(reversed, result.events[index])
	end
	result.events = reversed
	return result
end

function log_path()
	return LOG_PATH
end

return _M
