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

local gpio_sysfs = hardware.parse_gpio_sysfs_chips({
	{ name = "gpiochip1", label = "pmic-gpio", base = "64", ngpio = "16" },
	{ name = "gpiochip0", label = "soc-pinctrl", base = 0, ngpio = 64 },
	{ name = "../invalid", label = "bad", base = 0, ngpio = 8 },
	{ name = "gpiochip2", label = "bad-range", base = -1, ngpio = 8 },
}, true)
assert(gpio_sysfs.available and gpio_sysfs.count == 2 and #gpio_sysfs.chips == 2)
assert(gpio_sysfs.chips[1].name == "gpiochip0" and gpio_sysfs.chips[1].label == "soc-pinctrl")
assert(gpio_sysfs.chips[1].base == 0 and gpio_sysfs.chips[1].ngpio == 64)
assert(gpio_sysfs.chips[2].base == 64 and gpio_sysfs.chips[2].ngpio == 16)
assert(not hardware.parse_gpio_sysfs_chips({}, false).available,
	"missing GPIO sysfs must remain explicitly unavailable")

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

local manyInputs = {}
for index = 1, 40 do
	table.insert(manyInputs, "I: Bus=0019 Vendor=0001 Product=0001 Version=0001")
	table.insert(manyInputs, 'N: Name="gpio-button-' .. tostring(index) .. '"')
end
local cappedInputs = hardware.parse_input_devices(table.concat(manyInputs, "\n"))
assert(cappedInputs.count == 40 and #cappedInputs.devices == 32 and cappedInputs.truncated, "input inventory must be capped")

local buttonEvents = hardware.parse_button_events([[
1700000001|101|reset|pressed|0|key
1700000006|102|reset|released|5|key
1700000007|103|wps|pressed|0|key
]], 1700000010)
assert(buttonEvents.available and buttonEvents.count == 3 and #buttonEvents.events == 3)
assert(not buttonEvents.monitor_available, "the monitor connection state is supplied by the controller")
assert(buttonEvents.events[1].button == "reset" and buttonEvents.events[1].action == "pressed")
assert(buttonEvents.events[2].seen_seconds == 5 and buttonEvents.events[2].sequence == "102")
assert(buttonEvents.events[3].type == "key" and buttonEvents.sampled_at == 1700000010)
assert(not hardware.parse_button_events(nil).available, "a missing event log must be unavailable")

local manyButtonEvents = {}
for index = 1, 70 do
	table.insert(manyButtonEvents, string.format("%d|%d|reset|released|%d|key", 1700000000 + index, index, index))
end
table.insert(manyButtonEvents, "1700000100|101|bad/name|pressed|0|key")
table.insert(manyButtonEvents, "1700000101|102|reset|timeout|3|key")
table.insert(manyButtonEvents, "1700000102|103|wps|released|999999999|key")
local cappedButtonEvents = hardware.parse_button_events(table.concat(manyButtonEvents, "\n"))
assert(cappedButtonEvents.count == 70 and #cappedButtonEvents.events == 64 and cappedButtonEvents.truncated)
assert(cappedButtonEvents.events[1].sequence == "7" and cappedButtonEvents.events[64].sequence == "70",
	"the parser must retain the latest 64 well-formed events")

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

print("hardware-io: GPIO debugfs/sysfs, input-device, button-event, trigger and LED validation tests passed")
