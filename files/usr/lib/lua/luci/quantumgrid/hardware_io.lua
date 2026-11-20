module("luci.quantumgrid.hardware_io", package.seeall)

local MAX_GPIO_CHIPS = 16
local MAX_GPIO_LINES = 128
local MAX_NAME_LENGTH = 64

local function trim(value)
	return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function safe_text(value, limit)
	if type(value) ~= "string" then return "" end
	return trim(value:gsub("[%c]", " ")):sub(1, limit or 96)
end

local function is_button_label(label, consumer)
	local value = (tostring(label or "") .. " " .. tostring(consumer or "")):lower()
	for _, token in ipairs({ "button", "reset", "wps", "power", "key", "wlan" }) do
		if value:find(token, 1, true) then return true end
	end
	return false
end

function parse_gpio_debugfs(contents)
	local result = {
		available = type(contents) == "string",
		chips = {},
		chip_count = 0,
		lines = {},
		line_count = 0,
		truncated = false
	}
	if type(contents) ~= "string" then return result end

	for line in contents:gmatch("[^\r\n]+") do
		local chip, first, last = line:match("^%s*([%w_.%-]+):%s+GPIOs%s+(%d+)%-(%d+)")
		if chip then
			result.chip_count = result.chip_count + 1
			if #result.chips < MAX_GPIO_CHIPS then
				table.insert(result.chips, {
					name = safe_text(chip, 64),
					first_gpio = tonumber(first),
					last_gpio = tonumber(last)
				})
			else
				result.truncated = true
			end
		else
			local number, description, direction, state =
				line:match("^%s*gpio%-(%d+)%s+%((.-)%)%s+(%a+)%s+(%a+)")
			if number then
				result.line_count = result.line_count + 1
				if #result.lines < MAX_GPIO_LINES then
					local label, consumer = description:match("^(.-)%|(.*)$")
					if label == nil then label, consumer = description, "" end
					label = safe_text(label, 96)
					consumer = safe_text(consumer, 96)
					direction = direction:lower()
					state = state:lower()
					local value = state == "hi" and 1 or state == "lo" and 0 or nil
					table.insert(result.lines, {
						number = tonumber(number),
						label = label,
						consumer = consumer,
						direction = (direction == "in" or direction == "out") and direction or "unknown",
						state = (state == "hi" or state == "lo") and (state == "hi" and "high" or "low") or "unknown",
						value = value,
						is_button = is_button_label(label, consumer)
					})
				else
					result.truncated = true
				end
			end
		end
	end
	return result
end

function parse_input_devices(contents)
	local result = {
		available = type(contents) == "string",
		devices = {},
		count = 0,
		truncated = false
	}
	if type(contents) ~= "string" then return result end

	local current = {}
	local function finish_device()
		if type(current.name) == "string" and current.name ~= "" then
			result.count = result.count + 1
			if #result.devices < 32 then
				local lower_name = current.name:lower()
				local button_like = false
				for _, token in ipairs({ "button", "gpio", "reset", "wps", "power" }) do
					if lower_name:find(token, 1, true) then
						button_like = true
						break
					end
				end
				table.insert(result.devices, {
					name = current.name,
					bus = current.bus,
					handlers = current.handlers or {},
					event_nodes = current.event_nodes or {},
					button_like = button_like
				})
			else
				result.truncated = true
			end
		end
		current = {}
	end

	for line in contents:gmatch("[^\r\n]+") do
		local bus = line:match("^I:%s+Bus=([%x]+)")
		if bus then
			finish_device()
			current.bus = bus:upper()
		else
			local name = line:match('^N:%s+Name="(.-)"')
			if name then
				if current.name then finish_device() end
				current.name = safe_text(name, 128)
			else
				local handler_text = line:match("^H:%s+Handlers=(.*)$")
				if handler_text then
					current.handlers = {}
					current.event_nodes = {}
					for handler in handler_text:gmatch("[%w_.%-]+") do
						if #current.handlers < 16 then
							table.insert(current.handlers, handler)
						end
						if handler:match("^event%d+$") and #current.event_nodes < 8 then
							table.insert(current.event_nodes, handler)
						end
					end
				end
			end
		end
	end
	finish_device()
	return result
end

local MAX_BUTTON_EVENTS = 64

function parse_button_events(contents, sampled_at)
	local result = {
		available = type(contents) == "string",
		monitor_available = false,
		events = {},
		count = 0,
		truncated = false,
		sampled_at = tonumber(sampled_at) or os.time()
	}
	if type(contents) ~= "string" then return result end

	for line in contents:gmatch("[^\r\n]+") do
		local timestamp, sequence, button, action, seen, event_type =
			line:match("^(%d+)|(%d+)|([%w_.%-]+)|([%a]+)|(%d+)|([%a]+)$")
		local at = tonumber(timestamp)
		local duration = tonumber(seen)
		if timestamp and #timestamp <= 12 and sequence and #sequence <= 20
			and button and #button <= 64
			and (action == "pressed" or action == "released")
			and seen and #seen <= 9
			and (event_type == "key" or event_type == "switch")
			and at and at >= 0 and at <= 999999999999
			and duration and duration >= 0 and duration <= 31536000 then
			result.count = result.count + 1
			if #result.events >= MAX_BUTTON_EVENTS then
				table.remove(result.events, 1)
				result.truncated = true
			end
			table.insert(result.events, {
				timestamp = at,
				sequence = sequence,
				button = safe_text(button, 64),
				action = action,
				seen_seconds = duration,
				type = event_type
			})
		end
	end
	return result
end

function parse_trigger_text(contents)
	if type(contents) ~= "string" then
		return { available = false, active = nil }
	end
	local active = contents:match("%[([%w_.%-]+)%]")
	if not active then
		return { available = false, active = nil }
	end
	return { available = true, active = active }
end

function validate_led_update(name, brightness, maximum)
	if type(name) ~= "string" or #name < 1 or #name > MAX_NAME_LENGTH
		or name == "." or name == ".." or not name:match("^[%w_.:%-]+$") then
		return nil, "Invalid LED class device name."
	end
	if type(maximum) ~= "number" or maximum ~= math.floor(maximum)
		or maximum < 1 or maximum > 65535 then
		return nil, "The LED maximum brightness is unavailable or outside the supported range."
	end

	local value
	if type(brightness) == "number" then
		value = brightness
	elseif type(brightness) == "string" and brightness:match("^%d+$") then
		value = tonumber(brightness)
	else
		return nil, "Brightness must be a whole number."
	end
	if not value or value ~= math.floor(value) or value < 0 or value > maximum then
		return nil, "Brightness must be between 0 and the LED's reported maximum."
	end

	return {
		name = name,
		brightness = value,
		max_brightness = maximum
	}
end
