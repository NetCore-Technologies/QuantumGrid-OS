package.path = "files/usr/lib/lua/?.lua;" .. package.path
local hardware = require "luci.quantumgrid.hardware_io"

local gpio = hardware.parse_gpio_debugfs([[
gpiochip0: GPIOs 0-31, parent: platform/1000000.pinctrl, pinctrl-msm
 gpio-3   (                    |reset               ) in  hi IRQ
 gpio-7   (wps                 ) in  lo IRQ
 gpio-12  (status-led           ) out hi
 gpio-18  (                    ) in  lo
]])
assert(gpio.available == true, "readable debugfs data should be available")
assert(gpio.chip_count == 1 and #gpio.chips == 1, "GPIO chip header should be parsed")
assert(gpio.chips[1].name == "gpiochip0" and gpio.chips[1].first_gpio == 0 and gpio.chips[1].last_gpio == 31)
assert(gpio.line_count == 4 and #gpio.lines == 4, "GPIO lines should be parsed")
assert(gpio.lines[1].number == 3 and gpio.lines[1].direction == "in")
assert(gpio.lines[1].state == "high" and gpio.lines[1].value == 1)
assert(gpio.lines[1].is_button == true, "reset consumers should be identified as button-like inputs")
assert(gpio.lines[2].is_button == true and gpio.lines[2].state == "low", "WPS input should be identified")
assert(gpio.lines[3].direction == "out" and gpio.lines[3].is_button == false)
assert(gpio.lines[4].value == 0 and gpio.lines[4].state == "low")
assert(hardware.parse_gpio_debugfs(nil).available == false, "missing debugfs must be reported unavailable")

local many = {}
for index = 1, 140 do
	table.insert(many, " gpio-" .. tostring(index) .. " (line-" .. tostring(index) .. ") in hi")
end
local capped = hardware.parse_gpio_debugfs(table.concat(many, "\n"))
assert(capped.line_count == 140 and #capped.lines == 128 and capped.truncated, "GPIO inventory must be capped")

local input = hardware.parse_input_devices([[
I: Bus=0019 Vendor=0001 Product=0001 Version=0100
N: Name="gpio-keys"
P: Phys=gpio-keys/input0
H: Handlers=kbd event0

I: Bus=0011 Vendor=0001 Product=0001 Version=ab41
N: Name="Power Button"
H: Handlers=kbd event1

I: Bus=0011 Vendor=0002 Product=0003 Version=0001
N: Name="USB Keyboard"
H: Handlers=sysrq kbd event2
]])
assert(input.available and input.count == 3 and #input.devices == 3, "Linux input devices should be parsed")
assert(input.devices[1].name == "gpio-keys" and input.devices[1].button_like)
assert(input.devices[1].bus == "0019" and input.devices[1].event_nodes[1] == "event0")
assert(input.devices[2].button_like and input.devices[2].event_nodes[1] == "event1")
assert(not input.devices[3].button_like and input.devices[3].handlers[1] == "sysrq")
assert(not hardware.parse_input_devices(nil).available, "missing input inventory must be unavailable")

local trigger = hardware.parse_trigger_text("none timer [heartbeat] default-on")
assert(trigger.available and trigger.active == "heartbeat", "active LED trigger should be parsed")
local noTrigger = hardware.parse_trigger_text("trigger data unavailable")
assert(not noTrigger.available and noTrigger.active == nil, "unparseable trigger state must not be treated as controllable")

local led = hardware.validate_led_update("aw1000:blue:status", "128", 255)
assert(led and led.name == "aw1000:blue:status" and led.brightness == 128 and led.max_brightness == 255)
assert(hardware.validate_led_update("status", 0, 1) ~= nil, "zero brightness should be valid")
assert(hardware.validate_led_update("status", 1, 1) ~= nil, "maximum brightness should be valid")

local function expect_invalid(name, brightness, maximum, label)
	local result, err = hardware.validate_led_update(name, brightness, maximum)
	assert(result == nil, label .. " should be rejected")
	assert(type(err) == "string" and #err > 0, label .. " should explain rejection")
end
expect_invalid("../brightness", "1", 255, "path traversal")
expect_invalid("led/brightness", "1", 255, "path separator")
expect_invalid("..", "1", 255, "dot path")
expect_invalid("status", "-1", 255, "negative brightness")
expect_invalid("status", "256", 255, "brightness above maximum")
expect_invalid("status", "1.5", 255, "fractional brightness")
expect_invalid("status", "on", 255, "non-numeric brightness")
expect_invalid("status", "1", 0, "zero maximum")
expect_invalid("status", "1", 65536, "unsupported maximum")
expect_invalid(string.rep("a", 65), "1", 255, "overlong LED name")

print("hardware-io: GPIO discovery, trigger parsing and LED validation tests passed")
