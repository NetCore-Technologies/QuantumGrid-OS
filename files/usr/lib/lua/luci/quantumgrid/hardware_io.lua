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
