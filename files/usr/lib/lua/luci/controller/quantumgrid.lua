-- QuantumGrid read-only telemetry API for the Arcadyan AW1000.
-- Every request is served below LuCI's authenticated admin tree.
-- No user-provided command, path, UCI write or arbitrary ubus call is accepted.

module("luci.controller.quantumgrid", package.seeall)

local previous_cpu = nil
local previous_survey = {}
local wireless_capability_cache = {}
local wifi_scan_cache = nil
local wifi_scan_cache_at = 0
local cellular_cache = nil
local cellular_cache_at = 0

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

local function wireless_survey(ifname, frequency)
	local response = ubus_call("iwinfo", "survey", { device = ifname }) or {}
	local entries = type(response.results) == "table" and response.results or {}
	local sampled_at = os.time()

	for _, entry in ipairs(entries) do
		local mhz = tonumber(entry.mhz)
		local active_time = tonumber(entry.active_time)
		local busy_time = tonumber(entry.busy_time)
		if frequency and mhz == frequency and active_time and busy_time
			and active_time > 0 and busy_time >= 0 and busy_time <= active_time then
			local result = { supported = true }
			local previous = previous_survey[ifname]
			if previous and previous.mhz == mhz then
				local interval = sampled_at - previous.sampled_at
				local active_delta = active_time - previous.active_time
				local busy_delta = busy_time - previous.busy_time
				if interval > 0 and interval <= 20 and active_delta > 0
					and busy_delta >= 0 and busy_delta <= active_delta then
					result.busy_percent = busy_delta / active_delta * 100
					result.interval_seconds = interval
				end
			end
			previous_survey[ifname] = {
				mhz = mhz,
				active_time = active_time,
				busy_time = busy_time,
				sampled_at = sampled_at
			}
			return result
		end
	end

	previous_survey[ifname] = nil
	return { supported = false }
end

local function wireless_status()
	local status = ubus_call("network.wireless", "status", {}) or {}
	local result = {}

	for name, radio in pairs(status) do
		if type(radio) == "table" then
			local channel_device = nil
			for _, candidate in ipairs(radio.interfaces or {}) do
				local candidate_name = candidate.ifname
				if type(candidate_name) == "string" and candidate_name:match("^[%w_.%-]+$") then
					channel_device = candidate_name
					break
				end
			end
			local channels = {}
			local txpower_levels = {}
			if channel_device then
				local cached_capabilities = wireless_capability_cache[channel_device]
				if cached_capabilities and os.time() - cached_capabilities.sampled_at < 60 then
					channels = cached_capabilities.channels
					txpower_levels = cached_capabilities.txpower_levels
				else
				local power_list = ubus_call("iwinfo", "txpowerlist", { device = channel_device }) or {}
				for _, entry in ipairs(power_list.results or {}) do
					if #txpower_levels < 64 then
						local dbm = tonumber(entry.dbm)
						local mw = tonumber(entry.mw)
						if dbm and dbm >= 0 and dbm <= 100 and mw and mw >= 0 and mw <= 100000 then
							table.insert(txpower_levels, {
								dbm = dbm, mw = mw,
								active = entry.active == true or entry.active == 1
							})
						end
					end
				end
				local frequency_list = ubus_call("iwinfo", "freqlist", { device = channel_device }) or {}
				for _, entry in ipairs(frequency_list.results or {}) do
					if #channels < 128 then
						local channel = tonumber(entry.channel)
						local frequency = tonumber(entry.mhz)
						if channel and channel > 0 and frequency and frequency > 0 then
							local band = "Unknown"
							if frequency >= 5925 then band = "6 GHz"
							elseif frequency >= 5000 then band = "5 GHz"
							elseif frequency >= 2400 then band = "2.4 GHz" end
							local flags = {}
							if type(entry.flags) == "table" then
								for _, flag in ipairs(entry.flags) do
									if type(flag) == "string" and #flags < 8 then table.insert(flags, flag) end
								end
							end
							local active = nil
							if entry.active ~= nil then active = entry.active == true or entry.active == 1 end
							table.insert(channels, {
								channel = channel, frequency_mhz = frequency, band = band,
								restricted = entry.restricted == true or entry.restricted == 1,
								active = active, flags = flags
							})
						end
					end
				end
				wireless_capability_cache[channel_device] = {
					sampled_at = os.time(),
					channels = channels,
					txpower_levels = txpower_levels
				}
				end
			end
			local item = {
				name = name, up = radio.up == true, interfaces = {},
				channels = channels, txpower_levels = txpower_levels
			}
			for _, iface in ipairs(radio.interfaces or {}) do
				local config = type(iface.config) == "table" and iface.config or {}
				local ifname = iface.ifname
				local valid_ifname = type(ifname) == "string" and ifname:match("^[%w_.%-]+$") ~= nil
				local info = valid_ifname and (ubus_call("iwinfo", "info", { device = ifname }) or {}) or {}
				local interface_up = valid_ifname and iface.config ~= nil and radio.up == true
				local survey = interface_up and wireless_survey(ifname, tonumber(info.frequency)) or { supported = false }
				local hardware_modes = {}
				if type(info.hwmodes) == "table" then
					for _, mode in ipairs(info.hwmodes) do
						if type(mode) == "string" and #hardware_modes < 16 then
							table.insert(hardware_modes, mode)
						end
					end
				end
				local ht_modes = {}
				if type(info.htmodes) == "table" then
					for _, mode in ipairs(info.htmodes) do
						if type(mode) == "string" and #ht_modes < 32 then
							table.insert(ht_modes, mode)
						end
					end
				end
				table.insert(item.interfaces, {
					ifname = ifname or "",
					ssid = config.ssid or info.ssid or "",
					mode = config.mode or info.mode or "",
					up = interface_up,
					survey_supported = survey.supported == true,
					channel_busy_percent = survey.busy_percent,
					survey_interval_seconds = survey.interval_seconds,
					channel = tonumber(info.channel),
					frequency_mhz = tonumber(info.frequency),
					country = type(info.country) == "string" and info.country or nil,
					hwmode = type(info.hwmode) == "string" and info.hwmode or nil,
					htmode = type(info.htmode) == "string" and info.htmode or nil,
					hardware_modes = hardware_modes,
					ht_modes = ht_modes,
					center_channel_1 = tonumber(info.center_chan1),
					center_channel_2 = tonumber(info.center_chan2),
					txpower_dbm = tonumber(info.txpower),
					signal_dbm = tonumber(info.signal),
					noise_dbm = tonumber(info.noise),
					bitrate_kbps = tonumber(info.bitrate),
					quality = tonumber(info.quality),
					quality_max = tonumber(info.quality_max)
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
local function wireless_rate_details(rate)
	if type(rate) ~= "table" then return nil end
	local is_eht = rate.eht == true or rate.eht == 1
	local is_he = rate.he == true or rate.he == 1
	local is_vht = rate.vht == true or rate.vht == 1
	local is_ht = rate.ht == true or rate.ht == 1
	local phy = "Legacy"
	if is_eht then phy = "EHT"
	elseif is_he then phy = "HE"
	elseif is_vht then phy = "VHT"
	elseif is_ht then phy = "HT" end
	return {
		phy = phy,
		mcs = tonumber(rate.mcs),
		nss = tonumber(rate.nss),
		width_mhz = tonumber(rate.mhz),
		short_gi = rate.short_gi == true or rate.short_gi == 1,
		he_gi = tonumber(rate.he_gi),
		eht_gi = tonumber(rate.eht_gi)
	}
end

local function wireless_clients(radios)
	local result = {}
	for _, radio in ipairs(radios or {}) do
		for _, iface in ipairs(radio.interfaces or {}) do
			local ifname = iface.ifname
			local valid_ifname = type(ifname) == "string" and ifname:match("^[%w_.%-]+$") ~= nil
			if valid_ifname then
				-- rpcd-mod-iwinfo is included in the AW1000 image and exposes
				-- station signal, bitrate, counters, connection and auth state.
				local associations = ubus_call("iwinfo", "assoclist", { device = ifname }) or {}
				local frequency = tonumber(iface.frequency_mhz)
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
						local rx_details = wireless_rate_details(rx)
						local tx_details = wireless_rate_details(tx)
						table.insert(result, {
							ifname = ifname,
							radio = tostring(radio.name or ""),
							ssid = tostring(iface.ssid or info.ssid or ""),
							mac = mac:lower(),
							associated = true,
							authorized = station.authorized == true,
							signal_dbm = tonumber(station.signal_avg) or tonumber(station.signal),
							signal_avg_dbm = tonumber(station.signal_avg),
							signal_current_dbm = tonumber(station.signal),
							noise_dbm = tonumber(station.noise),
							rx_rate_mbps = rx_rate and rx_rate > 0 and rx_rate / 1000 or nil,
							tx_rate_mbps = tx_rate and tx_rate > 0 and tx_rate / 1000 or nil,
							rx_details = rx_details,
							tx_details = tx_details,
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


local function build_wifi_scan()
	local radios = wireless_status()
	local results = {}
	local seen_interfaces = {}
	local seen_bssids = {}
	local scanned = 0
	local failed = 0
	local truncated = false

	for _, radio in ipairs(radios) do
		for _, iface in ipairs(radio.interfaces or {}) do
			local ifname = iface.ifname
			local valid_ifname = type(ifname) == "string"
				and ifname:match("^[%w_.%-]+$") ~= nil
			if iface.up == true and valid_ifname and not seen_interfaces[ifname] then
				seen_interfaces[ifname] = true
				local response = ubus_call("iwinfo", "scan", { device = ifname })
				if type(response) == "table" and type(response.results) == "table" then
					scanned = scanned + 1
					for _, network in ipairs(response.results) do
						if #results >= 128 then truncated = true break end
						if type(network) == "table" then
							local bssid = type(network.bssid) == "string" and network.bssid or ""
							local valid_bssid = bssid:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") ~= nil
							local unique_key = ifname .. ":" .. bssid:lower()
							if valid_bssid and not seen_bssids[unique_key] then
								seen_bssids[unique_key] = true
								local frequency = tonumber(network.mhz)
								local signal = tonumber(network.signal)
								-- rpcd encodes signed RSSI in a u32 blob attribute.
								if signal and signal > 2147483647 then signal = signal - 4294967296 end
								local band = "Unknown"
								if frequency then
									if frequency >= 5925 then band = "6 GHz"
									elseif frequency >= 5000 then band = "5 GHz"
									elseif frequency >= 2400 then band = "2.4 GHz" end
								end
								local ssid = type(network.ssid) == "string" and network.ssid or ""
								if #ssid > 128 then ssid = ssid:sub(1, 128) end
								local encryption = type(network.encryption) == "table" and network.encryption or {}
								local ht_operation = type(network.ht_operation) == "table" and network.ht_operation or nil
								local vht_operation = type(network.vht_operation) == "table" and network.vht_operation or nil
								local he_operation = type(network.he_operation) == "table" and network.he_operation or nil
								local eht_operation = type(network.eht_operation) == "table" and network.eht_operation or nil
								local security = "Unknown"
								local authentication = {}
								local ciphers = {}
								if type(encryption.ciphers) == "table" then
									for _, cipher in ipairs(encryption.ciphers) do
										if type(cipher) == "string" and #ciphers < 12 then
											table.insert(ciphers, cipher)
										end
									end
								end
								if encryption.enabled == false or encryption.enabled == 0 then
									security = "Open"
								elseif encryption.enabled == true or encryption.enabled == 1 then
									if type(encryption.wpa) == "table" and #encryption.wpa > 0 then
										local versions = {}
										for _, version in ipairs(encryption.wpa) do
											local number = tonumber(version)
											if number == 1 or number == 2 or number == 3 then
												table.insert(versions, "WPA" .. tostring(number))
											end
										end
										security = #versions > 0 and table.concat(versions, "/") or "WPA"
										if type(encryption.authentication) == "table" then
											for _, method in ipairs(encryption.authentication) do
												if type(method) == "string" and #authentication < 8 then
													table.insert(authentication, method)
												end
											end
										end
									elseif type(encryption.wep) == "table" and #encryption.wep > 0 then
										security = "WEP"
									else
										security = "Encrypted"
									end
								end
								table.insert(results, {
									radio = tostring(radio.name or ""), ifname = ifname,
									ssid = ssid, bssid = bssid:lower(),
									mode = type(network.mode) == "string" and network.mode or "",
									channel = tonumber(network.channel), frequency_mhz = frequency,
									band = band, signal_dbm = signal,
									security = security, authentication = authentication, ciphers = ciphers,
									ht_operation = ht_operation and {
										primary_channel = tonumber(ht_operation.primary_channel),
										secondary_channel_offset = type(ht_operation.secondary_channel_offset) == "string"
											and ht_operation.secondary_channel_offset or nil,
										channel_width = tonumber(ht_operation.channel_width)
									} or nil,
									vht_operation = vht_operation and {
										channel_width = tonumber(vht_operation.channel_width),
										center_freq_1 = tonumber(vht_operation.center_freq_1),
										center_freq_2 = tonumber(vht_operation.center_freq_2)
									} or nil,
									he_operation = he_operation and {
										channel_width = tonumber(he_operation.channel_width),
										center_freq_1 = tonumber(he_operation.center_freq_1),
										center_freq_2 = tonumber(he_operation.center_freq_2)
									} or nil,
									eht_operation = eht_operation and {
										channel_width = tonumber(eht_operation.channel_width),
										center_freq_1 = tonumber(eht_operation.center_freq_1),
										center_freq_2 = tonumber(eht_operation.center_freq_2)
									} or nil,
									quality = tonumber(network.quality), quality_max = tonumber(network.quality_max)
								})
							end
						end
					end
				else
					failed = failed + 1
				end
			end
			if truncated then break end
		end
		if truncated then break end
	end

	table.sort(results, function(left, right)
		local lc, rc = left.channel or 999, right.channel or 999
		if lc == rc then return (left.signal_dbm or -200) > (right.signal_dbm or -200) end
		return lc < rc
	end)
	return {
		ok = true, scanned_at = os.time(), cached = false,
		interfaces_scanned = scanned, interfaces_failed = failed,
		truncated = truncated, results = results
	}
end

function action_wifi_scan()
	local http = require "luci.http"
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

	local now = os.time()
	local payload = wifi_scan_cache
	if not payload or now - wifi_scan_cache_at >= 30 then
		payload = build_wifi_scan()
		wifi_scan_cache = payload
		wifi_scan_cache_at = now
	else
		payload = {
			ok = payload.ok, scanned_at = payload.scanned_at, cached = true,
			interfaces_scanned = payload.interfaces_scanned,
			interfaces_failed = payload.interfaces_failed, truncated = payload.truncated,
			results = payload.results
		}
	end
	http.prepare_content("application/json; charset=UTF-8")
	http.write_json(payload)
end

function index()
	local page = entry({"admin", "services", "quantumgrid"}, call("action_index"), _("QuantumGrid"), 10)
	page.dependent = false
	entry({"admin", "services", "quantumgrid", "api"}, call("action_api")).leaf = true
	entry({"admin", "services", "quantumgrid", "wifi-scan"}, call("action_wifi_scan")).leaf = true
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

local function security_status(uci, fs)
	local result = {
		firewall_installed = fs.access("/etc/init.d/firewall") == true,
		firewall_config_available = fs.access("/etc/config/firewall") == true,
		firewall_config_readable = false,
		zones = {},
		rules_count = 0,
		redirects_count = 0,
		nft_available = false,
		nft_tables = {},
		adblock_fast = {
			installed = fs.access("/etc/init.d/adblock-fast") == true,
			config_available = fs.access("/etc/config/adblock-fast") == true,
			configured_enabled = false
		},
		vpn = {
			wireguard_tool_installed = fs.access("/usr/bin/wg") == true,
			openvpn_service_installed = fs.access("/etc/init.d/openvpn") == true,
			wireguard_interfaces = {},
			openvpn_enabled_instances = 0
		}
	}
	local config_ok = pcall(function()
		uci:foreach("firewall", "zone", function(section)
			if #result.zones < 32 then
				local networks = {}
				if type(section.network) == "table" then
					for _, network in ipairs(section.network) do table.insert(networks, tostring(network)) end
				elseif type(section.network) == "string" and section.network ~= "" then
					table.insert(networks, section.network)
				end
				table.insert(result.zones, {
					name = tostring(section.name or section[".name"] or ""),
					networks = networks,
					input = tostring(section.input or ""),
					output = tostring(section.output or ""),
					forward = tostring(section.forward or ""),
					masquerade = section.masq == "1"
				})
			end
		end)
		uci:foreach("firewall", "rule", function() result.rules_count = result.rules_count + 1 end)
		uci:foreach("firewall", "redirect", function() result.redirects_count = result.redirects_count + 1 end)
	end)
	result.firewall_config_readable = config_ok

	local adblock_ok, adblock_enabled = pcall(uci.get, uci, "adblock-fast", "config", "enabled")
	if adblock_ok then result.adblock_fast.configured_enabled = adblock_enabled == "1" end

	pcall(function()
		uci:foreach("network", "interface", function(section)
			if section.proto == "wireguard" and #result.vpn.wireguard_interfaces < 16 then
				local name = tostring(section[".name"] or "")
				if name:match("^[%w_.%-]+$") then
					local status = ubus_call("network.interface." .. name, "status", {}) or {}
					table.insert(result.vpn.wireguard_interfaces, {
						name = name,
						up = status.up == true,
						device = tostring(status.device or status.l3_device or "")
					})
				end
			end
		end)
		uci:foreach("openvpn", "openvpn", function(section)
			if section.enabled == "1" then
				result.vpn.openvpn_enabled_instances = result.vpn.openvpn_enabled_instances + 1
			end
		end)
	end)

	-- Enumerate nftables tables only. This fixed command never accepts user input.
	local util = require "luci.util"
	local exec_ok, output = pcall(util.exec, "nft list tables")
	if exec_ok and type(output) == "string" then
		result.nft_available = true
		for line in output:gmatch("[^\r\n]+") do
			local family, name = line:match("^table%s+(%S+)%s+(%S+)")
			if family and name and #result.nft_tables < 32 then
				table.insert(result.nft_tables, family .. "/" .. name)
			end
		end
	end
	return result
end

local function sqm_status(uci, fs)
	local result = {
		installed = fs.access("/etc/init.d/sqm") == true,
		config_available = fs.access("/etc/config/sqm") == true,
		queues = {},
		runtime_available = false,
		qdiscs = {}
	}
	local ok = pcall(function()
		uci:foreach("sqm", "queue", function(section)
			if #result.queues < 16 then
				table.insert(result.queues, {
					name = tostring(section[".name"] or ""),
					enabled = section.enabled == "1",
					interface = tostring(section.interface or ""),
					download_kbps = tonumber(section.download),
					upload_kbps = tonumber(section.upload),
					qdisc = tostring(section.qdisc or ""),
					script = tostring(section.script or ""),
					linklayer = tostring(section.linklayer or "")
				})
			end
		end)
	end)
	result.config_readable = ok

	-- Fixed read-only command; no request or UCI value is passed to a shell.
	local util = require "luci.util"
	local exec_ok, output = pcall(util.exec, "tc -s qdisc show")
	if exec_ok and type(output) == "string" then
		result.runtime_available = true
		local current = nil
		for line in output:gmatch("[^\r\n]+") do
			local kind, handle, details = line:match("^qdisc%s+(%S+)%s+(%S+)%s*(.*)$")
			if kind then
				current = {
					kind = kind,
					handle = handle,
					device = details:match("dev%s+(%S+)"),
					parent = details:match("parent%s+(%S+)"),
					root = details:match("%f[%a]root%f[%A]") ~= nil
				}
				if #result.qdiscs < 64 then
					table.insert(result.qdiscs, current)
				else
					current = nil
				end
			elseif current then
				local bytes, packets, dropped, overlimits, requeues =
					line:match("Sent%s+(%d+)%s+bytes%s+(%d+)%s+pkt%s+%(%s*dropped%s+(%d+),%s*overlimits%s+(%d+)%s+requeues%s+(%d+)%)")
				if bytes then
					current.bytes = tonumber(bytes)
					current.packets = tonumber(packets)
					current.dropped = tonumber(dropped)
					current.overlimits = tonumber(overlimits)
					current.requeues = tonumber(requeues)
				end
				local backlog_bytes, backlog_packets = line:match("backlog%s+(%d+)b%s+(%d+)p")
				if backlog_bytes then
					current.backlog_bytes = tonumber(backlog_bytes)
					current.backlog_packets = tonumber(backlog_packets)
				end
			end
		end
	end
	return result
end

local function cellular_status(fs)
	local now = os.time()
	if cellular_cache and now - cellular_cache_at < 8 then
		return cellular_cache
	end

	local modem_present = fs.access("/dev/cdc-wdm0") == true
		or fs.access("/dev/ttyUSB2") == true
		or fs.access("/dev/ttyUSB3") == true
	local qmi_available = fs.access("/dev/cdc-wdm0") == true
		and fs.access("/sbin/uqmi") == true
	local result = {
		modem_present = modem_present,
		qmi_available = qmi_available,
		device = qmi_available and "/dev/cdc-wdm0" or "",
		sampled_at = now
	}

	if qmi_available then
		local util = require "luci.util"
		local jsonc = require "luci.jsonc"
		local serving_ok, serving_output = pcall(util.exec, "/sbin/uqmi -s -d /dev/cdc-wdm0 -t 1000 --get-serving-system")
		if serving_ok and type(serving_output) == "string" then
			local parse_ok, serving = pcall(jsonc.parse, serving_output)
			if parse_ok and type(serving) == "table" then
				result.registration = tostring(serving.registration or "")
				result.registered = serving.registration == "registered"
				result.operator = tostring(serving.plmn_description or "")
				result.mcc = tonumber(serving.plmn_mcc)
				result.mnc = tonumber(serving.plmn_mnc)
				result.roaming = serving.roaming == true
				result.radio_interfaces = {}
				for _, radio in ipairs(serving.radio_interface or {}) do
					if type(radio) == "string" then table.insert(result.radio_interfaces, radio) end
				end
			end
		end

		local signal_ok, signal_output = pcall(util.exec, "/sbin/uqmi -s -d /dev/cdc-wdm0 -t 1000 --get-signal-info")
		if signal_ok and type(signal_output) == "string" then
			local parse_ok, signal = pcall(jsonc.parse, signal_output)
			if parse_ok and type(signal) == "table" then
				result.signal_type = tostring(signal.type or "")
				result.rssi_dbm = tonumber(signal.rssi)
				result.rsrp_dbm = tonumber(signal.rsrp)
				result.rsrq_db = tonumber(signal.rsrq)
				result.snr_db = tonumber(signal.snr)
			end
		end

		local data_ok, data_output = pcall(util.exec, "/sbin/uqmi -s -d /dev/cdc-wdm0 -t 1000 --get-data-status")
		if data_ok and type(data_output) == "string" then
			local parse_ok, data_status = pcall(jsonc.parse, data_output)
			if parse_ok and type(data_status) == "string" then
				result.data_status = data_status
			end
		end
	end

	cellular_cache = result
	cellular_cache_at = now
	return result
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
	local cellular = cellular_status(fs)
	local wireless = wireless_status()
	local sqm = sqm_status(uci, fs)
	local security = security_status(uci, fs)

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
		sqm = sqm,
		security = security,
		cellular = cellular,
		phone = {
			service_installed = phone_service,
			enabled = phone_enabled,
			patch_installed = phone_patch
		}
	})
end
