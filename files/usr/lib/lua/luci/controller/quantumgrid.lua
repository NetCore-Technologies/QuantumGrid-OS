-- QuantumGrid read-only telemetry API for the Arcadyan AW1000.
-- Every request is served below LuCI's authenticated admin tree.
-- No user-provided command, path, UCI write or arbitrary ubus call is accepted.

module("luci.controller.quantumgrid", package.seeall)

local previous_cpu = nil

local function read_file(path)
	local file = io.open(path, "r")
	if not file then return nil end
	local value = file:read("*a")
	file:close()
	return value
end

local function read_number(path)
	local value = read_file(path)
	return value and tonumber(value:match("^%s*([%d%.]+)")) or nil
end

local function ubus_call(object, method, arguments)
	local util = require "luci.util"
	local ok, result = pcall(util.ubus, object, method, arguments or {})
	if ok and type(result) == "table" then return result end
	return nil
end

local function cpu_usage()
	local line = read_file("/proc/stat")
	local cpu = line and line:match("^(cpu%s+[^\n]+)")
	if not cpu then return nil end

	local values = {}
	for value in cpu:gmatch("%d+") do
		table.insert(values, tonumber(value))
	end
	if #values < 4 then return nil end

	local total = 0
	for _, value in ipairs(values) do total = total + value end
	local idle = (values[4] or 0) + (values[5] or 0)
	local current = { total = total, idle = idle }
	local usage = nil

	if previous_cpu then
		local elapsed = total - previous_cpu.total
		local idle_delta = idle - previous_cpu.idle
		if elapsed > 0 then
			usage = math.max(0, math.min(100, (elapsed - idle_delta) * 100 / elapsed))
		end
	end
	previous_cpu = current
	return usage
end

local function memory_info()
	local values = {}
	local contents = read_file("/proc/meminfo") or ""
	for key, value in contents:gmatch("([%w_]+):%s+(%d+)%s+kB") do
		values[key] = tonumber(value)
	end

	local total = values.MemTotal or 0
	local available = values.MemAvailable or values.MemFree or 0
	local used = math.max(0, total - available)
	return {
		total_kib = total,
		available_kib = available,
		used_percent = total > 0 and used * 100 / total or nil
	}
end

local function temperature_c()
	local fs = require "nixio.fs"
	for zone = 0, 7 do
		local path = "/sys/class/thermal/thermal_zone" .. zone .. "/temp"
		if fs.access(path) then
			local value = read_number(path)
			if value then
				if value > 1000 then value = value / 1000 end
				if value > -20 and value < 150 then return value end
			end
		end
	end
	return nil
end

local function network_interfaces()
	local dump = ubus_call("network.interface", "dump", {}) or {}
	local source = dump.interface or {}
	local result = {}

	for _, item in ipairs(source) do
		local device = item.l3_device or item.device or ""
		local safe_device = type(device) == "string" and device:match("^[%w_.%-]+$") ~= nil
		local rx = safe_device and read_number("/sys/class/net/" .. device .. "/statistics/rx_bytes") or nil
		local tx = safe_device and read_number("/sys/class/net/" .. device .. "/statistics/tx_bytes") or nil
		local addresses = {}

		for _, address in ipairs(item["ipv4-address"] or {}) do
			if type(address.address) == "string" then
				table.insert(addresses, address.address)
			end
		end

		table.insert(result, {
			name = item.interface or item.name or "",
			device = device,
			up = item.up == true,
			is_wan = item.interface == "wan" or item.interface == "wan6",
			rx_bytes = rx or 0,
			tx_bytes = tx or 0,
			ipv4 = addresses
		})
	end
	return result
end

local function wireless_status()
	local status = ubus_call("network.wireless", "status", {}) or {}
	local result = {}

	for name, radio in pairs(status) do
		if type(radio) == "table" then
			local item = { name = name, up = radio.up == true, interfaces = {} }
			for _, iface in ipairs(radio.interfaces or {}) do
				local config = type(iface.config) == "table" and iface.config or {}
				table.insert(item.interfaces, {
					ifname = iface.ifname or "",
					ssid = config.ssid or "",
					mode = config.mode or "",
					up = iface.ifname ~= nil and iface.config ~= nil
				})
			end
			table.insert(result, item)
		end
	end
	return result
end

local function ping_probe()
	local util = require "luci.util"
	-- Fixed diagnostic destination; no client-supplied shell arguments.
	local output = util.exec("/bin/ping -c 1 -W 1 1.1.1.1 2>/dev/null") or ""
	local latency = output:match("time[=<]([%d%.]+)%s*ms")
	return { ok = latency ~= nil, latency_ms = latency and tonumber(latency) or nil }
end

function index()
	local page = entry({"admin", "services", "quantumgrid"}, call("action_index"), _("QuantumGrid"), 10)
	page.dependent = false
	entry({"admin", "services", "quantumgrid", "api"}, call("action_api")).leaf = true
end

function action_index()
	require("luci.http").redirect("/quantumgrid/")
end

function action_api()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local uci = require("luci.model.uci").cursor()
	local uptime = read_number("/proc/uptime") or 0
	local load = read_file("/proc/loadavg") or ""
	local load1, load5, load15 = load:match("^([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)")
	local memory = memory_info()
	local ping = ping_probe()
	local phone_enabled = uci:get("fxs", "main", "enabled") == "1"
	local phone_patch = fs.access("/etc/fxs/si3226x_patch.bin") == true
	local phone_service = fs.access("/etc/init.d/fxsd") == true
	local modem_present = fs.access("/dev/cdc-wdm0") == true
		or fs.access("/dev/ttyUSB2") == true
		or fs.access("/dev/ttyUSB3") == true

	http.prepare_content("application/json; charset=UTF-8")
	http.write_json({
		ok = true,
		timestamp = os.time(),
		system = {
			uptime_seconds = uptime,
			load_avg = { tonumber(load1) or 0, tonumber(load5) or 0, tonumber(load15) or 0 },
			cpu_percent = cpu_usage(),
			memory = memory,
			temperature_c = temperature_c(),
			ping_ok = ping.ok,
			ping_ms = ping.latency_ms
		},
		interfaces = network_interfaces(),
		wireless = wireless_status(),
		cellular = { modem_present = modem_present },
		phone = {
			service_installed = phone_service,
			enabled = phone_enabled,
			patch_installed = phone_patch
		}
	})
end
