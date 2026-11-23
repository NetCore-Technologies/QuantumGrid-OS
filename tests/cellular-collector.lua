package.path = "files/usr/lib/lua/?.lua;" .. package.path

local cellular = require "luci.quantumgrid.cellular"

local serving_command = "/sbin/uqmi -s -d /dev/cdc-wdm0 -t 1000 --get-serving-system"
local signal_command = "/sbin/uqmi -s -d /dev/cdc-wdm0 -t 1000 --get-signal-info"
local data_command = "/sbin/uqmi -s -d /dev/cdc-wdm0 -t 1000 --get-data-status"

local function fixture(accessible, outputs)
	local commands, parsed = {}, {}
	local dependencies = {
		now = 1790000123,
		access = function(path) return accessible[path] == true end,
		exec = function(command)
			commands[#commands + 1] = command
			local result = outputs[command]
			if type(result) == "function" then return result() end
			return result
		end,
		parse = function(output)
			parsed[#parsed + 1] = output
			local result = outputs["parsed:" .. output]
			if type(result) == "function" then return result() end
			if result == nil then error("invalid JSON fixture") end
			return result
		end
	}
	return dependencies, commands, parsed
end

-- Serial-only presence is useful evidence that a modem is attached, but is not QMI.
do
	local deps, commands = fixture({
		["/dev/ttyUSB2"] = true,
		["/sbin/uqmi"] = true
	}, {})
	local result = cellular.collect_status(deps)
	assert(result.modem_present and not result.qmi_available)
	assert(#commands == 0, "serial-only modem detection must not invoke QMI")
end

-- A QMI node without the uqmi binary stays explicitly unavailable.
do
	local deps, commands = fixture({ ["/dev/cdc-wdm0"] = true }, {})
	local result = cellular.collect_status(deps)
	assert(result.modem_present and not result.qmi_available)
	assert(#commands == 0)
end

-- Serving, signal and data status use only three fixed, bounded, read-only commands.
do
	local outputs = {
		[serving_command] = "serving-json",
		[signal_command] = "signal-json",
		[data_command] = "data-json",
		["parsed:serving-json"] = {
			registration = "registered",
			plmn_description = "Example Network",
			plmn_mcc = 505,
			plmn_mnc = 1,
			roaming = false,
			radio_interface = { "lte", "nr5g" }
		},
		["parsed:signal-json"] = {
			type = "nr5g", rssi = -72, rsrp = -94, rsrq = -10, snr = 18
		},
		["parsed:data-json"] = "connected"
	}
	local deps, commands, parses = fixture({
		["/dev/cdc-wdm0"] = true,
		["/sbin/uqmi"] = true
	}, outputs)
	local result = cellular.collect_status(deps)
	assert(result.qmi_available and result.modem_present)
	assert(result.sampled_at == 1790000123)
	assert(result.registration == "registered" and result.roaming == false)
	assert(result.operator == "Example Network")
	assert(result.radio_interfaces[2] == "nr5g")
	assert(result.rsrp_dbm == -94 and result.snr_db == 18)
	assert(result.data_status == "connected")
	assert(#commands == 3 and #parses == 3)
	assert(commands[1] == serving_command)
	assert(commands[2] == signal_command)
	assert(commands[3] == data_command)
end

-- Command errors, oversized output and malformed JSON never become telemetry.
do
	local outputs = {
		[serving_command] = function() error("uqmi unavailable") end,
		[signal_command] = string.rep("x", 8193),
		[data_command] = "not-json",
		["parsed:not-json"] = function() error("parse failed") end
	}
	local deps, commands, parses = fixture({
		["/dev/cdc-wdm0"] = true,
		["/sbin/uqmi"] = true
	}, outputs)
	local result = cellular.collect_status(deps)
	assert(result.qmi_available)
	assert(result.registration == nil and result.rsrp_dbm == nil and result.data_status == nil)
	assert(#commands == 3)
	assert(#parses == 1, "failed and oversized command output must not reach the parser")
end

-- Unexpected decoded JSON types are ignored.
do
	local outputs = {
		[serving_command] = "array-json",
		[signal_command] = "number-json",
		[data_command] = "boolean-json",
		["parsed:array-json"] = { "registered" },
		["parsed:number-json"] = 42,
		["parsed:boolean-json"] = true
	}
	local deps = fixture({
		["/dev/cdc-wdm0"] = true,
		["/sbin/uqmi"] = true
	}, outputs)
	local result = cellular.collect_status(deps)
	assert(result.registration == nil)
	assert(result.rssi_dbm == nil)
	assert(result.data_status == nil)
end

-- Incomplete dependencies fail closed without executing a shell command.
do
	local result = cellular.collect_status({ access = function() return true end })
	assert(not result.modem_present and not result.qmi_available)
end

print("cellular-collector: fixed QMI commands, output bounds, device availability and parse-failure tests passed")
