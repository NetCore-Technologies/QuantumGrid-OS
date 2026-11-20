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

function parse_gpio_sysfs_chips(entries, available)
	local result = {
		available = available == true,
		chips = {},
		count = 0,
		truncated = false
	}
	if type(entries) ~= "table" then return result end

	for _, entry in ipairs(entries) do
		if type(entry) == "table" and type(entry.name) == "string"
			and #entry.name <= 32 and entry.name:match("^gpiochip%d+$") then
			local base = tonumber(entry.base)
			local count = tonumber(entry.ngpio)
			if base and count and base >= 0 and base <= 4294967295
				and count >= 1 and count <= 1024
				and math.floor(base) == base and math.floor(count) == count then
				result.count = result.count + 1
				if #result.chips < 16 then
					table.insert(result.chips, {
						name = entry.name,
						label = safe_text(entry.label, 96),
						base = base,
						ngpio = count
					})
				else
					result.truncated = true
				end
			end
		end
	end
	table.sort(result.chips, function(left, right) return left.base < right.base end)
	return result
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

local function aw1000_gpio_reference()
	return {
		available = true,
		model = "Arcadyan AW1000",
		compatible = "arcadyan,aw1000",
		source_url = "https://github.com/openwrt/openwrt/blob/master/target/linux/qualcommax/dts/ipq8072-aw1000.dts",
		source_blob_sha = "42ad979f2997c6dbae8f3ae2d944e3f654efc81b",
		offset_namespace = "Qualcomm TLMM local GPIO offsets",
		warning = "This is the upstream AW1000 device-tree reference, not a runtime ownership probe. TLMM offsets are not necessarily the global GPIO numbers shown by debugfs/sysfs. All output-capable lines remain locked; no GPIO writes are exposed.",
		buttons = {
			{ name = "Wi-Fi / WLAN", purpose = "Physical Wi-Fi button", tlmm_offset = 2, direction = "input", active_level = "low", owner = "gpio-keys", linux_key = "KEY_WLAN" },
			{ name = "WPS", purpose = "Physical WPS button", tlmm_offset = 62, direction = "input", active_level = "low", owner = "gpio-keys", linux_key = "KEY_WPS_BUTTON" },
			{ name = "Reset", purpose = "Physical reset button", tlmm_offset = 67, direction = "input", active_level = "low", owner = "gpio-keys", linux_key = "KEY_RESTART", note = "Native reset/failsafe handler may perform recovery or factory-reset actions." }
		},
		auxiliary = {
			{ name = "LTE power key", purpose = "Modem power-key control", tlmm_offset = 54, direction = "output", active_level = "high", owner = "gpio-export", initial_level = "high" },
			{ name = "LTE power", purpose = "Modem power rail control", tlmm_offset = 30, direction = "output", active_level = "high", owner = "gpio-export", initial_level = "high" },
			{ name = "LTE reset", purpose = "Modem reset control", tlmm_offset = 63, direction = "output", active_level = "high", owner = "gpio-export", initial_level = "high" },
			{ name = "USB VBUS", purpose = "USB VBUS regulator enable", tlmm_offset = 9, direction = "regulator", active_level = "low", owner = "fixed regulator usb_vbus", note = "The DTS marks the regulator boot-on; do not treat this as an arbitrary GPIO output." }
		},
		bus_signals = {
			{ name = "LED expander SPI clock", purpose = "74HC595 serial clock", tlmm_offset = 18, direction = "signal", active_level = "high", owner = "spi-gpio" },
			{ name = "LED expander SPI data", purpose = "74HC595 MOSI", tlmm_offset = 19, direction = "signal", active_level = "high", owner = "spi-gpio" },
			{ name = "LED expander enable", purpose = "74HC595 output enable", tlmm_offset = 20, direction = "signal", active_level = "high", owner = "spi-gpio" },
			{ name = "MDIO clock", purpose = "Ethernet management clock (MDC)", tlmm_offset = 68, direction = "signal", active_level = "n/a", owner = "MDIO pinctrl" },
			{ name = "MDIO data", purpose = "Ethernet management data (MDIO)", tlmm_offset = 69, direction = "signal", active_level = "n/a", owner = "MDIO pinctrl" }
		},
		phy_resets = {
			{ name = "MDIO bus reset", purpose = "Ethernet PHY bus reset", tlmm_offset = 37, direction = "reset", active_level = "low", owner = "MDIO controller" },
			{ name = "QCA8081 WAN PHY reset", purpose = "2.5GbE WAN PHY reset", tlmm_offset = 64, direction = "reset", active_level = "low", owner = "QCA8081 PHY" }
		},
		led_expander = {
			part = "Fairchild 74HC595",
			register_count = 2,
			clock_tlmm_offset = 18,
			data_tlmm_offset = 19,
			enable_tlmm_offset = 20,
			outputs = {
				{ name = "Power", label = "green:power", output_index = 0, active_level = "high" },
				{ name = "Wi-Fi", label = "green:wifi", output_index = 1, active_level = "high" },
				{ name = "Internet", label = "green:internet", output_index = 2, active_level = "high" },
				{ name = "5G red", label = "red:5g", output_index = 3, active_level = "low" },
				{ name = "5G green", label = "green:5g", output_index = 4, active_level = "low" },
				{ name = "5G blue", label = "blue:5g", output_index = 5, active_level = "low" },
				{ name = "Signal red", label = "red:signal", output_index = 6, active_level = "low" },
				{ name = "Signal green", label = "green:signal", output_index = 8, active_level = "low" },
				{ name = "Signal blue", label = "blue:signal", output_index = 9, active_level = "low" },
				{ name = "Phone", label = "green:phone", output_index = 11, active_level = "high" }
			}
		}
	}
end

function parse_board_gpio_reference(compatible_contents)
	local result = { available = false }
	if type(compatible_contents) ~= "string" then return result end
	for item in compatible_contents:gmatch("[^%z]+") do
		if item == "arcadyan,aw1000" then
			return aw1000_gpio_reference()
		end
	end
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
