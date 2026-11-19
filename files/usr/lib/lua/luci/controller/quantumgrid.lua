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

local function valid_ipv4(address)
	if type(address) ~= "string" then return false end
	local a, b, c, d = address:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	if not a then return false end
	for _, part in ipairs({ a, b, c, d }) do
		local octet = tonumber(part)
		if not octet or octet < 0 or octet > 255 then return false end
	end
	return true
end

-- Unexpired dnsmasq leases are address allocations, not proof of reachability.
local function dhcp_clients()
	local contents = read_file("/tmp/dhcp.leases") or ""
	local now = os.time()
	local result = {}

	for line in contents:gmatch("[^\r\n]+") do
		local expires, mac, ip, hostname = line:match("^(%d+)%s+(%S+)%s+(%S+)%s+(%S+)")
		local expiry = tonumber(expires)
		local valid_mac = mac and mac:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") ~= nil
		if expiry and valid_mac and valid_ipv4(ip) and (expiry == 0 or expiry > now) then
			local remaining = nil
			if expiry > 0 then remaining = math.max(0, expiry - now) end
			table.insert(result, {
				hostname = hostname ~= "*" and hostname or "",
				ip = ip,
				mac = mac:lower(),
				lease_remaining_seconds = remaining and math.floor(remaining) or nil
			})
		end
	end

	table.sort(result, function(left, right)
		local left_name = left.hostname ~= "" and left.hostname:lower() or left.ip
		local right_name = right.hostname ~= "" and right.hostname:lower() or right.ip
		return left_name < right_name
	end)
	return result
end

-- Read associated Wi-Fi stations from hostapd's read-only ubus API.
-- RSSI and rates are optional because some drivers do not expose every field.
local function wireless_clients(radios)
	local result = {}
	for _, radio in ipairs(radios or {}) do
		for _, iface in ipairs(radio.interfaces or {}) do
			local ifname = iface.ifname
			local valid_ifname = type(ifname) == "string" and ifname:match("^[%w_.%-]+$") ~= nil
			if valid_ifname then
				-- rpcd-mod-iwinfo is included in the AW1000 image and exposes
				-- station signal, bitrate, counters, connection and auth state.
				local info = ubus_call("iwinfo", "info", { device = ifname }) or {}
				local associations = ubus_call("iwinfo", "assoclist", { device = ifname }) or {}
				local frequency = tonumber(info.frequency)
				local band = "Unknown"
				if frequency then
					if frequency >= 5925 then band = "6 GHz"
					elseif frequency >= 5000 then band = "5 GHz"
					elseif frequency >= 2400 then band = "2.4 GHz" end
				end
				for _, station in ipairs(associations.results or {}) do
					local mac = type(station) == "table" and station.mac or nil
					local valid_mac = type(mac) == "string"
						and mac:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") ~= nil
					if valid_mac then
						local rx = type(station.rx) == "table" and station.rx or {}
						local tx = type(station.tx) == "table" and station.tx or {}
						local rx_rate = tonumber(rx.rate)
						local tx_rate = tonumber(tx.rate)
						table.insert(result, {
							ifname = ifname,
							radio = tostring(radio.name or ""),
							ssid = tostring(iface.ssid or info.ssid or ""),
							mac = mac:lower(),
							associated = true,
							authorized = station.authorized == true,
							signal_dbm = tonumber(station.signal_avg) or tonumber(station.signal),
							noise_dbm = tonumber(station.noise),
							rx_rate_mbps = rx_rate and rx_rate > 0 and rx_rate / 1000 or nil,
							tx_rate_mbps = tx_rate and tx_rate > 0 and tx_rate / 1000 or nil,
							frequency_mhz = frequency,
							band = band,
							connected_seconds = tonumber(station.connected_time),
							inactive_ms = tonumber(station.inactive),
							rx_bytes = tonumber(rx.bytes),
							tx_bytes = tonumber(tx.bytes),
							rx_packets = tonumber(rx.packets),
							tx_packets = tonumber(tx.packets),
							tx_retries = tonumber(tx.retries),
							tx_failed = tonumber(tx.failed)
						})
					end
				end
			end
		end
	end
	table.sort(result, function(left, right)
		if left.ifname == right.ifname then return left.mac < right.mac end
		return left.ifname < right.ifname
	end)
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
	entry({"admin", "services", "quantumgrid", "password"}, call("action_set_password")).leaf = true
end

function action_set_password()
	local http = require "luci.http"
	local sys = require "luci.sys"
	local password = http.formvalue("password", true)
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		http.status(405, "Method Not Allowed")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json({ ok = false, error = "POST is required." })
		return
	end

	if not host or origin ~= scheme .. "://" .. host then
		http.status(403, "Forbidden")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json({ ok = false, error = "A same-origin request is required." })
		return
	end

	if type(password) ~= "string" or #password < 8 or #password > 128
		or password:find("%z") or password:find("\r") or password:find("\n") then
		http.status(400, "Bad Request")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json({ ok = false, error = "Password must be 8 to 128 characters." })
		return
	end

	-- First-boot bootstrap only: never replace an existing root password.
	local current_hash = sys.user.getpasswd("root")
	if current_hash ~= nil and current_hash ~= "" then
		http.status(409, "Conflict")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json({ ok = false, error = "The router already has a root password." })
		return
	end

	local ok, status = pcall(sys.user.setpasswd, "root", password)
	if not ok or (type(status) == "number" and status ~= 0) then
		http.status(500, "Internal Server Error")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json({ ok = false, error = "OpenWrt could not set the initial root password." })
		return
	end

	http.prepare_content("application/json; charset=UTF-8")
	http.write_json({ ok = true })
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
	local wireless = wireless_status()

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
		clients = dhcp_clients(),
		wireless = wireless,
		wireless_clients = wireless_clients(wireless),
		cellular = { modem_present = modem_present },
		phone = {
			service_installed = phone_service,
			enabled = phone_enabled,
			patch_installed = phone_patch
		}
	})
end
