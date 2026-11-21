-- QuantumGrid read-only telemetry API for the Arcadyan AW1000.
-- Every request is served below LuCI's authenticated admin tree.
-- No user-provided command, path, UCI write or arbitrary ubus call is accepted.

module("luci.controller.quantumgrid", package.seeall)

local previous_cpu = nil
local previous_survey = {}
local wireless_capability_cache = {}
local wifi_scan_cache = nil
local wifi_scan_cache_at = 0
local latency_test_cache = nil
local latency_test_cache_at = 0
local cellular_cache = nil
local cellular_cache_at = 0

local management_transport = require "luci.quantumgrid.management_transport"

local function require_https(http)
	return management_transport.require_https(http)
end

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

local function record_audit(http, action, target, outcome)
	local require_ok, audit = pcall(require, "luci.quantumgrid.audit")
	if not require_ok or type(audit) ~= "table" or type(audit.append) ~= "function" then
		return false
	end
	local ok, recorded = pcall(audit.append, {
		timestamp = os.time(),
		actor = "root",
		remote_ip = http.getenv("REMOTE_ADDR") or "",
		action = action,
		target = target,
		outcome = outcome
	})
	return ok and recorded == true
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
		local statistics_path = safe_device and ("/sys/class/net/" .. device .. "/statistics/") or nil
		local read_stat = function(name)
			return statistics_path and read_number(statistics_path .. name) or nil
		end
		local rx = read_stat("rx_bytes")
		local tx = read_stat("tx_bytes")
		local addresses = {}

		for _, address in ipairs(item["ipv4-address"] or {}) do
			if type(address.address) == "string" then
				table.insert(addresses, address.address)
			end
		end

		local ipv6_addresses = {}
		for _, address in ipairs(item["ipv6-address"] or {}) do
			local value = type(address.address) == "string" and address.address or ""
			if value ~= "" and value:match("^[%x:%.]+$") then
				local prefix = tonumber(address.mask)
				if prefix and prefix >= 0 and prefix <= 128 then
					table.insert(ipv6_addresses, value .. "/" .. tostring(prefix))
				else
					table.insert(ipv6_addresses, value)
				end
			end
		end

		local dns_servers = {}
		for _, server in ipairs(item["dns-server"] or {}) do
			if type(server) == "string" and #server <= 64 and server:match("^[%x:%.]+$") then
				table.insert(dns_servers, server)
			end
		end

		table.insert(result, {
			name = item.interface or item.name or "",
			device = device,
			up = item.up == true,
			is_wan = item.interface == "wan" or item.interface == "wan6",
			rx_bytes = rx or 0,
			tx_bytes = tx or 0,
			rx_packets = read_stat("rx_packets"),
			tx_packets = read_stat("tx_packets"),
			rx_errors = read_stat("rx_errors"),
			tx_errors = read_stat("tx_errors"),
			rx_dropped = read_stat("rx_dropped"),
			tx_dropped = read_stat("tx_dropped"),
			ipv4 = addresses,
			ipv6 = ipv6_addresses,
			dns_servers = dns_servers
		})
	end
	return result
end


local function default_route_inventory(fs)
	local result = { available = false, routes = {} }
	if fs.access("/sbin/ip") ~= true then return result end

	local util = require "luci.util"
	local families = {
		{ command = "/sbin/ip -4 route show table all", name = "IPv4" },
		{ command = "/sbin/ip -6 route show table all", name = "IPv6" }
	}
	local route_types = {
		blackhole = true, unreachable = true, prohibit = true, throw = true,
		nat = true, unicast = true
	}

	for _, family in ipairs(families) do
		local ok, output = pcall(util.exec, family.command)
		if ok and type(output) == "string" then
			result.available = true
			for line in output:gmatch("[^\r\n]+") do
				local route_type = "unicast"
				local route = line
				local first, rest = line:match("^(%S+)%s+(.*)$")
				if first and route_types[first] and rest and rest:match("^default%s") then
					route_type = first
					route = rest
				end
				if route:match("^default%s") or route == "default" then
					local gateway = route:match("%svia%s+(%S+)")
					local device = route:match("%sdev%s+(%S+)")
					local table_name = route:match("%stable%s+(%S+)") or "main"
					local metric = tonumber(route:match("%smetric%s+(%d+)"))
					local protocol = route:match("%sproto%s+(%S+)")
					local valid_device = device and device:match("^[%w_.%-]+$") ~= nil
					local valid_gateway = gateway and gateway:match("^[%w:%.%-_]+$") ~= nil
					local valid_table = table_name:match("^[%w_.%-]+$") ~= nil
					local valid_protocol = protocol and protocol:match("^[%w_.%-]+$") ~= nil
					if #result.routes < 64 then
						table.insert(result.routes, {
							family = family.name,
							route_type = route_type,
							table = valid_table and table_name or "unknown",
							device = valid_device and device or "",
							gateway = valid_gateway and gateway or "",
							metric = metric and metric >= 0 and metric or nil,
							protocol = valid_protocol and protocol or ""
						})
					end
				end
			end
		end
	end

	table.sort(result.routes, function(left, right)
		if left.family ~= right.family then return left.family < right.family end
		if left.table ~= right.table then return left.table < right.table end
		return (left.metric or 2147483647) < (right.metric or 2147483647)
	end)
	return result
end

local function static_route_inventory(uci, fs)
	local result = {
		available = false,
		routes = {},
		count = 0,
		truncated = false,
		invalid_count = 0
	}
	if fs.access("/etc/config/network") ~= true then return result end

	local interfaces = {}
	local interface_seen = {}
	local interface_ok = pcall(function()
		uci:foreach("network", "interface", function(section)
			local name = type(section[".name"]) == "string" and section[".name"] or ""
			if name:match("^[%w_.%-]+$") and name ~= "loopback" and not interface_seen[name] then
				interface_seen[name] = true
				table.insert(interfaces, { name = name })
			end
		end)
	end)
	if not interface_ok then return result end

	local routing = require "luci.quantumgrid.routing"
	local routes_ok = pcall(function()
		for _, kind in ipairs({
			{ section_type = "route", family = "IPv4" },
			{ section_type = "route6", family = "IPv6" }
		}) do
			uci:foreach("network", kind.section_type, function(section)
				result.count = result.count + 1
				if #result.routes >= 128 then
					result.truncated = true
					return
				end
				local section_name = type(section[".name"]) == "string" and section[".name"] or ""
				local update, validation_error = routing.validate_static_route(
					kind.family,
					section.interface,
					section.target,
					section.gateway or "",
					section.metric or "",
					section.table or "",
					interfaces,
					{})
				if update and section_name:match("^[%w_.%-]+$") then
					table.insert(result.routes, {
						section = section_name,
						family = kind.family,
						interface = update.interface,
						target = update.target,
						gateway = update.gateway,
						metric = update.metric,
						table = update.table,
						enabled = section.disabled ~= "1"
					})
				else
					result.invalid_count = result.invalid_count + 1
				end
			end)
		end
	end)
	result.available = routes_ok
	if not routes_ok then
		result.routes = {}
		result.invalid_count = 0
		result.truncated = false
	end
	table.sort(result.routes, function(left, right)
		if left.family ~= right.family then return left.family < right.family end
		if left.table ~= right.table then return left.table < right.table end
		if left.target ~= right.target then return left.target < right.target end
		return left.interface < right.interface
	end)
	return result
end
local function policy_rule_inventory(fs)
	local result = { available = false, rules = {}, count = 0, truncated = false }
	if fs.access("/sbin/ip") ~= true then return result end

	local routing = require "luci.quantumgrid.routing"
	local util = require "luci.util"
	local families = {
		{ command = "/sbin/ip -4 rule show", name = "IPv4" },
		{ command = "/sbin/ip -6 rule show", name = "IPv6" }
	}

	for _, family in ipairs(families) do
		local ok, output = pcall(util.exec, family.command)
		if ok and type(output) == "string" then
			result.available = true
			local rules, count, truncated = routing.parse_policy_rules(output, family.name)
			result.count = result.count + count
			result.truncated = result.truncated or truncated
			for _, rule in ipairs(rules) do
				if #result.rules < 64 then
					table.insert(result.rules, rule)
				else
					result.truncated = true
				end
			end
		end
	end

	table.sort(result.rules, function(left, right)
		if left.family ~= right.family then return left.family < right.family end
		if left.priority ~= right.priority then return left.priority < right.priority end
		return left.selectors < right.selectors
	end)
	return result
end

local function mwan3_status(uci, fs)
	local result = {
		installed = fs.access("/etc/init.d/mwan3") == true,
		available = false,
		count = 0,
		truncated = false,
		interfaces = {},
		config_available = fs.access("/etc/config/mwan3") == true,
		config_count = 0,
		config_truncated = false,
		config_invalid_count = 0,
		config_interfaces = {}
	}
	if result.config_available then
		local config = require "luci.quantumgrid.mwan3_config"
		local config_ok = pcall(function()
			uci:foreach("mwan3", "interface", function(section)
				result.config_count = result.config_count + 1
				if #result.config_interfaces < 16 then
					local name = tostring(section[".name"] or "")
					local projected = config.project_section(name, section)
					if projected then
						table.insert(result.config_interfaces, projected)
					else
						result.config_invalid_count = result.config_invalid_count + 1
					end
				else
					result.config_truncated = true
				end
			end)
		end)
		if not config_ok then
			result.config_available = false
			result.config_interfaces = {}
		end
	end
	if not result.installed then return result end

	local response = ubus_call("mwan3", "status", { section = "interfaces" })
	local policies = ubus_call("mwan3", "status", { section = "policies" })
	local connected = ubus_call("mwan3", "status", { section = "connected" })
	local normalizer = require "luci.quantumgrid.mwan3"
	local inventory = normalizer.normalize_status(response, policies, connected)
	result.available = inventory.available
	result.count = inventory.count
	result.truncated = inventory.truncated
	result.interfaces = inventory.interfaces
	result.policies_available = inventory.policies_available
	result.policy_count = inventory.policy_count
	result.policies = inventory.policies
	result.connected_available = inventory.connected_available
	result.connected_ipv4 = inventory.connected_ipv4
	result.connected_ipv6 = inventory.connected_ipv6
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

local function wireless_option_list(value)
	local result = {}
	if type(value) == "string" then
		for item in value:gmatch("%S+") do table.insert(result, item) end
	elseif type(value) == "table" then
		for _, item in ipairs(value) do
			if type(item) == "string" then table.insert(result, item) end
		end
	end
	return result
end

local function wireless_vlan_owned_for_ap(section, ap_section)
	if type(section) ~= "table" or type(ap_section) ~= "string" then return false end
	local section_name = tostring(section[".name"] or "")
	local vid = tostring(section.vid or "")
	local prefix = "qgrid_" .. ap_section .. "_"
	local iface_list = wireless_option_list(section.iface)
	local network_list = wireless_option_list(section.network)
	local numeric_vid = tonumber(vid)
	for option in pairs(section) do
		if type(option) == "string" and option:sub(1, 1) ~= "." and
			option ~= "name" and option ~= "vid" and option ~= "iface" and option ~= "network" then
			return false
		end
	end
	return #ap_section <= 48
		and vid:match("^[1-9]%d*$") ~= nil
		and numeric_vid ~= nil and numeric_vid >= 1 and numeric_vid <= 4094
		and section_name == prefix .. vid
		and section.name == "qg" .. vid
		and #iface_list == 1 and iface_list[1] == ap_section
		and #network_list == 1
end

local function wireless_vlan_sections_for_ap(uci, ap_section)
	local result = { sections = {}, unmanaged = false, available = false }
	local ok = pcall(function()
		uci:foreach("wireless", "wifi-vlan", function(section)
			local iface_list = wireless_option_list(section.iface)
			local section_name = tostring(section[".name"] or "")
			local prefix = "qgrid_" .. ap_section .. "_"
			local attached = section_name:sub(1, #prefix) == prefix
			for _, iface in ipairs(iface_list) do
				if iface == ap_section then attached = true break end
			end
			if attached then
				if #result.sections >= 16 then
					result.unmanaged = true
					return
				end
				local network_list = wireless_option_list(section.network)
				local section_name = tostring(section[".name"] or "")
				local name = tostring(section.name or "")
				local vid = tostring(section.vid or "")
				local managed = wireless_vlan_owned_for_ap(section, ap_section)
				if not managed then result.unmanaged = true end
				table.insert(result.sections, {
					section = section_name,
					name = name,
					vid = tonumber(vid) or 0,
					network = #network_list == 1 and network_list[1] or "",
					managed = managed
				})
			end
		end)
	end)
	result.available = ok
	if not ok then result.unmanaged = true end
	return result
end

local function wireless_config_inventory(uci, radios)
	local result = {}
	local ok = pcall(function()
		uci:foreach("wireless", "wifi-iface", function(section)
			if #result >= 32 then return end
			local mode = tostring(section.mode or "")
			local radio = tostring(section.device or "")
			local name = tostring(section[".name"] or "")
			if mode == "ap" and name:match("^[%w_%-]+$") and radio:match("^[%w_%-]+$") then
				local radio_type = uci:get("wireless", radio, ".type")
				if radio_type == "wifi-device" then
					local radio_status = nil
					for _, candidate in ipairs(radios or {}) do
						if candidate.name == radio then
							radio_status = candidate
							break
						end
					end
					local supported_htmodes, seen_htmodes = {}, {}
					for _, iface in ipairs(radio_status and radio_status.interfaces or {}) do
						for _, htmode in ipairs(iface.ht_modes or {}) do
							if type(htmode) == "string" and #htmode <= 16 and not seen_htmodes[htmode] then
								seen_htmodes[htmode] = true
								table.insert(supported_htmodes, htmode)
							end
						end
					end
					table.sort(supported_htmodes)
					local channel = uci:get("wireless", radio, "channel")
					local networks, seen_networks = {}, {}
					for _, network in ipairs(wireless_option_list(section.network)) do
						if network:match("^[%w_.%-]+$") and not seen_networks[network] then
							seen_networks[network] = true
							table.insert(networks, network)
						end
					end
					local vlan_inventory = wireless_vlan_sections_for_ap(uci, name)
					local dynamic_vlan = tonumber(section.dynamic_vlan) or 0
					local radius_vlan_unmanaged = vlan_inventory.unmanaged or not vlan_inventory.available
					if dynamic_vlan > 0 and dynamic_vlan ~= 2 then radius_vlan_unmanaged = true end
					if dynamic_vlan > 0 and #vlan_inventory.sections == 0 then radius_vlan_unmanaged = true end
					for _, option in ipairs({ "vlan_file", "vlan_bridge", "vlan_tagged_interface", "vlan_no_bridge", "vlan_naming" }) do
						local value = section[option]
						if type(value) == "string" and value ~= "" and value ~= "0" then
							radius_vlan_unmanaged = true
						end
					end
					table.insert(result, {
						section = name,
						radio = radio,
						mode = mode,
						ssid = tostring(section.ssid or ""),
						networks = networks,
						dynamic_vlan = dynamic_vlan,
						radius_vlan_unmanaged = radius_vlan_unmanaged,
						radius_vlan_mappings = vlan_inventory.sections,
						encryption = tostring(section.encryption or "none"),
						ieee80211w = tostring(section.ieee80211w or ""),
						ieee80211k = section.ieee80211k == "1",
						ieee80211v = section.ieee80211v == "1",
						hidden = section.hidden == "1",
						key_set = type(section.key) == "string" and section.key ~= "",
						radius_auth_server = tostring(section.auth_server or ""),
						radius_auth_port = tonumber(section.auth_port) or 1812,
						radius_secret_set = type(section.auth_secret) == "string" and section.auth_secret ~= "",
						accounting_server = tostring(section.acct_server or ""),
						accounting_port = tonumber(section.acct_port) or 1813,
						accounting_secret_set = type(section.acct_secret) == "string" and section.acct_secret ~= "",
						interface_disabled = section.disabled == "1",
						radio_disabled = uci:get("wireless", radio, "disabled") == "1",
						channel = type(channel) == "string" and channel ~= "" and channel or "auto",
						htmode = tostring(uci:get("wireless", radio, "htmode") or ""),
						htmodes = supported_htmodes,
						txpower = tonumber(uci:get("wireless", radio, "txpower")),
						txpower_levels = radio_status and radio_status.txpower_levels or {}
					})
				end
			end
		end)
	end)
	return { available = ok, sections = result }
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
				local bssid = type(info.bssid) == "string" and info.bssid:lower() or nil
				if bssid and not bssid:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") then bssid = nil end
				table.insert(item.interfaces, {
					ifname = ifname or "",
					ssid = config.ssid or info.ssid or "",
					bssid = bssid,
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



local function build_latency_test()
	local util = require "luci.util"
	-- Five bounded ICMP requests to a fixed address. Never accept shell args or a host from the browser.
	local exec_ok, output = pcall(util.exec, "/bin/ping -c 5 -W 1 -i 0.2 1.1.1.1 2>/dev/null")
	if not exec_ok or type(output) ~= "string" then
		return { ok = false, error = "The router could not execute its ICMP diagnostic." }
	end

	local samples = {}
	for value in output:gmatch("time[=<]([%d%.]+)%s*ms") do
		local sample = tonumber(value)
		if sample and sample >= 0 and sample <= 60000 and #samples < 5 then
			table.insert(samples, sample)
		end
	end

	local minimum, maximum, total = nil, nil, 0
	local jitter_total = 0
	for index, sample in ipairs(samples) do
		minimum = minimum and math.min(minimum, sample) or sample
		maximum = maximum and math.max(maximum, sample) or sample
		total = total + sample
		if index > 1 then
			jitter_total = jitter_total + math.abs(sample - samples[index - 1])
		end
	end

	local received = #samples
	return {
		ok = true,
		target = "1.1.1.1",
		packets_sent = 5,
		packets_received = received,
		packet_loss_percent = (5 - received) * 20,
		min_ms = minimum,
		average_ms = received > 0 and total / received or nil,
		max_ms = maximum,
		jitter_ms = received > 1 and jitter_total / (received - 1) or nil,
		jitter_method = "mean absolute difference between consecutive successful RTT samples",
		sampled_at = os.time(),
		cached = false
	}
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
	if not require_https(http) then return end
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


function action_latency_test()
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
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		http.status(403, "Forbidden")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json({ ok = false, error = "A same-origin request is required." })
		return
	end

	local now = os.time()
	local payload = latency_test_cache
	if payload and now - latency_test_cache_at < 30 then
		local cached = {}
		for key, value in pairs(payload) do cached[key] = value end
		cached.cached = true
		cached.retry_after_seconds = math.max(0, 30 - (now - latency_test_cache_at))
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(cached)
		return
	end

	payload = build_latency_test()
	if not payload.ok then
		http.status(503, "Service Unavailable")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
		return
	end
	latency_test_cache = payload
	latency_test_cache_at = now
	http.prepare_content("application/json; charset=UTF-8")
	http.write_json(payload)
end

function index()
	local page = entry({"admin", "services", "quantumgrid"}, call("action_index"), _("QuantumGrid"), 10)
	page.dependent = false
	entry({"admin", "services", "quantumgrid", "api"}, call("action_api")).leaf = true
	entry({"admin", "services", "quantumgrid", "wifi-scan"}, call("action_wifi_scan")).leaf = true
	entry({"admin", "services", "quantumgrid", "latency-test"}, call("action_latency_test")).leaf = true
	entry({"admin", "services", "quantumgrid", "password"}, call("action_set_password")).leaf = true
	entry({"admin", "services", "quantumgrid", "sqm-update"}, call("action_sqm_update")).leaf = true
	entry({"admin", "services", "quantumgrid", "mwan3-interface-update"}, call("action_mwan3_interface_update")).leaf = true
	entry({"admin", "services", "quantumgrid", "sqm-cake-profile"}, call("action_sqm_cake_profile")).leaf = true
	entry({"admin", "services", "quantumgrid", "sqm-client-qos-add"}, call("action_sqm_client_qos_add")).leaf = true
	entry({"admin", "services", "quantumgrid", "sqm-client-qos-download-add"}, call("action_sqm_client_qos_download_add")).leaf = true
	entry({"admin", "services", "quantumgrid", "sqm-client-qos-remove"}, call("action_sqm_client_qos_remove")).leaf = true
	entry({"admin", "services", "quantumgrid", "wireless-update"}, call("action_wireless_update")).leaf = true
	entry({"admin", "services", "quantumgrid", "usteer-update"}, call("action_usteer_update")).leaf = true
	entry({"admin", "services", "quantumgrid", "packages"}, call("action_packages")).leaf = true
	entry({"admin", "services", "quantumgrid", "config-backup"}, call("action_config_backup")).leaf = true
	entry({"admin", "services", "quantumgrid", "config-restore"}, call("action_config_restore")).leaf = true
	entry({"admin", "services", "quantumgrid", "audit"}, call("action_audit_log")).leaf = true
	entry({"admin", "services", "quantumgrid", "dhcp-reservation"}, call("action_dhcp_reservation")).leaf = true
	entry({"admin", "services", "quantumgrid", "dhcp-reservation-update"}, call("action_dhcp_reservation_update")).leaf = true
	entry({"admin", "services", "quantumgrid", "dhcp-reservation-remove"}, call("action_dhcp_reservation_remove")).leaf = true
	entry({"admin", "services", "quantumgrid", "dhcp-scope-update"}, call("action_dhcp_scope_update")).leaf = true
	entry({"admin", "services", "quantumgrid", "dhcp-scope-toggle"}, call("action_dhcp_scope_toggle")).leaf = true
	entry({"admin", "services", "quantumgrid", "dhcp-scope-add"}, call("action_dhcp_scope_add")).leaf = true
	entry({"admin", "services", "quantumgrid", "dhcp-scope-remove"}, call("action_dhcp_scope_remove")).leaf = true
	entry({"admin", "services", "quantumgrid", "bridge-vlan-update"}, call("action_bridge_vlan_update")).leaf = true
	entry({"admin", "services", "quantumgrid", "bridge-vlan-remove"}, call("action_bridge_vlan_remove")).leaf = true
	entry({"admin", "services", "quantumgrid", "office-forwarding-add"}, call("action_office_forwarding_add")).leaf = true
	entry({"admin", "services", "quantumgrid", "office-forwarding-remove"}, call("action_office_forwarding_remove")).leaf = true
	entry({"admin", "services", "quantumgrid", "office-zone-update"}, call("action_office_zone_update")).leaf = true
	entry({"admin", "services", "quantumgrid", "office-wifi-network-update"}, call("action_office_wifi_network_update")).leaf = true
	entry({"admin", "services", "quantumgrid", "office-port-forward-add"}, call("action_office_port_forward_add")).leaf = true
	entry({"admin", "services", "quantumgrid", "office-port-forward-remove"}, call("action_office_port_forward_remove")).leaf = true
	entry({"admin", "services", "quantumgrid", "office-port-forward-toggle"}, call("action_office_port_forward_toggle")).leaf = true
	entry({"admin", "services", "quantumgrid", "office-ipv6-pinhole-add"}, call("action_office_ipv6_pinhole_add")).leaf = true
	entry({"admin", "services", "quantumgrid", "office-ipv6-pinhole-remove"}, call("action_office_ipv6_pinhole_remove")).leaf = true
	entry({"admin", "services", "quantumgrid", "office-ipv6-pinhole-toggle"}, call("action_office_ipv6_pinhole_toggle")).leaf = true
	entry({"admin", "services", "quantumgrid", "office-segment-add"}, call("action_office_segment_add")).leaf = true
	entry({"admin", "services", "quantumgrid", "static-route-add"}, call("action_static_route_add")).leaf = true
	entry({"admin", "services", "quantumgrid", "static-route-remove"}, call("action_static_route_remove")).leaf = true
	entry({"admin", "services", "quantumgrid", "remote-syslog"}, call("action_remote_syslog_update")).leaf = true
	entry({"admin", "services", "quantumgrid", "packages-update"}, call("action_package_operation")).leaf = true
	entry({"admin", "services", "quantumgrid", "led-update"}, call("action_led_update")).leaf = true
end

local function sqm_restart(sys)
	local ok, status = pcall(sys.call, "/etc/init.d/sqm restart >/dev/null 2>&1")
	return ok and status == 0
end

local function restore_sqm_queue(uci, section, snapshot)
	for option, previous in pairs(snapshot) do
		if previous == false then
			local ok, result = pcall(uci.delete, uci, "sqm", section, option)
			if not ok or result ~= true then
				pcall(uci.revert, uci, "sqm")
				return false
			end
		else
			local ok, result = pcall(uci.set, uci, "sqm", section, option, previous)
			if not ok or result ~= true then
				pcall(uci.revert, uci, "sqm")
				return false
			end
		end
	end
	local ok, committed = pcall(uci.commit, uci, "sqm")
	if not ok or committed ~= true then
		pcall(uci.revert, uci, "sqm")
		return false
	end
	return true
end

local function restore_wireless_option(uci, section, option, previous)
	if previous == false then
		local ok, result = pcall(uci.delete, uci, "wireless", section, option)
		return ok and result == true
	end
	local ok, result
	if type(previous) == "table" then
		ok, result = pcall(uci.set_list, uci, "wireless", section, option, previous)
	else
		ok, result = pcall(uci.set, uci, "wireless", section, option, previous)
	end
	return ok and result == true
end

local function restore_wireless_vlan_sections(uci, interface, snapshot)
	local prefix = "qgrid_" .. interface .. "_"
	local current = {}
	local inspect_ok = pcall(function()
		uci:foreach("wireless", "wifi-vlan", function(section)
			local section_name = tostring(section[".name"] or "")
			if section_name:sub(1, #prefix) == prefix then
				table.insert(current, section_name)
			end
		end)
	end)
	if not inspect_ok then return false end
	for _, section in ipairs(current) do
		local delete_ok, deleted = pcall(uci.delete, uci, "wireless", section)
		if not delete_ok or deleted ~= true then return false end
	end

	for _, item in ipairs(snapshot.wifi_vlans or {}) do
		if type(item) ~= "table" or type(item.section) ~= "string"
			or type(item.name) ~= "string" or type(item.vid) ~= "string"
			or type(item.network) ~= "string" then return false end
		local create_ok, created = pcall(uci.section, uci, "wireless", "wifi-vlan", item.section, {
			name = item.name,
			vid = item.vid
		})
		if not create_ok or created ~= item.section then return false end
		local iface_ok, iface_set = pcall(uci.set_list, uci, "wireless", item.section, "iface", { interface })
		local network_ok, network_set = pcall(uci.set_list, uci, "wireless", item.section, "network", { item.network })
		if not iface_ok or iface_set ~= true or not network_ok or network_set ~= true then return false end
	end
	return true
end

local function restore_wireless_snapshot(uci, radio, interface, snapshot)
	for option, value in pairs(snapshot.radio) do
		if not restore_wireless_option(uci, radio, option, value) then
			pcall(uci.revert, uci, "wireless")
			return false
		end
	end
	for option, value in pairs(snapshot.interface) do
		if not restore_wireless_option(uci, interface, option, value) then
			pcall(uci.revert, uci, "wireless")
			return false
		end
	end
	if snapshot.manage_radius_vlans and
		not restore_wireless_vlan_sections(uci, interface, snapshot) then
		pcall(uci.revert, uci, "wireless")
		return false
	end
	local ok, result = pcall(uci.commit, uci, "wireless")
	return ok and result == true
end

local function wireless_channel_allowed(radio_name, channel)
	if channel == "auto" then return true end
	local status = ubus_call("network.wireless", "status", {}) or {}
	local radio = status[radio_name]
	if type(radio) ~= "table" then return false end

	for _, iface in ipairs(radio.interfaces or {}) do
		local ifname = iface.ifname
		if type(ifname) == "string" and ifname:match("^[%w_.%-]+$") then
			local response = ubus_call("iwinfo", "freqlist", { device = ifname }) or {}
			for _, entry in ipairs(response.results or {}) do
				if tonumber(entry.channel) == tonumber(channel) then
					return not (entry.restricted == true or entry.restricted == 1)
				end
			end
		end
	end
	return false
end

local function wireless_radio_modes(radio_name)
	local result = {}
	for _, radio in ipairs(wireless_status()) do
		if radio.name == radio_name then
			for _, iface in ipairs(radio.interfaces or {}) do
				for _, mode in ipairs(iface.ht_modes or {}) do
					if type(mode) == "string" then result[mode] = true end
				end
			end
			break
		end
	end
	return result
end

local function wireless_radio_power_levels(radio_name)
	for _, radio in ipairs(wireless_status()) do
		if radio.name == radio_name then
			local result = {}
			for _, item in ipairs(radio.txpower_levels or {}) do
				if tonumber(item.dbm) then result[tostring(tonumber(item.dbm))] = true end
			end
			return result
		end
	end
	return {}
end


local function wireless_network_inventory(uci, fs)
	local office = office_network_status(uci, fs)
	return {
		interfaces = office.interfaces or {},
		bridges = office.bridges or {},
		vlans = office.vlans or {},
		zones = office.zones or {},
		available = office.available == true and office.firewall_available == true,
		truncated = office.truncated == true
	}
end

local function network_interface_for_remote_address(remote_ip, interfaces)
	if not valid_ipv4(remote_ip) then
		return nil, "The current administrator session is not using a validated IPv4 address."
	end
	local util = require "luci.util"
	local ok, output = pcall(util.exec, "/sbin/ip -4 route get " .. remote_ip .. " 2>/dev/null")
	if not ok or type(output) ~= "string" then
		return nil, "The router could not inspect the administrator's IPv4 return route."
	end
	local device = output:match("%sdev%s+([%w_.%-]+)")
	if not device then
		return nil, "The administrator's IPv4 return route has no validated network device."
	end
	local found = nil
	for _, iface in ipairs(type(interfaces) == "table" and interfaces or {}) do
		if type(iface) == "table" and iface.device == device then
			if found then return nil, "The administrator's IPv4 return device maps to more than one network interface." end
			found = iface.name
		end
	end
	if not found then
		return nil, "The administrator's IPv4 return device is not mapped to a known network interface."
	end
	return found
end

function action_wireless_update()
	local http = require "luci.http"
	local sys = require "luci.sys"
	local fs = require "nixio.fs"
	local uci = require("luci.model.uci").cursor()
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then http.status(status, status == 400 and "Bad Request" or
			status == 403 and "Forbidden" or status == 404 and "Not Found" or
			status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or status == 503 and "Service Unavailable" or
			status == 502 and "Bad Gateway" or "Internal Server Error") end
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	if fs.access("/sbin/wifi") ~= true or fs.access("/etc/config/wireless") ~= true then
		respond(503, { ok = false, error = "Wireless configuration or the Wi-Fi reload utility is unavailable." })
		return
	end

	local validator = require "luci.quantumgrid.wireless"
	local update, validation_error = validator.validate_update(
		http.formvalue("radio", true),
		http.formvalue("section", true),
		http.formvalue("ssid", true),
		http.formvalue("encryption", true),
		http.formvalue("key", true) or "",
		http.formvalue("hidden", true),
		http.formvalue("channel", true),
		http.formvalue("htmode", true),
		http.formvalue("txpower", true),
		http.formvalue("allow_open", true),
		http.formvalue("confirmed", true),
		http.formvalue("radius_server", true),
		http.formvalue("radius_port", true),
		http.formvalue("radius_secret", true) or "",
		http.formvalue("accounting_server", true),
		http.formvalue("accounting_port", true),
		http.formvalue("accounting_secret", true) or ""
	)
	if not update then
		respond(400, { ok = false, error = validation_error })
		return
	end
	local roaming_features, roaming_error = validator.validate_roaming_features(
		update.encryption,
		http.formvalue("ieee80211k", true),
		http.formvalue("ieee80211v", true)
	)
	if not roaming_features then
		respond(400, { ok = false, error = roaming_error })
		return
	end
	update.ieee80211k = roaming_features.ieee80211k
	update.ieee80211v = roaming_features.ieee80211v
	if fs.access("/etc/config/network") ~= true or fs.access("/etc/config/firewall") ~= true then
		respond(503, { ok = false, error = "Network or firewall configuration is unavailable; SSID network binding cannot be verified." })
		return
	end
	local requested_network = http.formvalue("network", true)
	local network_inventory = wireless_network_inventory(uci, fs)
	if not network_inventory.available or network_inventory.truncated then
		respond(503, { ok = false, error = "Network or firewall interface inventories are unavailable or truncated; SSID network binding cannot be verified." })
		return
	end
	local office_validator = require "luci.quantumgrid.office_networks"
	local binding, binding_error = office_validator.validate_wireless_network_binding(
		requested_network, network_inventory.interfaces, network_inventory.zones)
	if not binding then
		respond(400, { ok = false, error = binding_error })
		return
	end
	update.network = binding.network

	local radio_type_ok, radio_type = pcall(uci.get, uci, "wireless", update.radio, ".type")
	local interface_type_ok, interface_type = pcall(uci.get, uci, "wireless", update.section, ".type")
	if not radio_type_ok or not interface_type_ok then
		respond(500, { ok = false, error = "Could not inspect the selected wireless configuration." })
		return
	end
	if radio_type ~= "wifi-device" or interface_type ~= "wifi-iface" then
		respond(404, { ok = false, error = "Only an existing Wi-Fi radio and AP interface can be edited." })
		return
	end
	if uci:get("wireless", update.section, "device") ~= update.radio
		or uci:get("wireless", update.section, "mode") ~= "ap" then
		respond(400, { ok = false, error = "The selected interface is not an AP on the selected radio." })
		return
	end

	local current_channel = uci:get("wireless", update.radio, "channel") or "auto"
	local expected_channel_ok, expected_channel_error, expected_channel_status =
		validator.validate_expected_current_channel(
			http.formvalue("expected_current_channel", true), current_channel)
	if not expected_channel_ok then
		respond(expected_channel_status or 400, { ok = false, error = expected_channel_error })
		return
	end
	if update.channel ~= current_channel and not wireless_channel_allowed(update.radio, update.channel) then
		respond(400, { ok = false, error = "That channel is not reported as available and unrestricted by the radio driver." })
		return
	end

	local current_htmode = uci:get("wireless", update.radio, "htmode") or "auto"
	if update.htmode ~= current_htmode and update.htmode ~= "auto" then
		local supported_modes = wireless_radio_modes(update.radio)
		if not supported_modes[update.htmode] then
			respond(400, { ok = false, error = "That width/PHY mode is not reported as supported by the selected radio." })
			return
		end
	end

	local current_txpower = uci:get("wireless", update.radio, "txpower") or "auto"
	if update.txpower ~= current_txpower and update.txpower ~= "auto" then
		local supported_power = wireless_radio_power_levels(update.radio)
		if not supported_power[update.txpower] then
			respond(400, { ok = false, error = "That transmit-power level is not reported as available by the selected radio." })
			return
		end
	end

	local current_ap_config = uci:get_all("wireless", update.section)
	if type(current_ap_config) ~= "table" or current_ap_config[".type"] ~= "wifi-iface" then
		respond(404, { ok = false, error = "The selected AP configuration no longer exists." })
		return
	end
	local current_networks = {}
	if type(current_ap_config.network) == "string" then
		for name in current_ap_config.network:gmatch("%S+") do table.insert(current_networks, name) end
	elseif type(current_ap_config.network) == "table" then
		for _, name in ipairs(current_ap_config.network) do
			if type(name) == "string" then table.insert(current_networks, name) end
		end
	end
	local current_network = #current_networks == 1 and current_networks[1] or nil
	if current_network ~= update.network then
		local management_network, route_error = network_interface_for_remote_address(
			http.getenv("REMOTE_ADDR"), network_inventory.interfaces)
		if not management_network then
			respond(409, { ok = false, error = route_error .. " Use an out-of-band management path to change this SSID's VLAN binding." })
			return
		end
		if update.network == management_network and current_network ~= management_network then
			respond(409, { ok = false, error = "This operation would move a different SSID onto the administrator's management network. Use an out-of-band path to make that change." })
			return
		end
		for _, attached in ipairs(current_networks) do
			if attached == management_network and update.network ~= management_network then
				respond(409, { ok = false, error = "This AP currently carries the administrator's management network. Keep that network attached or use a separate/out-of-band management connection before moving the SSID." })
				return
			end
		end
	end

	local current_encryption = uci:get("wireless", update.section, "encryption") or "none"
	local enterprise_encryption = update.encryption == "wpa2" or update.encryption == "wpa3"
	local current_key = uci:get("wireless", update.section, "key")
	if update.encryption ~= "none" and not enterprise_encryption and not update.key_supplied
		and (current_encryption ~= update.encryption or type(current_key) ~= "string" or current_key == "") then
		respond(400, { ok = false, error = "Enter a new passphrase when enabling or changing wireless security." })
		return
	end
	local current_radius_server = uci:get("wireless", update.section, "auth_server") or ""
	local current_radius_secret = uci:get("wireless", update.section, "auth_secret")
	if enterprise_encryption and not update.radius_secret_supplied
		and (not (current_encryption == "wpa2" or current_encryption == "wpa3") or current_radius_server ~= update.radius_server
			or type(current_radius_secret) ~= "string" or current_radius_secret == "") then
		respond(400, { ok = false, error = "Enter a new RADIUS shared secret when enabling enterprise security or changing its server." })
		return
	end
	local current_accounting_server = uci:get("wireless", update.section, "acct_server") or ""
	local current_accounting_secret = uci:get("wireless", update.section, "acct_secret")
	if enterprise_encryption and update.accounting_server ~= "" and not update.accounting_secret_supplied
		and (not (current_encryption == "wpa2" or current_encryption == "wpa3") or current_accounting_server ~= update.accounting_server
			or type(current_accounting_secret) ~= "string" or current_accounting_secret == "") then
		respond(400, { ok = false, error = "Enter a new RADIUS accounting shared secret when enabling accounting or changing its server." })
		return
	end

	local manage_radius_vlans_value = http.formvalue("manage_radius_vlans", true)
	local dynamic_vlan_value = http.formvalue("dynamic_vlan_enabled", true)
	local radius_vlan_json = http.formvalue("radius_vlan_mappings", true)
	if (manage_radius_vlans_value ~= "0" and manage_radius_vlans_value ~= "1")
		or (dynamic_vlan_value ~= "0" and dynamic_vlan_value ~= "1")
		or type(radius_vlan_json) ~= "string" or #radius_vlan_json > 8192 then
		respond(400, { ok = false, error = "Explicit RADIUS dynamic VLAN controls and a bounded mapping list are required." })
		return
	end
	local manage_radius_vlans = manage_radius_vlans_value == "1"
	local dynamic_vlan_enabled = dynamic_vlan_value == "1"
	local jsonc = require "luci.jsonc"
	local mappings_ok, requested_mappings = pcall(jsonc.parse, radius_vlan_json)
	if not mappings_ok or type(requested_mappings) ~= "table" then
		respond(400, { ok = false, error = "RADIUS VLAN mappings must be a valid JSON array." })
		return
	end
	local mapping_count = 0
	for key in pairs(requested_mappings) do
		if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
			respond(400, { ok = false, error = "RADIUS VLAN mappings must be a JSON array, not an object." })
			return
		end
		mapping_count = mapping_count + 1
	end
	if mapping_count ~= #requested_mappings then
		respond(400, { ok = false, error = "RADIUS VLAN mappings must be a contiguous JSON array." })
		return
	end
	local radius_vlan_inventory = wireless_vlan_sections_for_ap(uci, update.section)
	local current_dynamic_vlan = tonumber(current_ap_config.dynamic_vlan) or 0
	local has_custom_vlan_options = false
	for _, option in ipairs({ "vlan_file", "vlan_bridge", "vlan_tagged_interface", "vlan_no_bridge", "vlan_naming" }) do
		local value = current_ap_config[option]
		if type(value) == "string" and value ~= "" and value ~= "0" then
			has_custom_vlan_options = true
		end
	end
	local radius_vlan_unmanaged = radius_vlan_inventory.unmanaged
		or has_custom_vlan_options
		or (current_dynamic_vlan > 0 and #radius_vlan_inventory.sections == 0)
	if manage_radius_vlans and radius_vlan_unmanaged then
		respond(409, { ok = false, error = "This AP already has RADIUS VLAN settings QuantumGrid cannot safely identify or manage. Its existing wifi-vlan mappings and hostapd options were left untouched." })
		return
	end
	if not manage_radius_vlans then
		if dynamic_vlan_enabled or #requested_mappings > 0 then
			respond(400, { ok = false, error = "Unmanaged RADIUS VLAN configuration must not be changed through this editor." })
			return
		end
		if current_dynamic_vlan > 0 and not enterprise_encryption then
			respond(409, { ok = false, error = "This AP has externally managed dynamic VLAN assignment. Keep Enterprise security enabled or disable its RADIUS VLAN configuration through the administrator-managed hostapd settings." })
			return
		end
	end

	local validated_radius_vlans = {}
	if manage_radius_vlans then
		if #update.section > 48 then
			respond(400, { ok = false, error = "This AP section name is too long for deterministic managed RADIUS VLAN mapping identifiers." })
			return
		end
		if dynamic_vlan_enabled then
			if not enterprise_encryption then
				respond(400, { ok = false, error = "RADIUS dynamic VLAN requires WPA2-Enterprise or WPA3-Enterprise security." })
				return
			end
			local validated, mapping_error = office_validator.validate_radius_dynamic_vlan_mappings(
				requested_mappings, network_inventory.interfaces, network_inventory.bridges,
				network_inventory.vlans, network_inventory.zones)
			if not validated then
				respond(400, { ok = false, error = mapping_error })
				return
			end
			validated_radius_vlans = validated
		elseif #requested_mappings ~= 0 then
			respond(400, { ok = false, error = "Disable RADIUS dynamic VLAN by removing all VLAN mappings." })
			return
		end
	else
		if #requested_mappings ~= 0 then
			respond(400, { ok = false, error = "VLAN mappings cannot be submitted when their configuration is not managed by QuantumGrid." })
			return
		end
	end

	local snapshot = { radio = {}, interface = {} }
	snapshot.manage_radius_vlans = manage_radius_vlans
	snapshot.wifi_vlans = {}
	if manage_radius_vlans then
		for _, item in ipairs(radius_vlan_inventory.sections) do
			if not item.managed or item.section == "" or item.name == "" or item.vid <= 0 or item.network == "" then
				respond(409, { ok = false, error = "An existing RADIUS VLAN mapping is not a complete QuantumGrid-managed entry. No changes were made." })
				return
			end
			table.insert(snapshot.wifi_vlans, {
				section = item.section,
				name = item.name,
				vid = tostring(item.vid),
				network = item.network
			})
		end
	end
	for _, option in ipairs({ "channel", "htmode", "txpower" }) do
		local ok, value = pcall(uci.get, uci, "wireless", update.radio, option)
		if not ok then
			respond(500, { ok = false, error = "Could not snapshot the selected radio settings." })
			return
		end
		snapshot.radio[option] = value or false
	end
	for _, option in ipairs({ "ssid", "network", "encryption", "key", "hidden", "auth_server", "auth_port", "auth_secret", "acct_server", "acct_port", "acct_secret", "ieee80211w", "ieee80211k", "ieee80211v", "dynamic_vlan" }) do
		local ok, value = pcall(uci.get, uci, "wireless", update.section, option)
		if not ok then
			respond(500, { ok = false, error = "Could not snapshot the selected AP settings." })
			return
		end
		snapshot.interface[option] = value or false
	end

	local radio_updates = { channel = update.channel }
	if update.htmode == "auto" then
		radio_updates.htmode = false
	else
		radio_updates.htmode = update.htmode
	end
	if update.txpower == "auto" then
		radio_updates.txpower = false
	else
		radio_updates.txpower = update.txpower
	end
	local interface_updates = {
		ssid = update.ssid,
		network = update.network,
		encryption = update.encryption,
		hidden = update.hidden,
		ieee80211k = update.ieee80211k == "1" and "1" or false,
		ieee80211v = update.ieee80211v == "1" and "1" or false
	}
	if enterprise_encryption then
		interface_updates.auth_server = update.radius_server
		interface_updates.auth_port = update.radius_port
		if update.radius_secret_supplied then
			interface_updates.auth_secret = update.radius_secret
		end
	else
		interface_updates.auth_server = false
		interface_updates.auth_port = false
		interface_updates.auth_secret = false
	end
	if update.encryption == "wpa3" then
		interface_updates.ieee80211w = "2"
	elseif current_encryption == "wpa3" then
		interface_updates.ieee80211w = false
	end
	if enterprise_encryption and update.accounting_server ~= "" then
		interface_updates.acct_server = update.accounting_server
		interface_updates.acct_port = update.accounting_port
		if update.accounting_secret_supplied then
			interface_updates.acct_secret = update.accounting_secret
		end
	else
		interface_updates.acct_server = false
		interface_updates.acct_port = false
		interface_updates.acct_secret = false
	end
	if update.encryption == "none" then
		interface_updates.key = false
	elseif update.key_supplied then
		interface_updates.key = update.key
	end
	if manage_radius_vlans then
		interface_updates.dynamic_vlan = dynamic_vlan_enabled and "2" or false
	end

	local function stage_radius_vlan_mappings()
		if not manage_radius_vlans then return true end
		for _, item in ipairs(radius_vlan_inventory.sections) do
			local delete_ok, deleted = pcall(uci.delete, uci, "wireless", item.section)
			if not delete_ok or deleted ~= true then return false end
		end
		for _, mapping in ipairs(validated_radius_vlans) do
			local section_id = "qgrid_" .. update.section .. "_" .. mapping.vid
			local existing_type = uci:get("wireless", section_id, ".type")
			if existing_type ~= nil then return false end
			local section_ok, section = pcall(uci.section, uci, "wireless", "wifi-vlan", section_id, {
				name = mapping.name,
				vid = mapping.vid
			})
			if not section_ok or section ~= section_id then return false end
			local iface_ok, iface_set = pcall(uci.set_list, uci, "wireless", section_id, "iface", { update.section })
			local network_ok, network_set = pcall(uci.set_list, uci, "wireless", section_id, "network", { mapping.network })
			if not iface_ok or iface_set ~= true or not network_ok or network_set ~= true then return false end
		end
		return true
	end

	local function set_options(section, options)
		for option, value in pairs(options) do
			local ok, result
			if value == false then
				ok, result = pcall(uci.delete, uci, "wireless", section, option)
			else
				ok, result = pcall(uci.set, uci, "wireless", section, option, value)
			end
			if not ok or result ~= true then return false end
		end
		return true
	end

	if not set_options(update.radio, radio_updates)
		or not set_options(update.section, interface_updates)
		or not stage_radius_vlan_mappings() then
		pcall(uci.revert, uci, "wireless")
		respond(500, { ok = false, error = "Wireless settings could not be staged; no reload was attempted." })
		return
	end

	local commit_ok, committed = pcall(uci.commit, uci, "wireless")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "wireless")
		respond(500, { ok = false, error = "Wireless settings could not be committed; no reload was attempted." })
		return
	end

	local reload_ok, reload_status = pcall(sys.call, "/sbin/wifi reload >/dev/null 2>&1")
	if not reload_ok or reload_status ~= 0 then
		local rollback_saved = restore_wireless_snapshot(uci, update.radio, update.section, snapshot)
		local rollback_ok, rollback_status = false, -1
		if rollback_saved then
			rollback_ok, rollback_status = pcall(sys.call, "/sbin/wifi reload >/dev/null 2>&1")
		end
		local rolled_back = rollback_saved and rollback_ok and rollback_status == 0
		record_audit(http, "wireless.update", update.section, "failed")
		respond(502, {
			ok = false,
			error = rolled_back
				and "Wi-Fi reload failed. The previous radio and AP settings were restored."
				or "Wi-Fi reload failed and rollback could not be confirmed. Inspect wireless configuration locally before applying more changes.",
			rolled_back = rolled_back
		})
		return
	end

	record_audit(http, "wireless.update", update.section, "success")
	local response_radius_vlan_mappings = {}
	if manage_radius_vlans then
		response_radius_vlan_mappings = validated_radius_vlans
	else
		for _, item in ipairs(radius_vlan_inventory.sections) do
			table.insert(response_radius_vlan_mappings, {
				vid = tostring(item.vid),
				network = item.network,
				name = item.name
			})
		end
	end
	respond(nil, {
		ok = true,
		radio = update.radio,
		section = update.section,
		ssid = update.ssid,
		network = update.network,
		encryption = update.encryption,
		hidden = update.hidden == "1",
		channel = update.channel,
		htmode = update.htmode,
		txpower = update.txpower,
		key_set = update.encryption ~= "none" and not enterprise_encryption,
		ieee80211w = update.encryption == "wpa3" and "2" or nil,
		ieee80211k = update.ieee80211k == "1",
		ieee80211v = update.ieee80211v == "1",
		radius_auth_server = enterprise_encryption and update.radius_server or nil,
		radius_auth_port = enterprise_encryption and tonumber(update.radius_port) or nil,
		radius_secret_set = enterprise_encryption,
		accounting_server = enterprise_encryption and update.accounting_server ~= "" and update.accounting_server or nil,
		accounting_port = enterprise_encryption and update.accounting_server ~= "" and tonumber(update.accounting_port) or nil,
		accounting_secret_set = enterprise_encryption and update.accounting_server ~= "",
		dynamic_vlan = manage_radius_vlans and (dynamic_vlan_enabled and 2 or 0) or current_dynamic_vlan,
		radius_vlan_count = manage_radius_vlans and #validated_radius_vlans or #radius_vlan_inventory.sections,
		radius_vlan_mappings = response_radius_vlan_mappings,
		reloaded = true,
		rolled_back = false
	})
end



function action_usteer_update()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local manager = require "luci.quantumgrid.usteer"
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"
	local options = {
		"enabled", "network", "syslog", "local_mode", "ipv6",
		"assoc_steering", "probe_steering", "aggressiveness",
		"load_kick_enabled", "min_snr", "min_connect_snr", "roam_scan_snr", "roam_trigger_snr",
		"band_steering_interval", "band_steering_min_snr",
		"band_steering_threshold", "load_balancing_threshold"
	}

	local function respond(status, payload)
		if status then
			http.status(status, status == 400 and "Bad Request" or
				status == 403 and "Forbidden" or status == 404 and "Not Found" or
				status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
				status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
				"Internal Server Error")
		end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	if fs.access("/etc/init.d/usteer") ~= true or fs.access("/sbin/usteerd") ~= true or
		fs.access("/etc/config/usteer") ~= true then
		respond(503, {
			ok = false,
			error = "The usteer daemon, service script or UCI configuration is unavailable in this firmware."
		})
		return
	end
	if http.formvalue("confirmed", true) ~= "1" then
		respond(400, { ok = false, error = "Explicit confirmation is required before changing the roaming service." })
		return
	end

	local requested_enabled = http.formvalue("enabled", true)
	local network_name = http.formvalue("network", true) or ""
	local network_inventory = nil
	local access_point_inventory = nil
	if requested_enabled == "1" then
		network_inventory = wireless_network_inventory(uci, fs)
		if not network_inventory.available or network_inventory.truncated then
			respond(503, {
				ok = false,
				error = "The routed-network or firewall-zone inventory is unavailable or truncated; the inter-AP network cannot be verified."
			})
			return
		end
		access_point_inventory = usteer_access_point_inventory(uci)
		if not access_point_inventory.available or access_point_inventory.truncated then
			respond(503, {
				ok = false,
				error = "The AP inventory is unavailable or truncated; roaming prerequisites cannot be verified across every local SSID."
			})
			return
		end
	end

	local ssid_json = http.formvalue("ssids", true) or ""
	if #ssid_json > 4096 then
		respond(400, { ok = false, error = "The roaming SSID list exceeds the maximum request size." })
		return
	end
	local jsonc = require "luci.jsonc"
	local ssids_ok, ssids = pcall(jsonc.parse, ssid_json)
	if not ssids_ok or type(ssids) ~= "table" then
		respond(400, { ok = false, error = "The roaming SSID selection must be a valid JSON array." })
		return
	end

	local binding = nil
	if requested_enabled == "1" then
		local office = require "luci.quantumgrid.office_networks"
		local binding_error
		binding, binding_error = office.validate_wireless_network_binding(
			network_name, network_inventory.interfaces, network_inventory.zones)
		if not binding then
			respond(400, { ok = false, error = binding_error })
			return
		end
	end
	local update, validation_error = manager.validate({
		confirmed = "1",
		enabled = requested_enabled,
		aggressiveness = http.formvalue("aggressiveness", true),
		assoc_steering = http.formvalue("assoc_steering", true),
		probe_steering = http.formvalue("probe_steering", true),
		band_steering_interval = http.formvalue("band_steering_interval", true),
		band_steering_min_snr = http.formvalue("band_steering_min_snr", true),
		band_steering_threshold = http.formvalue("band_steering_threshold", true),
		load_balancing_threshold = http.formvalue("load_balancing_threshold", true),
		ssids = ssids
	}, binding, access_point_inventory.access_points)
	if not update then
		respond(400, { ok = false, error = validation_error })
		return
	end

	local section_name = nil
	local section_count = 0
	local sections_ok = pcall(function()
		uci:foreach("usteer", "usteer", function(section)
			section_count = section_count + 1
			if section_count == 1 then section_name = section[".name"] end
		end)
	end)
	if not sections_ok or section_count ~= 1 or
		type(section_name) ~= "string" or not section_name:match("^[%w_.%-]+$") then
		if not update.enabled then
			local stop_ok, stop_status = pcall(sys.call,
				"/etc/init.d/usteer stop >/dev/null 2>&1 && /etc/init.d/usteer disable >/dev/null 2>&1")
			if not stop_ok or stop_status ~= 0 then
				respond(502, {
					ok = false,
					error = "The usteer configuration is ambiguous and the daemon could not be stopped and disabled. Inspect service state locally.",
					rolled_back = false
				})
				return
			end
			local nixio = require "nixio"
			local stopped = false
			for attempt = 1, 10 do
				if type(ubus_call("usteer", "get_config", {})) ~= "table" then
					stopped = true
					break
				end
				if attempt < 10 then pcall(nixio.nanosleep, 0, 200000000) end
			end
			if not stopped then
				respond(502, {
					ok = false,
					error = "The usteer service did not disappear from ubus after the stop request. Startup was disabled; verify the daemon locally.",
					rolled_back = false
				})
				return
			end
			record_audit(http, "wireless.usteer.update", "ambiguous-config", "success")
			respond(nil, {
				ok = true,
				enabled = false,
				network = "",
				ssid_list = {},
				aggressiveness = 0,
				assoc_steering = false,
				probe_steering = false,
				band_steering_interval = 0,
				band_steering_min_snr = -60,
				band_steering_threshold = 5,
				load_balancing_threshold = 0,
				status = "disabled",
				running = false,
				local_node_count = 0,
				remote_host_count = 0,
				associated_clients = 0,
				service_action_completed = true,
				rolled_back = false
			})
			return
		end
		respond(409, {
			ok = false,
			error = "QuantumGrid requires exactly one existing usteer configuration section before enabling roaming. Resolve duplicate or missing sections first; the service can still be stopped and disabled."
		})
		return
	end
	local snapshot_ok, snapshot = pcall(uci.get_all, uci, "usteer", section_name)
	if not snapshot_ok or type(snapshot) ~= "table" or snapshot[".type"] ~= "usteer" then
		respond(500, { ok = false, error = "The existing usteer settings could not be snapshotted safely." })
		return
	end

	local previous = {}
	for _, option in ipairs(options) do previous[option] = snapshot[option] end
	previous.ssid_list = snapshot.ssid_list
	previous.aggressiveness_mac_list = snapshot.aggressiveness_mac_list
	local previous_init_enabled = fs.access("/etc/rc.d/S50usteer") == true
	local previous_config_enabled = snapshot.enabled ~= "0"
	local desired = { enabled = update.enabled and "1" or "0" }
	if update.enabled then
		desired.network = update.network
		desired.syslog = "1"
		desired.local_mode = "0"
		desired.ipv6 = "0"
		desired.assoc_steering = "0"
		desired.probe_steering = "0"
		desired.load_kick_enabled = "0"
		desired.min_snr = "0"
		desired.min_connect_snr = "0"
		desired.roam_scan_snr = "0"
		desired.roam_trigger_snr = "0"
		desired.aggressiveness = tostring(update.aggressiveness)
		desired.band_steering_interval = tostring(update.band_steering_interval)
		desired.band_steering_min_snr = tostring(update.band_steering_min_snr)
		desired.band_steering_threshold = tostring(update.band_steering_threshold)
		desired.load_balancing_threshold = tostring(update.load_balancing_threshold)
	end

	local function restore_configuration()
		local restored = true
		for _, option in ipairs(options) do
			local value = previous[option]
			local ok, result
			if value == nil then
				ok, result = pcall(uci.delete, uci, "usteer", section_name, option)
				if not ok or result == false then restored = false end
			else
				ok, result = pcall(uci.set, uci, "usteer", section_name, option, value)
				if not ok or result ~= true then restored = false end
			end
		end
		local list_ok, list_result
		if type(previous.ssid_list) == "table" then
			list_ok, list_result = pcall(uci.set_list, uci, "usteer", section_name, "ssid_list", previous.ssid_list)
		else
			list_ok, list_result = pcall(uci.delete, uci, "usteer", section_name, "ssid_list")
			if list_ok and list_result == nil then list_result = true end
		end
		if not list_ok or list_result ~= true then restored = false end
		local override_ok, override_result
		if type(previous.aggressiveness_mac_list) == "table" then
			override_ok, override_result = pcall(uci.set_list, uci, "usteer", section_name, "aggressiveness_mac_list", previous.aggressiveness_mac_list)
		else
			override_ok, override_result = pcall(uci.delete, uci, "usteer", section_name, "aggressiveness_mac_list")
			if override_ok and override_result == nil then override_result = true end
		end
		if not override_ok or override_result ~= true then restored = false end
		local commit_ok, committed = false, false
		if restored then commit_ok, committed = pcall(uci.commit, uci, "usteer") end
		return restored and commit_ok and committed == true
	end

	local function restore_service()
		local init_command = previous_init_enabled
			and "/etc/init.d/usteer enable"
			or "/etc/init.d/usteer disable"
		local service_command = previous_init_enabled and previous_config_enabled
			and "/etc/init.d/usteer restart"
			or "/etc/init.d/usteer stop"
		local ok, status = pcall(sys.call, init_command .. " >/dev/null 2>&1 && " ..
			service_command .. " >/dev/null 2>&1")
		if not ok or status ~= 0 then return false end
		if previous_init_enabled and previous_config_enabled then
			for attempt = 1, 10 do
				if type(ubus_call("usteer", "get_config", {})) == "table" then return true end
				if attempt < 10 then pcall(require("nixio").nanosleep, 0, 200000000) end
			end
			return false
		end
		for attempt = 1, 10 do
			if type(ubus_call("usteer", "get_config", {})) ~= "table" then return true end
			if attempt < 10 then pcall(require("nixio").nanosleep, 0, 200000000) end
		end
		return false
	end

	local function rollback()
		pcall(uci.revert, uci, "usteer")
		local config_restored = restore_configuration()
		local service_restored = config_restored and restore_service()
		return config_restored and service_restored
	end

	for option, value in pairs(desired) do
		local ok, result = pcall(uci.set, uci, "usteer", section_name, option, value)
		if not ok or result ~= true then
			pcall(uci.revert, uci, "usteer")
			respond(500, { ok = false, error = "Roaming settings could not be staged; the daemon was not restarted." })
			return
		end
	end
	if update.enabled then
		local override_ok, override_result = pcall(uci.delete, uci, "usteer", section_name, "aggressiveness_mac_list")
		if not override_ok or override_result == false then
			pcall(uci.revert, uci, "usteer")
			respond(500, { ok = false, error = "Per-client aggressiveness overrides could not be cleared safely." })
			return
		end
		local list_ok, list_result = pcall(uci.set_list, uci, "usteer", section_name, "ssid_list", update.ssids)
		if not list_ok or list_result ~= true then
			pcall(uci.revert, uci, "usteer")
			respond(500, { ok = false, error = "The managed roaming SSID allowlist could not be staged." })
			return
		end
	end

	local commit_ok, committed = pcall(uci.commit, uci, "usteer")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "usteer")
		respond(500, { ok = false, error = "Roaming settings could not be committed; the daemon was not restarted." })
		return
	end

	local command = update.enabled
		and "/etc/init.d/usteer enable >/dev/null 2>&1 && /etc/init.d/usteer restart >/dev/null 2>&1"
		or "/etc/init.d/usteer stop >/dev/null 2>&1 && /etc/init.d/usteer disable >/dev/null 2>&1"
	local restart_ok, restart_status = pcall(sys.call, command)
	if not restart_ok or restart_status ~= 0 then
		local rolled_back = rollback()
		record_audit(http, "wireless.usteer.update", section_name, "failed")
		respond(502, {
			ok = false,
			error = rolled_back
				and "The roaming service transition failed. Previous usteer settings and startup state were restored."
				or "The roaming service transition failed and rollback could not be confirmed. Inspect usteer configuration and daemon state locally.",
			rolled_back = rolled_back
		})
		return
	end

	local nixio = require "nixio"
	local runtime = nil
	local ready = false
	for attempt = 1, 10 do
		local status = usteer_status(uci, fs)
		if update.enabled then
			if status.running and manager.local_ess_ready(update.ssids, access_point_inventory.access_points, status) and
				status.policy_verified == true and
				status.local_ess_verified == true and
				(status.status == "cluster" or status.status == "local_only") and
				status.network == update.network and #status.ssid_list == #update.ssids then
					runtime = status
					ready = true
					break
				end
		else
			if status.status == "disabled" and not status.running then
				runtime = status
				ready = true
				break
			end
		end
		runtime = status
		if attempt < 10 then pcall(nixio.nanosleep, 0, 200000000) end
	end
	if not ready then
		local rolled_back = rollback()
		record_audit(http, "wireless.usteer.update", section_name, "failed")
		respond(502, {
			ok = false,
			error = rolled_back
				and "The usteer service did not reach the requested runtime state. Previous settings were restored."
				or "The usteer service did not reach the requested runtime state and rollback could not be confirmed. Inspect local wireless and daemon state.",
			rolled_back = rolled_back,
			runtime_status = runtime and runtime.status or "unavailable"
		})
		return
	end

	record_audit(http, "wireless.usteer.update", section_name, "success")
	respond(nil, {
		ok = true,
		enabled = update.enabled,
		network = update.enabled and update.network or (previous.network or ""),
		ssid_list = update.enabled and update.ssids or wireless_option_list(previous.ssid_list),
		aggressiveness = update.enabled and update.aggressiveness or tonumber(previous.aggressiveness) or 0,
		assoc_steering = false,
		probe_steering = false,
		load_kick_enabled = false,
		min_snr = 0,
		min_connect_snr = 0,
		roam_scan_snr = 0,
		roam_trigger_snr = 0,
		band_steering_interval = update.enabled and update.band_steering_interval or tonumber(previous.band_steering_interval) or 0,
		band_steering_min_snr = update.enabled and update.band_steering_min_snr or tonumber(previous.band_steering_min_snr) or -60,
		band_steering_threshold = update.enabled and update.band_steering_threshold or tonumber(previous.band_steering_threshold) or 5,
		load_balancing_threshold = update.enabled and update.load_balancing_threshold or tonumber(previous.load_balancing_threshold) or 0,
		status = runtime.status,
		running = runtime.running,
		local_node_count = runtime.local_node_count,
		remote_host_count = runtime.remote_host_count,
		associated_clients = runtime.associated_clients,
		policy_verified = runtime.policy_verified == true,
		local_ess_verified = runtime.local_ess_verified == true,
		service_action_completed = true,
		rolled_back = false
	})
end


function action_sqm_update()
	local http = require "luci.http"
	local sys = require "luci.sys"
	local fs = require "nixio.fs"
	local uci = require("luci.model.uci").cursor()
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then http.status(status, status == 400 and "Bad Request" or
			status == 403 and "Forbidden" or status == 404 and "Not Found" or
			status == 405 and "Method Not Allowed" or status == 503 and "Service Unavailable" or
			status == 502 and "Bad Gateway" or "Internal Server Error") end
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	if fs.access("/etc/init.d/sqm") ~= true or fs.access("/etc/config/sqm") ~= true then
		respond(503, { ok = false, error = "SQM service or configuration is not installed." })
		return
	end

	local validator = require "luci.quantumgrid.sqm"
	local update, validation_error = validator.validate_queue_update(
		http.formvalue("section", true),
		http.formvalue("enabled", true),
		http.formvalue("download", true),
		http.formvalue("upload", true),
		http.formvalue("linklayer", true),
		http.formvalue("overhead", true),
		http.formvalue("tc_mpu", true)
	)
	if not update then
		respond(400, { ok = false, error = validation_error })
		return
	end

	local section_type_ok, section_type = pcall(uci.get, uci, "sqm", update.section, ".type")
	if not section_type_ok then
		respond(500, { ok = false, error = "Could not read SQM queue configuration." })
		return
	end
	if section_type ~= "queue" then
		respond(404, { ok = false, error = "Only an existing SQM queue section can be edited." })
		return
	end

	local snapshot_options = { "enabled", "download", "upload" }
	local options = {
		enabled = update.enabled,
		download = update.download,
		upload = update.upload
	}
	if update.linklayer ~= nil then
		for _, option in ipairs({ "linklayer", "overhead", "tcMPU" }) do
			table.insert(snapshot_options, option)
		end
		options.linklayer = update.linklayer
		options.overhead = update.overhead
		options.tcMPU = update.tc_mpu
	end
	local snapshot = {}
	for _, option in ipairs(snapshot_options) do
		local ok, value = pcall(uci.get, uci, "sqm", update.section, option)
		if not ok then
			respond(500, { ok = false, error = "Could not snapshot the existing SQM queue settings." })
			return
		end
		snapshot[option] = value or false
	end
	for option, value in pairs(options) do
		local ok, result = pcall(uci.set, uci, "sqm", update.section, option, value)
		if not ok or result ~= true then
			pcall(uci.revert, uci, "sqm")
			respond(500, { ok = false, error = "SQM configuration could not be updated; no restart was attempted." })
			return
		end
	end

	local commit_ok, committed = pcall(uci.commit, uci, "sqm")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "sqm")
		respond(500, { ok = false, error = "SQM configuration could not be committed; no restart was attempted." })
		return
	end

	if not sqm_restart(sys) then
		local rollback_saved = restore_sqm_queue(uci, update.section, snapshot)
		local rollback_restarted = rollback_saved and sqm_restart(sys)
		record_audit(http, "sqm.update", update.section, "failed")
		respond(502, {
			ok = false,
			error = rollback_restarted
				and "SQM restart failed. The previous queue settings were restored."
				or "SQM restart failed and rollback could not be confirmed. Inspect SQM configuration and service state before further changes.",
			rolled_back = rollback_restarted
		})
		return
	end

	record_audit(http, "sqm.update", update.section, "success")
	respond(nil, {
		ok = true,
		section = update.section,
		enabled = update.enabled == "1",
		download_kbps = tonumber(update.download),
		upload_kbps = tonumber(update.upload),
		linklayer = update.linklayer,
		overhead_bytes = tonumber(update.overhead),
		tc_mpu_bytes = tonumber(update.tc_mpu),
		restarted = true,
		rolled_back = false
	})
end


function action_mwan3_interface_update()
	local http = require "luci.http"
	local sys = require "luci.sys"
	local fs = require "nixio.fs"
	local uci = require("luci.model.uci").cursor()
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then http.status(status, status == 400 and "Bad Request" or
			status == 403 and "Forbidden" or status == 404 and "Not Found" or
			status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
			status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
			"Internal Server Error") end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	if http.formvalue("confirmed", true) ~= "1" then
		respond(400, { ok = false, error = "Explicit confirmation is required before changing Multi-WAN health checks." })
		return
	end
	if fs.access("/etc/init.d/mwan3") ~= true or fs.access("/etc/config/mwan3") ~= true then
		respond(503, { ok = false, error = "The native mwan3 service or configuration is unavailable." })
		return
	end

	local jsonc = require "luci.jsonc"
	local track_ips_json = http.formvalue("track_ips", true)
	local track_ips = nil
	if type(track_ips_json) == "string" and #track_ips_json <= 4096 then
		local parse_ok, parsed = pcall(jsonc.parse, track_ips_json)
		if parse_ok and type(parsed) == "table" then track_ips = parsed end
	end
	if not track_ips then
		respond(400, { ok = false, error = "Tracking targets must be a JSON array containing valid IP addresses." })
		return
	end

	local validator = require "luci.quantumgrid.mwan3_config"
	local update, validation_error = validator.validate_update({
		section = http.formvalue("section", true),
		enabled = http.formvalue("enabled", true),
		track_ips = track_ips,
		reliability = http.formvalue("reliability", true),
		count = http.formvalue("count", true),
		timeout = http.formvalue("timeout", true),
		interval = http.formvalue("interval", true),
		down = http.formvalue("down", true),
		up = http.formvalue("up", true),
		initial_state = http.formvalue("initial_state", true)
	})
	if not update then
		respond(400, { ok = false, error = validation_error })
		return
	end

	local section_ok, current = pcall(uci.get_all, uci, "mwan3", update.section)
	if not section_ok then
		respond(500, { ok = false, error = "Could not read the current mwan3 configuration." })
		return
	end
	if type(current) ~= "table" or current[".type"] ~= "interface" then
		respond(404, { ok = false, error = "Only an existing mwan3 interface section can be edited." })
		return
	end

	local snapshot = validator.snapshot(current)
	if not snapshot then
		respond(409, { ok = false, error = "The existing mwan3 health settings cannot be snapshotted safely; no change was made." })
		return
	end
	if not validator.stage_update(uci, update.section, update) then
		pcall(uci.revert, uci, "mwan3")
		respond(500, { ok = false, error = "The mwan3 health settings could not be staged; no service restart was attempted." })
		return
	end

	local commit_ok, committed = pcall(uci.commit, uci, "mwan3")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "mwan3")
		respond(500, { ok = false, error = "The mwan3 health settings could not be committed; no service restart was attempted." })
		return
	end

	local restart_ok, restart_status = pcall(sys.call, "/etc/init.d/mwan3 restart >/dev/null 2>&1")
	if not restart_ok or restart_status ~= 0 then
		local rollback_saved = validator.restore(uci, update.section, snapshot)
		local rollback_restart_ok, rollback_restart_status = false, -1
		if rollback_saved then
			rollback_restart_ok, rollback_restart_status = pcall(sys.call, "/etc/init.d/mwan3 restart >/dev/null 2>&1")
		end
		local recovered = rollback_saved and rollback_restart_ok and rollback_restart_status == 0
		record_audit(http, "mwan3.interface.update", update.section, "failed")
		respond(502, {
			ok = false,
			error = recovered
				and "mwan3 restart failed. The previous health-check settings were restored and the service restarted."
				or "mwan3 restart failed and rollback could not be confirmed. Inspect mwan3 configuration and routing locally.",
			rolled_back = recovered
		})
		return
	end

	record_audit(http, "mwan3.interface.update", update.section, "success")
	respond(nil, {
		ok = true,
		section = update.section,
		enabled = update.enabled == "1",
		track_ips = update.track_ips,
		reliability = tonumber(update.reliability),
		count = tonumber(update.count),
		timeout = tonumber(update.timeout),
		interval = tonumber(update.interval),
		down = tonumber(update.down),
		up = tonumber(update.up),
		initial_state = update.initial_state,
		restarted = true,
		rolled_back = false
	})
end


function action_sqm_cake_profile()
	local http = require "luci.http"
	local sys = require "luci.sys"
	local fs = require "nixio.fs"
	local uci = require("luci.model.uci").cursor()
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"
	local function respond(status, payload)
		if status then http.status(status, status == 400 and "Bad Request" or status == 403 and "Forbidden" or
			status == 404 and "Not Found" or status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
			status == 503 and "Service Unavailable" or status == 502 and "Bad Gateway" or "Internal Server Error") end
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end
	if http.getenv("REQUEST_METHOD") ~= "POST" then respond(405, { ok = false, error = "POST is required." }); return end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then respond(403, { ok = false, error = "A same-origin request is required." }); return end
	if fs.access("/etc/init.d/sqm") ~= true or fs.access("/etc/config/sqm") ~= true then
		respond(503, { ok = false, error = "SQM service or configuration is not installed." }); return
	end
	local validator = require "luci.quantumgrid.sqm"
	local update, validation_error = validator.validate_cake_profile_update(http.formvalue("section", true), http.formvalue("profile", true))
	if not update then respond(400, { ok = false, error = validation_error }); return end
	local section_type_ok, section_type = pcall(uci.get, uci, "sqm", update.section, ".type")
	if not section_type_ok then respond(500, { ok = false, error = "Could not read SQM queue configuration." }); return end
	if section_type ~= "queue" then respond(404, { ok = false, error = "Only an existing SQM queue section can be edited." }); return end
	local qdisc_ok, qdisc = pcall(uci.get, uci, "sqm", update.section, "qdisc")
	if not qdisc_ok then respond(500, { ok = false, error = "Could not read the SQM queue discipline." }); return end
	if type(qdisc) ~= "string" or qdisc:lower() ~= "cake" then
		respond(409, { ok = false, error = "CAKE profiles can only be applied to an existing CAKE queue." }); return
	end
	-- SQM-scripts applies ingress and egress CAKE arguments independently.
	-- Snapshot and compose both sides before staging either mutation.
	local option_names = { "iqdisc_opts", "eqdisc_opts" }
	local snapshot, staged = {}, {}
	for _, option in ipairs(option_names) do
		local snapshot_ok, previous = pcall(uci.get, uci, "sqm", update.section, option)
		if not snapshot_ok then
			respond(500, { ok = false, error = "Could not snapshot the existing ingress and egress CAKE options." })
			return
		end
		local options, options_error = validator.build_cake_profile_options(previous, update.profile)
		if options == nil then
			respond(400, { ok = false, error = options_error })
			return
		end
		if previous == nil then snapshot[option] = false else snapshot[option] = previous end
		staged[option] = options
	end

	for _, option in ipairs(option_names) do
		local options = staged[option]
		local write_ok, written = true, true
		if options == "" then
			if snapshot[option] ~= false then
				write_ok, written = pcall(uci.delete, uci, "sqm", update.section, option)
			end
		else
			write_ok, written = pcall(uci.set, uci, "sqm", update.section, option, options)
		end
		if not write_ok or written ~= true then
			pcall(uci.revert, uci, "sqm")
			respond(500, { ok = false, error = "Ingress and egress CAKE options could not be staged; no restart was attempted." })
			return
		end
	end
	local commit_ok, committed = pcall(uci.commit, uci, "sqm")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "sqm")
		respond(500, { ok = false, error = "CAKE options could not be committed; no restart was attempted." }); return
	end
	if not sqm_restart(sys) then
		local rollback_saved = restore_sqm_queue(uci, update.section, snapshot)
		local rollback_restarted = rollback_saved and sqm_restart(sys)
		record_audit(http, "sqm.cake-profile", update.section, "failed")
		respond(502, { ok = false,
			error = rollback_restarted and "SQM restart failed. The previous CAKE options were restored."
				or "SQM restart failed and rollback could not be confirmed. Inspect SQM configuration and service state before further changes.",
			rolled_back = rollback_restarted }); return
	end
	record_audit(http, "sqm.cake-profile", update.section, "success")
	respond(nil, { ok = true, section = update.section, profile = update.profile, restarted = true, rolled_back = false })
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
	if not require_https(http) then return end

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

	record_audit(http, "admin.password.setup", "root", "success")
	http.prepare_content("application/json; charset=UTF-8")
	http.write_json({ ok = true })
end

function action_package_operation()
	local http = require "luci.http"
	local sys = require "luci.sys"
	local fs = require "nixio.fs"
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then
			http.status(status, status == 400 and "Bad Request" or
				status == 403 and "Forbidden" or
				status == 405 and "Method Not Allowed" or
				status == 503 and "Service Unavailable" or
				status == 502 and "Bad Gateway" or "Internal Server Error")
		end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end

	local validator = require "luci.quantumgrid.package_operations"
	local request, validation_error = validator.validate(
		http.formvalue("operation", true),
		http.formvalue("package", true) or "",
		http.formvalue("confirmed", true)
	)
	if not request then
		respond(400, { ok = false, error = validation_error })
		return
	end
	local operation = request.operation
	local package = request.package

	local manager, binary = nil, nil
	for _, candidate in ipairs({ "/sbin/apk", "/usr/bin/apk" }) do
		if fs.access(candidate) == true then manager, binary = "apk", candidate break end
	end
	if not binary then
		for _, candidate in ipairs({ "/bin/opkg", "/usr/bin/opkg" }) do
			if fs.access(candidate) == true then manager, binary = "opkg", candidate break end
		end
	end
	if not binary then
		respond(503, { ok = false, error = "No supported APK or OPKG package manager was detected." })
		return
	end

	local command
	if manager == "apk" then
		if operation == "update" then command = binary .. " update"
		elseif operation == "install" then command = binary .. " add " .. package
		else command = binary .. " del " .. package end
	else
		if operation == "update" then command = binary .. " update"
		elseif operation == "install" then command = binary .. " install " .. package
		else command = binary .. " remove " .. package end
	end

	local log_path = validator.create_secure_log_file(os.tmpname, require "nixio")
	if not log_path then
		respond(500, { ok = false, error = "A private package-operation log file could not be reserved." })
		return
	end
	local call_ok, exit_code = pcall(sys.call, command .. " > " .. log_path .. " 2>&1")
	local output = ""
	local file = io.open(log_path, "r")
	if file then
		output = file:read(6000) or ""
		file:close()
	end
	os.remove(log_path)
	output = output:gsub("\r", "\n"):gsub("[%z\1-\9\11\12\14-\31\127]", " "):sub(1, 6000)

	local audit_action = operation == "install" and "package.install"
		or operation == "remove" and "package.remove" or "package.feed.update"
	local audit_target = package ~= "" and package or manager
	if not call_ok or exit_code ~= 0 then
		record_audit(http, audit_action, audit_target, "failed")
		respond(502, {
			ok = false,
			manager = manager,
			operation = operation,
			package = package ~= "" and package or nil,
			exit_code = call_ok and tonumber(exit_code) or nil,
			output = output,
			error = "The " .. manager .. " package operation failed. Check the package feed, free storage and dependency messages below."
		})
		return
	end

	record_audit(http, audit_action, audit_target, "success")
	respond(nil, {
		ok = true,
		manager = manager,
		operation = operation,
		package = package ~= "" and package or nil,
		exit_code = 0,
		output = output,
		sampled_at = os.time()
	})
end


function action_packages()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local util = require "luci.util"

	if http.getenv("REQUEST_METHOD") ~= "GET" then
		http.status(405, "Method Not Allowed")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json({ ok = false, error = "GET is required." })
		return
	end

	local manager = "unknown"
	local command = nil
	if fs.access("/sbin/apk") == true then
		manager = "apk"
		command = "/sbin/apk list -I"
	elseif fs.access("/usr/bin/apk") == true then
		manager = "apk"
		command = "/usr/bin/apk list -I"
	elseif fs.access("/bin/opkg") == true then
		manager = "opkg"
		command = "/bin/opkg list-installed"
	elseif fs.access("/usr/bin/opkg") == true then
		manager = "opkg"
		command = "/usr/bin/opkg list-installed"
	end

	if not command then
		http.status(503, "Service Unavailable")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json({ ok = false, error = "No supported package manager was detected." })
		return
	end

	local exec_ok, output = pcall(util.exec, command)
	if not exec_ok or type(output) ~= "string" then
		http.status(503, "Service Unavailable")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json({ ok = false, error = "The package manager could not read its installed-package database." })
		return
	end

	local parser = require "luci.quantumgrid.packages"
	local inventory = parser.parse(manager, output, 1500)
	http.header("Cache-Control", "no-store")
	http.prepare_content("application/json; charset=UTF-8")
	http.write_json({
		ok = true,
		manager = inventory.manager,
		count = inventory.count,
		truncated = inventory.truncated,
		packages = inventory.packages,
		sampled_at = os.time()
	})
end


function action_index()
	require("luci.http").redirect("/quantumgrid/")
end

local function security_status(uci, fs)
	local certificate_fingerprint_output = nil
	if fs.access("/usr/bin/openssl") == true then
		local util_ok, util = pcall(require, "luci.util")
		if util_ok and type(util) == "table" and type(util.exec) == "function" then
			-- Fixed certificate path and fixed read-only arguments; never return PEM/key contents.
			local exec_ok, output = pcall(util.exec,
				"/usr/bin/openssl x509 -in /etc/uhttpd.crt -noout -fingerprint -sha256 2>/dev/null")
			if exec_ok and type(output) == "string" and #output <= 4096 then
				certificate_fingerprint_output = output
			end
		end
	end
	local firewall_inventory = require "luci.quantumgrid.firewall_inventory"
	local firewall_runtime = require "luci.quantumgrid.firewall_runtime"
	local result = {
		firewall_installed = fs.access("/etc/init.d/firewall") == true,
		firewall_config_available = fs.access("/etc/config/firewall") == true,
		firewall_config_readable = false,
		zones = {},
		rules = {},
		rules_count = 0,
		redirects = {},
		redirects_count = 0,
		redirects_truncated = false,
		nft_available = false,
		nft_tables = {},
		nft_runtime = firewall_runtime.unavailable(os.time(), false),
		management_transport = management_transport.inspect(uci, fs, certificate_fingerprint_output),
		adblock_fast = {
			installed = fs.access("/etc/init.d/adblock-fast") == true,
			config_available = fs.access("/etc/config/adblock-fast") == true,
			configured_enabled = false
		},
		vpn = {
			wireguard_tool_installed = fs.access("/usr/bin/wg") == true,
			openvpn_service_installed = fs.access("/etc/init.d/openvpn") == true,
			wireguard_interfaces = {},
			wireguard_peers_available = false,
			wireguard_peer_count = 0,
			wireguard_peers_truncated = false,
			wireguard_peers = {},
			openvpn_enabled_instances = 0
		}
	}
	local function rule_value(value, limit)
		local values = {}
		if type(value) == "string" then
			if value ~= "" then table.insert(values, value) end
		elseif type(value) == "table" then
			for _, item in ipairs(value) do
				if type(item) == "string" and item ~= "" and #values < 8 then
					table.insert(values, item)
				end
			end
		end
		return table.concat(values, " "):gsub("[%c]", " "):sub(1, limit or 96)
	end
	local function has_rule_value(value)
		return (type(value) == "string" and value ~= "") or
			(type(value) == "table" and #value > 0)
	end

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
		uci:foreach("firewall", "rule", function(section)
			result.rules_count = result.rules_count + 1
			if #result.rules < 64 then
				local name = rule_value(section.name or section[".name"], 64)
				if name == "" then name = "unnamed-rule-" .. tostring(result.rules_count) end
				table.insert(result.rules, {
					name = name,
					source_zone = rule_value(section.src, 48),
					destination_zone = rule_value(section.dest, 48),
					protocol = rule_value(section.proto, 48),
					target = rule_value(section.target, 24):upper(),
					family = rule_value(section.family, 16),
					source_port = rule_value(section.src_port, 48),
					destination_port = rule_value(section.dest_port, 48),
					enabled = section.enabled ~= "0",
					source_ip_match = has_rule_value(section.src_ip),
					destination_ip_match = has_rule_value(section.dest_ip),
					source_mac_match = has_rule_value(section.src_mac)
				})
			end
		end)
		uci:foreach("firewall", "redirect", function(section)
			result.redirects_count = result.redirects_count + 1
			if #result.redirects < 64 then
				local summary = firewall_inventory.summarize_redirect(section, result.redirects_count)
				if summary then table.insert(result.redirects, summary) end
			else
				result.redirects_truncated = true
			end
		end)
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
	-- wg dump is fixed and read-only. The parser discards keys and endpoint fields.
	if result.vpn.wireguard_tool_installed then
		local peer_ok, peer_output = pcall(util.exec, "wg show all dump")
		if peer_ok and type(peer_output) == "string" then
			local parser = require "luci.quantumgrid.wireguard"
			local peers = parser.parse_dump(peer_output, os.time())
			result.vpn.wireguard_peers_available = peers.available
			result.vpn.wireguard_peer_count = peers.count
			result.vpn.wireguard_peers_truncated = peers.truncated
			result.vpn.wireguard_peers = peers.peers
		end
	end

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

	local nft_binary = fs.access("/usr/sbin/nft") == true and "/usr/sbin/nft" or
		fs.access("/usr/bin/nft") == true and "/usr/bin/nft" or nil
	local fw4_present = false
	for _, table_name in ipairs(result.nft_tables) do
		if table_name == "inet/fw4" then fw4_present = true break end
	end
	if fw4_present then
		if nft_binary then
			local runtime_ok, runtime_output = pcall(util.exec,
				nft_binary .. " -j list table inet fw4 2>/dev/null")
			if runtime_ok and type(runtime_output) == "string" then
				if #runtime_output > 512 * 1024 then
					result.nft_runtime = firewall_runtime.unavailable(os.time(), true, true)
				else
					local jsonc = require "luci.jsonc"
					local decoded_ok, decoded = pcall(jsonc.parse, runtime_output)
					if decoded_ok and type(decoded) == "table" then
						result.nft_runtime = firewall_runtime.parse(decoded, os.time())
					else
						result.nft_runtime = firewall_runtime.unavailable(os.time(), false, true)
					end
				end
			else
				result.nft_runtime = firewall_runtime.unavailable(os.time(), false, true)
			end
		else
			result.nft_runtime = firewall_runtime.unavailable(os.time(), false, true)
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
		qdiscs = {},
		qdiscs_truncated = false,
		client_policy_available = fs.access("/etc/config/firewall") == true,
		client_policies = {},
		client_policies_truncated = false
	}
	local sqm_validator = require "luci.quantumgrid.sqm"
	local ok = pcall(function()
		uci:foreach("sqm", "queue", function(section)
			if #result.queues < 16 then
				local queue = {
					name = tostring(section[".name"] or ""),
					enabled = section.enabled == "1",
					interface = tostring(section.interface or ""),
					download_kbps = tonumber(section.download),
					upload_kbps = tonumber(section.upload),
					qdisc = tostring(section.qdisc or ""),
					script = tostring(section.script or ""),
					linklayer = tostring(section.linklayer or ""),
					overhead = tonumber(section.overhead),
					tc_mpu = tonumber(section.tcMPU)
				}
				if queue.qdisc:lower() == "cake" then
					queue.cake_profile = sqm_validator.detect_cake_profile_pair(
						section.iqdisc_opts, section.eqdisc_opts)
				end
				table.insert(result.queues, queue)
			end
		end)
	end)
	result.config_readable = ok

	-- Fixed read-only command; no request or UCI value is passed to a shell.
	local util = require "luci.util"
	local exec_ok, output = pcall(util.exec, "tc -s qdisc show")
	if exec_ok then
		result.runtime_available, result.qdiscs, result.qdiscs_truncated =
			sqm_validator.parse_qdisc_inventory(output)
	end
	for _, queue in ipairs(result.queues) do
		queue.runtime_state = sqm_validator.queue_runtime_state(
			queue, result.qdiscs, result.runtime_available, result.qdiscs_truncated)
	end
	if result.client_policy_available then
		local qos = require "luci.quantumgrid.qos"
		local read_ok, policies, truncated = pcall(qos.read_client_policies, uci, 32)
		if read_ok and type(policies) == "table" then
			result.client_policies = policies
			result.client_policies_truncated = truncated == true
		else
			result.client_policy_available = false
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


local function conntrack_status(fs)
	local count_path = "/proc/sys/net/netfilter/nf_conntrack_count"
	local maximum_path = "/proc/sys/net/netfilter/nf_conntrack_max"
	if fs.access(count_path) ~= true or fs.access(maximum_path) ~= true then
		return { available = false }
	end

	local parser = require "luci.quantumgrid.conntrack"
	return parser.summarize(read_file(count_path), read_file(maximum_path))
end


local function platform_status(fs)
	local board = ubus_call("system", "board", {}) or {}
	local release = type(board.release) == "table" and board.release or {}
	local profile_data = nil
	local profile_path = "/etc/quantumgrid/device-profile.json"
	local stat_ok, profile_stat = pcall(fs.stat, profile_path)
	if stat_ok and type(profile_stat) == "table" and
		type(profile_stat.size) == "number" and profile_stat.size > 0 and profile_stat.size <= 32768 then
		local profile_file = io.open(profile_path, "r")
		if profile_file then
			local profile_contents = profile_file:read(32769) or ""
			profile_file:close()
			if #profile_contents > 0 and #profile_contents <= 32768 then
				local parse_ok, parsed = pcall(function()
					return require("luci.jsonc").parse(profile_contents)
				end)
				if parse_ok and type(parsed) == "table" then profile_data = parsed end
			end
		end
	end
	local device_profile = require("luci.quantumgrid.device_profile").inspect(
		profile_data, board.board_name)
	local device_identity_contents = nil
	local identity_file = io.open("/etc/quantumgrid/device-id", "r")
	if identity_file then
		local candidate = identity_file:read(34) or ""
		local overflow = identity_file:read(1)
		identity_file:close()
		if not overflow then device_identity_contents = candidate end
	end
	local device_identity = require("luci.quantumgrid.device_identity").inspect(
		device_identity_contents)
	local modules = {
		{ name = "ath11k Wi-Fi driver", path = "/sys/module/ath11k" },
		{ name = "mac80211 wireless stack", path = "/sys/module/mac80211" },
		{ name = "Qualcomm NSS core driver", path = "/sys/module/qca_nss_drv" },
		{ name = "Qualcomm NSS datapath / EDMA driver", path = "/sys/module/qca_nss_dp" },
		{ name = "Qualcomm switch SDK", path = "/sys/module/qca_ssdk" },
		{ name = "Qualcomm NSS ECM", path = "/sys/module/ecm" },
		{ name = "Qualcomm multicast snooping (MCS)", path = "/sys/module/qca_mcs" },
		{ name = "WireGuard", path = "/sys/module/wireguard" },
		{ name = "CAKE scheduler", path = "/sys/module/sch_cake" }
	}
	local tools = {
		{ name = "ubus", paths = { "/sbin/ubus", "/usr/bin/ubus" } },
		{ name = "uci", paths = { "/sbin/uci", "/bin/uci" } },
		{ name = "iwinfo", paths = { "/sbin/iwinfo", "/usr/bin/iwinfo" } },
		{ name = "uqmi", paths = { "/sbin/uqmi", "/usr/bin/uqmi" } },
		{ name = "nft", paths = { "/usr/sbin/nft", "/sbin/nft" } },
		{ name = "tc", paths = { "/sbin/tc", "/usr/sbin/tc" } },
		{ name = "NSS statistics utility", paths = { "/usr/bin/nss_stats", "/sbin/nss_stats" } }
	}
	local services = {
		{ name = "Network manager", path = "/etc/init.d/network" },
		{ name = "Firewall", path = "/etc/init.d/firewall" },
		{ name = "DNS and DHCP", path = "/etc/init.d/dnsmasq" },
		{ name = "Smart Queue Management", path = "/etc/init.d/sqm" },
		{ name = "Qualcomm NSS CPU/IRQ tuning", path = "/etc/init.d/qca-nss-drv" },
		{ name = "Qualcomm NSS ECM integration", path = "/etc/init.d/qca-nss-ecm" },
		{ name = "Wi-Fi roaming assist (usteer)", path = "/etc/init.d/usteer" },
		{ name = "Adblock Fast", path = "/etc/init.d/adblock-fast" },
		{ name = "FXS voice daemon", path = "/etc/init.d/fxsd" }
	}
	for _, item in ipairs(modules) do
		item.loaded = fs.access(item.path) == true
		item.path = nil
	end
	local kernel_release = read_file("/proc/sys/kernel/osrelease") or ""
	local kernel_module_path = nil
	if kernel_release:match("^[%w%.%+_%-]+$") then
		kernel_module_path = "/lib/modules/" .. kernel_release .. "/modules.dep"
	end
	local kernel_module_inventory = require("luci.quantumgrid.kernel_modules").parse(
		kernel_module_path and read_file(kernel_module_path) or nil,
		read_file("/proc/modules"),
		2000
	)
	for _, item in ipairs(tools) do
		item.available = false
		for _, path in ipairs(item.paths) do
			if fs.access(path) == true then item.available = true break end
		end
		item.paths = nil
	end
	for _, item in ipairs(services) do
		item.installed = fs.access(item.path) == true
		item.path = nil
	end
	local storage = {}
	local mtd = read_file("/proc/mtd") or ""
	for line in mtd:gmatch("[^\r\n]+") do
		if #storage >= 32 then break end
		local device, size_hex, erase_hex, name =
			line:match("^(mtd%d+):%s+(%x+)%s+(%x+)%s+\"([^\"]+)\"")
		local size = size_hex and tonumber(size_hex, 16) or nil
		local erase = erase_hex and tonumber(erase_hex, 16) or nil
		if device and size and erase then
			table.insert(storage, {
				device = device, name = name:sub(1, 80),
				size_bytes = size, erase_size_bytes = erase
			})
		end
	end
	local block_devices = {}
	local partitions = read_file("/proc/partitions") or ""
	for line in partitions:gmatch("[^\r\n]+") do
		if #block_devices >= 64 then break end
		local major, minor, blocks, name =
			line:match("^%s*(%d+)%s+(%d+)%s+(%d+)%s+([%w_.%-]+)%s*$")
		local block_count = tonumber(blocks)
		if major and minor and block_count and block_count > 0 then
			table.insert(block_devices, {
				name = name:sub(1, 96),
				major = tonumber(major),
				minor = tonumber(minor),
				size_bytes = block_count * 1024
			})
		end
	end

	local mounts = {}
	local mount_table = read_file("/proc/mounts") or ""
	for line in mount_table:gmatch("[^\r\n]+") do
		if #mounts >= 32 then break end
		local source, mountpoint, filesystem, options =
			line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
		local relevant = mountpoint == "/" or mountpoint == "/rom"
			or mountpoint == "/overlay" or mountpoint == "/tmp"
			or (mountpoint and mountpoint:match("^/mnt/") ~= nil)
		if source and relevant then
			local mount = {
				source = source:sub(1, 128),
				mountpoint = mountpoint:sub(1, 128),
				filesystem = filesystem:sub(1, 48),
				read_only = ("," .. options .. ","):find(",ro,", 1, true) ~= nil
			}
			if type(fs.statvfs) == "function" then
				local ok, stats = pcall(fs.statvfs, mountpoint)
				if ok and type(stats) == "table" then
					local blocks = tonumber(stats.blocks)
					local free_blocks = tonumber(stats.bfree)
					local available_blocks = tonumber(stats.bavail)
					local fragment_size = tonumber(stats.frsize)
					if blocks and blocks > 0 and fragment_size and fragment_size > 0 then
						mount.total_bytes = blocks * fragment_size
						if available_blocks and available_blocks >= 0 then
							mount.available_bytes = available_blocks * fragment_size
						end
						if free_blocks and free_blocks >= 0 then
							mount.used_percent = math.max(0, math.min(100,
								((blocks - free_blocks) / blocks) * 100))
						end
					end
				end
			end
			table.insert(mounts, mount)
		end
	end

	local package_manager = "Not detected"
	if fs.access("/sbin/apk") == true or fs.access("/usr/bin/apk") == true then
		package_manager = "apk"
	elseif fs.access("/bin/opkg") == true or fs.access("/usr/bin/opkg") == true then
		package_manager = "opkg"
	end
	local field = function(value, limit)
		if type(value) ~= "string" or value == "" then return nil end
		return value:gsub("[%c]", " "):sub(1, limit or 160)
	end
	local ath11k_nss_parameter = (read_file("/sys/module/ath11k/parameters/nss_offload") or ""):gsub("%s", ""):lower()
	local ath11k_nss_enabled = ath11k_nss_parameter == "1" or ath11k_nss_parameter == "y"
	local acceleration_components = {
		{
			name = "EDMA device-tree node",
			kind = "device-tree",
			present = fs.access("/sys/firmware/devicetree/base/soc/edma@3ab00000") == true,
			detail = "Qualcomm EDMA node in the running device tree"
		},
		{
			name = "ESS / PPE switch device-tree node",
			kind = "device-tree",
			present = fs.access("/sys/firmware/devicetree/base/soc/ess-switch@3a000000") == true,
			detail = "Ethernet switch and PPE-capable ESS node; node presence does not prove NSS acceleration"
		},
		{
			name = "NSS core 0 device-tree node",
			kind = "device-tree",
			present = fs.access("/sys/firmware/devicetree/base/soc/nss@40000000") == true,
			detail = "NSS core 0 platform description"
		},
		{
			name = "NSS core 1 device-tree node",
			kind = "device-tree",
			present = fs.access("/sys/firmware/devicetree/base/soc/nss@40800000") == true,
			detail = "NSS core 1 platform description"
		},
		{
			name = "NSS core driver",
			kind = "kernel-module",
			present = fs.access("/sys/module/qca_nss_drv") == true,
			detail = "qca_nss_drv.ko loaded in the running kernel"
		},
		{
			name = "NSS datapath / EDMA driver",
			kind = "kernel-module",
			present = fs.access("/sys/module/qca_nss_dp") == true,
			detail = "qca_nss_dp.ko loaded; this is not proof that flows are being offloaded"
		},
		{
			name = "Qualcomm SSDK",
			kind = "kernel-module",
			present = fs.access("/sys/module/qca_ssdk") == true,
			detail = "qca_ssdk kernel module loaded"
		},
		{
			name = "NSS Enhanced Connection Manager",
			kind = "kernel-module",
			present = fs.access("/sys/module/ecm") == true,
			detail = "ecm.ko loaded for flow classification and offload coordination"
		},
		{
			name = "NSS firmware core 0",
			kind = "firmware",
			present = fs.access("/lib/firmware/qca-nss0-retail.bin") == true,
			detail = "qca-nss0-retail.bin"
		},
		{
			name = "NSS firmware core 1",
			kind = "firmware",
			present = fs.access("/lib/firmware/qca-nss1-retail.bin") == true,
			detail = "qca-nss1-retail.bin"
		},
		{
			name = "Wi-Fi driver",
			kind = "kernel-module",
			present = fs.access("/sys/module/ath11k") == true,
			detail = "ath11k loaded; this alone does not prove NSS Wi-Fi hooks are compiled or active"
		},
		{
			name = "ath11k NSS offload parameter",
			kind = "kernel-module",
			present = ath11k_nss_enabled,
			detail = "The driver's nss_offload module parameter must report enabled"
		}
	}
	local acceleration = require("luci.quantumgrid.acceleration").summarize(acceleration_components)
	return {
		available = next(board) ~= nil,
		hostname = field(board.hostname, 64),
		model = field(board.model, 128),
		board_name = field(board.board_name, 128),
		system = field(board.system, 128),
		kernel = field(board.kernel, 96) or field(read_file("/proc/sys/kernel/osrelease"), 96),
		distribution = field(release.distribution, 96),
		version = field(release.version, 64),
		revision = field(release.revision, 96),
		target = field(release.target, 128),
		description = field(release.description, 192),
		package_manager = package_manager,
		device_profile = device_profile,
		device_identity = device_identity,
		acceleration = acceleration,
		modules = modules,
		kernel_modules = kernel_module_inventory,
		tools = tools, services = services, storage = storage,
		block_devices = block_devices, mounts = mounts
	}
end


local function office_network_status(uci, fs)
	local util = require "luci.util"
	local validator = require "luci.quantumgrid.office_networks"
	local source = {
		redirects = {},
		ipv6_pinholes = {},
		available = false,
		truncated = false,
		firewall_available = false,
		wireless_available = false,
		dhcp_available = false,
		interfaces = {},
		bridges = {},
		vlans = {},
		zones = {},
		forwardings = {},
		wifi_aps = {},
		dhcp_scopes = {},
		static_leases = {},
		sampled_at = os.time()
	}
	local network_ok = pcall(function()
		uci:foreach("network", "interface", function(section)
			if #source.interfaces >= 64 then source.truncated = true return end
			local name = tostring(section[".name"] or "")
			if not name:match("^[%w_.%-]+$") then return end
			local status = ubus_call("network.interface." .. name, "status", {}) or {}
			local device = section.device
			if type(device) ~= "string" or device == "" then
				device = type(section.ifname) == "string" and section.ifname or ""
			end
			if type(device) ~= "string" or not device:match("^[%w][%w_.%-]*$") then device = "" end
			local neighbor_device = status.l3_device or status.device or device
			if type(neighbor_device) ~= "string" or not neighbor_device:match("^[%w][%w_.%-]*$") then
				neighbor_device = ""
			end
			local ipv6_neighbors = {}
			if status.up == true and neighbor_device ~= "" and fs.access("/sbin/ip") == true then
				local command = "/sbin/ip -6 neigh show dev " .. neighbor_device .. " 2>/dev/null | head -n 64"
				local command_ok, output = pcall(util.exec, command)
				if command_ok and type(output) == "string" then
					ipv6_neighbors = validator.parse_ipv6_neighbor_inventory(output, neighbor_device)
				end
			end
			table.insert(source.interfaces, {
				name = name,
				protocol = tostring(section.proto or ""),
				device = device,
				l3_device = neighbor_device,
				up = status.up == true,
				ipv4 = section.ipaddr,
				netmask = section.netmask,
				ip6assign = section.ip6assign,
				ipv6 = section.ip6addr,
				ipv6_neighbors = ipv6_neighbors
			})
		end)
		uci:foreach("network", "device", function(section)
			if #source.bridges >= 32 then source.truncated = true return end
			if section.type == "bridge" then
				local name = tostring(section.name or "")
				if name:match("^[%w_.%-]+$") then
					table.insert(source.bridges, {
						name = name,
						type = section.type,
						ports = section.ports,
						vlan_filtering = section.vlan_filtering == "1"
					})
				end
			end
		end)
		uci:foreach("network", "bridge-vlan", function(section)
			if #source.vlans >= 64 then source.truncated = true return end
			local name = tostring(section[".name"] or "")
			local device = tostring(section.device or "")
			if name:match("^[%w_.%-]+$") and device:match("^[%w_.%-]+$")
				and tonumber(section.vlan) then
				table.insert(source.vlans, {
					name = name,
					device = device,
					vlan = section.vlan,
					ports = section.ports
				})
			end
		end)
	end)
	source.available = network_ok and fs.access("/etc/config/network") == true

	local firewall_ok = pcall(function()
		uci:foreach("firewall", "zone", function(section)
			if #source.zones >= 32 then source.truncated = true return end
			local name = tostring(section.name or section[".name"] or "")
			local section_name = tostring(section[".name"] or "")
			if name:match("^[%w_.%-]+$") and section_name:match("^[%w_.%-]+$") then
				table.insert(source.zones, {
					section = section_name,
					name = name,
					networks = section.network,
					input = section.input,
					output = section.output,
					forward = section.forward,
					masquerade = section.masq == "1"
				})
			end
		end)
		uci:foreach("firewall", "forwarding", function(section)
			if #source.forwardings >= 64 then source.truncated = true return end
			local name = tostring(section.name or section[".name"] or "")
			local section_name = tostring(section[".name"] or "")
			local source_zone = tostring(section.src or "")
			local destination_zone = tostring(section.dest or "")
			if name:match("^[%w_.%-]+$") and section_name:match("^[%w_.%-]+$")
				and source_zone:match("^[%w_.%-]+$") and destination_zone:match("^[%w_.%-]+$") then
				table.insert(source.forwardings, {
					name = name,
					section = section_name,
					source = source_zone,
					destination = destination_zone
				})
			end
		end)

		uci:foreach("firewall", "redirect", function(section)
			if #source.redirects >= 64 then source.truncated = true return end
			local section_name = tostring(section[".name"] or "")
			local name = tostring(section.name or section_name)
			local source_zone = tostring(section.src or "")
			local destination_zone = tostring(section.dest or "")
			local protocol = section.proto
			if type(protocol) == "table" then protocol = table.concat(protocol, " ") end
			protocol = tostring(protocol or "")
			local source_port = tonumber(section.src_dport)
			local destination_port = tonumber(section.dest_port)
			local destination_ip = tostring(section.dest_ip or "")
			local target = tostring(section.target or "DNAT"):upper()
			local family = tostring(section.family or ""):lower()
			if section_name:match("^[%w_.%-]+$") and name:match("^[%w_.%-]+$")
				and source_zone:match("^[%w_.%-]+$") and destination_zone:match("^[%w_.%-]+$")
				and target == "DNAT" and (family == "" or family == "ipv4")
				and (protocol == "tcp" or protocol == "udp" or protocol == "tcp udp")
				and source_port and source_port >= 1 and source_port <= 65535
				and destination_port and destination_port >= 1 and destination_port <= 65535
				and destination_ip:match("^%d+%.%d+%.%d+%.%d+$") then
				table.insert(source.redirects, {
					section = section_name,
					name = name,
					source = source_zone,
					destination = destination_zone,
					protocol = protocol,
					source_port = source_port,
					destination_ip = destination_ip,
					destination_port = destination_port,
					enabled = section.enabled ~= "0",
					target = target,
					family = family
				})
			end
		end)
		uci:foreach("firewall", "rule", function(section)
			if #source.ipv6_pinholes >= 64 then source.truncated = true return end
			local section_name = tostring(section[".name"] or "")
			local raw_name = tostring(section.name or "")
			local display_name = raw_name:match("^QuantumGrid IPv6 pinhole: ([A-Za-z0-9][A-Za-z0-9_.%-]*)$")
			local source_zone = tostring(section.src or "")
			local destination_zone = tostring(section.dest or "")
			local protocol = section.proto
			if type(protocol) == "table" then protocol = table.concat(protocol, " ") end
			protocol = tostring(protocol or "")
			local destination_port = tonumber(section.dest_port)
			local destination_ip = tostring(section.dest_ip or "")
			if display_name and section_name:match("^[%w_.%-]+$")
				and source_zone:match("^[%w_.%-]+$") and destination_zone:match("^[%w_.%-]+$")
				and section.family == "ipv6" and section.target == "ACCEPT"
				and (protocol == "tcp" or protocol == "udp" or protocol == "tcp udp")
				and destination_port and destination_port >= 1 and destination_port <= 65535
				and destination_port == math.floor(destination_port)
				and destination_ip:find(":", 1, true) then
				table.insert(source.ipv6_pinholes, {
					section = section_name,
					name = display_name,
					source = source_zone,
					destination = destination_zone,
					protocol = protocol,
					destination_ip = destination_ip,
					destination_port = destination_port,
					enabled = section.enabled ~= "0"
				})
			end
		end)
	end)
	source.firewall_available = firewall_ok and fs.access("/etc/config/firewall") == true

	local wireless_ok = pcall(function()
		uci:foreach("wireless", "wifi-iface", function(section)
			if #source.wifi_aps >= 32 then source.truncated = true return end
			local name = tostring(section[".name"] or "")
			if name:match("^[%w_.%-]+$") then
				local networks = {}
				if type(section.network) == "string" then
					if section.network:match("^[%w_.%-]+$") then table.insert(networks, section.network) end
				elseif type(section.network) == "table" then
					for _, network in ipairs(section.network) do
						if type(network) == "string" and network:match("^[%w_.%-]+$") then
							table.insert(networks, network)
						end
					end
				end
				table.insert(source.wifi_aps, {
					section = name,
					mode = section.mode,
					ssid = section.ssid,
					device = section.device,
					networks = networks,
					disabled = section.disabled == "1"
				})
			end
		end)
	end)
	source.wireless_available = wireless_ok and fs.access("/etc/config/wireless") == true

	local dhcp_ok = pcall(function()
		uci:foreach("dhcp", "dhcp", function(section)
			if #source.dhcp_scopes >= 64 then source.truncated = true return end
			local name = tostring(section[".name"] or "")
			local interface = tostring(section.interface or "")
			if name:match("^[%w_.%-]+$") and interface:match("^[%w_.%-]+$") then
				table.insert(source.dhcp_scopes, {
					section = name,
					name = name,
					interface = interface,
					start = section.start,
					limit = section.limit,
					lease_time = section.leasetime,
					ignore = section.ignore == "1",
					dhcpv6 = section.dhcpv6,
					ra = section.ra,
					ndp = section.ndp,
					ra_flags = section.ra_flags,
					ra_slaac = section.ra_slaac ~= "0",
					ra_dns = section.ra_dns ~= "0",
					ra_preference = section.ra_preference or "medium",
					ra_lifetime = tonumber(section.ra_lifetime) or 2700,
					dhcpv6_na = section.dhcpv6_na ~= "0",
					dhcpv6_pd = section.dhcpv6_pd ~= "0",
					dhcpv6_assignall = section.dhcpv6_assignall ~= "0",
					dhcpv6_pd_min_len = tonumber(section.dhcpv6_pd_min_len) or 62
				})
			end
		end)
		uci:foreach("dhcp", "host", function(section)
			if #source.static_leases >= 256 then source.truncated = true return end
			table.insert(source.static_leases, {
				section = section[".name"],
				name = section.name or section[".name"],
				mac = section.mac,
				ipv4 = section.ip
			})
		end)
	end)
	source.dhcp_available = dhcp_ok and fs.access("/etc/config/dhcp") == true

	local parser = require "luci.quantumgrid.office_networks"
	return parser.build_inventory(source)
end


local function usteer_access_point_inventory(uci)
	local result = {}
	local total = 0
	local ok = pcall(function()
		uci:foreach("wireless", "wifi-iface", function(section)
			if section.mode ~= "ap" then return end
			total = total + 1
			if #result >= 64 then return end
			local name = type(section[".name"]) == "string" and section[".name"] or ""
			local radio = type(section.device) == "string" and section.device or ""
			if not name:match("^[%w_.%-]+$") or not radio:match("^[%w_.%-]+$") then return end
			local radio_ok, radio_type = pcall(uci.get, uci, "wireless", radio, ".type")
			if not radio_ok or radio_type ~= "wifi-device" then return end
			local networks = {}
			for _, network in ipairs(wireless_option_list(section.network)) do
				if type(network) == "string" and network:match("^[%w_.%-]+$") then
					table.insert(networks, network)
				end
			end
			local encryption = type(section.encryption) == "string" and section.encryption or "none"
			table.insert(result, {
				section = name,
				radio = radio,
				mode = "ap",
				ssid = type(section.ssid) == "string" and section.ssid or "",
				networks = networks,
				encryption = encryption,
				key = type(section.key) == "string" and section.key or "",
				auth_server = type(section.auth_server) == "string" and section.auth_server or "",
				auth_port = tonumber(section.auth_port) or 1812,
				auth_secret = type(section.auth_secret) == "string" and section.auth_secret or "",
				acct_server = type(section.acct_server) == "string" and section.acct_server or "",
				acct_port = tonumber(section.acct_port) or 1813,
				acct_secret = type(section.acct_secret) == "string" and section.acct_secret or "",
				auth_server2 = type(section.auth_server2) == "string" and section.auth_server2 or "",
				auth_port2 = tonumber(section.auth_port2) or 1812,
				auth_secret2 = type(section.auth_secret2) == "string" and section.auth_secret2 or "",
				acct_server2 = type(section.acct_server2) == "string" and section.acct_server2 or "",
				acct_port2 = tonumber(section.acct_port2) or 1813,
				acct_secret2 = type(section.acct_secret2) == "string" and section.acct_secret2 or "",
				nasid = type(section.nasid) == "string" and section.nasid or "",
				ieee80211w = type(section.ieee80211w) == "string" and section.ieee80211w or "",
				dynamic_vlan = type(section.dynamic_vlan) == "string" and section.dynamic_vlan or "0",
				ieee80211r = type(section.ieee80211r) == "string" and section.ieee80211r or "0",
				mobility_domain = type(section.mobility_domain) == "string" and section.mobility_domain or "",
				ft_over_ds = type(section.ft_over_ds) == "string" and section.ft_over_ds or "0",
				ft_psk_generate_local = type(section.ft_psk_generate_local) == "string" and section.ft_psk_generate_local or "0",
				ieee80211k = section.ieee80211k == "1" and "1" or "0",
				ieee80211v = section.ieee80211v == "1" and "1" or "0",
				disabled = section.disabled == "1",
				radio_disabled = uci:get("wireless", radio, "disabled") == "1"
			})
		end)
	end)
	return {
		available = ok,
		truncated = total > #result,
		count = total,
		access_points = result
	}
end

local function usteer_status(uci, fs)
	local manager = require "luci.quantumgrid.usteer"
	local service_installed = fs.access("/etc/init.d/usteer") == true
	local binary_installed = fs.access("/sbin/usteerd") == true
	local config_available = fs.access("/etc/config/usteer") == true
	local init_enabled = fs.access("/etc/rc.d/S50usteer") == true
	local section_count = 0
	local section = nil
	local section_ok = config_available and pcall(function()
		uci:foreach("usteer", "usteer", function(candidate)
			section_count = section_count + 1
			if section_count == 1 then section = candidate end
		end)
	end) or false
	local configured = section_ok and section_count == 1 and
		type(section) == "table" and section[".type"] == "usteer"
	local result = {
		available = service_installed and binary_installed and config_available,
		service_installed = service_installed,
		binary_installed = binary_installed,
		config_available = config_available,
		configured = configured,
		configured_enabled = configured and section.enabled ~= "0",
		init_enabled = init_enabled,
		running = false,
		status = "unavailable",
		network = "",
		ssid_list = {},
		aggressiveness = tonumber(section and section.aggressiveness) or 1,
		syslog = section and section.syslog == "1" or false,
		ipv6 = section and section.ipv6 == "1" or false,
		assoc_steering = section and section.assoc_steering == "1" or false,
		probe_steering = section and section.probe_steering == "1" or false,
		load_kick_enabled = section and section.load_kick_enabled == "1" or false,
		min_snr = tonumber(section and section.min_snr) or 0,
		min_connect_snr = tonumber(section and section.min_connect_snr) or 0,
		roam_scan_snr = tonumber(section and section.roam_scan_snr) or 0,
		roam_trigger_snr = tonumber(section and section.roam_trigger_snr) or 0,
		local_mode = section and section.local_mode == "1" or false,
		band_steering_interval = tonumber(section and section.band_steering_interval) or 0,
		band_steering_min_snr = tonumber(section and section.band_steering_min_snr) or -60,
		band_steering_threshold = tonumber(section and section.band_steering_threshold) or 5,
		load_balancing_threshold = tonumber(section and section.load_balancing_threshold) or 0,
		aggressiveness_override_count = #wireless_option_list(section and section.aggressiveness_mac_list),
		local_node_count = 0,
		local_nodes_truncated = false,
		local_nodes_invalid_count = 0,
		policy_verified = false,
		local_ess_verified = false,
		remote_host_count = 0,
		remote_hosts_truncated = false,
		associated_clients = 0,
		local_nodes = {},
		remote_hosts_available = false,
		sampled_at = os.time()
	}
	if not result.available or not configured then return result end

	result.network = type(section.network) == "string" and section.network or ""
	result.ssid_list = wireless_option_list(section.ssid_list)
	local access_points = usteer_access_point_inventory(uci)
	if not result.configured_enabled or not init_enabled then
		result.status = "disabled"
		return result
	end

	local runtime_config = ubus_call("usteer", "get_config", {})
	local local_nodes = ubus_call("usteer", "local_info", {})
	local remote_hosts = ubus_call("usteer", "remote_hosts", {})
	local runtime = manager.summarize_runtime(
		type(runtime_config) == "table" and runtime_config or nil,
		type(local_nodes) == "table" and local_nodes or nil,
		type(remote_hosts) == "table" and remote_hosts or nil
	)
	result.running = type(runtime_config) == "table" and type(local_nodes) == "table"
	result.local_node_count = runtime.local_node_count
	result.local_nodes_truncated = runtime.local_nodes_truncated
	result.local_nodes_invalid_count = runtime.local_nodes_invalid_count
	result.remote_host_count = runtime.remote_host_count
	result.remote_hosts_truncated = runtime.remote_hosts_truncated
	result.associated_clients = runtime.associated_clients
	result.local_nodes = runtime.local_nodes
	result.remote_hosts_available = type(remote_hosts) == "table"
	result.local_ess_verified = access_points.available == true and access_points.truncated ~= true and
		manager.local_ess_ready(result.ssid_list, access_points.access_points, runtime)
	if not result.running then
		result.status = "not_running"
		return result
	end

	local runtime_matches = manager.runtime_policy_matches(runtime_config, result)
	result.policy_verified = runtime_matches
	if not runtime_matches or not result.local_ess_verified then
		result.status = "review"
	elseif result.remote_host_count > 0 then
		result.status = "cluster"
	else
		result.status = "local_only"
	end
	return result
end


local function remote_syslog_status(uci, fs)
	local remote_syslog = require "luci.quantumgrid.remote_syslog"
	local pid_contents = read_file("/var/run/stunnel/stunnel.pid")
	local pid = type(pid_contents) == "string" and pid_contents:match("^%s*(%d+)%s*$") or nil
	local process = {
		pid = pid_contents,
		comm = pid and read_file("/proc/" .. pid .. "/comm") or nil,
		cmdline = pid and read_file("/proc/" .. pid .. "/cmdline") or nil
	}
	return remote_syslog.inspect_status(uci, fs, os.time(), process)
end


local function hardware_io_status(fs)
	local hardware = require "luci.quantumgrid.hardware_io"
	local board_compatible = read_file("/proc/device-tree/compatible") or
		read_file("/sys/firmware/devicetree/base/compatible")
	local board_reference = hardware.parse_board_gpio_reference(board_compatible)
	local gpio = hardware.parse_gpio_debugfs(read_file("/sys/kernel/debug/gpio"))
	local gpio_sysfs_entries = {}
	local gpio_sysfs_ok, gpio_sysfs_iter = pcall(fs.dir, "/sys/bus/gpio/devices")
	local gpio_sysfs_available = gpio_sysfs_ok and type(gpio_sysfs_iter) == "function"
	if gpio_sysfs_available then
		for name in gpio_sysfs_iter do
			if type(name) == "string" and #gpio_sysfs_entries < 64
				and name:match("^gpiochip%d+$") then
				local base = "/sys/bus/gpio/devices/" .. name
				table.insert(gpio_sysfs_entries, {
					name = name,
					label = read_file(base .. "/label"),
					base = read_number(base .. "/base"),
					ngpio = read_number(base .. "/ngpio")
				})
			end
		end
	end
	gpio.sysfs = hardware.parse_gpio_sysfs_chips(gpio_sysfs_entries, gpio_sysfs_available)
	local input_devices = hardware.parse_input_devices(read_file("/proc/bus/input/devices"))
	local button_events = hardware.parse_button_events(
		read_file("/var/run/quantumgrid/button-events.tsv"), os.time())
	button_events.monitor_available =
		fs.access("/var/run/quantumgrid/button-events.monitor") == true
	local leds = {}
	local iterator_ok, iterator = pcall(fs.dir, "/sys/class/leds")
	local leds_available = iterator_ok and type(iterator) == "function"
	if leds_available then
		for name in iterator do
			if type(name) == "string" and name ~= "." and name ~= ".."
				and #leds < 32 and #name <= 64 and name:match("^[%w_.:%-]+$") then
				local base = "/sys/class/leds/" .. name
				local brightness = read_number(base .. "/brightness")
				local maximum = read_number(base .. "/max_brightness")
				local trigger = hardware.parse_trigger_text(read_file(base .. "/trigger"))
				table.insert(leds, {
					name = name,
					brightness = brightness,
					max_brightness = maximum,
					trigger = trigger.active,
					trigger_available = trigger.available,
					controllable = trigger.available and trigger.active == "none"
						and brightness ~= nil and maximum ~= nil
						and maximum >= 1 and maximum <= 65535
				})
			end
		end
	end
	table.sort(leds, function(left, right) return left.name < right.name end)

	local button_handlers = {}
	local button_iter_ok, button_iter = pcall(fs.dir, "/etc/rc.button")
	local button_hooks_available = button_iter_ok and type(button_iter) == "function"
	if button_hooks_available then
		for name in button_iter do
			if type(name) == "string" and name ~= "." and name ~= ".."
				and #button_handlers < 32 and #name <= 64
				and name:match("^[%w_.%-]+$") then
				table.insert(button_handlers, name)
			end
		end
	end
	table.sort(button_handlers)
	local button_driver_loaded = fs.access("/sys/module/gpio_button_hotplug") == true

	return {
		available = gpio.available or gpio.sysfs.available or input_devices.available or leds_available or button_hooks_available,
		gpio = gpio,
		input_devices = input_devices,
		leds_available = leds_available,
		leds = leds,
		button_driver_loaded = button_driver_loaded,
		button_hooks_available = button_hooks_available,
		button_handlers = button_handlers,
		button_events = button_events,
		board_reference = board_reference,
		sampled_at = os.time()
	}
end

function action_led_update()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local hardware = require "luci.quantumgrid.hardware_io"
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then
			http.status(status, status == 400 and "Bad Request" or
				status == 403 and "Forbidden" or status == 404 and "Not Found" or
				status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
				status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
				"Internal Server Error")
		end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end

	local name = http.formvalue("name", true)
	local base = type(name) == "string" and name:match("^[%w_.:%-]+$") and
		#name > 0 and #name <= 64 and name ~= "." and name ~= ".." and
		("/sys/class/leds/" .. name) or nil
	if not base or fs.access(base) ~= true or fs.access(base .. "/brightness") ~= true then
		respond(404, { ok = false, error = "The requested LED class device was not found." })
		return
	end

	local trigger = hardware.parse_trigger_text(read_file(base .. "/trigger"))
	if not trigger.available then
		respond(503, { ok = false, error = "The LED trigger state is unavailable; no change was made." })
		return
	end
	if trigger.active ~= "none" then
		respond(409, { ok = false, error = "This LED is controlled by a kernel trigger. Select the none trigger in native system settings before changing brightness." })
		return
	end

	local maximum = read_number(base .. "/max_brightness")
	local update, validation_error = hardware.validate_led_update(
		name, http.formvalue("brightness", true), maximum)
	if not update then
		respond(400, { ok = false, error = validation_error })
		return
	end
	local previous = read_number(base .. "/brightness")
	if previous == nil or previous < 0 or previous > update.max_brightness then
		respond(503, { ok = false, error = "The current LED brightness could not be read safely." })
		return
	end

	local current_trigger = hardware.parse_trigger_text(read_file(base .. "/trigger"))
	if not current_trigger.available then
		respond(503, { ok = false, error = "The LED trigger state became unavailable; no change was made." })
		return
	end
	if current_trigger.active ~= "none" then
		respond(409, { ok = false, error = "The LED trigger changed while preparing the update; no change was made." })
		return
	end

	local function write_brightness(value)
		local handle = io.open(base .. "/brightness", "w")
		if not handle then return false end
		local write_ok, written = pcall(handle.write, handle, tostring(value))
		local close_ok, closed = pcall(handle.close, handle)
		return write_ok and written ~= nil and close_ok and closed ~= nil
	end

	if not write_brightness(update.brightness) then
		record_audit(http, "hardware.led.update", update.name, "failed")
		respond(503, { ok = false, error = "The kernel LED brightness attribute rejected the write." })
		return
	end
	local confirmed = read_number(base .. "/brightness")
	if confirmed ~= update.brightness then
		record_audit(http, "hardware.led.update", update.name, "failed")
		local rollback = write_brightness(previous)
		local restored = rollback and read_number(base .. "/brightness") == previous
		respond(502, {
			ok = false,
			error = restored and "The LED did not retain the requested brightness; the previous value was restored."
				or "The LED brightness could not be verified or rolled back. Inspect the physical LED state locally.",
			rolled_back = restored
		})
		return
	end

	record_audit(http, "hardware.led.update", update.name, "success")
	respond(nil, {
		ok = true,
		name = update.name,
		brightness = update.brightness,
		max_brightness = update.max_brightness,
		applied = true,
		persistent = false
	})
end

local function backup_release_identity(contents)
	if type(contents) ~= "string" or #contents < 1 or #contents > 16384 then return nil end
	local target = contents:match("DISTRIB_TARGET=['\"]([^'\"]+)['\"]")
	local architecture = contents:match("DISTRIB_ARCH=['\"]([^'\"]+)['\"]")
	if type(target) ~= "string" or type(architecture) ~= "string" or
		not target:match("^[%w_%.%-/]+$") or not architecture:match("^[%w_%.%-]+$") then
		return nil
	end
	return { target = target, architecture = architecture }
end

local function quantumgrid_backup_context(fs)
	local platform = platform_status(fs)
	local profile = type(platform) == "table" and platform.device_profile or nil
	local identity = type(platform) == "table" and platform.device_identity or nil
	if type(profile) ~= "table" or profile.available ~= true or profile.status ~= "matched" or
		type(profile.profile_id) ~= "string" or type(platform.board_name) ~= "string" or
		type(identity) ~= "table" or identity.available ~= true or
		type(identity.id) ~= "string" then
		return nil, "A matched QuantumGrid hardware profile and stable device identity are required for safe backup and restore."
	end
	local release = backup_release_identity(read_file("/etc/openwrt_release"))
	if not release then
		return nil, "The current OpenWrt target and architecture could not be verified."
	end
	return {
		profile_id = profile.profile_id,
		board_name = platform.board_name,
		device_id = identity.id,
		target = release.target,
		architecture = release.architecture
	}
end

local function inspect_quantumgrid_config_archive(path, context, validator, util, sys)
	if type(path) ~= "string" or type(context) ~= "table" then
		return nil, "The restore archive or current device context is unavailable."
	end
	local archive_file, archive_open_error = io.open(path, "rb")
	if not archive_file then
		return nil, "The configuration archive could not be opened: " .. tostring(archive_open_error or "unknown error")
	end
	local archive_size = archive_file:seek("end")
	local archive_close_ok, archive_close_result = pcall(archive_file.close, archive_file)
	local validated_archive_size, archive_size_error = validator.validate_archive_size(archive_size)
	if not archive_close_ok or not archive_close_result or not validated_archive_size then
		return nil, archive_size_error or "The configuration archive size could not be verified."
	end
	local tar_ok, tar_status = pcall(sys.call, "/bin/tar -tzf " .. path .. " >/dev/null 2>&1")
	if not tar_ok or tar_status ~= 0 then
		return nil, "The configuration archive is not a readable gzip tar archive."
	end
	local listing_ok, listing_text = pcall(util.exec,
		"/bin/tar -tvzf " .. path .. " 2>/dev/null | head -c 4194305")
	if not listing_ok or type(listing_text) ~= "string" then
		return nil, "The configuration archive member list could not be inspected."
	end
	local listing, listing_error = validator.validate_archive_listing(listing_text)
	if not listing then return nil, listing_error end
	local sizes = {}
	for _, item in ipairs(listing.entries) do sizes[item.path] = item.size end
	if not sizes["etc/quantumgrid/device-id"] or sizes["etc/quantumgrid/device-id"] > 33 or
		sizes["etc/quantumgrid/device-id"] < 32 or
		not sizes["etc/quantumgrid/device-profile.json"] or
		sizes["etc/quantumgrid/device-profile.json"] > 32768 or
		sizes["etc/quantumgrid/device-profile.json"] < 2 or
		not sizes["etc/openwrt_release"] or sizes["etc/openwrt_release"] > 16384 or
		sizes["etc/openwrt_release"] < 1 then
		return nil, "The archive's device, profile or OpenWrt target metadata has an unsafe size."
	end
	local function read_member(member)
		local ok, value = pcall(util.exec,
			"/bin/tar -xOzf " .. path .. " " .. member .. " 2>/dev/null")
		if not ok or type(value) ~= "string" then return nil end
		return value
	end
	local archive_id = read_member(listing.device_id_path)
	local identity_ok, identity_error = validator.validate_device_identity(archive_id, context.device_id)
	if not identity_ok then return nil, identity_error end
	local profile_contents = read_member(listing.profile_path)
	if type(profile_contents) ~= "string" or #profile_contents > 32768 then
		return nil, "The archived hardware profile could not be read safely."
	end
	local jsonc = require "luci.jsonc"
	local parse_ok, archived_profile = pcall(jsonc.parse, profile_contents)
	if not parse_ok or type(archived_profile) ~= "table" then
		return nil, "The archived hardware profile is malformed."
	end
	local profile_status = require("luci.quantumgrid.device_profile").inspect(
		archived_profile, context.board_name)
	if type(profile_status) ~= "table" or profile_status.available ~= true or
		profile_status.status ~= "matched" or profile_status.profile_id ~= context.profile_id then
		return nil, "The archived hardware profile does not match this router and firmware build profile."
	end
	local archive_release_text = read_member(listing.release_path)
	local archive_release = backup_release_identity(archive_release_text)
	if not archive_release then return nil, "The archived OpenWrt target metadata is malformed." end
	local compatible, compatibility_error = validator.validate_platform_compatibility(
		archive_release.target, context.target, archive_release.architecture, context.architecture)
	if not compatible then return nil, compatibility_error end
	return listing
end

local function ensure_sysupgrade_backup_paths()
	local required = {
		"/etc/quantumgrid/audit.jsonl",
		"/etc/quantumgrid/audit.jsonl.1",
		"/etc/quantumgrid/device-id",
		"/etc/quantumgrid/device-profile.json",
		"/etc/openwrt_release"
	}
	local present = {}
	local current = io.open("/etc/sysupgrade.conf", "r")
	if current then
		for line in current:lines() do
			present[line:gsub("\r$", "")] = true
		end
		local close_ok, close_result = pcall(current.close, current)
		if not close_ok or not close_result then return nil, "The existing sysupgrade backup list could not be closed safely." end
	end
	local missing = {}
	for _, path in ipairs(required) do
		if not present[path] then missing[#missing + 1] = path end
	end
	if #missing > 0 then
		local append, append_error = io.open("/etc/sysupgrade.conf", "a")
		if not append then return nil, "The native sysupgrade backup list could not be updated: " .. tostring(append_error or "unknown error") end
		local write_ok, write_error = pcall(function()
			if not append:write("\n") then error("append failed") end
			for _, path in ipairs(missing) do
				if not append:write(path, "\n") then error("append failed") end
			end
			if not append:flush() then error("flush failed") end
		end)
		local close_ok, close_result = pcall(append.close, append)
		if not write_ok or not close_ok or not close_result then
			return nil, "The required device/profile metadata could not be added to the native sysupgrade backup list."
		end
	end
	return true
end

local CONFIG_ARCHIVE_LOCK_PATH = "/tmp/quantumgrid-config-archive.lock"

local function acquire_config_archive_lock(sys)
	local ok, status = pcall(sys.call,
		"/bin/mkdir " .. CONFIG_ARCHIVE_LOCK_PATH .. " >/dev/null 2>&1")
	if not ok or status ~= 0 then return nil end
	local released = false
	return function()
		if released then return true end
		local release_ok, release_status = pcall(sys.call,
			"/bin/rmdir " .. CONFIG_ARCHIVE_LOCK_PATH .. " >/dev/null 2>&1")
		if release_ok and release_status == 0 then
			released = true
			return true
		end
		return nil
	end
end

function action_config_backup()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local validator = require "luci.quantumgrid.config_backup"
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then
			http.status(status, status == 400 and "Bad Request" or
				status == 403 and "Forbidden" or status == 405 and "Method Not Allowed" or
				status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
				"Internal Server Error")
		end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	local confirmed, confirmation_error = validator.validate_confirmation(
		http.formvalue("confirmed", true))
	if not confirmed then
		respond(400, { ok = false, error = confirmation_error })
		return
	end
	if fs.access("/sbin/sysupgrade") ~= true then
		respond(503, { ok = false, error = "The native sysupgrade backup utility is unavailable." })
		return
	end
	local context, context_error = quantumgrid_backup_context(fs)
	if not context then
		respond(503, { ok = false, error = context_error })
		return
	end
	if fs.access("/bin/mkdir") ~= true or fs.access("/bin/rmdir") ~= true then
		respond(503, { ok = false, error = "Atomic configuration archive locking utilities are unavailable." })
		return
	end
	local release_archive_lock = acquire_config_archive_lock(sys)
	if not release_archive_lock then
		respond(409, { ok = false, error = "A configuration backup or restore is already active. Retry after it finishes." })
		return
	end

	local backup_paths_ok, backup_paths_error = ensure_sysupgrade_backup_paths()
	if not backup_paths_ok then
		release_archive_lock()
		respond(503, { ok = false, error = backup_paths_error })
		return
	end

	local util = require "luci.util"
	local mktemp_command = nil
	if fs.access("/bin/mktemp") == true then
		mktemp_command = "/bin/mktemp"
	elseif fs.access("/usr/bin/mktemp") == true then
		mktemp_command = "/usr/bin/mktemp"
	end
	if not mktemp_command then
		release_archive_lock()
		respond(503, { ok = false, error = "A secure mktemp utility is unavailable; no backup was created." })
		return
	end
	local temp_ok, temp_output = pcall(util.exec,
		mktemp_command .. " /tmp/quantumgrid-config-backup.XXXXXX")
	local generated_path = type(temp_output) == "string"
		and temp_output:match("^([%w_./%-]+)") or nil
	if generated_path then generated_path = generated_path:gsub("%s+$", "") end
	if not temp_ok then generated_path = nil end
	local backup_path, path_error = validator.validate_temp_path(generated_path)
	if not backup_path or fs.access(backup_path) ~= true then
		release_archive_lock()
		respond(500, { ok = false, error = path_error or "The secure temporary backup file was not created." })
		return
	end

	local command_ok, command_status = pcall(sys.call,
		"/sbin/sysupgrade -b " .. backup_path .. " >/dev/null 2>&1")
	if not command_ok or command_status ~= 0 then
		record_audit(http, "system.config.backup", "sysupgrade", "failed")
		local removed = os.remove(backup_path)
		local lock_released = release_archive_lock()
		respond(503, { ok = false, error = removed and lock_released and
			"The router could not create a configuration backup archive." or
			"The backup failed and its temporary file or shared lock could not be cleaned up. Clear the archive lock only after verifying no backup or restore is active." })
		return
	end
	local archive_listing, archive_error = inspect_quantumgrid_config_archive(
		backup_path, context, validator, util, sys)
	if not archive_listing then
		record_audit(http, "system.config.backup", "sysupgrade", "failed")
		local removed = os.remove(backup_path)
		local lock_released = release_archive_lock()
		respond(503, { ok = false, error = "The native backup did not contain a complete, compatible recovery manifest: " .. tostring(archive_error) ..
			(removed and lock_released and "" or " Temporary archive or lock cleanup also needs operator attention.") })
		return
	end

	local archive, open_error = io.open(backup_path, "rb")
	if not archive then
		local removed = os.remove(backup_path)
		local lock_released = release_archive_lock()
		respond(500, { ok = false, error = "The configuration backup was created but could not be read: " .. tostring(open_error or "unknown error") ..
			(removed and lock_released and "" or " Temporary archive or lock cleanup needs operator attention.") })
		return
	end
	local size = archive:seek("end")
	local validated_size, size_error = validator.validate_archive_size(size)
	if not validated_size then
		pcall(archive.close, archive)
		local removed = os.remove(backup_path)
		local lock_released = release_archive_lock()
		respond(503, { ok = false, error = tostring(size_error) ..
			(removed and lock_released and "" or " Temporary archive or lock cleanup needs operator attention.") })
		return
	end
	local seek_ok = archive:seek("set", 0)
	if seek_ok ~= 0 then
		pcall(archive.close, archive)
		local removed = os.remove(backup_path)
		local lock_released = release_archive_lock()
		respond(500, { ok = false, error = removed and lock_released and
			"The configuration backup archive could not be rewound for download." or
			"The archive could not be rewound and temporary cleanup needs operator attention." })
		return
	end
	local read_ok, contents = pcall(archive.read, archive, "*a")
	local close_ok, close_result = pcall(archive.close, archive)
	local remove_ok, remove_result = os.remove(backup_path)
	local lock_released = release_archive_lock()
	if not read_ok or not close_ok or not close_result or not remove_ok or not remove_result then
		respond(500, { ok = false, error = "The configuration backup could not be read, closed, deleted and unlocked cleanly. Inspect the archive lock and temporary files before retrying." })
		return
	end
	if type(contents) ~= "string" or #contents ~= validated_size then
		respond(500, { ok = false, error = "The configuration backup archive could not be read completely." })
		return
	end

	record_audit(http, "system.config.backup", "sysupgrade", "success")
	local filename = "quantumgrid-config-backup-" .. tostring(os.date("!%Y%m%dT%H%M%SZ")) .. ".tar.gz"
	http.header("Cache-Control", "no-store")
	http.header("X-Content-Type-Options", "nosniff")
	http.header("Content-Disposition", 'attachment; filename="' .. filename .. '"')
	http.header("Content-Length", tostring(validated_size))
	http.prepare_content("application/gzip")
	http.write(contents)
end



function action_config_restore()
    local http = require "luci.http"
    local fs = require "nixio.fs"
    local sys = require "luci.sys"
    local util = require "luci.util"
    local validator = require "luci.quantumgrid.config_backup"
    local host = http.getenv("HTTP_HOST")
    local origin = http.getenv("HTTP_ORIGIN")
    local scheme = http.getenv("HTTPS") == "on" and "https" or "http"
    local MAX_UPLOAD_BYTES = 64 * 1024 * 1024
    local upload_state = { file = nil, metadata = nil, count = 0, bytes = 0, closed = false, error = nil }
    local restore_path = nil
    local rollback_path = nil
    local restore_lock_acquired = false
    local restore_lock_path = CONFIG_ARCHIVE_LOCK_PATH
    local restore_authorized = false
    local restore_audit_attempted = false
    local restore_audit_target = "preflight"

    local function respond(status, payload)
        if status then
            http.status(status, status == 400 and "Bad Request" or
                status == 403 and "Forbidden" or status == 405 and "Method Not Allowed" or
                status == 409 and "Conflict" or status == 413 and "Payload Too Large" or
                status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
                "Internal Server Error")
        end
        http.header("Cache-Control", "no-store")
        http.prepare_content("application/json; charset=UTF-8")
        http.write_json(payload)
    end

    local function cleanup(preserve_rollback)
        if upload_state.file and not upload_state.closed then
            pcall(upload_state.file.close, upload_state.file)
            upload_state.closed = true
        end
        if restore_path then os.remove(restore_path) end
        if rollback_path and not preserve_rollback then os.remove(rollback_path) end
        if restore_lock_acquired then
            pcall(sys.call, "/bin/rmdir " .. restore_lock_path .. " >/dev/null 2>&1")
            restore_lock_acquired = false
        end
    end

    local function audit_restore(outcome)
        if not restore_authorized or restore_audit_attempted then return false end
        restore_audit_attempted = true
        return record_audit(http, "system.config.restore", restore_audit_target, outcome)
    end

    local function fail(status, message, extra, preserve_rollback)
        audit_restore("failed")
        cleanup(preserve_rollback)
        local payload = { ok = false, error = message }
        if type(extra) == "table" then
            for key, value in pairs(extra) do payload[key] = value end
        end
        respond(status, payload)
    end

    if http.getenv("REQUEST_METHOD") ~= "POST" then
        respond(405, { ok = false, error = "POST is required." })
        return
    end
    if not require_https(http) then return end
    if not host or origin ~= scheme .. "://" .. host then
        respond(403, { ok = false, error = "A same-origin request is required." })
        return
    end
    restore_authorized = true
    local content_type = http.getenv("CONTENT_TYPE") or ""
    local normalized_content_type = content_type:lower():match("^%s*([^;%s]+)")
    if normalized_content_type ~= "application/gzip" and normalized_content_type ~= "application/octet-stream" then
        fail(400, "The decrypted configuration archive must be streamed as application/gzip.")
        return
    end
    local content_length = http.getenv("CONTENT_LENGTH")
    if content_length and content_length ~= "" then
        if not content_length:match("^%d+$") or tonumber(content_length) > MAX_UPLOAD_BYTES + 1024 * 1024 then
            fail(413, "The configuration archive upload exceeds the 64 MiB restore limit.")
            return
        end
    end
    if fs.access("/sbin/sysupgrade") ~= true or fs.access("/bin/tar") ~= true or
        fs.access("/sbin/reboot") ~= true or fs.access("/bin/sleep") ~= true or
        fs.access("/bin/mkdir") ~= true or fs.access("/bin/rmdir") ~= true then
        fail(503, "Native sysupgrade, tar or reboot utilities are unavailable; no configuration was changed.")
        return
    end

    local context, context_error = quantumgrid_backup_context(fs)
    if not context then
        fail(503, context_error)
        return
    end
    restore_audit_target = context.profile_id
    local lock_ok, lock_status = pcall(sys.call,
        "/bin/mkdir " .. restore_lock_path .. " >/dev/null 2>&1")
    if not lock_ok or lock_status ~= 0 then
        fail(409, "Another configuration backup or restore is already active, or the archive lock could not be acquired. No archive was applied.")
        return
    end
    restore_lock_acquired = true

    local backup_paths_ok, backup_paths_error = ensure_sysupgrade_backup_paths()
    if not backup_paths_ok then
        fail(503, backup_paths_error)
        return
    end

    local mktemp_command = nil
    if fs.access("/bin/mktemp") == true then
        mktemp_command = "/bin/mktemp"
    elseif fs.access("/usr/bin/mktemp") == true then
        mktemp_command = "/usr/bin/mktemp"
    end
    if not mktemp_command then
        fail(503, "A secure mktemp utility is unavailable; no restore was started.")
        return
    end

    local function create_temp(template, validate_path)
        local ok, output = pcall(util.exec, mktemp_command .. " " .. template)
        local raw = type(output) == "string" and output:match("^([%w_./%-]+)") or nil
        if raw then raw = raw:gsub("%s+$", "") end
        if not ok then raw = nil end
        local checked, path_error = validate_path(raw)
        if not checked or fs.access(checked) ~= true then
            return nil, path_error or "A secure temporary restore file could not be created."
        end
        return checked
    end

    local temp_path, temp_error = create_temp(
        "/tmp/quantumgrid-config-restore.XXXXXX", validator.validate_restore_temp_path)
    if not temp_path then
        fail(503, temp_error)
        return
    end
    restore_path = temp_path
    local upload, upload_open_error = io.open(restore_path, "wb")
    if not upload then
        fail(503, "The secure restore upload file could not be opened: " .. tostring(upload_open_error or "unknown error"))
        return
    end
    upload_state.file = upload

    local handler_ok = pcall(http.setfilehandler, function(field, chunk, eof)
        if type(field) ~= "table" or field.name ~= "raw" or
            (field.encoding ~= "application/gzip" and field.encoding ~= "application/octet-stream") then
            upload_state.error = "Only one raw gzip archive request body is accepted."
        elseif not upload_state.metadata then
            upload_state.metadata = field
            upload_state.count = 1
        elseif upload_state.metadata ~= field then
            upload_state.error = "Multiple archive upload streams are not accepted."
        end

        if type(chunk) == "string" and #chunk > 0 then
            upload_state.bytes = upload_state.bytes + #chunk
            if upload_state.bytes > MAX_UPLOAD_BYTES then
                upload_state.error = "The configuration archive upload exceeds the 64 MiB restore limit."
            elseif not upload_state.error and upload_state.file then
                local write_ok, write_result = pcall(upload_state.file.write, upload_state.file, chunk)
                if not write_ok or not write_result then
                    upload_state.error = "The uploaded configuration archive could not be written to secure temporary storage."
                end
            end
        end

        if eof and upload_state.file and not upload_state.closed then
            local close_ok, close_result = pcall(upload_state.file.close, upload_state.file)
            upload_state.closed = close_ok and close_result ~= nil
            if not upload_state.closed then
                upload_state.error = "The uploaded configuration archive could not be closed safely."
            end
            upload_state.file = nil
        end
    end)
    if not handler_ok then
        fail(503, "The router HTTP layer cannot safely stream the configuration archive upload.")
        return
    end

    local parse_ok = pcall(http.formvalue, "__quantumgrid_stream_body")
    if not parse_ok then
        fail(400, "The raw configuration archive request body could not be parsed.")
        return
    end
    local confirmed = http.getenv("HTTP_X_QUANTUMGRID_RESTORE_CONFIRMED")
    local same_device_confirmed = http.getenv("HTTP_X_QUANTUMGRID_SAME_DEVICE")
    local restore_confirmed, confirmation_error =
        validator.validate_restore_confirmation(confirmed, same_device_confirmed)
    if not restore_confirmed then
        fail(400, confirmation_error)
        return
    end
    if upload_state.error then
        fail(400, upload_state.error)
        return
    end
    if not upload_state.metadata or upload_state.count ~= 1 or not upload_state.closed or
        upload_state.bytes < 1 or fs.access(restore_path) ~= true then
        fail(400, "Exactly one complete configuration archive file must be uploaded.")
        return
    end
    local upload_size, size_error = validator.validate_archive_size(upload_state.bytes)
    if not upload_size then
        fail(413, size_error)
        return
    end

    local statvfs_ok, temp_stats = false, nil
    if type(fs.statvfs) == "function" then
        statvfs_ok, temp_stats = pcall(fs.statvfs, "/tmp")
    end
    local available_temp_bytes = statvfs_ok and type(temp_stats) == "table" and
        tonumber(temp_stats.bavail) and tonumber(temp_stats.frsize) and
        tonumber(temp_stats.bavail) * tonumber(temp_stats.frsize) or nil
    local capacity_ok, capacity_error = validator.validate_restore_temp_capacity(
        available_temp_bytes, upload_size)
    if not capacity_ok then
        fail(503, capacity_error)
        return
    end

    local uploaded_listing, uploaded_error = inspect_quantumgrid_config_archive(
        restore_path, context, validator, util, sys)
    if not uploaded_listing then
        fail(400, uploaded_error)
        return
    end

    local rollback_temp, rollback_temp_error = create_temp(
        "/tmp/quantumgrid-config-rollback.XXXXXX", validator.validate_rollback_temp_path)
    if not rollback_temp then
        fail(503, rollback_temp_error)
        return
    end
    rollback_path = rollback_temp
    local rollback_create_ok, rollback_create_status = pcall(sys.call,
        "/sbin/sysupgrade -b " .. rollback_path .. " >/dev/null 2>&1")
    if not rollback_create_ok or rollback_create_status ~= 0 then
        fail(503, "The router could not create a rollback snapshot. The requested backup was not applied.")
        return
    end
    local rollback_listing, rollback_error = inspect_quantumgrid_config_archive(
        rollback_path, context, validator, util, sys)
    if not rollback_listing then
        fail(503, "The rollback snapshot could not be validated: " .. tostring(rollback_error))
        return
    end

    local restore_ok, restore_status = pcall(sys.call,
        "/sbin/sysupgrade -r " .. restore_path .. " >/dev/null 2>&1")
    if not restore_ok or restore_status ~= 0 then
        local rollback_ok, rollback_status = pcall(sys.call,
            "/sbin/sysupgrade -r " .. rollback_path .. " >/dev/null 2>&1")
        local rolled_back = rollback_ok and rollback_status == 0
        audit_restore("failed")
        if rolled_back then
            cleanup()
            local reboot_ok, reboot_status = pcall(sys.call,
                "( /bin/sleep 3; /sbin/reboot ) >/dev/null 2>&1 </dev/null &")
            local reboot_scheduled = reboot_ok and reboot_status == 0
            respond(502, {
                ok = false,
                error = reboot_scheduled and
                    "The requested archive could not be applied. The pre-restore configuration was restored and a reboot was scheduled."
                    or "The requested archive could not be applied. The pre-restore configuration was restored, but a reboot must be started locally.",
                rolled_back = true,
                reboot_scheduled = reboot_scheduled
            })
            return
        end
        fail(502,
            "The restore failed and the pre-restore configuration could not be restored. Keep the router powered and use an out-of-band recovery path. The validated rollback archive has been preserved at " .. tostring(rollback_path) .. ".",
            { rolled_back = false, reboot_scheduled = false, rollback_archive = rollback_path }, true)
        return
    end

    audit_restore("success")
    local reboot_ok, reboot_status = pcall(sys.call,
        "( /bin/sleep 3; /sbin/reboot ) >/dev/null 2>&1 </dev/null &")
    local reboot_scheduled = reboot_ok and reboot_status == 0
    if not reboot_scheduled then
        cleanup(true)
        respond(502, {
            ok = false,
            error = "The configuration was restored, but the router could not schedule its reboot. Reboot it from an out-of-band management path. The validated rollback archive has been preserved at " .. tostring(rollback_path) .. ".",
            restored = true,
            reboot_scheduled = false,
            rollback_archive = rollback_path,
            profile_id = context.profile_id
        })
        return
    end
    cleanup()
    respond(nil, {
        ok = true,
        restored = true,
        reboot_scheduled = true,
        profile_id = context.profile_id,
        target = context.target
    })
end


local function bridge_vlan_management_context(remote_ip, target_bridge)
	if type(target_bridge) ~= "string" or not target_bridge:match("^[%w_.%-]+$") then
		return nil, "The target bridge identifier is invalid."
	end
	if type(remote_ip) ~= "string" then
		return nil, "The router cannot identify the current administrator's IPv4 management path."
	end
	local a, b, c, d = remote_ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	if not a then
		return nil, "Manage bridge VLANs over an IPv4 administrator session so the management path can be protected."
	end
	for _, value in ipairs({ a, b, c, d }) do
		local octet = tonumber(value)
		if not octet or octet < 0 or octet > 255 or tostring(octet) ~= value then
			return nil, "The current administrator IPv4 address is invalid; no VLAN change was made."
		end
	end
	local util = require "luci.util"
	local ok, output = pcall(util.exec, "/sbin/ip -4 route get " .. remote_ip .. " 2>/dev/null")
	if not ok or type(output) ~= "string" then
		return nil, "The current administrator route could not be inspected. No VLAN change was made."
	end
	local route_device = output:match("%sdev%s+([%w_.%-]+)")
	if not route_device then
		return nil, "The current administrator route has no validated output device. No VLAN change was made."
	end
	local base_bridge, vlan_id = route_device:match("^([%w_.%-]+)%.(%d+)$")
	if base_bridge == target_bridge then
		local numeric = tonumber(vlan_id)
		if numeric and numeric >= 1 and numeric <= 4094 then
			return { bridge = target_bridge, vlan_id = numeric, native_bridge = false }
		end
	end
	if route_device == target_bridge then
		return { bridge = target_bridge, native_bridge = true }
	end
	return { bridge = target_bridge, native_bridge = false }
end

local function bridge_vlan_untagged_map(ports)
	local result = {}
	for _, raw in ipairs(type(ports) == "table" and ports or {}) do
		if type(raw) == "string" then
			local name = raw:match("^([%w_.%-]+):u%*?$")
			if name then result[name] = raw end
		end
	end
	return result
end

local function native_bridge_untagged_path_preserved(previous_ports, next_ports)
	local previous = bridge_vlan_untagged_map(previous_ports)
	local next_values = bridge_vlan_untagged_map(next_ports)
	for name, raw in pairs(previous) do
		if next_values[name] ~= raw then return false end
	end
	for name, raw in pairs(next_values) do
		if previous[name] ~= raw then return false end
	end
	return true
end

local function restore_bridge_vlan_section(uci, section, snapshot)
	if type(snapshot) ~= "table" or type(section) ~= "string"
		or type(snapshot.device) ~= "string" or type(snapshot.vlan) ~= "string" then
		return false
	end
	local type_ok, current_type = pcall(uci.get, uci, "network", section, ".type")
	if not type_ok then return false end
	local restore_ok, restored
	if current_type == "bridge-vlan" then
		local device_ok, device_set = pcall(uci.set, uci, "network", section, "device", snapshot.device)
		local vlan_ok, vlan_set = pcall(uci.set, uci, "network", section, "vlan", snapshot.vlan)
		restore_ok = device_ok and device_set == true and vlan_ok and vlan_set == true
		restored = restore_ok
	elseif current_type == nil then
		restore_ok, restored = pcall(uci.section, uci, "network", "bridge-vlan", section, {
			device = snapshot.device,
			vlan = snapshot.vlan
		})
		restore_ok = restore_ok and restored ~= nil and restored ~= false
	else
		return false
	end
	if not restore_ok or not restored then return false end
	local ports_ok, ports_result
	if type(snapshot.ports) == "table" then
		ports_ok, ports_result = pcall(uci.set_list, uci, "network", section, "ports", snapshot.ports)
	elseif snapshot.ports == false then
		local current_ports = uci:get("network", section, "ports")
		if current_ports == nil then
			ports_ok, ports_result = true, true
		else
			ports_ok, ports_result = pcall(uci.delete, uci, "network", section, "ports")
		end
	else
		return false
	end
	if not ports_ok or ports_result ~= true then return false end
	local commit_ok, committed = pcall(uci.commit, uci, "network")
	return commit_ok and committed == true
end

function action_bridge_vlan_update()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local validator = require "luci.quantumgrid.office_networks"
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then
			http.status(status, status == 400 and "Bad Request" or
				status == 403 and "Forbidden" or status == 404 and "Not Found" or
				status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
				status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
				"Internal Server Error")
		end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	if http.formvalue("confirmed", true) ~= "1" then
		respond(400, { ok = false, error = "Explicit confirmation is required before changing bridge VLAN membership." })
		return
	end
	if fs.access("/etc/config/network") ~= true or fs.access("/etc/init.d/network") ~= true then
		respond(503, { ok = false, error = "Network configuration or the native network reload service is unavailable." })
		return
	end

	local device = http.formvalue("device", true)
	local vlan_id = http.formvalue("vlan", true)
	local requested_section = http.formvalue("section", true) or ""
	if requested_section ~= "" and (not requested_section:match("^[A-Za-z0-9_.%-]+$")
		or requested_section == "." or requested_section == ".." or #requested_section > 64) then
		respond(400, { ok = false, error = "The selected bridge VLAN section identifier is invalid." })
		return
	end

	local bridge = nil
	local bridge_ok = pcall(function()
		uci:foreach("network", "device", function(section)
			if section.type == "bridge" and section.name == device then bridge = section end
		end)
	end)
	if not bridge_ok then
		respond(500, { ok = false, error = "Bridge device configuration could not be inspected safely." })
		return
	end
	if type(bridge) ~= "table" or bridge.vlan_filtering ~= "1" then
		respond(409, { ok = false, error = "Only an existing bridge with VLAN filtering enabled can be managed here. Enable and verify filtering through native LuCI first." })
		return
	end

	local existing = {}
	local existing_ok = pcall(function()
		uci:foreach("network", "bridge-vlan", function(section)
			table.insert(existing, {
				section = tostring(section[".name"] or ""),
				device = tostring(section.device or ""),
				vlan = tostring(section.vlan or ""),
				ports = section.ports
			})
		end)
	end)
	if not existing_ok then
		respond(500, { ok = false, error = "Existing VLAN membership could not be inspected safely." })
		return
	end
	local inventory = office_network_status(uci, fs)
	if inventory.truncated then
		respond(409, { ok = false, error = "The network inventory is truncated. Reduce the inventory before changing VLAN membership so duplicate VLAN IDs and PVID assignments can be checked completely." })
		return
	end

	local snapshot = nil
	if requested_section ~= "" then
		local snapshot_ok, current = pcall(uci.get_all, uci, "network", requested_section)
		if not snapshot_ok or type(current) ~= "table" or current[".type"] ~= "bridge-vlan" then
			respond(404, { ok = false, error = "The selected bridge VLAN no longer exists." })
			return
		end
		if current.device ~= device then
			respond(409, { ok = false, error = "A bridge VLAN can only be edited on its existing bridge. Remove and recreate it to move it to another bridge." })
			return
		end
		snapshot = {
			device = current.device or false,
			vlan = current.vlan or false,
			ports = type(current.ports) == "table" and current.ports or false
		}
	end

	local update, validation_error = validator.validate_bridge_vlan(
		device, vlan_id, http.formvalue("ports", true), bridge.ports, existing,
		requested_section ~= "" and requested_section or nil)
	if not update then
		respond(400, { ok = false, error = validation_error })
		return
	end
	local management, management_error = bridge_vlan_management_context(
		http.getenv("REMOTE_ADDR"), update.device)
	if not management then
		respond(409, { ok = false, error = management_error })
		return
	end
	if management.vlan_id and management.vlan_id == update.vlan_id then
		respond(409, { ok = false, error = "This is the VLAN carrying the current administrator session. It cannot be edited from that session." })
		return
	end
	if management.native_bridge then
		local previous_ports = snapshot and snapshot.ports or {}
		if not native_bridge_untagged_path_preserved(previous_ports, update.ports) then
			respond(409, { ok = false, error = "This administrator session is using the bridge's native untagged path. The operation must preserve every existing untagged port membership exactly; add tagged membership or use an out-of-band management path." })
			return
		end
	end

	local section = requested_section
	if section == "" then
		local create_ok, created = pcall(uci.section, uci, "network", "bridge-vlan", nil, {
			device = update.device,
			vlan = tostring(update.vlan_id)
		})
		if not create_ok or type(created) ~= "string" or created == "" then
			pcall(uci.revert, uci, "network")
			respond(500, { ok = false, error = "The new bridge VLAN section could not be staged in UCI." })
			return
		end
		section = created
	else
		local device_ok, device_set = pcall(uci.set, uci, "network", section, "device", update.device)
		local vlan_ok, vlan_set = pcall(uci.set, uci, "network", section, "vlan", tostring(update.vlan_id))
		if not device_ok or device_set ~= true or not vlan_ok or vlan_set ~= true then
			pcall(uci.revert, uci, "network")
			respond(500, { ok = false, error = "The bridge VLAN change could not be staged safely." })
			return
		end
	end

	local ports_ok, ports_set = pcall(uci.set_list, uci, "network", section, "ports", update.ports)
	if not ports_ok or ports_set ~= true then
		pcall(uci.revert, uci, "network")
		respond(500, { ok = false, error = "The bridge VLAN port membership could not be staged safely." })
		return
	end
	local commit_ok, committed = pcall(uci.commit, uci, "network")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "network")
		respond(500, { ok = false, error = "The bridge VLAN configuration could not be committed; network reload was not attempted." })
		return
	end

	local reload_ok, reload_status = pcall(sys.call, "/etc/init.d/network reload >/dev/null 2>&1")
	if not reload_ok or reload_status ~= 0 then
		local rollback_ok, rolled_back = false, false
		if snapshot then
			rollback_ok, rolled_back = pcall(restore_bridge_vlan_section, uci, section, snapshot)
		else
			local delete_ok, deleted = pcall(uci.delete, uci, "network", section)
			local rollback_commit_ok, rollback_committed = false, false
			if delete_ok and deleted == true then
				rollback_commit_ok, rollback_committed = pcall(uci.commit, uci, "network")
			end
			rollback_ok = rollback_commit_ok and rollback_committed == true
			rolled_back = rollback_ok
		end
		local rollback_reload_ok, rollback_reload_status = false, -1
		if rollback_ok and rolled_back then
			rollback_reload_ok, rollback_reload_status = pcall(sys.call, "/etc/init.d/network reload >/dev/null 2>&1")
		end
		local recovered = rollback_ok and rolled_back and rollback_reload_ok and rollback_reload_status == 0
		record_audit(http, "office.vlan.update", section, "failed")
		respond(502, {
			ok = false,
			error = recovered
				and "The network reload failed. The previous bridge VLAN configuration was restored."
				or "The network reload failed and bridge VLAN rollback could not be confirmed. Inspect network configuration and management connectivity locally.",
			rolled_back = recovered
		})
		return
	end

	record_audit(http, "office.vlan.update", section, "success")
	respond(nil, {
		ok = true,
		section = section,
		device = update.device,
		vlan_id = update.vlan_id,
		ports = update.ports,
		reloaded = true,
		rolled_back = false
	})
end

function action_bridge_vlan_remove()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then
			http.status(status, status == 400 and "Bad Request" or
				status == 403 and "Forbidden" or status == 404 and "Not Found" or
				status == 405 and "Method Not Allowed" or status == 502 and "Bad Gateway" or
				status == 503 and "Service Unavailable" or "Internal Server Error")
		end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	if http.formvalue("confirmed", true) ~= "1" then
		respond(400, { ok = false, error = "Explicit confirmation is required before removing a bridge VLAN." })
		return
	end
	if fs.access("/etc/config/network") ~= true or fs.access("/etc/init.d/network") ~= true then
		respond(503, { ok = false, error = "Network configuration or the native network reload service is unavailable." })
		return
	end

	local section = http.formvalue("section", true)
	if type(section) ~= "string" or #section > 64
		or not section:match("^[A-Za-z0-9_.%-]+$") or section == "." or section == ".." then
		respond(400, { ok = false, error = "The bridge VLAN section identifier is invalid." })
		return
	end
	local snapshot_ok, current = pcall(uci.get_all, uci, "network", section)
	if not snapshot_ok or type(current) ~= "table" or current[".type"] ~= "bridge-vlan" then
		respond(404, { ok = false, error = "The selected bridge VLAN no longer exists." })
		return
	end
	local inventory = office_network_status(uci, fs)
	if inventory.truncated then
		respond(409, { ok = false, error = "The network inventory is truncated. Resolve the inventory before removing VLAN membership." })
		return
	end
	local previous = {
		device = current.device,
		vlan = current.vlan,
		ports = type(current.ports) == "table" and current.ports or false
	}
	local management, management_error = bridge_vlan_management_context(
		http.getenv("REMOTE_ADDR"), previous.device)
	if not management then
		respond(409, { ok = false, error = management_error })
		return
	end
	if management.vlan_id and tonumber(previous.vlan) == management.vlan_id then
		respond(409, { ok = false, error = "This is the VLAN carrying the current administrator session. It cannot be removed from that session." })
		return
	end
	if management.native_bridge and next(bridge_vlan_untagged_map(previous.ports)) ~= nil then
		respond(409, { ok = false, error = "This VLAN contains untagged members on the bridge's native administrator path. Remove it only through an out-of-band management path." })
		return
	end
	if type(previous.device) ~= "string" or previous.device == ""
		or type(previous.vlan) ~= "string" or previous.vlan == "" then
		respond(409, { ok = false, error = "The current bridge VLAN is incomplete and cannot be removed safely." })
		return
	end
	local bridge_found = false
	local bridge_ok = pcall(function()
		uci:foreach("network", "device", function(section_config)
			if section_config.type == "bridge" and section_config.name == previous.device
				and section_config.vlan_filtering == "1" then bridge_found = true end
		end)
	end)
	if not bridge_ok or not bridge_found then
		respond(409, { ok = false, error = "The original VLAN-filtering bridge could not be confirmed; no change was made." })
		return
	end

	local delete_ok, deleted = pcall(uci.delete, uci, "network", section)
	if not delete_ok or deleted ~= true then
		pcall(uci.revert, uci, "network")
		respond(500, { ok = false, error = "The bridge VLAN could not be staged for removal." })
		return
	end
	local commit_ok, committed = pcall(uci.commit, uci, "network")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "network")
		respond(500, { ok = false, error = "The bridge VLAN removal could not be committed; network reload was not attempted." })
		return
	end

	local reload_ok, reload_status = pcall(sys.call, "/etc/init.d/network reload >/dev/null 2>&1")
	if not reload_ok or reload_status ~= 0 then
		local restore_ok, restored = pcall(restore_bridge_vlan_section, uci, section, previous)
		local rollback_reload_ok, rollback_reload_status = false, -1
		if restore_ok and restored then
			rollback_reload_ok, rollback_reload_status = pcall(sys.call, "/etc/init.d/network reload >/dev/null 2>&1")
		end
		local recovered = restore_ok and restored and rollback_reload_ok and rollback_reload_status == 0
		record_audit(http, "office.vlan.remove", section, "failed")
		respond(502, {
			ok = false,
			error = recovered
				and "The network reload failed. The bridge VLAN section was restored."
				or "The network reload failed and the bridge VLAN could not be fully restored. Inspect network configuration and management connectivity locally.",
			rolled_back = recovered
		})
		return
	end

	record_audit(http, "office.vlan.remove", section, "success")
	respond(nil, {
		ok = true,
		section = section,
		device = previous.device,
		vlan_id = tonumber(previous.vlan),
		removed = true,
		reloaded = true,
		rolled_back = false
	})
end

local function restore_office_forwarding_section(uci, section, snapshot)
	if type(section) ~= "string" or type(snapshot) ~= "table" then return false end
	local section_ok, restored = pcall(uci.section, uci, "firewall", "forwarding", section, snapshot)
	if not section_ok or not restored then return false end
	local commit_ok, committed = pcall(uci.commit, uci, "firewall")
	return commit_ok and committed == true
end

function action_office_forwarding_add()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local validator = require "luci.quantumgrid.office_networks"
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then
			http.status(status, status == 400 and "Bad Request" or
				status == 403 and "Forbidden" or status == 404 and "Not Found" or
				status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
				status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
				"Internal Server Error")
		end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	if http.formvalue("confirmed", true) ~= "1" then
		respond(400, { ok = false, error = "Explicit confirmation is required before adding firewall forwarding." })
		return
	end
	if fs.access("/etc/config/firewall") ~= true or fs.access("/etc/init.d/firewall") ~= true then
		respond(503, { ok = false, error = "Firewall configuration or the native firewall reload service is unavailable." })
		return
	end

	local inventory = office_network_status(uci, fs)
	if not inventory.firewall_available or inventory.truncated then
		respond(409, { ok = false, error = "The firewall inventory is unavailable or truncated. Resolve it before changing inter-zone forwarding." })
		return
	end
	local zones = {}
	for _, zone in ipairs(inventory.zones or {}) do
		table.insert(zones, { name = zone.name, networks = zone.networks })
	end
	local update, validation_error = validator.validate_office_forwarding(
		http.formvalue("source", true),
		http.formvalue("destination", true),
		zones,
		inventory.forwardings)
	if not update then
		respond(400, { ok = false, error = validation_error })
		return
	end

	local section_ok, section = pcall(uci.section, uci, "firewall", "forwarding", nil, {
		src = update.source,
		dest = update.destination
	})
	if not section_ok or type(section) ~= "string" or section == "" then
		pcall(uci.revert, uci, "firewall")
		respond(500, { ok = false, error = "The firewall forwarding could not be staged in UCI." })
		return
	end
	local commit_ok, committed = pcall(uci.commit, uci, "firewall")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "firewall")
		respond(500, { ok = false, error = "The firewall forwarding could not be committed; firewall reload was not attempted." })
		return
	end

	local reload_ok, reload_status = pcall(sys.call, "/etc/init.d/firewall reload >/dev/null 2>&1")
	if not reload_ok or reload_status ~= 0 then
		local delete_ok, deleted = pcall(uci.delete, uci, "firewall", section)
		local rollback_commit_ok, rollback_committed = false, false
		if delete_ok and deleted == true then
			rollback_commit_ok, rollback_committed = pcall(uci.commit, uci, "firewall")
		end
		local rollback_reload_ok, rollback_reload_status = false, -1
		if rollback_commit_ok and rollback_committed == true then
			rollback_reload_ok, rollback_reload_status = pcall(sys.call, "/etc/init.d/firewall reload >/dev/null 2>&1")
		end
		local recovered = delete_ok and deleted == true and rollback_commit_ok
			and rollback_committed == true and rollback_reload_ok and rollback_reload_status == 0
		record_audit(http, "office.forwarding.add", section, "failed")
		respond(502, {
			ok = false,
			error = recovered
				and "The firewall reload failed. The new forwarding was removed and the previous policy restored."
				or "The firewall reload failed and rollback could not be confirmed. Inspect firewall configuration and service state locally.",
			rolled_back = recovered
		})
		return
	end

	record_audit(http, "office.forwarding.add", section, "success")
	respond(nil, {
		ok = true,
		section = section,
		source = update.source,
		destination = update.destination,
		reloaded = true,
		rolled_back = false
	})
end

function action_office_forwarding_remove()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local validator = require "luci.quantumgrid.office_networks"
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then
			http.status(status, status == 400 and "Bad Request" or
				status == 403 and "Forbidden" or status == 404 and "Not Found" or
				status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
				status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
				"Internal Server Error")
		end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	if http.formvalue("confirmed", true) ~= "1" then
		respond(400, { ok = false, error = "Explicit confirmation is required before removing firewall forwarding." })
		return
	end
	if fs.access("/etc/config/firewall") ~= true or fs.access("/etc/init.d/firewall") ~= true then
		respond(503, { ok = false, error = "Firewall configuration or the native firewall reload service is unavailable." })
		return
	end

	local inventory = office_network_status(uci, fs)
	if not inventory.firewall_available or inventory.truncated then
		respond(409, { ok = false, error = "The firewall inventory is unavailable or truncated. Resolve it before changing inter-zone forwarding." })
		return
	end
	local section = http.formvalue("section", true)
	if type(section) ~= "string" or #section > 64
		or not section:match("^[A-Za-z0-9_.%-]+$") or section == "." or section == ".." then
		respond(400, { ok = false, error = "The firewall forwarding section identifier is invalid." })
		return
	end
	local snapshot_ok, snapshot = pcall(uci.get_all, uci, "firewall", section)
	if not snapshot_ok or type(snapshot) ~= "table" or snapshot[".type"] ~= "forwarding" then
		respond(404, { ok = false, error = "The selected firewall forwarding no longer exists." })
		return
	end
	local previous, snapshot_error = validator.snapshot_firewall_forwarding_section(snapshot)
	if not previous then
		respond(500, { ok = false, error = snapshot_error or "The original firewall forwarding could not be snapshotted safely." })
		return
	end

	local delete_ok, deleted = pcall(uci.delete, uci, "firewall", section)
	if not delete_ok or deleted ~= true then
		pcall(uci.revert, uci, "firewall")
		respond(500, { ok = false, error = "The firewall forwarding could not be staged for removal." })
		return
	end
	local commit_ok, committed = pcall(uci.commit, uci, "firewall")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "firewall")
		respond(500, { ok = false, error = "The firewall forwarding removal could not be committed; firewall reload was not attempted." })
		return
	end

	local reload_ok, reload_status = pcall(sys.call, "/etc/init.d/firewall reload >/dev/null 2>&1")
	if not reload_ok or reload_status ~= 0 then
		local restore_ok, restored = pcall(uci.section, uci, "firewall", "forwarding", section, previous.values)
		local rollback_commit_ok, rollback_committed = false, false
		if restore_ok and restored then
			rollback_commit_ok, rollback_committed = pcall(uci.commit, uci, "firewall")
		end
		local rollback_reload_ok, rollback_reload_status = false, -1
		if rollback_commit_ok and rollback_committed == true then
			rollback_reload_ok, rollback_reload_status = pcall(sys.call, "/etc/init.d/firewall reload >/dev/null 2>&1")
		end
		local recovered = restore_ok and restored and rollback_commit_ok
			and rollback_committed == true and rollback_reload_ok and rollback_reload_status == 0
		record_audit(http, "office.forwarding.remove", section, "failed")
		respond(502, {
			ok = false,
			error = recovered
				and "The firewall reload failed. The complete forwarding section was restored."
				or "The firewall reload failed and the forwarding could not be fully restored. Inspect firewall configuration and service state locally.",
			rolled_back = recovered
		})
		return
	end

	record_audit(http, "office.forwarding.remove", section, "success")
	respond(nil, {
		ok = true,
		section = section,
		source = previous.values.src or "",
		destination = previous.values.dest or "",
		removed = true,
		reloaded = true,
		rolled_back = false
	})
end

local function restore_office_zone_policy_options(uci, section, snapshot)
	if type(section) ~= "string" or type(snapshot) ~= "table" then return false end
	for option, previous in pairs(snapshot) do
		if previous.present then
			local ok, result = pcall(uci.set, uci, "firewall", section, option, previous.value)
			if not ok or result ~= true then
				pcall(uci.revert, uci, "firewall")
				return false
			end
		else
			local current = uci:get("firewall", section, option)
			if current ~= nil then
				local ok, result = pcall(uci.delete, uci, "firewall", section, option)
				if not ok or result ~= true then
					pcall(uci.revert, uci, "firewall")
					return false
				end
			end
		end
	end
	local commit_ok, committed = pcall(uci.commit, uci, "firewall")
	return commit_ok and committed == true
end

local function office_zone_contains_network(zone, network)
	for _, item in ipairs(type(zone.networks) == "table" and zone.networks or {}) do
		if item == network then return true end
	end
	return false
end

local function office_zone_matches_management_route(zone, inventory, remote_ip)
	if type(remote_ip) ~= "string" then return nil end
	local a, b, c, d = remote_ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	if not a then return nil end
	for _, part in ipairs({ a, b, c, d }) do
		local octet = tonumber(part)
		if not octet or octet < 0 or octet > 255 or tostring(octet) ~= part then return nil end
	end
	local util = require "luci.util"
	local ok, output = pcall(util.exec, "/sbin/ip -4 route get " .. remote_ip .. " 2>/dev/null")
	if not ok or type(output) ~= "string" then return nil end
	local device = output:match("%sdev%s+([%w_.%-]+)")
	if not device then return nil end
	local matched_interface = false
	for _, iface in ipairs(inventory.interfaces or {}) do
		if iface.device == device then
			matched_interface = true
			if office_zone_contains_network(zone, iface.name) then return true end
		end
	end
	if matched_interface then return false end
	return nil
end

function action_office_zone_update()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local validator = require "luci.quantumgrid.office_networks"
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then
			http.status(status, status == 400 and "Bad Request" or
				status == 403 and "Forbidden" or status == 404 and "Not Found" or
				status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
				status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
				"Internal Server Error")
		end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	if http.formvalue("confirmed", true) ~= "1" then
		respond(400, { ok = false, error = "Explicit confirmation is required before changing firewall zone policy." })
		return
	end
	if fs.access("/etc/config/firewall") ~= true or fs.access("/etc/init.d/firewall") ~= true then
		respond(503, { ok = false, error = "Firewall configuration or the native firewall reload service is unavailable." })
		return
	end

	local inventory = office_network_status(uci, fs)
	if not inventory.firewall_available or inventory.truncated then
		respond(409, { ok = false, error = "The firewall inventory is unavailable or truncated. Resolve it before changing zone policy." })
		return
	end
	local section = http.formvalue("section", true)
	local output_policy = http.formvalue("output", true)
	local forward_policy = http.formvalue("forward", true)
	local masquerade = http.formvalue("masquerade", true)
	local update, validation_error = validator.validate_office_zone_policy(
		section, output_policy, forward_policy, masquerade, inventory.zones)
	if not update then
		respond(400, { ok = false, error = validation_error })
		return
	end

	local snapshot_ok, snapshot = pcall(uci.get_all, uci, "firewall", update.section)
	if not snapshot_ok or type(snapshot) ~= "table" or snapshot[".type"] ~= "zone" then
		respond(404, { ok = false, error = "The selected firewall zone no longer exists." })
		return
	end
	local previous, snapshot_error = validator.snapshot_firewall_zone_policy_options(snapshot)
	if not previous then
		respond(500, { ok = false, error = snapshot_error or "The current firewall zone policy could not be snapshotted." })
		return
	end

	local current_output = type(snapshot.output) == "string" and snapshot.output or "ACCEPT"
	local output_changes = update.output_write and
		((update.output == "INHERIT" and snapshot.output ~= nil)
			or (update.output ~= "INHERIT" and update.output ~= current_output))
	local output_tightening = update.output == "REJECT" or update.output == "DROP" or update.output == "INHERIT"
	if output_changes and output_tightening then
		local target_zone = nil
		for _, zone in ipairs(inventory.zones or {}) do
			if zone.section == update.section then target_zone = zone break end
		end
		local management_match = nil
		if target_zone then
			management_match = office_zone_matches_management_route(
				target_zone, inventory, http.getenv("REMOTE_ADDR"))
		end
		if management_match == nil then
			respond(409, { ok = false, error = "QuantumGrid cannot prove that a restrictive output policy will preserve the current administrator's return route. Use a verified out-of-band session or leave the output policy unchanged." })
			return
		elseif management_match then
			respond(409, { ok = false, error = "The selected zone carries the current administrator's IPv4 session. Its output policy cannot be tightened or reset to an unknown default from that session." })
			return
		end
	end

	local function stage_policy(option, value, write_option, current_value)
		if not write_option or value == "UNCHANGED" then return true end
		if value == "INHERIT" then
			if current_value == nil then return true end
			local ok, result = pcall(uci.delete, uci, "firewall", update.section, option)
			return ok and result == true
		end
		local ok, result = pcall(uci.set, uci, "firewall", update.section, option, value)
		return ok and result == true
	end

	local output_ok = stage_policy("output", update.output, update.output_write, snapshot.output)
	local forward_ok = stage_policy("forward", update.forward, update.forward_write, snapshot.forward)
	local masq_ok, masq_set = pcall(uci.set, uci, "firewall", update.section, "masq", update.masq_value)
	if not output_ok or not forward_ok or not masq_ok or masq_set ~= true then
		pcall(uci.revert, uci, "firewall")
		respond(500, { ok = false, error = "The firewall zone policy could not be staged safely." })
		return
	end
	local commit_ok, committed = pcall(uci.commit, uci, "firewall")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "firewall")
		respond(500, { ok = false, error = "The firewall zone policy could not be committed; firewall reload was not attempted." })
		return
	end

	local reload_ok, reload_status = pcall(sys.call, "/etc/init.d/firewall reload >/dev/null 2>&1")
	if not reload_ok or reload_status ~= 0 then
		local rollback_ok, rollback_restored = pcall(
			restore_office_zone_policy_options, uci, update.section, previous.options)
		local rollback_reload_ok, rollback_reload_status = false, -1
		if rollback_ok and rollback_restored then
			rollback_reload_ok, rollback_reload_status = pcall(sys.call, "/etc/init.d/firewall reload >/dev/null 2>&1")
		end
		local recovered = rollback_ok and rollback_restored
			and rollback_reload_ok and rollback_reload_status == 0
		record_audit(http, "office.zone.update", update.section, "failed")
		respond(502, {
			ok = false,
			error = recovered
				and "The firewall reload failed. The previous output, forward and masquerade options were restored."
				or "The firewall reload failed and zone-policy rollback could not be confirmed. Inspect firewall configuration and service state locally.",
			rolled_back = recovered
		})
		return
	end

	local applied_output = uci:get("firewall", update.section, "output") or ""
	local applied_forward = uci:get("firewall", update.section, "forward") or ""
	record_audit(http, "office.zone.update", update.section, "success")
	respond(nil, {
		ok = true,
		section = update.section,
		name = snapshot.name or update.section,
		input = snapshot.input or "",
		output = applied_output,
		forward = applied_forward,
		masquerade = update.masquerade,
		input_unchanged = true,
		reloaded = true,
		rolled_back = false
	})
end

local function office_segment_reload(sys, ipv6_enabled)
	local network_ok, network_status = pcall(sys.call, "/etc/init.d/network reload >/dev/null 2>&1")
	local firewall_ok, firewall_status = pcall(sys.call, "/etc/init.d/firewall reload >/dev/null 2>&1")
	local dhcp_ok, dhcp_status = pcall(sys.call, "/etc/init.d/dnsmasq restart >/dev/null 2>&1")
	local odhcpd_ok, odhcpd_status = true, 0
	if ipv6_enabled then
		odhcpd_ok, odhcpd_status = pcall(sys.call, "/etc/init.d/odhcpd restart >/dev/null 2>&1")
	end
	return network_ok and network_status == 0
		and firewall_ok and firewall_status == 0
		and dhcp_ok and dhcp_status == 0
		and odhcpd_ok and odhcpd_status == 0
end

local function restore_office_segment(uci, sys, network_section, dhcp_section,
	zone_section, zone_networks_present, previous_zone_networks, rule_sections, ipv6_enabled)
	local writes_ok = true
	local function delete_if_present(config, section)
		if type(section) ~= "string" or section == "" then return end
		local type_ok, section_type = pcall(uci.get, uci, config, section, ".type")
		if not type_ok then writes_ok = false return end
		if section_type ~= nil then
			local delete_ok, deleted = pcall(uci.delete, uci, config, section)
			if not delete_ok or deleted ~= true then writes_ok = false end
		end
	end
	delete_if_present("network", network_section)
	delete_if_present("dhcp", dhcp_section)
	for _, section in ipairs(type(rule_sections) == "table" and rule_sections or {}) do
		delete_if_present("firewall", section)
	end

	if type(zone_section) == "string" and zone_section ~= "" then
		local zone_type_ok, zone_type = pcall(uci.get, uci, "firewall", zone_section, ".type")
		if not zone_type_ok or zone_type ~= "zone" then
			writes_ok = false
		elseif zone_networks_present then
			local networks = type(previous_zone_networks) == "table" and previous_zone_networks or
				type(previous_zone_networks) == "string" and { previous_zone_networks } or {}
			local set_ok, set_result = pcall(uci.set_list, uci, "firewall", zone_section, "network", networks)
			if not set_ok or set_result ~= true then writes_ok = false end
		else
			local current = uci:get("firewall", zone_section, "network")
			if current ~= nil then
				local delete_ok, deleted = pcall(uci.delete, uci, "firewall", zone_section, "network")
				if not delete_ok or deleted ~= true then writes_ok = false end
			end
		end
	end

	for _, config in ipairs({ "network", "firewall", "dhcp" }) do
		local commit_ok, committed = pcall(uci.commit, uci, config)
		if not commit_ok or committed ~= true then writes_ok = false end
	end
	local services_ok = office_segment_reload(sys, ipv6_enabled)
	return writes_ok and services_ok
end

function action_office_segment_add()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local validator = require "luci.quantumgrid.office_networks"
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then
			http.status(status, status == 400 and "Bad Request" or
				status == 403 and "Forbidden" or status == 404 and "Not Found" or
				status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
				status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
				"Internal Server Error")
		end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	if http.formvalue("confirmed", true) ~= "1" then
		respond(400, { ok = false, error = "Explicit confirmation is required before provisioning an office network." })
		return
	end
	local ipv6, ipv6_error = validator.validate_office_segment_ipv6(http.formvalue("ipv6_enabled", true) or "0")
	if not ipv6 then
		respond(400, { ok = false, error = ipv6_error })
		return
	end
	if ipv6.enabled and fs.access("/etc/init.d/odhcpd") ~= true then
		respond(503, { ok = false, error = "Dual-stack provisioning requires the odhcpd DHCPv6/Router Advertisement service." })
		return
	end
	if fs.access("/etc/config/network") ~= true or fs.access("/etc/config/firewall") ~= true
		or fs.access("/etc/config/dhcp") ~= true
		or fs.access("/etc/init.d/network") ~= true or fs.access("/etc/init.d/firewall") ~= true
		or fs.access("/etc/init.d/dnsmasq") ~= true then
		respond(503, { ok = false, error = "Network, firewall, DHCP configuration or a required service is unavailable." })
		return
	end

	local inventory = office_network_status(uci, fs)
	if not inventory.available or not inventory.firewall_available or not inventory.dhcp_available
		or inventory.truncated then
		respond(409, { ok = false, error = "The network, firewall or DHCP inventory is unavailable or truncated. Resolve it before provisioning a new segment." })
		return
	end

	local requested_zone = http.formvalue("zone", true)
	if type(requested_zone) ~= "string" or #requested_zone > 64
		or not requested_zone:match("^[A-Za-z0-9_.%-]+$") then
		respond(400, { ok = false, error = "Select an existing firewall zone." })
		return
	end
	local zones = {}
	local zone_found = false
	for _, zone in ipairs(inventory.zones or {}) do
		local selected = zone.section == requested_zone
		if selected then zone_found = true end
		table.insert(zones, {
			section = zone.section,
			name = zone.name,
			networks = zone.networks,
			input = zone.input,
			output = zone.output,
			forward = zone.forward,
			selected = selected
		})
	end
	if not zone_found then
		respond(409, { ok = false, error = "The selected firewall zone no longer exists." })
		return
	end

	local update, validation_error = validator.validate_office_segment(
		http.formvalue("name", true),
		http.formvalue("bridge", true),
		http.formvalue("vlan", true),
		http.formvalue("address", true),
		http.formvalue("netmask", true),
		http.formvalue("start", true),
		http.formvalue("limit", true),
		http.formvalue("leasetime", true),
		inventory.interfaces,
		inventory.bridges,
		inventory.vlans,
		zones,
		inventory.dhcp_scopes)
	if not update then
		respond(400, { ok = false, error = validation_error })
		return
	end
	if ipv6.enabled and update.zone_output ~= "ACCEPT" then
		respond(400, { ok = false, error = "Dual-stack segments require the selected firewall zone to allow router-originated output so Router Advertisements can reach the VLAN." })
		return
	end

	local network_section = update.name
	local dhcp_section = "dhcp_" .. update.name
	local rule_sections = {
		"qgrid_" .. update.name .. "_dhcp",
		"qgrid_" .. update.name .. "_dnsudp",
		"qgrid_" .. update.name .. "_dnstcp"
	}
	if ipv6.enabled then
		table.insert(rule_sections, "qgrid_" .. update.name .. "_dhcpv6")
		table.insert(rule_sections, "qgrid_" .. update.name .. "_dns6udp")
		table.insert(rule_sections, "qgrid_" .. update.name .. "_dns6tcp")
		table.insert(rule_sections, "qgrid_" .. update.name .. "_icmp6")
	end
	if #dhcp_section > 64 then
		respond(400, { ok = false, error = "The generated DHCP section identifier is too long." })
		return
	end
	if uci:get("network", network_section, ".type") ~= nil or
		uci:get("dhcp", dhcp_section, ".type") ~= nil then
		respond(409, { ok = false, error = "A network or DHCP section with the generated identifier already exists." })
		return
	end
	for _, rule_section in ipairs(rule_sections) do
		if uci:get("firewall", rule_section, ".type") ~= nil then
			respond(409, { ok = false, error = "A firewall rule with a generated identifier already exists. Choose a different network name." })
			return
		end
	end

	local zone_snapshot_ok, zone_snapshot = pcall(uci.get_all, uci, "firewall", update.zone_section)
	if not zone_snapshot_ok or type(zone_snapshot) ~= "table" or zone_snapshot[".type"] ~= "zone" then
		respond(409, { ok = false, error = "The selected firewall zone could not be snapshotted safely." })
		return
	end
	local previous_zone_networks_present = zone_snapshot.network ~= nil
	local previous_zone_networks = zone_snapshot.network
	local zone_networks = {}
	if type(previous_zone_networks) == "string" then
		for value in previous_zone_networks:gmatch("%S+") do table.insert(zone_networks, value) end
	elseif type(previous_zone_networks) == "table" then
		for _, value in ipairs(previous_zone_networks) do
			if type(value) == "string" then table.insert(zone_networks, value) end
		end
	end
	for _, network in ipairs(zone_networks) do
		if network == update.name then
			respond(409, { ok = false, error = "The selected firewall zone already contains this network name." })
			return
		end
	end
	table.insert(zone_networks, update.name)

	local network_options = {
		proto = "static",
		device = update.device,
		ipaddr = update.address,
		netmask = update.netmask,
		defaultroute = "0",
		peerdns = "0",
		delegate = ipv6.enabled and "1" or "0"
	}
	if ipv6.enabled then
		network_options.ip6assign = ipv6.ip6assign
	end
	local network_ok, network_created = pcall(
		uci.section, uci, "network", "interface", network_section, network_options)
	if not network_ok or network_created ~= network_section then
		pcall(uci.revert, uci, "network")
		respond(500, { ok = false, error = "The new office network interface could not be staged." })
		return
	end

	local dhcp_options = {
		interface = update.name,
		start = update.dhcp_start,
		limit = update.dhcp_limit,
		leasetime = update.lease_time
	}
	if ipv6.enabled then
		dhcp_options.dhcpv6 = ipv6.dhcpv6
		dhcp_options.ra = ipv6.ra
		dhcp_options.ra_flags = ipv6.ra_flags
		dhcp_options.ra_slaac = ipv6.ra_slaac
		dhcp_options.ra_dns = ipv6.ra_dns
		dhcp_options.ra_preference = ipv6.ra_preference
		dhcp_options.ra_lifetime = ipv6.ra_lifetime
		dhcp_options.dhcpv6_na = ipv6.dhcpv6_na
		dhcp_options.dhcpv6_pd = ipv6.dhcpv6_pd
		dhcp_options.dhcpv6_assignall = ipv6.dhcpv6_assignall
		dhcp_options.ndp = ipv6.ndp
	else
		dhcp_options.dhcpv6 = "disabled"
		dhcp_options.ra = "disabled"
		dhcp_options.ndp = "disabled"
	end
	local dhcp_ok, dhcp_created = pcall(
		uci.section, uci, "dhcp", "dhcp", dhcp_section, dhcp_options)
	if not dhcp_ok or dhcp_created ~= dhcp_section then
		pcall(uci.revert, uci, "network")
		pcall(uci.revert, uci, "dhcp")
		respond(500, { ok = false, error = "The DHCP scope could not be staged. No service was reloaded." })
		return
	end

	local zone_set_ok, zone_set = pcall(uci.set_list, uci, "firewall", update.zone_section, "network", zone_networks)
	if not zone_set_ok or zone_set ~= true then
		pcall(uci.revert, uci, "network")
		pcall(uci.revert, uci, "dhcp")
		pcall(uci.revert, uci, "firewall")
		respond(500, { ok = false, error = "The firewall zone attachment could not be staged. No service was reloaded." })
		return
	end

	local rule_definitions = {
		{ section = rule_sections[1], protocol = "udp", source_port = "68", port = "67", label = "DHCP", family = "ipv4" },
		{ section = rule_sections[2], protocol = "udp", port = "53", label = "DNS UDP", family = "ipv4" },
		{ section = rule_sections[3], protocol = "tcp", port = "53", label = "DNS TCP", family = "ipv4" }
	}
	if ipv6.enabled then
		table.insert(rule_definitions, {
			section = rule_sections[4], protocol = "udp", source_port = "546",
			port = "547", label = "DHCPv6", family = "ipv6"
		})
		table.insert(rule_definitions, {
			section = rule_sections[5], protocol = "udp", port = "53",
			label = "DNSv6 UDP", family = "ipv6"
		})
		table.insert(rule_definitions, {
			section = rule_sections[6], protocol = "tcp", port = "53",
			label = "DNSv6 TCP", family = "ipv6"
		})
		table.insert(rule_definitions, {
			section = rule_sections[7], protocol = "icmp",
			label = "IPv6 neighbour discovery",
			family = "ipv6",
			icmp_types = { "router-solicitation", "neighbour-solicitation", "neighbour-advertisement" }
		})
	end
	for _, rule in ipairs(rule_definitions) do
		local source_ip = rule.family == "ipv4" and rule.label ~= "DHCP"
			and update.subnet_cidr or nil
		local destination_ip = rule.family == "ipv4" and rule.label ~= "DHCP"
			and update.address or nil
		local create_ok, created = pcall(uci.section, uci, "firewall", "rule", rule.section, {
			name = "QuantumGrid " .. update.name .. " " .. rule.label,
			src = update.zone_name,
			proto = rule.protocol,
			src_port = rule.source_port,
			dest_ip = destination_ip,
			src_ip = source_ip,
			dest_port = rule.port,
			icmp_type = rule.icmp_types,
			family = rule.family,
			target = "ACCEPT"
		})
		if not create_ok or created ~= rule.section then
			local recovered = restore_office_segment(uci, sys, network_section, dhcp_section,
				update.zone_section, previous_zone_networks_present, previous_zone_networks, rule_sections, ipv6.enabled)
			record_audit(http, "office.segment.add", update.name, "failed")
			respond(500, {
				error = recovered and "A required office-segment firewall rule could not be staged. The partial configuration was removed."
					or "An office-segment firewall rule could not be staged and the previous configuration could not be fully restored.",
					rolled_back = recovered
			})
			return
		end
	end

	local commits_ok = true
	for _, config in ipairs({ "network", "dhcp", "firewall" }) do
		local commit_ok, committed = pcall(uci.commit, uci, config)
		if not commit_ok or committed ~= true then commits_ok = false end
	end
	if not commits_ok then
		local recovered = restore_office_segment(uci, sys, network_section, dhcp_section,
			update.zone_section, previous_zone_networks_present, previous_zone_networks, rule_sections, ipv6.enabled)
		record_audit(http, "office.segment.add", update.name, "failed")
		respond(500, {
			error = recovered and "One or more configuration commits failed. The partial segment was removed and previous services reloaded."
				or "One or more configuration commits failed and rollback could not be confirmed. Inspect network, firewall and DHCP configuration locally.",
			rolled_back = recovered
		})
		return
	end

	local applied = office_segment_reload(sys, ipv6.enabled)
	if not applied then
		local recovered = restore_office_segment(uci, sys, network_section, dhcp_section,
			update.zone_section, previous_zone_networks_present, previous_zone_networks, rule_sections, ipv6.enabled)
		record_audit(http, "office.segment.add", update.name, "failed")
		respond(502, {
			error = recovered and "A network, firewall or DHCP service reload failed. The new segment was removed and the previous configuration restored."
				or "A service reload failed and cross-package rollback could not be confirmed. Inspect network, firewall and DHCP configuration locally; management connectivity may be affected.",
			rolled_back = recovered
		})
		return
	end

	record_audit(http, "office.segment.add", update.name, "success")
	respond(nil, {
		ok = true,
		name = update.name,
		device = update.device,
		address = update.address,
		netmask = update.netmask,
		zone = update.zone_name,
		pool_start_ip = update.pool_start_ip,
		pool_end_ip = update.pool_end_ip,
		firewall_rules = #rule_definitions,
		ipv6_enabled = ipv6.enabled,
		ipv6_assign = ipv6.ip6assign,
		dhcpv6 = ipv6.dhcpv6,
		ra = ipv6.ra,
		ra_flags = ipv6.ra_flags or {},
		ra_slaac = ipv6.ra_slaac or "0",
		ra_dns = ipv6.ra_dns or "0",
		ra_preference = ipv6.ra_preference or "medium",
		ra_lifetime = tonumber(ipv6.ra_lifetime) or 0,
		dhcpv6_na = ipv6.dhcpv6_na or "0",
		dhcpv6_pd = ipv6.dhcpv6_pd or "0",
		dhcpv6_assignall = ipv6.dhcpv6_assignall or "0",
		ndp = ipv6.ndp,
		network_reloaded = true,
		firewall_reloaded = true,
		dhcp_restarted = true,
		odhcpd_restarted = ipv6.enabled,
		rolled_back = false
	})
end

local function office_management_network(inventory, remote_ip)
	if type(remote_ip) ~= "string" then return nil end
	local a, b, c, d = remote_ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	if not a then return nil end
	for _, part in ipairs({ a, b, c, d }) do
		local octet = tonumber(part)
		if not octet or octet < 0 or octet > 255 or tostring(octet) ~= part then return nil end
	end
	local util = require "luci.util"
	local ok, output = pcall(util.exec, "/sbin/ip -4 route get " .. remote_ip .. " 2>/dev/null")
	if not ok or type(output) ~= "string" then return nil end
	local device = output:match("%sdev%s+([%w_.%-]+)")
	if not device then return nil end
	for _, iface in ipairs(inventory.interfaces or {}) do
		if iface.device == device then return iface.name end
	end
	return nil
end


function action_sqm_client_qos_add()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"
	local function respond(status, payload)
		if status then http.status(status, status == 400 and "Bad Request" or
			status == 403 and "Forbidden" or status == 404 and "Not Found" or
			status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
			status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
			"Internal Server Error") end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end
	if http.getenv("REQUEST_METHOD") ~= "POST" then respond(405, { ok = false, error = "POST is required." }); return end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then respond(403, { ok = false, error = "A same-origin request is required." }); return end
	if http.formvalue("confirmed", true) ~= "1" then
		respond(400, { ok = false, error = "Explicit confirmation is required before adding a per-client DSCP policy." }); return
	end
	if fs.access("/etc/config/firewall") ~= true or fs.access("/etc/init.d/firewall") ~= true then
		respond(503, { ok = false, error = "Firewall configuration or native reload service is unavailable." }); return
	end
	local inventory = office_network_status(uci, fs)
	if not inventory.firewall_available or inventory.truncated then
		respond(409, { ok = false, error = "The firewall zone inventory is unavailable or truncated. Resolve it before changing client QoS policies." }); return
	end
	local qos = require "luci.quantumgrid.qos"
	local update, validation_error = qos.validate_client_policy(
		http.formvalue("mac", true),
		http.formvalue("source_zone", true),
		http.formvalue("destination_zone", true),
		http.formvalue("dscp_class", true),
		inventory.zones)
	if not update then respond(400, { ok = false, error = validation_error }); return end
	local existing, policies_truncated, policies_error = qos.read_client_policies(uci, 32)
	if not existing then
		respond(500, { ok = false, error = policies_error or "Existing client QoS policies could not be read safely." }); return
	end
	if policies_truncated or #existing >= 32 then
		respond(409, { ok = false, error = "The client QoS policy inventory is full or truncated. Remove an existing QuantumGrid policy before adding another." }); return
	end
	if qos.has_duplicate_client_policy(existing, update) then
		respond(409, { ok = false, error = "A QuantumGrid policy already exists for this client and zone pair. Remove it before creating a replacement." }); return
	end

	local section_ok, section = pcall(uci.section, uci, "firewall", "rule", nil, {
		name = update.name,
		src = update.source_zone,
		dest = update.destination_zone,
		proto = "all",
		src_mac = update.mac,
		target = "dscp",
		set_dscp = update.dscp_class,
		enabled = "1"
	})
	if not section_ok or type(section) ~= "string" or section == "" then
		pcall(uci.revert, uci, "firewall")
		respond(500, { ok = false, error = "The client DSCP policy could not be staged in UCI." }); return
	end
	local commit_ok, committed = pcall(uci.commit, uci, "firewall")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "firewall")
		respond(500, { ok = false, error = "The client DSCP policy could not be committed; firewall reload was not attempted." }); return
	end
	local reload_ok, reload_status = pcall(sys.call, "/etc/init.d/firewall reload >/dev/null 2>&1")
	if not reload_ok or reload_status ~= 0 then
		local delete_ok, deleted = pcall(uci.delete, uci, "firewall", section)
		local rollback_commit_ok, rollback_committed = false, false
		if delete_ok and deleted == true then rollback_commit_ok, rollback_committed = pcall(uci.commit, uci, "firewall") end
		local rollback_reload_ok, rollback_reload_status = false, -1
		if rollback_commit_ok and rollback_committed == true then
			rollback_reload_ok, rollback_reload_status = pcall(sys.call, "/etc/init.d/firewall reload >/dev/null 2>&1")
		end
		local rolled_back = delete_ok and deleted == true and rollback_commit_ok
			and rollback_committed == true and rollback_reload_ok and rollback_reload_status == 0
		record_audit(http, "sqm.client-qos.add", section, "failed")
		respond(502, {
			ok = false,
			error = rolled_back
				and "Firewall reload failed. The new client DSCP rule was removed."
				or "Firewall reload failed and the new client DSCP rule rollback could not be confirmed. Inspect firewall configuration locally.",
			rolled_back = rolled_back
		}); return
	end
	record_audit(http, "sqm.client-qos.add", section, "success")
	respond(nil, {
		ok = true, section = section, mac = update.mac, direction = "upload", protocol = "all",
		source_zone = update.source_zone, destination_zone = update.destination_zone,
		dscp_class = update.dscp_class, reloaded = true, rolled_back = false
	})
end

function action_sqm_client_qos_download_add()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"
	local function respond(status, payload)
		if status then http.status(status, status == 400 and "Bad Request" or
			status == 403 and "Forbidden" or status == 404 and "Not Found" or
			status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
			status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
			"Internal Server Error") end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end
	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." }); return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." }); return
	end
	if http.formvalue("confirmed", true) ~= "1" then
		respond(400, { ok = false, error = "Explicit confirmation is required before adding a per-client download DSCP policy." }); return
	end
	if fs.access("/etc/config/firewall") ~= true or fs.access("/etc/init.d/firewall") ~= true or
		fs.access("/etc/config/dhcp") ~= true then
		respond(503, { ok = false, error = "Firewall, DHCP reservation configuration or native firewall reload service is unavailable." }); return
	end

	local inventory = office_network_status(uci, fs)
	if not inventory.available or not inventory.firewall_available or not inventory.dhcp_available or
		inventory.truncated then
		respond(409, {
			ok = false,
			error = "Network, firewall or static DHCP reservation inventory is unavailable or truncated. Resolve inventory errors before adding download marking."
		}); return
	end
	local qos = require "luci.quantumgrid.qos"
	local update, validation_error = qos.validate_client_download_policy(
		http.formvalue("mac", true),
		http.formvalue("destination_ip", true),
		http.formvalue("source_zone", true),
		http.formvalue("destination_zone", true),
		http.formvalue("dscp_class", true),
		inventory.zones,
		inventory.interfaces,
		inventory.static_leases)
	if not update then
		respond(400, { ok = false, error = validation_error }); return
	end

	local existing, policies_truncated, policies_error = qos.read_client_policies(uci, 32)
	if not existing then
		respond(500, { ok = false, error = policies_error or "Existing client QoS policies could not be read safely." }); return
	end
	if policies_truncated or #existing >= 32 then
		respond(409, { ok = false, error = "The client QoS policy inventory is full or truncated. Remove an existing QuantumGrid policy before adding another." }); return
	end
	if qos.has_duplicate_client_policy(existing, update) then
		respond(409, { ok = false, error = "A QuantumGrid policy already exists for this client and zone pair. Remove it before creating a replacement." }); return
	end

	local section_ok, section = pcall(uci.section, uci, "firewall", "rule", nil, {
		name = update.name,
		src = update.source_zone,
		dest = update.destination_zone,
		proto = "all",
		dest_ip = update.destination_ip,
		target = "dscp",
		set_dscp = update.dscp_class,
		enabled = "1"
	})
	if not section_ok or type(section) ~= "string" or section == "" then
		pcall(uci.revert, uci, "firewall")
		respond(500, { ok = false, error = "The client download DSCP policy could not be staged in UCI." }); return
	end
	local commit_ok, committed = pcall(uci.commit, uci, "firewall")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "firewall")
		respond(500, { ok = false, error = "The client download DSCP policy could not be committed; firewall reload was not attempted." }); return
	end
	local reload_ok, reload_status = pcall(sys.call, "/etc/init.d/firewall reload >/dev/null 2>&1")
	if not reload_ok or reload_status ~= 0 then
		local delete_ok, deleted = pcall(uci.delete, uci, "firewall", section)
		local rollback_commit_ok, rollback_committed = false, false
		if delete_ok and deleted == true then rollback_commit_ok, rollback_committed = pcall(uci.commit, uci, "firewall") end
		local rollback_reload_ok, rollback_reload_status = false, -1
		if rollback_commit_ok and rollback_committed == true then
			rollback_reload_ok, rollback_reload_status = pcall(sys.call, "/etc/init.d/firewall reload >/dev/null 2>&1")
		end
		local rolled_back = delete_ok and deleted == true and rollback_commit_ok and
			rollback_committed == true and rollback_reload_ok and rollback_reload_status == 0
		record_audit(http, "sqm.client-qos.download.add", section, "failed")
		respond(502, {
			ok = false,
			error = rolled_back and
				"Firewall reload failed. The new client download DSCP rule was removed."
				or "Firewall reload failed and the new client download DSCP rule rollback could not be confirmed. Inspect firewall configuration locally.",
			rolled_back = rolled_back
		}); return
	end
	record_audit(http, "sqm.client-qos.download.add", section, "success")
	respond(nil, {
		ok = true, section = section, direction = "download", protocol = "all",
		mac = update.mac, destination_ip = update.destination_ip,
		source_zone = update.source_zone, destination_zone = update.destination_zone,
		dscp_class = update.dscp_class, reloaded = true, rolled_back = false
	})
end


function action_sqm_client_qos_remove()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"
	local function respond(status, payload)
		if status then http.status(status, status == 400 and "Bad Request" or
			status == 403 and "Forbidden" or status == 404 and "Not Found" or
			status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
			status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
			"Internal Server Error") end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end
	if http.getenv("REQUEST_METHOD") ~= "POST" then respond(405, { ok = false, error = "POST is required." }); return end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then respond(403, { ok = false, error = "A same-origin request is required." }); return end
	if http.formvalue("confirmed", true) ~= "1" then
		respond(400, { ok = false, error = "Explicit confirmation is required before removing a per-client DSCP policy." }); return
	end
	if fs.access("/etc/config/firewall") ~= true or fs.access("/etc/init.d/firewall") ~= true then
		respond(503, { ok = false, error = "Firewall configuration or native reload service is unavailable." }); return
	end
	local section = http.formvalue("section", true)
	local qos = require "luci.quantumgrid.qos"
	local valid_section, section_error = qos.validate_client_policy_section(section)
	if not valid_section then respond(400, { ok = false, error = section_error }); return end
	local snapshot_ok, snapshot = pcall(uci.get_all, uci, "firewall", valid_section)
	if not snapshot_ok or type(snapshot) ~= "table" or snapshot[".type"] ~= "rule" then
		respond(404, { ok = false, error = "The selected firewall rule no longer exists." }); return
	end
	local previous, snapshot_error = qos.snapshot_client_policy_section(snapshot)
	if not previous then
		respond(404, { ok = false, error = snapshot_error or "The selected rule is not a QuantumGrid-owned client DSCP policy." }); return
	end
	local delete_ok, deleted = pcall(uci.delete, uci, "firewall", valid_section)
	if not delete_ok or deleted ~= true then
		pcall(uci.revert, uci, "firewall")
		respond(500, { ok = false, error = "The client DSCP rule could not be staged for removal." }); return
	end
	local commit_ok, committed = pcall(uci.commit, uci, "firewall")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "firewall")
		respond(500, { ok = false, error = "The client DSCP rule removal could not be committed; firewall reload was not attempted." }); return
	end
	local reload_ok, reload_status = pcall(sys.call, "/etc/init.d/firewall reload >/dev/null 2>&1")
	if not reload_ok or reload_status ~= 0 then
		local restore_ok, restored = pcall(uci.section, uci, "firewall", "rule", valid_section, previous.values)
		local rollback_commit_ok, rollback_committed = false, false
		if restore_ok and restored then rollback_commit_ok, rollback_committed = pcall(uci.commit, uci, "firewall") end
		local rollback_reload_ok, rollback_reload_status = false, -1
		if rollback_commit_ok and rollback_committed == true then
			rollback_reload_ok, rollback_reload_status = pcall(sys.call, "/etc/init.d/firewall reload >/dev/null 2>&1")
		end
		local rolled_back = restore_ok and restored and rollback_commit_ok
			and rollback_committed == true and rollback_reload_ok and rollback_reload_status == 0
		record_audit(http, "sqm.client-qos.remove", valid_section, "failed")
		respond(502, {
			ok = false,
			error = rolled_back
				and "Firewall reload failed. The previous client DSCP rule was restored."
				or "Firewall reload failed and the client DSCP rule rollback could not be confirmed. Inspect firewall configuration locally.",
			rolled_back = rolled_back
		}); return
	end
	local summary = qos.summarize_client_policy(snapshot)
	record_audit(http, "sqm.client-qos.remove", valid_section, "success")
	respond(nil, {
		ok = true, section = valid_section, mac = summary.mac,
		direction = summary.direction, protocol = summary.protocol,
		destination_ip = summary.destination_ip,
		source_zone = summary.source_zone, destination_zone = summary.destination_zone,
		dscp_class = summary.dscp_class, removed = true, reloaded = true, rolled_back = false
	})
end

function action_office_wifi_network_update()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local validator = require "luci.quantumgrid.office_networks"
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then
			http.status(status, status == 400 and "Bad Request" or
				status == 403 and "Forbidden" or status == 404 and "Not Found" or
				status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
				status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
				"Internal Server Error")
		end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	if http.formvalue("confirmed", true) ~= "1" then
		respond(400, { ok = false, error = "Explicit confirmation is required before changing an AP network binding." })
		return
	end
	if fs.access("/etc/config/wireless") ~= true or fs.access("/sbin/wifi") ~= true then
		respond(503, { ok = false, error = "Wireless configuration or the native Wi-Fi reload command is unavailable." })
		return
	end

	local inventory = office_network_status(uci, fs)
	if not inventory.available or inventory.truncated then
		respond(409, { ok = false, error = "The office network inventory is unavailable or truncated. Resolve it before changing an AP network binding." })
		return
	end
	local section = http.formvalue("section", true)
	local target = http.formvalue("network", true)
	local update, validation_error = validator.validate_office_wifi_ap_network(
		section, target, inventory.wifi_aps, inventory.interfaces, inventory.zones)
	if not update then
		respond(400, { ok = false, error = validation_error })
		return
	end

	local snapshot_ok, snapshot = pcall(uci.get_all, uci, "wireless", update.section)
	if not snapshot_ok or type(snapshot) ~= "table" or snapshot[".type"] ~= "wifi-iface"
		or snapshot.mode ~= "ap" then
		respond(404, { ok = false, error = "The selected wireless AP no longer exists." })
		return
	end
	local previous, snapshot_error = validator.snapshot_wifi_ap_network(snapshot)
	if not previous then
		respond(500, { ok = false, error = snapshot_error or "The current AP network binding could not be snapshotted." })
		return
	end
	local unchanged = previous.present and #previous.value == 1 and previous.value[1] == update.network
	if unchanged then
		respond(nil, {
			ok = true,
			section = update.section,
			ssid = snapshot.ssid or "",
			network = update.network,
			networks = { update.network },
			reloaded = false,
			rolled_back = false
		})
		return
	end

	local management_network = office_management_network(inventory, http.getenv("REMOTE_ADDR"))
	if type(previous.value) == "table" and #previous.value > 0 then
		if not management_network then
			respond(409, { ok = false, error = "QuantumGrid cannot prove the current administrator's IPv4 return network. Use an out-of-band session before moving an existing SSID to another network." })
			return
		end
		for _, current_network in ipairs(previous.value) do
			if current_network == management_network then
				respond(409, { ok = false, error = "This AP currently carries the administrator's management network. Its network binding cannot be moved from that session; use a separate AP or out-of-band access." })
				return
			end
		end
	end

	local set_ok, set_result = pcall(uci.set_list, uci, "wireless", update.section, "network", { update.network })
	if not set_ok or set_result ~= true then
		pcall(uci.revert, uci, "wireless")
		respond(500, { ok = false, error = "The AP network binding could not be staged safely." })
		return
	end
	local commit_ok, committed = pcall(uci.commit, uci, "wireless")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "wireless")
		respond(500, { ok = false, error = "The AP network binding could not be committed; Wi-Fi reload was not attempted." })
		return
	end

	local reload_ok, reload_status = pcall(sys.call, "/sbin/wifi reload >/dev/null 2>&1")
	if not reload_ok or reload_status ~= 0 then
		local restore_ok, restored = false, false
		if previous.present then
			restore_ok, restored = pcall(uci.set_list, uci, "wireless", update.section, "network", previous.value)
		else
			local current = uci:get("wireless", update.section, "network")
			if current == nil then
				restore_ok, restored = true, true
			else
				restore_ok, restored = pcall(uci.delete, uci, "wireless", update.section, "network")
			end
		end
		local rollback_commit_ok, rollback_committed = false, false
		if restore_ok and restored == true then
			rollback_commit_ok, rollback_committed = pcall(uci.commit, uci, "wireless")
		end
		local rollback_reload_ok, rollback_reload_status = false, -1
		if rollback_commit_ok and rollback_committed == true then
			rollback_reload_ok, rollback_reload_status = pcall(sys.call, "/sbin/wifi reload >/dev/null 2>&1")
		end
		local rolled_back = restore_ok and restored == true and rollback_commit_ok
			and rollback_committed == true and rollback_reload_ok and rollback_reload_status == 0
		record_audit(http, "office.wifi.network.update", update.section, "failed")
		respond(502, {
			ok = false,
			error = rolled_back
				and "The Wi-Fi reload failed. The previous AP network binding was restored."
				or "The Wi-Fi reload failed and AP network-binding rollback could not be confirmed. Inspect wireless configuration and client connectivity locally.",
			rolled_back = rolled_back
		})
		return
	end

	record_audit(http, "office.wifi.network.update", update.section, "success")
	respond(nil, {
		ok = true,
		section = update.section,
		ssid = snapshot.ssid or "",
		network = update.network,
		networks = { update.network },
		reloaded = true,
		rolled_back = false
	})
end

local function office_restore_firewall_redirect(uci, section, snapshot)
	if type(section) ~= "string" or type(snapshot) ~= "table" then return false end
	local section_ok, restored = pcall(uci.section, uci, "firewall", "redirect", section, snapshot)
	if not section_ok or not restored then return false end
	local commit_ok, committed = pcall(uci.commit, uci, "firewall")
	return commit_ok and committed == true
end

function action_office_port_forward_add()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local validator = require "luci.quantumgrid.office_networks"
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then
			http.status(status, status == 400 and "Bad Request" or
				status == 403 and "Forbidden" or status == 404 and "Not Found" or
				status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
				status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
				"Internal Server Error")
		end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	if http.formvalue("confirmed", true) ~= "1" then
		respond(400, { ok = false, error = "Explicit confirmation is required before opening a WAN port." })
		return
	end
	if fs.access("/etc/config/firewall") ~= true or fs.access("/etc/init.d/firewall") ~= true then
		respond(503, { ok = false, error = "Firewall configuration or native reload service is unavailable." })
		return
	end

	local inventory = office_network_status(uci, fs)
	if not inventory.firewall_available or inventory.truncated then
		respond(409, { ok = false, error = "The firewall inventory is unavailable or truncated. Resolve it before adding an Internet-facing port-forward." })
		return
	end
	local protocol = http.formvalue("protocol", true)
	local update, validation_error = validator.validate_office_port_forward(
		http.formvalue("name", true),
		http.formvalue("source", true),
		http.formvalue("destination", true),
		protocol,
		http.formvalue("source_port", true),
		http.formvalue("destination_ip", true),
		http.formvalue("destination_port", true),
		inventory.zones,
		inventory.interfaces,
		inventory.redirects)
	if not update then
		respond(400, { ok = false, error = validation_error })
		return
	end
	local proto = {}
	if protocol == "tcp" or protocol == "tcp udp" then table.insert(proto, "tcp") end
	if protocol == "udp" or protocol == "tcp udp" then table.insert(proto, "udp") end
	local section_ok, section = pcall(uci.section, uci, "firewall", "redirect", nil, {
		name = update.name,
		src = update.source,
		src_dport = update.source_port,
		dest = update.destination,
		dest_ip = update.destination_ip,
		dest_port = update.destination_port,
		proto = proto,
		target = "DNAT",
		enabled = "1"
	})
	if not section_ok or type(section) ~= "string" or section == "" then
		pcall(uci.revert, uci, "firewall")
		respond(500, { ok = false, error = "The firewall port-forward could not be staged in UCI." })
		return
	end
	local commit_ok, committed = pcall(uci.commit, uci, "firewall")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "firewall")
		respond(500, { ok = false, error = "The firewall port-forward could not be committed; firewall reload was not attempted." })
		return
	end
	local reload_ok, reload_status = pcall(sys.call, "/etc/init.d/firewall reload >/dev/null 2>&1")
	if not reload_ok or reload_status ~= 0 then
		local delete_ok, deleted = pcall(uci.delete, uci, "firewall", section)
		local rollback_commit_ok, rollback_committed = false, false
		if delete_ok and deleted == true then
			rollback_commit_ok, rollback_committed = pcall(uci.commit, uci, "firewall")
		end
		local rollback_reload_ok, rollback_reload_status = false, -1
		if rollback_commit_ok and rollback_committed == true then
			rollback_reload_ok, rollback_reload_status = pcall(sys.call, "/etc/init.d/firewall reload >/dev/null 2>&1")
		end
		local rolled_back = delete_ok and deleted == true and rollback_commit_ok
			and rollback_committed == true and rollback_reload_ok and rollback_reload_status == 0
		record_audit(http, "office.port-forward.add", section, "failed")
		respond(502, {
			ok = false,
			error = rolled_back
				and "Firewall reload failed. The new port-forward was removed and previous policy restored."
				or "Firewall reload failed and port-forward rollback could not be confirmed. Inspect the firewall configuration and service state locally.",
			rolled_back = rolled_back
		})
		return
	end
	record_audit(http, "office.port-forward.add", section, "success")
	respond(nil, {
		ok = true,
		section = section,
		name = update.name,
		source = update.source,
		destination = update.destination,
		protocol = update.protocol,
		source_port = tonumber(update.source_port),
		destination_ip = update.destination_ip,
		destination_port = tonumber(update.destination_port),
		reloaded = true,
		rolled_back = false
	})
end

function action_office_port_forward_remove()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local validator = require "luci.quantumgrid.office_networks"
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then
			http.status(status, status == 400 and "Bad Request" or
				status == 403 and "Forbidden" or status == 404 and "Not Found" or
				status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
				status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
				"Internal Server Error")
		end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	if http.formvalue("confirmed", true) ~= "1" then
		respond(400, { ok = false, error = "Explicit confirmation is required before removing a WAN port-forward." })
		return
	end
	if fs.access("/etc/config/firewall") ~= true or fs.access("/etc/init.d/firewall") ~= true then
		respond(503, { ok = false, error = "Firewall configuration or native reload service is unavailable." })
		return
	end
	local section = http.formvalue("section", true)
	if type(section) ~= "string" or #section < 1 or #section > 64
		or not section:match("^[%w_.%-]+$") or section == "." or section == ".." then
		respond(400, { ok = false, error = "The firewall redirect section identifier is invalid." })
		return
	end
	local snapshot_ok, snapshot = pcall(uci.get_all, uci, "firewall", section)
	if not snapshot_ok or type(snapshot) ~= "table" or snapshot[".type"] ~= "redirect" then
		respond(404, { ok = false, error = "The selected firewall redirect no longer exists." })
		return
	end
	local previous, snapshot_error = validator.snapshot_firewall_redirect_section(snapshot)
	if not previous then
		respond(500, { ok = false, error = snapshot_error or "The original firewall redirect could not be snapshotted safely." })
		return
	end
	local delete_ok, deleted = pcall(uci.delete, uci, "firewall", section)
	if not delete_ok or deleted ~= true then
		pcall(uci.revert, uci, "firewall")
		respond(500, { ok = false, error = "The firewall redirect could not be staged for removal." })
		return
	end
	local commit_ok, committed = pcall(uci.commit, uci, "firewall")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "firewall")
		respond(500, { ok = false, error = "The firewall redirect removal could not be committed; firewall reload was not attempted." })
		return
	end
	local reload_ok, reload_status = pcall(sys.call, "/etc/init.d/firewall reload >/dev/null 2>&1")
	if not reload_ok or reload_status ~= 0 then
		local restore_ok, restored = pcall(uci.section, uci, "firewall", "redirect", section, previous.values)
		local rollback_commit_ok, rollback_committed = false, false
		if restore_ok and restored then
			rollback_commit_ok, rollback_committed = pcall(uci.commit, uci, "firewall")
		end
		local rollback_reload_ok, rollback_reload_status = false, -1
		if rollback_commit_ok and rollback_committed == true then
			rollback_reload_ok, rollback_reload_status = pcall(sys.call, "/etc/init.d/firewall reload >/dev/null 2>&1")
		end
		local rolled_back = restore_ok and restored and rollback_commit_ok
			and rollback_committed == true and rollback_reload_ok and rollback_reload_status == 0
		record_audit(http, "office.port-forward.remove", section, "failed")
		respond(502, {
			ok = false,
			error = rolled_back
				and "Firewall reload failed. The complete port-forward rule was restored."
				or "Firewall reload failed and the port-forward rule could not be fully restored. Inspect firewall configuration and service state locally.",
			rolled_back = rolled_back
		})
		return
	end
	record_audit(http, "office.port-forward.remove", section, "success")
	respond(nil, {
		ok = true,
		section = section,
		removed = true,
		reloaded = true,
		rolled_back = false
	})
end


function action_office_port_forward_toggle()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local validator = require "luci.quantumgrid.office_networks"
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then
			http.status(status, status == 400 and "Bad Request" or
				status == 403 and "Forbidden" or status == 404 and "Not Found" or
				status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
				status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
				"Internal Server Error")
		end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	if http.formvalue("confirmed", true) ~= "1" then
		respond(400, { ok = false, error = "Explicit confirmation is required before changing an Internet-facing IPv4 port-forward." })
		return
	end
	if fs.access("/etc/config/firewall") ~= true or fs.access("/etc/init.d/firewall") ~= true then
		respond(503, { ok = false, error = "Firewall configuration or native reload service is unavailable." })
		return
	end

	local section = http.formvalue("section", true)
	if type(section) ~= "string" or #section < 1 or #section > 64
		or not section:match("^[%w_.%-]+$") or section == "." or section == ".." then
		respond(400, { ok = false, error = "The firewall redirect section identifier is invalid." })
		return
	end
	local requested = http.formvalue("enabled", true)
	if requested ~= "0" and requested ~= "1" then
		respond(400, { ok = false, error = "Enabled state must be explicitly selected." })
		return
	end

	local inventory = office_network_status(uci, fs)
	if not inventory.firewall_available or inventory.truncated then
		respond(409, { ok = false, error = "The firewall inventory is unavailable or truncated. Resolve it before changing a port-forward." })
		return
	end
	local eligible = false
	for _, redirect in ipairs(inventory.redirects or {}) do
		if type(redirect) == "table" and redirect.section == section then
			eligible = true
			break
		end
	end
	if not eligible then
		respond(404, { ok = false, error = "The selected section is not a validated IPv4 DNAT port-forward in the current office inventory." })
		return
	end

	local snapshot_ok, snapshot = pcall(uci.get_all, uci, "firewall", section)
	if not snapshot_ok or type(snapshot) ~= "table" or snapshot[".type"] ~= "redirect" then
		respond(404, { ok = false, error = "The selected firewall redirect no longer exists." })
		return
	end
	local previous, snapshot_error = validator.snapshot_firewall_redirect_section(snapshot)
	if not previous then
		respond(500, { ok = false, error = snapshot_error or "The original firewall redirect could not be snapshotted safely." })
		return
	end
	local previous_value = previous.values.enabled
	local previous_enabled = previous_value ~= "0"
	local desired_enabled = requested == "1"
	if previous_enabled == desired_enabled then
		respond(nil, {
			ok = true,
			section = section,
			enabled = desired_enabled,
			changed = false,
			reloaded = false,
			rolled_back = false
		})
		return
	end

	local stage_ok, staged = pcall(uci.set, uci, "firewall", section, "enabled", requested)
	if not stage_ok or staged ~= true then
		pcall(uci.revert, uci, "firewall")
		respond(500, { ok = false, error = "The port-forward enabled state could not be staged in UCI." })
		return
	end
	local commit_ok, committed = pcall(uci.commit, uci, "firewall")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "firewall")
		respond(500, { ok = false, error = "The port-forward enabled state could not be committed; firewall reload was not attempted." })
		return
	end

	local reload_ok, reload_status = pcall(sys.call, "/etc/init.d/firewall reload >/dev/null 2>&1")
	if not reload_ok or reload_status ~= 0 then
		local restore_ok, restored
		if previous_value == nil then
			restore_ok, restored = pcall(uci.delete, uci, "firewall", section, "enabled")
		else
			restore_ok, restored = pcall(uci.set, uci, "firewall", section, "enabled", previous_value)
		end
		local rollback_commit_ok, rollback_committed = false, false
		if restore_ok and restored == true then
			rollback_commit_ok, rollback_committed = pcall(uci.commit, uci, "firewall")
		end
		local rollback_reload_ok, rollback_reload_status = false, -1
		if rollback_commit_ok and rollback_committed == true then
			rollback_reload_ok, rollback_reload_status = pcall(sys.call, "/etc/init.d/firewall reload >/dev/null 2>&1")
		end
		local rolled_back = restore_ok and restored == true and rollback_commit_ok
			and rollback_committed == true and rollback_reload_ok and rollback_reload_status == 0
		record_audit(http, "office.port-forward.toggle", section, "failed")
		respond(502, {
			ok = false,
			error = rolled_back
				and "Firewall reload failed. The previous port-forward enabled state was restored."
				or "Firewall reload failed and the previous port-forward state could not be confirmed. Inspect firewall configuration and service state locally.",
			rolled_back = rolled_back
		})
		return
	end

	record_audit(http, "office.port-forward.toggle", section, "success")
	respond(nil, {
		ok = true,
		section = section,
		enabled = desired_enabled,
		changed = true,
		reloaded = true,
		rolled_back = false
	})
end

function action_office_ipv6_pinhole_add()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local validator = require "luci.quantumgrid.office_networks"
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then
			http.status(status, status == 400 and "Bad Request" or
				status == 403 and "Forbidden" or status == 404 and "Not Found" or
				status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
				status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
				"Internal Server Error")
		end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	if http.formvalue("confirmed", true) ~= "1" then
		respond(400, { ok = false, error = "Explicit confirmation is required before allowing inbound IPv6 traffic." })
		return
	end
	if fs.access("/etc/config/firewall") ~= true or fs.access("/etc/init.d/firewall") ~= true then
		respond(503, { ok = false, error = "Firewall configuration or native reload service is unavailable." })
		return
	end

	local inventory = office_network_status(uci, fs)
	if not inventory.firewall_available or inventory.truncated then
		respond(409, { ok = false, error = "The network/firewall inventory is unavailable or truncated. Resolve it before adding an Internet-facing IPv6 rule." })
		return
	end
	local protocol = http.formvalue("protocol", true)
	local update, validation_error = validator.validate_office_ipv6_pinhole(
		http.formvalue("name", true),
		http.formvalue("source", true),
		http.formvalue("destination", true),
		protocol,
		http.formvalue("destination_ip", true),
		http.formvalue("destination_port", true),
		inventory.zones,
		inventory.interfaces,
		inventory.ipv6_pinholes)
	if not update then
		respond(400, { ok = false, error = validation_error })
		return
	end
	local proto = {}
	if protocol == "tcp" or protocol == "tcp udp" then table.insert(proto, "tcp") end
	if protocol == "udp" or protocol == "tcp udp" then table.insert(proto, "udp") end
	local section_ok, section = pcall(uci.section, uci, "firewall", "rule", nil, {
		name = "QuantumGrid IPv6 pinhole: " .. update.name,
		src = update.source,
		dest = update.destination,
		dest_ip = update.destination_ip,
		dest_port = update.destination_port,
		proto = proto,
		family = "ipv6",
		target = "ACCEPT",
		enabled = "1"
	})
	if not section_ok or type(section) ~= "string" or section == "" then
		pcall(uci.revert, uci, "firewall")
		respond(500, { ok = false, error = "The scoped IPv6 firewall rule could not be staged in UCI." })
		return
	end
	local commit_ok, committed = pcall(uci.commit, uci, "firewall")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "firewall")
		respond(500, { ok = false, error = "The IPv6 pinhole could not be committed; firewall reload was not attempted." })
		return
	end
	local reload_ok, reload_status = pcall(sys.call, "/etc/init.d/firewall reload >/dev/null 2>&1")
	if not reload_ok or reload_status ~= 0 then
		local delete_ok, deleted = pcall(uci.delete, uci, "firewall", section)
		local rollback_commit_ok, rollback_committed = false, false
		if delete_ok and deleted == true then
			rollback_commit_ok, rollback_committed = pcall(uci.commit, uci, "firewall")
		end
		local rollback_reload_ok, rollback_reload_status = false, -1
		if rollback_commit_ok and rollback_committed == true then
			rollback_reload_ok, rollback_reload_status = pcall(sys.call, "/etc/init.d/firewall reload >/dev/null 2>&1")
		end
		local rolled_back = delete_ok and deleted == true and rollback_commit_ok
			and rollback_committed == true and rollback_reload_ok and rollback_reload_status == 0
		record_audit(http, "office.ipv6-pinhole.add", section, "failed")
		respond(502, {
			ok = false,
			error = rolled_back
				and "Firewall reload failed. The new IPv6 pinhole was removed."
				or "Firewall reload failed and the IPv6 pinhole rollback could not be confirmed. Inspect firewall configuration and service state locally.",
			rolled_back = rolled_back
		})
		return
	end
	record_audit(http, "office.ipv6-pinhole.add", section, "success")
	respond(nil, {
		ok = true,
		section = section,
		name = update.name,
		source = update.source,
		destination = update.destination,
		protocol = update.protocol,
		destination_ip = update.destination_ip,
		destination_port = tonumber(update.destination_port),
		family = "ipv6",
		reloaded = true,
		rolled_back = false
	})
end

function action_office_ipv6_pinhole_remove()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local validator = require "luci.quantumgrid.office_networks"
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then
			http.status(status, status == 400 and "Bad Request" or
				status == 403 and "Forbidden" or status == 404 and "Not Found" or
				status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
				status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
				"Internal Server Error")
		end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	if http.formvalue("confirmed", true) ~= "1" then
		respond(400, { ok = false, error = "Explicit confirmation is required before removing an IPv6 firewall rule." })
		return
	end
	if fs.access("/etc/config/firewall") ~= true or fs.access("/etc/init.d/firewall") ~= true then
		respond(503, { ok = false, error = "Firewall configuration or native reload service is unavailable." })
		return
	end
	local section = http.formvalue("section", true)
	if type(section) ~= "string" or #section < 1 or #section > 64
		or not section:match("^[%w_.%-]+$") or section == "." or section == ".." then
		respond(400, { ok = false, error = "The firewall IPv6 rule section identifier is invalid." })
		return
	end
	local snapshot_ok, snapshot = pcall(uci.get_all, uci, "firewall", section)
	if not snapshot_ok or type(snapshot) ~= "table" or snapshot[".type"] ~= "rule" then
		respond(404, { ok = false, error = "The selected firewall rule no longer exists." })
		return
	end
	local previous, snapshot_error = validator.snapshot_office_ipv6_pinhole(snapshot)
	if not previous then
		respond(404, { ok = false, error = snapshot_error or "The selected rule is not a QuantumGrid-managed IPv6 pinhole." })
		return
	end
	local delete_ok, deleted = pcall(uci.delete, uci, "firewall", section)
	if not delete_ok or deleted ~= true then
		pcall(uci.revert, uci, "firewall")
		respond(500, { ok = false, error = "The IPv6 firewall rule could not be staged for removal." })
		return
	end
	local commit_ok, committed = pcall(uci.commit, uci, "firewall")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "firewall")
		respond(500, { ok = false, error = "The IPv6 firewall rule removal could not be committed; firewall reload was not attempted." })
		return
	end
	local reload_ok, reload_status = pcall(sys.call, "/etc/init.d/firewall reload >/dev/null 2>&1")
	if not reload_ok or reload_status ~= 0 then
		local restore_ok, restored = pcall(uci.section, uci, "firewall", "rule", section, previous.values)
		local rollback_commit_ok, rollback_committed = false, false
		if restore_ok and restored then
			rollback_commit_ok, rollback_committed = pcall(uci.commit, uci, "firewall")
		end
		local rollback_reload_ok, rollback_reload_status = false, -1
		if rollback_commit_ok and rollback_committed == true then
			rollback_reload_ok, rollback_reload_status = pcall(sys.call, "/etc/init.d/firewall reload >/dev/null 2>&1")
		end
		local rolled_back = restore_ok and restored and rollback_commit_ok
			and rollback_committed == true and rollback_reload_ok and rollback_reload_status == 0
		record_audit(http, "office.ipv6-pinhole.remove", section, "failed")
		respond(502, {
			ok = false,
			error = rolled_back
				and "Firewall reload failed. The original IPv6 pinhole was restored."
				or "Firewall reload failed and the IPv6 pinhole could not be fully restored. Inspect firewall configuration and service state locally.",
			rolled_back = rolled_back
		})
		return
	end
	record_audit(http, "office.ipv6-pinhole.remove", section, "success")
	respond(nil, {
		ok = true,
		section = section,
		removed = true,
		reloaded = true,
		rolled_back = false
	})
end


function action_office_ipv6_pinhole_toggle()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local validator = require "luci.quantumgrid.office_networks"
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then
			http.status(status, status == 400 and "Bad Request" or
				status == 403 and "Forbidden" or status == 404 and "Not Found" or
				status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
				status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
				"Internal Server Error")
		end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	if http.formvalue("confirmed", true) ~= "1" then
		respond(400, { ok = false, error = "Explicit confirmation is required before changing an Internet-facing IPv6 pinhole." })
		return
	end
	if fs.access("/etc/config/firewall") ~= true or fs.access("/etc/init.d/firewall") ~= true then
		respond(503, { ok = false, error = "Firewall configuration or native reload service is unavailable." })
		return
	end
	local section = http.formvalue("section", true)
	if type(section) ~= "string" or #section < 1 or #section > 64
		or not section:match("^[%w_.%-]+$") or section == "." or section == ".." then
		respond(400, { ok = false, error = "The firewall IPv6 rule section identifier is invalid." })
		return
	end
	local requested = http.formvalue("enabled", true)
	if requested ~= "0" and requested ~= "1" then
		respond(400, { ok = false, error = "Enabled state must be explicitly selected." })
		return
	end
	local snapshot_ok, snapshot = pcall(uci.get_all, uci, "firewall", section)
	if not snapshot_ok or type(snapshot) ~= "table" or snapshot[".type"] ~= "rule" then
		respond(404, { ok = false, error = "The selected IPv6 firewall rule no longer exists." })
		return
	end
	local previous, snapshot_error = validator.snapshot_office_ipv6_pinhole(snapshot)
	if not previous then
		respond(404, { ok = false, error = snapshot_error or "The selected rule is not a QuantumGrid-managed IPv6 pinhole." })
		return
	end
	local previous_value = previous.values.enabled
	local previous_enabled = previous_value ~= "0"
	local desired_enabled = requested == "1"
	if previous_enabled == desired_enabled then
		respond(nil, {
			ok = true,
			section = section,
			enabled = desired_enabled,
			changed = false,
			reloaded = false,
			rolled_back = false
		})
		return
	end
	local stage_ok, staged = pcall(uci.set, uci, "firewall", section, "enabled", requested)
	if not stage_ok or staged ~= true then
		pcall(uci.revert, uci, "firewall")
		respond(500, { ok = false, error = "The IPv6 pinhole enabled state could not be staged in UCI." })
		return
	end
	local commit_ok, committed = pcall(uci.commit, uci, "firewall")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "firewall")
		respond(500, { ok = false, error = "The IPv6 pinhole enabled state could not be committed; firewall reload was not attempted." })
		return
	end
	local reload_ok, reload_status = pcall(sys.call, "/etc/init.d/firewall reload >/dev/null 2>&1")
	if not reload_ok or reload_status ~= 0 then
		local restore_ok, restored
		if previous_value == nil then
			restore_ok, restored = pcall(uci.delete, uci, "firewall", section, "enabled")
		else
			restore_ok, restored = pcall(uci.set, uci, "firewall", section, "enabled", previous_value)
		end
		local rollback_commit_ok, rollback_committed = false, false
		if restore_ok and restored == true then
			rollback_commit_ok, rollback_committed = pcall(uci.commit, uci, "firewall")
		end
		local rollback_reload_ok, rollback_reload_status = false, -1
		if rollback_commit_ok and rollback_committed == true then
			rollback_reload_ok, rollback_reload_status = pcall(sys.call, "/etc/init.d/firewall reload >/dev/null 2>&1")
		end
		local rolled_back = restore_ok and restored == true and rollback_commit_ok
			and rollback_committed == true and rollback_reload_ok and rollback_reload_status == 0
		record_audit(http, "office.ipv6-pinhole.toggle", section, "failed")
		respond(502, {
			ok = false,
			error = rolled_back
				and "Firewall reload failed. The previous IPv6 pinhole enabled state was restored."
				or "Firewall reload failed and the previous IPv6 pinhole state could not be confirmed. Inspect firewall configuration and service state locally.",
			rolled_back = rolled_back
		})
		return
	end
	record_audit(http, "office.ipv6-pinhole.toggle", section, "success")
	respond(nil, {
		ok = true,
		section = section,
		enabled = desired_enabled,
		changed = true,
		reloaded = true,
		rolled_back = false
	})
end

function action_dhcp_scope_add()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local validator = require "luci.quantumgrid.office_networks"
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then
			http.status(status, status == 400 and "Bad Request" or
				status == 403 and "Forbidden" or status == 404 and "Not Found" or
				status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
				status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
				"Internal Server Error")
		end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	local confirmed, confirmation_error = validator.validate_reservation_confirmation(
		http.formvalue("confirmed", true))
	if not confirmed then
		respond(400, { ok = false, error = confirmation_error })
		return
	end
	if fs.access("/etc/config/dhcp") ~= true or fs.access("/etc/config/network") ~= true
		or fs.access("/etc/init.d/dnsmasq") ~= true then
		respond(503, { ok = false, error = "DHCP, network configuration or dnsmasq service is unavailable." })
		return
	end

	local network = http.formvalue("network", true)
	if type(network) ~= "string" or #network > 64 or not network:match("^[%w_.%-]+$") then
		respond(400, { ok = false, error = "Select an existing static LAN interface." })
		return
	end
	local network_ok, network_config = pcall(uci.get_all, uci, "network", network)
	if not network_ok or type(network_config) ~= "table" or network_config[".type"] ~= "interface"
		or network_config.proto ~= "static" then
		respond(409, { ok = false, error = "A new DHCP scope can only be added to an existing static IPv4 LAN interface." })
		return
	end
	local interface_address = type(network_config.ipaddr) == "string" and network_config.ipaddr or
		type(network_config.ipaddr) == "table" and network_config.ipaddr[1] or nil
	local netmask = type(network_config.netmask) == "string" and network_config.netmask or nil

	local existing_scope = false
	local scope_ok = pcall(function()
		uci:foreach("dhcp", "dhcp", function(scope)
			if scope.interface == network then existing_scope = true end
		end)
	end)
	if not scope_ok then
		respond(500, { ok = false, error = "Existing DHCP scopes could not be inspected safely." })
		return
	end
	if existing_scope then
		respond(409, { ok = false, error = "This network already has a DHCP scope. Edit or enable that existing scope instead of creating a duplicate." })
		return
	end

	local inventory = office_network_status(uci, fs)
	if inventory.truncated then
		respond(409, { ok = false, error = "The router's network inventory is truncated. Resolve or reduce the inventory before creating a DHCP pool so overlaps can be checked completely." })
		return
	end
	local other_ranges = {}
	for _, scope in ipairs(inventory.dhcp_scopes or {}) do
		if not scope.ignore then
			if scope.range_valid then
				table.insert(other_ranges, { start = scope.pool_start_ip, finish = scope.pool_end_ip })
			else
				respond(409, { ok = false, error = "An existing enabled DHCP scope has an uncalculable address range. Resolve it before creating another pool." })
				return
			end
		end
	end
	local update, validation_error = validator.validate_dhcp_scope_update(
		http.formvalue("start", true),
		http.formvalue("limit", true),
		http.formvalue("leasetime", true),
		interface_address, netmask, other_ranges)
	if not update then
		respond(400, { ok = false, error = validation_error })
		return
	end

	local section_ok, section = pcall(uci.section, uci, "dhcp", "dhcp", nil, {
		interface = network,
		start = update.start,
		limit = update.limit,
		leasetime = update.lease_time
	})
	if not section_ok or type(section) ~= "string" or section == "" then
		pcall(uci.revert, uci, "dhcp")
		respond(500, { ok = false, error = "The new DHCP scope could not be staged in UCI." })
		return
	end
	local commit_ok, committed = pcall(uci.commit, uci, "dhcp")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "dhcp")
		respond(500, { ok = false, error = "The new DHCP scope could not be committed; dnsmasq was not restarted." })
		return
	end

	local reload_ok, reload_status = pcall(sys.call, "/etc/init.d/dnsmasq restart >/dev/null 2>&1")
	if not reload_ok or reload_status ~= 0 then
		local delete_ok, deleted = pcall(uci.delete, uci, "dhcp", section)
		local rollback_commit_ok, rollback_committed = false, false
		if delete_ok and deleted == true then
			rollback_commit_ok, rollback_committed = pcall(uci.commit, uci, "dhcp")
		end
		local rollback_reload_ok, rollback_reload_status = false, -1
		if rollback_commit_ok and rollback_committed == true then
			rollback_reload_ok, rollback_reload_status = pcall(sys.call, "/etc/init.d/dnsmasq restart >/dev/null 2>&1")
		end
		local rolled_back = delete_ok and deleted == true and rollback_commit_ok
			and rollback_committed == true and rollback_reload_ok and rollback_reload_status == 0
		record_audit(http, "dhcp.scope.add", network, "failed")
		respond(502, {
			ok = false,
			error = rolled_back
				and "dnsmasq could not restart. The new DHCP scope was removed and the previous state restored."
				or "dnsmasq restart failed and the new DHCP scope could not be fully removed. Inspect DHCP configuration and service state locally.",
			rolled_back = rolled_back
		})
		return
	end

	record_audit(http, "dhcp.scope.add", section, "success")
	respond(nil, {
		ok = true,
		section = section,
		network = network,
		start = update.start,
		limit = update.limit,
		lease_time = update.lease_time,
		pool_start_ip = update.pool_start_ip,
		pool_end_ip = update.pool_end_ip,
		restarted = true,
		rolled_back = false
	})
end

function action_dhcp_scope_remove()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local validator = require "luci.quantumgrid.office_networks"
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then
			http.status(status, status == 400 and "Bad Request" or
				status == 403 and "Forbidden" or status == 404 and "Not Found" or
				status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
				status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
				"Internal Server Error")
		end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	local confirmed, confirmation_error = validator.validate_reservation_confirmation(
		http.formvalue("confirmed", true))
	if not confirmed then
		respond(400, { ok = false, error = confirmation_error })
		return
	end
	if fs.access("/etc/config/dhcp") ~= true or fs.access("/etc/init.d/dnsmasq") ~= true then
		respond(503, { ok = false, error = "DHCP configuration or dnsmasq service is unavailable." })
		return
	end

	local section, section_error = validator.validate_reservation_section(
		http.formvalue("section", true))
	if not section then
		respond(400, { ok = false, error = section_error })
		return
	end
	local snapshot_ok, snapshot = pcall(uci.get_all, uci, "dhcp", section)
	if not snapshot_ok or type(snapshot) ~= "table" or snapshot[".type"] ~= "dhcp" then
		respond(404, { ok = false, error = "The selected DHCP server scope no longer exists." })
		return
	end
	local previous, snapshot_error = validator.snapshot_dhcp_scope_section(snapshot)
	if not previous then
		respond(500, { ok = false, error = snapshot_error or "The original DHCP scope could not be snapshotted safely." })
		return
	end
	local interface = type(snapshot.interface) == "string" and snapshot.interface or ""
	local scope_name = section
	local delete_ok, deleted = pcall(uci.delete, uci, "dhcp", section)
	if not delete_ok or deleted ~= true then
		pcall(uci.revert, uci, "dhcp")
		respond(500, { ok = false, error = "The DHCP server scope could not be staged for removal." })
		return
	end
	local commit_ok, committed = pcall(uci.commit, uci, "dhcp")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "dhcp")
		respond(500, { ok = false, error = "The DHCP server scope removal could not be committed; dnsmasq was not restarted." })
		return
	end

	local reload_ok, reload_status = pcall(sys.call, "/etc/init.d/dnsmasq restart >/dev/null 2>&1")
	if not reload_ok or reload_status ~= 0 then
		local restore_ok, restored_section = pcall(uci.section, uci, "dhcp", "dhcp", section, previous.values)
		local rollback_commit_ok, rollback_committed = false, false
		if restore_ok and restored_section then
			rollback_commit_ok, rollback_committed = pcall(uci.commit, uci, "dhcp")
		end
		local rollback_reload_ok, rollback_reload_status = false, -1
		if rollback_commit_ok and rollback_committed == true then
			rollback_reload_ok, rollback_reload_status = pcall(sys.call, "/etc/init.d/dnsmasq restart >/dev/null 2>&1")
		end
		local rolled_back = restore_ok and restored_section and rollback_commit_ok
			and rollback_committed == true and rollback_reload_ok and rollback_reload_status == 0
		record_audit(http, "dhcp.scope.remove", scope_name, "failed")
		respond(502, {
			ok = false,
			error = rolled_back
				and "dnsmasq could not restart. The complete DHCP scope was restored and the previous service state recovered."
				or "dnsmasq restart failed and the complete DHCP scope could not be fully restored. Inspect DHCP configuration and service state locally.",
			rolled_back = rolled_back
		})
		return
	end

	record_audit(http, "dhcp.scope.remove", scope_name, "success")
	respond(nil, {
		ok = true,
		section = section,
		interface = interface,
		removed = true,
		restarted = true,
		rolled_back = false
	})
end

function action_dhcp_scope_toggle()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local validator = require "luci.quantumgrid.office_networks"
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then
			http.status(status, status == 400 and "Bad Request" or
				status == 403 and "Forbidden" or status == 404 and "Not Found" or
				status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
				status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
				"Internal Server Error")
		end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	local confirmed, confirmation_error = validator.validate_reservation_confirmation(
		http.formvalue("confirmed", true))
	if not confirmed then
		respond(400, { ok = false, error = confirmation_error })
		return
	end
	if fs.access("/etc/config/dhcp") ~= true or fs.access("/etc/init.d/dnsmasq") ~= true then
		respond(503, { ok = false, error = "DHCP configuration or dnsmasq service is unavailable." })
		return
	end

	local section, section_error = validator.validate_reservation_section(
		http.formvalue("section", true))
	if not section then
		respond(400, { ok = false, error = section_error })
		return
	end
	local requested = http.formvalue("enabled", true)
	if requested ~= "0" and requested ~= "1" then
		respond(400, { ok = false, error = "The DHCP enabled state must be explicitly set to 0 or 1." })
		return
	end
	local requested_enabled = requested == "1"
	local snapshot_ok, snapshot = pcall(uci.get_all, uci, "dhcp", section)
	if not snapshot_ok or type(snapshot) ~= "table" or snapshot[".type"] ~= "dhcp" then
		respond(404, { ok = false, error = "The selected DHCP server scope no longer exists." })
		return
	end
	local previous, snapshot_error = validator.snapshot_dhcp_scope_enabled(snapshot)
	if not previous then
		respond(500, { ok = false, error = snapshot_error or "The original DHCP scope state could not be snapshotted." })
		return
	end
	if previous.enabled == requested_enabled then
		respond(nil, {
			ok = true, section = section, enabled = requested_enabled,
			changed = false, restarted = false, rolled_back = false
		})
		return
	end

	if requested_enabled then
		local network = type(snapshot.interface) == "string" and snapshot.interface or ""
		if network == "" or not network:match("^[%w_.%-]+$") then
			respond(409, { ok = false, error = "The disabled DHCP scope is not attached to a valid network interface." })
			return
		end
		local network_ok, network_config = pcall(uci.get_all, uci, "network", network)
		if not network_ok or type(network_config) ~= "table" or network_config[".type"] ~= "interface"
			or network_config.proto ~= "static" then
			respond(409, { ok = false, error = "Only DHCP scopes attached to existing static IPv4 LAN interfaces can be enabled here." })
			return
		end
		local interface_address = type(network_config.ipaddr) == "string" and network_config.ipaddr or
			type(network_config.ipaddr) == "table" and network_config.ipaddr[1] or nil
		local netmask = type(network_config.netmask) == "string" and network_config.netmask or nil
		local inventory = office_network_status(uci, fs)
		local other_ranges = {}
		for _, scope in ipairs(inventory.dhcp_scopes or {}) do
			if scope.section ~= section and not scope.ignore then
				if scope.range_valid then
					table.insert(other_ranges, { start = scope.pool_start_ip, finish = scope.pool_end_ip })
				elseif scope.interface == network then
					respond(409, { ok = false, error = "Another enabled DHCP scope on this interface has an uncalculable range. Resolve it before enabling this scope." })
					return
				end
			end
		end
		local pool, pool_error = validator.validate_dhcp_pool_range(
			type(snapshot.start) == "string" and snapshot.start or "",
			type(snapshot.limit) == "string" and snapshot.limit or "",
			interface_address, netmask, other_ranges)
		if not pool then
			respond(409, { ok = false, error = "The disabled DHCP scope cannot be safely enabled: " .. tostring(pool_error) })
			return
		end
	end

	local change_ok, change_result
	if requested_enabled then
		change_ok, change_result = pcall(uci.delete, uci, "dhcp", section, "ignore")
	else
		change_ok, change_result = pcall(uci.set, uci, "dhcp", section, "ignore", "1")
	end
	if not change_ok or change_result ~= true then
		pcall(uci.revert, uci, "dhcp")
		respond(500, { ok = false, error = "The DHCP scope state could not be staged; dnsmasq was not restarted." })
		return
	end
	local commit_ok, committed = pcall(uci.commit, uci, "dhcp")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "dhcp")
		respond(500, { ok = false, error = "The DHCP scope state could not be committed; dnsmasq was not restarted." })
		return
	end

	local reload_ok, reload_status = pcall(sys.call, "/etc/init.d/dnsmasq restart >/dev/null 2>&1")
	if not reload_ok or reload_status ~= 0 then
		local restore_ok, restore_result
		if previous.ignore_present then
			restore_ok, restore_result = pcall(uci.set, uci, "dhcp", section, "ignore", previous.ignore_value)
		else
			restore_ok, restore_result = pcall(uci.delete, uci, "dhcp", section, "ignore")
		end
		local rollback_commit_ok, rollback_committed = false, false
		if restore_ok and restore_result == true then
			rollback_commit_ok, rollback_committed = pcall(uci.commit, uci, "dhcp")
		end
		local rollback_reload_ok, rollback_reload_status = false, -1
		if rollback_commit_ok and rollback_committed == true then
			rollback_reload_ok, rollback_reload_status = pcall(sys.call, "/etc/init.d/dnsmasq restart >/dev/null 2>&1")
		end
		local rolled_back = restore_ok and restore_result == true and rollback_commit_ok
			and rollback_committed == true and rollback_reload_ok and rollback_reload_status == 0
		record_audit(http, "dhcp.scope.toggle", section, "failed")
		respond(502, {
			ok = false,
			error = rolled_back
				and "dnsmasq could not restart. The previous DHCP scope enabled state was restored."
				or "dnsmasq restart failed and the previous DHCP scope state could not be fully restored. Inspect DHCP configuration and service state locally.",
			rolled_back = rolled_back
		})
		return
	end

	record_audit(http, "dhcp.scope.toggle", section, "success")
	respond(nil, {
		ok = true, section = section, enabled = requested_enabled,
		changed = true, restarted = true, rolled_back = false
	})
end

function action_dhcp_scope_update()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local validator = require "luci.quantumgrid.office_networks"
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then
			http.status(status, status == 400 and "Bad Request" or
				status == 403 and "Forbidden" or status == 404 and "Not Found" or
				status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
				status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
				"Internal Server Error")
		end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	local confirmed, confirmation_error = validator.validate_reservation_confirmation(
		http.formvalue("confirmed", true))
	if not confirmed then
		respond(400, { ok = false, error = confirmation_error })
		return
	end
	if fs.access("/etc/config/dhcp") ~= true or fs.access("/etc/config/network") ~= true
		or fs.access("/etc/init.d/dnsmasq") ~= true then
		respond(503, { ok = false, error = "DHCP, network configuration or dnsmasq service is unavailable." })
		return
	end

	local section, section_error = validator.validate_reservation_section(
		http.formvalue("section", true))
	if not section then
		respond(400, { ok = false, error = section_error })
		return
	end
	local snapshot_ok, snapshot = pcall(uci.get_all, uci, "dhcp", section)
	if not snapshot_ok or type(snapshot) ~= "table" or snapshot[".type"] ~= "dhcp" then
		respond(404, { ok = false, error = "The selected DHCP server scope no longer exists." })
		return
	end
	if snapshot.ignore == "1" then
		respond(409, { ok = false, error = "Disabled DHCP scopes cannot be edited from this control." })
		return
	end
	local network = type(snapshot.interface) == "string" and snapshot.interface or ""
	if network == "" or not network:match("^[%w_.%-]+$") then
		respond(409, { ok = false, error = "The DHCP scope is not attached to a valid network interface." })
		return
	end
	local network_ok, network_config = pcall(uci.get_all, uci, "network", network)
	if not network_ok or type(network_config) ~= "table"
		or network_config[".type"] ~= "interface" or network_config.proto ~= "static" then
		respond(409, { ok = false, error = "Only scopes attached to existing static IPv4 networks can be edited." })
		return
	end
	local interface_address = type(network_config.ipaddr) == "string" and network_config.ipaddr or
		type(network_config.ipaddr) == "table" and network_config.ipaddr[1] or nil
	local netmask = type(network_config.netmask) == "string" and network_config.netmask or nil

	local inventory = office_network_status(uci, fs)
	if inventory.truncated then
		respond(409, { ok = false, error = "The office network inventory is truncated. Resolve it before modifying DHCP ranges." })
		return
	end
	local other_ranges = {}
	for _, scope_config in ipairs(inventory.dhcp_scopes or {}) do
		if scope_config.section ~= section and not scope_config.ignore then
			if scope_config.range_valid then
				table.insert(other_ranges, {
					start = scope_config.pool_start_ip,
					finish = scope_config.pool_end_ip
				})
			elseif scope_config.interface == network then
				respond(409, { ok = false, error = "Another enabled DHCP scope on this interface has an uncalculable range. Resolve that scope before changing this pool." })
				return
			end
		end
	end

	local update, validation_error = validator.validate_dhcp_scope_update(
		http.formvalue("start", true),
		http.formvalue("limit", true),
		http.formvalue("leasetime", true),
		interface_address,
		netmask,
		other_ranges
	)
	if not update then
		respond(400, { ok = false, error = validation_error })
		return
	end
	local ipv6_modes, ipv6_error = validator.validate_dhcp_scope_ipv6_modes(
		http.formvalue("dhcpv6", true) or "UNCHANGED",
		http.formvalue("ra", true) or "UNCHANGED",
		http.formvalue("ndp", true) or "UNCHANGED")
	if not ipv6_modes then
		respond(400, { ok = false, error = ipv6_error })
		return
	end
	local ipv6_changed = ipv6_modes.dhcpv6 ~= "UNCHANGED"
		or ipv6_modes.ra ~= "UNCHANGED" or ipv6_modes.ndp ~= "UNCHANGED"

	local advanced_ipv6, advanced_error = validator.validate_dhcp_scope_ipv6_advanced(
		http.formvalue("ra_flags", true) or "UNCHANGED",
		http.formvalue("ra_slaac", true) or "UNCHANGED",
		http.formvalue("ra_dns", true) or "UNCHANGED",
		http.formvalue("ra_preference", true) or "UNCHANGED",
		http.formvalue("ra_lifetime", true) or "UNCHANGED",
		http.formvalue("dhcpv6_na", true) or "UNCHANGED",
		http.formvalue("dhcpv6_pd", true) or "UNCHANGED",
		http.formvalue("dhcpv6_assignall", true) or "UNCHANGED",
		http.formvalue("dhcpv6_pd_min_len", true) or "UNCHANGED")
	if not advanced_ipv6 then
		respond(400, { ok = false, error = advanced_error })
		return
	end
	local advanced_values = {
		ra_flags = advanced_ipv6.ra_flags,
		ra_slaac = advanced_ipv6.ra_slaac,
		ra_dns = advanced_ipv6.ra_dns,
		ra_preference = advanced_ipv6.ra_preference,
		ra_lifetime = advanced_ipv6.ra_lifetime,
		dhcpv6_na = advanced_ipv6.dhcpv6_na,
		dhcpv6_pd = advanced_ipv6.dhcpv6_pd,
		dhcpv6_assignall = advanced_ipv6.dhcpv6_assignall,
		dhcpv6_pd_min_len = advanced_ipv6.dhcpv6_pd_min_len
	}
	for _, value in pairs(advanced_values) do
		if value ~= "UNCHANGED" then ipv6_changed = true break end
	end
	if ipv6_changed and fs.access("/etc/init.d/odhcpd") ~= true then
		respond(503, { ok = false, error = "The native odhcpd service is unavailable. IPv6 scope settings were not changed." })
		return
	end

	local previous, snapshot_error = validator.snapshot_dhcp_scope_options(snapshot)
	if not previous then
		respond(500, { ok = false, error = snapshot_error or "The DHCP scope options could not be snapshotted safely." })
		return
	end
	local staged_options = {
		start = update.start,
		limit = update.limit,
		leasetime = update.lease_time
	}
	if ipv6_modes.dhcpv6 ~= "UNCHANGED" then staged_options.dhcpv6 = ipv6_modes.dhcpv6 end
	if ipv6_modes.ra ~= "UNCHANGED" then staged_options.ra = ipv6_modes.ra end
	if ipv6_modes.ndp ~= "UNCHANGED" then staged_options.ndp = ipv6_modes.ndp end
	for option, value in pairs(advanced_values) do
		if value ~= "UNCHANGED" and option ~= "ra_flags" then staged_options[option] = value end
	end
	for option, value in pairs(staged_options) do
		local set_ok, set_result = pcall(uci.set, uci, "dhcp", section, option, value)
		if not set_ok or set_result ~= true then
			pcall(uci.revert, uci, "dhcp")
			respond(500, { ok = false, error = "The DHCP scope update could not be staged; services were not restarted." })
			return
		end
	end
	if advanced_ipv6.ra_flags ~= "UNCHANGED" then
		local flags = {}
		if advanced_ipv6.ra_flags == "managed-config+other-config" then
			flags = { "managed-config", "other-config" }
		elseif advanced_ipv6.ra_flags ~= "none" then
			flags = { advanced_ipv6.ra_flags }
		else
			flags = { "none" }
		end
		local flags_ok, flags_result = pcall(uci.set_list, uci, "dhcp", section, "ra_flags", flags)
		if not flags_ok or flags_result ~= true then
			pcall(uci.revert, uci, "dhcp")
			respond(500, { ok = false, error = "RA flags could not be staged; services were not restarted." })
			return
		end
	end
	local commit_ok, committed = pcall(uci.commit, uci, "dhcp")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "dhcp")
		respond(500, { ok = false, error = "The DHCP scope update could not be committed; services were not restarted." })
		return
	end

	local dnsmasq_reload_ok, dnsmasq_reload_status = pcall(sys.call, "/etc/init.d/dnsmasq restart >/dev/null 2>&1")
	local odhcpd_reload_ok, odhcpd_reload_status = true, 0
	if dnsmasq_reload_ok and dnsmasq_reload_status == 0 and ipv6_changed then
		odhcpd_reload_ok, odhcpd_reload_status = pcall(sys.call, "/etc/init.d/odhcpd restart >/dev/null 2>&1")
	end
	if not dnsmasq_reload_ok or dnsmasq_reload_status ~= 0
		or not odhcpd_reload_ok or odhcpd_reload_status ~= 0 then
		local restored = true
		for _, previous_option in ipairs(previous) do
			local option_ok, option_result
			if previous_option.present then
				if previous_option.name == "ra_flags" and type(previous_option.value) == "table" then
					option_ok, option_result = pcall(uci.set_list, uci, "dhcp", section, previous_option.name, previous_option.value)
				else
					option_ok, option_result = pcall(uci.set, uci, "dhcp", section, previous_option.name, previous_option.value)
				end
			else
				local current = uci:get("dhcp", section, previous_option.name)
				if current == nil then
					option_ok, option_result = true, true
				else
					option_ok, option_result = pcall(uci.delete, uci, "dhcp", section, previous_option.name)
				end
			end
			if not option_ok or option_result ~= true then restored = false break end
		end
		local rollback_commit_ok, rollback_committed = false, false
		if restored then
			rollback_commit_ok, rollback_committed = pcall(uci.commit, uci, "dhcp")
		end
		local rollback_dnsmasq_ok, rollback_dnsmasq_status = false, -1
		local rollback_odhcpd_ok, rollback_odhcpd_status = true, 0
		if rollback_commit_ok and rollback_committed == true then
			rollback_dnsmasq_ok, rollback_dnsmasq_status = pcall(sys.call, "/etc/init.d/dnsmasq restart >/dev/null 2>&1")
			if ipv6_changed then
				rollback_odhcpd_ok, rollback_odhcpd_status = pcall(sys.call, "/etc/init.d/odhcpd restart >/dev/null 2>&1")
			end
		end
		local rolled_back = restored and rollback_commit_ok and rollback_committed == true
			and rollback_dnsmasq_ok and rollback_dnsmasq_status == 0
			and rollback_odhcpd_ok and rollback_odhcpd_status == 0
		record_audit(http, "dhcp.scope.update", section, "failed")
		respond(502, {
			ok = false,
			error = rolled_back
				and "A DHCP service reload failed. The previous IPv4 pool and IPv6 RA/DHCPv6/NDP settings were restored."
				or "A DHCP service reload failed and rollback could not be confirmed. Inspect DHCP, odhcpd and network service state locally.",
			rolled_back = rolled_back
		})
		return
	end

	record_audit(http, "dhcp.scope.update", section, "success")
	respond(nil, {
		ok = true,
		section = section,
		start = update.start,
		limit = update.limit,
		lease_time = update.lease_time,
		pool_start_ip = update.pool_start_ip,
		pool_end_ip = update.pool_end_ip,
		dhcpv6 = uci:get("dhcp", section, "dhcpv6") or "",
		ra = uci:get("dhcp", section, "ra") or "",
		ndp = uci:get("dhcp", section, "ndp") or "",
		ra_flags = uci:get_list("dhcp", section, "ra_flags") or {},
		ra_slaac = uci:get("dhcp", section, "ra_slaac") ~= "0",
		ra_dns = uci:get("dhcp", section, "ra_dns") ~= "0",
		ra_preference = uci:get("dhcp", section, "ra_preference") or "medium",
		ra_lifetime = tonumber(uci:get("dhcp", section, "ra_lifetime")) or 2700,
		dhcpv6_na = uci:get("dhcp", section, "dhcpv6_na") ~= "0",
		dhcpv6_pd = uci:get("dhcp", section, "dhcpv6_pd") ~= "0",
		dhcpv6_assignall = uci:get("dhcp", section, "dhcpv6_assignall") ~= "0",
		dhcpv6_pd_min_len = tonumber(uci:get("dhcp", section, "dhcpv6_pd_min_len")) or 62,
		restarted = true,
		dnsmasq_restarted = true,
		odhcpd_restarted = ipv6_changed,
		rolled_back = false
	})
end


function action_dhcp_reservation()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local validator = require "luci.quantumgrid.office_networks"
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then
			http.status(status, status == 400 and "Bad Request" or
				status == 403 and "Forbidden" or status == 404 and "Not Found" or
				status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
				status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
				"Internal Server Error")
		end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	local confirmed, confirmation_error = validator.validate_reservation_confirmation(
		http.formvalue("confirmed", true))
	if not confirmed then
		respond(400, { ok = false, error = confirmation_error })
		return
	end
	if fs.access("/etc/config/dhcp") ~= true or fs.access("/etc/config/network") ~= true then
		respond(503, { ok = false, error = "DHCP and network configuration files must both be available." })
		return
	end
	if fs.access("/etc/init.d/dnsmasq") ~= true then
		respond(503, { ok = false, error = "The native dnsmasq service is unavailable." })
		return
	end

	local reservation, validation_error = validator.validate_reservation(
		http.formvalue("name", true),
		http.formvalue("mac", true),
		http.formvalue("ipv4", true))
	if not reservation then
		respond(400, { ok = false, error = validation_error })
		return
	end
	local network = http.formvalue("network", true)
	if type(network) ~= "string" or #network > 64
		or not network:match("^[%w_.%-]+$") then
		respond(400, { ok = false, error = "Select an existing static LAN network." })
		return
	end

	local interface_address, netmask, protocol
	local interface_ok = pcall(function()
		uci:foreach("network", "interface", function(section)
			if section[".name"] == network then
				interface_address = type(section.ipaddr) == "string" and section.ipaddr or
					type(section.ipaddr) == "table" and section.ipaddr[1] or nil
				netmask = section.netmask
				protocol = section.proto
			end
		end)
	end)
	if not interface_ok or protocol ~= "static" or type(interface_address) ~= "string"
		or type(netmask) ~= "string" then
		respond(400, { ok = false, error = "Reservations are available only on an existing static IPv4 network with a readable netmask." })
		return
	end
	if not validator.ipv4_in_subnet(reservation.ipv4, interface_address, netmask) then
		respond(400, { ok = false, error = "The reserved IPv4 address must be a usable host address inside the selected network subnet." })
		return
	end

	local dhcp_scope = false
	local dhcp_ok = pcall(function()
		uci:foreach("dhcp", "dhcp", function(section)
			if section.interface == network and section.ignore ~= "1" then dhcp_scope = true end
		end)
	end)
	if not dhcp_ok or not dhcp_scope then
		respond(409, { ok = false, error = "The selected network does not have an enabled DHCP server scope." })
		return
	end

	local duplicate_mac, duplicate_ip = false, false
	local duplicate_ok = pcall(function()
		uci:foreach("dhcp", "host", function(section)
			local existing_mac = type(section.mac) == "string" and section.mac:lower() or ""
			if existing_mac == reservation.mac then duplicate_mac = true end
			if section.ip == reservation.ipv4 then duplicate_ip = true end
		end)
	end)
	if not duplicate_ok then
		respond(500, { ok = false, error = "Existing DHCP reservations could not be checked safely." })
		return
	end
	if duplicate_mac or duplicate_ip then
		respond(409, {
			ok = false,
			error = duplicate_mac and "This MAC address already has a DHCP reservation." or
				"This IPv4 address is already reserved by another DHCP host."
		})
		return
	end

	local leases = read_file("/tmp/dhcp.leases") or ""
	if validator.live_lease_conflict(leases, reservation.ipv4, reservation.mac) then
		respond(409, { ok = false, error = "The selected IPv4 address is currently leased to a different MAC address." })
		return
	end

	local qos = require "luci.quantumgrid.qos"
	local existing_policies, policies_truncated, policies_error = qos.read_client_policies(uci, 32)
	if not existing_policies then
		respond(500, { ok = false, error = policies_error or "Existing client QoS policies could not be checked safely." })
		return
	end
	if policies_truncated then
		respond(409, { ok = false, error = "The client QoS inventory is truncated. Resolve it before creating a reservation that could activate download marking." })
		return
	end
	if qos.find_download_policy_conflict(existing_policies, reservation.mac, reservation.ipv4) then
		respond(409, { ok = false, error = "A QuantumGrid download DSCP rule already references this client MAC or IPv4 address. Remove or correct that policy before creating this reservation." })
		return
	end

	local section_ok, section = pcall(uci.section, uci, "dhcp", "host", nil, {
		name = reservation.name,
		mac = reservation.mac,
		ip = reservation.ipv4,
		dns = "1"
	})
	if not section_ok or type(section) ~= "string" or section == "" then
		pcall(uci.revert, uci, "dhcp")
		respond(500, { ok = false, error = "The DHCP reservation could not be staged in UCI." })
		return
	end

	local commit_ok, committed = pcall(uci.commit, uci, "dhcp")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "dhcp")
		respond(500, { ok = false, error = "The DHCP reservation could not be committed; dnsmasq was not restarted." })
		return
	end

	local reload_ok, reload_status = pcall(sys.call, "/etc/init.d/dnsmasq restart >/dev/null 2>&1")
	if not reload_ok or reload_status ~= 0 then
		local delete_ok, deleted = pcall(uci.delete, uci, "dhcp", section)
		local rollback_commit_ok, rollback_committed = false, false
		if delete_ok and deleted == true then
			rollback_commit_ok, rollback_committed = pcall(uci.commit, uci, "dhcp")
		end
		local rollback_reload_ok, rollback_reload_status = false, -1
		if rollback_commit_ok and rollback_committed == true then
			rollback_reload_ok, rollback_reload_status = pcall(sys.call, "/etc/init.d/dnsmasq restart >/dev/null 2>&1")
		end
		local rolled_back = rollback_commit_ok and rollback_committed == true
			and rollback_reload_ok and rollback_reload_status == 0
		record_audit(http, "dhcp.reservation.add", network, "failed")
		respond(502, {
			ok = false,
			error = rolled_back
				and "dnsmasq could not restart. The new reservation was removed and the previous state restored."
				or "dnsmasq failed to restart and rollback could not be confirmed. Inspect DHCP configuration and service state locally.",
			rolled_back = rolled_back
		})
		return
	end

	record_audit(http, "dhcp.reservation.add", network, "success")
	respond(nil, {
		ok = true,
		section = section,
		name = reservation.name,
		mac = reservation.mac,
		ipv4 = reservation.ipv4,
		network = network,
		restarted = true,
		rolled_back = false
	})
end


function action_dhcp_reservation_update()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local validator = require "luci.quantumgrid.office_networks"
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then
			http.status(status, status == 400 and "Bad Request" or
				status == 403 and "Forbidden" or status == 404 and "Not Found" or
				status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
				status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
				"Internal Server Error")
		end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	local confirmed, confirmation_error = validator.validate_reservation_confirmation(
		http.formvalue("confirmed", true))
	if not confirmed then
		respond(400, { ok = false, error = confirmation_error })
		return
	end
	if fs.access("/etc/config/dhcp") ~= true or fs.access("/etc/config/network") ~= true
		or fs.access("/etc/init.d/dnsmasq") ~= true then
		respond(503, { ok = false, error = "DHCP, network configuration or dnsmasq service is unavailable." })
		return
	end

	local section, section_error = validator.validate_reservation_section(
		http.formvalue("section", true))
	if not section then
		respond(400, { ok = false, error = section_error })
		return
	end
	local snapshot_ok, snapshot = pcall(uci.get_all, uci, "dhcp", section)
	if not snapshot_ok or type(snapshot) ~= "table" or snapshot[".type"] ~= "host" then
		respond(404, { ok = false, error = "The selected DHCP host reservation no longer exists." })
		return
	end
	local previous, snapshot_error = validator.snapshot_dhcp_host_options(snapshot)
	if not previous then
		respond(500, { ok = false, error = snapshot_error or "The original reservation could not be snapshotted safely." })
		return
	end

	local reservation, validation_error = validator.validate_reservation(
		http.formvalue("name", true),
		http.formvalue("mac", true),
		http.formvalue("ipv4", true))
	if not reservation then
		respond(400, { ok = false, error = validation_error })
		return
	end
	local previous_mac = type(snapshot.mac) == "string" and snapshot.mac:lower() or ""
	local previous_ipv4 = type(snapshot.ip) == "string" and snapshot.ip or ""
	if previous_mac ~= reservation.mac or previous_ipv4 ~= reservation.ipv4 then
		local qos = require "luci.quantumgrid.qos"
		local existing_policies, policies_truncated, policies_error = qos.read_client_policies(uci, 32)
		if not existing_policies then
			respond(500, { ok = false, error = policies_error or "Existing client QoS policies could not be checked safely." })
			return
		end
		if policies_truncated then
			respond(409, { ok = false, error = "The client QoS inventory is truncated. Resolve it before changing a reservation used by download marking." })
			return
		end
		if qos.find_download_reservation_policy(existing_policies, previous_mac, previous_ipv4) then
			respond(409, { ok = false, error = "This static reservation is referenced by a download DSCP policy. Remove that policy before changing the reserved MAC or IPv4 address." })
			return
		end
	end
	local network = http.formvalue("network", true)
	if type(network) ~= "string" or #network > 64 or not network:match("^[%w_.%-]+$") then
		respond(400, { ok = false, error = "Select an existing static LAN network for subnet validation." })
		return
	end
	local network_ok, network_config = pcall(uci.get_all, uci, "network", network)
	if not network_ok or type(network_config) ~= "table" or network_config[".type"] ~= "interface"
		or network_config.proto ~= "static" then
		respond(409, { ok = false, error = "Reservations can only be validated against an existing static IPv4 LAN interface." })
		return
	end
	local interface_address = type(network_config.ipaddr) == "string" and network_config.ipaddr or
		type(network_config.ipaddr) == "table" and network_config.ipaddr[1] or nil
	local netmask = type(network_config.netmask) == "string" and network_config.netmask or nil
	if not interface_address or not netmask or not validator.ipv4_in_subnet(reservation.ipv4, interface_address, netmask) then
		respond(400, { ok = false, error = "The reserved IPv4 address must be a usable host address inside the selected LAN subnet." })
		return
	end
	local scope_exists = false
	local scope_ok = pcall(function()
		uci:foreach("dhcp", "dhcp", function(scope)
			if scope.interface == network and scope.ignore ~= "1" then scope_exists = true end
		end)
	end)
	if not scope_ok or not scope_exists then
		respond(409, { ok = false, error = "The selected LAN does not have an enabled DHCP scope." })
		return
	end

	local duplicate_mac, duplicate_ip, duplicate_name = false, false, false
	local duplicate_ok = pcall(function()
		uci:foreach("dhcp", "host", function(existing)
			if existing[".name"] ~= section then
				local existing_mac = type(existing.mac) == "string" and existing.mac:lower() or ""
				if existing_mac == reservation.mac then duplicate_mac = true end
				if existing.ip == reservation.ipv4 then duplicate_ip = true end
				if type(existing.name) == "string" and existing.name:lower() == reservation.name:lower() then duplicate_name = true end
			end
		end)
	end)
	if not duplicate_ok then
		respond(500, { ok = false, error = "Existing DHCP reservations could not be checked safely." })
		return
	end
	if duplicate_mac or duplicate_ip or duplicate_name then
		respond(409, {
			ok = false,
			error = duplicate_mac and "This MAC address already belongs to another DHCP reservation." or
				duplicate_ip and "This IPv4 address is already reserved by another DHCP host." or
				"This host name is already used by another DHCP reservation."
		})
		return
	end
	local leases = read_file("/tmp/dhcp.leases") or ""
	if validator.live_lease_conflict(leases, reservation.ipv4, reservation.mac) then
		respond(409, { ok = false, error = "The selected IPv4 address is currently leased to a different MAC address." })
		return
	end

	for _, value in ipairs({
		{ name = "name", value = reservation.name },
		{ name = "mac", value = reservation.mac },
		{ name = "ip", value = reservation.ipv4 }
	}) do
		local set_ok, set_result = pcall(uci.set, uci, "dhcp", section, value.name, value.value)
		if not set_ok or set_result ~= true then
			pcall(uci.revert, uci, "dhcp")
			respond(500, { ok = false, error = "The DHCP reservation update could not be staged; dnsmasq was not restarted." })
			return
		end
	end
	local commit_ok, committed = pcall(uci.commit, uci, "dhcp")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "dhcp")
		respond(500, { ok = false, error = "The DHCP reservation update could not be committed; dnsmasq was not restarted." })
		return
	end

	local reload_ok, reload_status = pcall(sys.call, "/etc/init.d/dnsmasq restart >/dev/null 2>&1")
	if not reload_ok or reload_status ~= 0 then
		local restored = true
		for _, previous_option in ipairs(previous) do
			local option_ok, option_result
			if previous_option.present then
				option_ok, option_result = pcall(uci.set, uci, "dhcp", section, previous_option.name, previous_option.value)
			else
				option_ok, option_result = pcall(uci.delete, uci, "dhcp", section, previous_option.name)
			end
			if not option_ok or option_result ~= true then restored = false break end
		end
		local rollback_commit_ok, rollback_committed = false, false
		if restored then rollback_commit_ok, rollback_committed = pcall(uci.commit, uci, "dhcp") end
		local rollback_reload_ok, rollback_reload_status = false, -1
		if rollback_commit_ok and rollback_committed == true then
			rollback_reload_ok, rollback_reload_status = pcall(sys.call, "/etc/init.d/dnsmasq restart >/dev/null 2>&1")
		end
		local rolled_back = restored and rollback_commit_ok and rollback_committed == true
			and rollback_reload_ok and rollback_reload_status == 0
		record_audit(http, "dhcp.reservation.update", "dhcp-host", "failed")
		respond(502, {
			ok = false,
			error = rolled_back
				and "dnsmasq could not restart. The original DHCP reservation was restored."
				or "dnsmasq restart failed and the original reservation could not be fully restored. Inspect DHCP configuration and service state locally.",
			rolled_back = rolled_back
		})
		return
	end

	record_audit(http, "dhcp.reservation.update", "dhcp-host", "success")
	respond(nil, {
		ok = true,
		section = section,
		name = reservation.name,
		mac = reservation.mac,
		ipv4 = reservation.ipv4,
		network = network,
		restarted = true,
		rolled_back = false
	})
end

function action_dhcp_reservation_remove()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local validator = require "luci.quantumgrid.office_networks"
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	local function respond(status, payload)
		if status then
			http.status(status, status == 400 and "Bad Request" or
				status == 403 and "Forbidden" or status == 404 and "Not Found" or
				status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
				status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
				"Internal Server Error")
		end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	local confirmed, confirmation_error = validator.validate_reservation_confirmation(
		http.formvalue("confirmed", true))
	if not confirmed then
		respond(400, { ok = false, error = confirmation_error })
		return
	end
	if fs.access("/etc/config/dhcp") ~= true or fs.access("/etc/init.d/dnsmasq") ~= true then
		respond(503, { ok = false, error = "DHCP configuration or dnsmasq service is unavailable." })
		return
	end

	local section, section_error = validator.validate_reservation_section(
		http.formvalue("section", true))
	if not section then
		respond(400, { ok = false, error = section_error })
		return
	end
	local snapshot_ok, snapshot = pcall(uci.get_all, uci, "dhcp", section)
	if not snapshot_ok or type(snapshot) ~= "table" or snapshot[".type"] ~= "host" then
		respond(404, { ok = false, error = "The selected DHCP host reservation no longer exists." })
		return
	end
	local mac = type(snapshot.mac) == "string" and snapshot.mac:lower() or ""
	local ipv4 = type(snapshot.ip) == "string" and snapshot.ip or ""
	local name = type(snapshot.name) == "string" and snapshot.name or section
	if mac == "" or ipv4 == "" then
		respond(409, { ok = false, error = "The selected UCI host section is not a valid static IPv4 reservation." })
		return
	end

	local qos = require "luci.quantumgrid.qos"
	local existing_policies, policies_truncated, policies_error = qos.read_client_policies(uci, 32)
	if not existing_policies then
		respond(500, { ok = false, error = policies_error or "Existing client QoS policies could not be checked safely." })
		return
	end
	if policies_truncated then
		respond(409, { ok = false, error = "The client QoS inventory is truncated. Resolve it before removing a reservation used by download marking." })
		return
	end
	if qos.find_download_reservation_policy(existing_policies, mac, ipv4) then
		respond(409, { ok = false, error = "This static reservation is referenced by a download DSCP policy. Remove that policy before removing the reservation." })
		return
	end

	local restore_values = {}
	for key, value in pairs(snapshot) do
		if key ~= ".name" and key ~= ".type" and key ~= ".anonymous" then
			restore_values[key] = value
		end
	end
	local delete_ok, deleted = pcall(uci.delete, uci, "dhcp", section)
	if not delete_ok or deleted ~= true then
		pcall(uci.revert, uci, "dhcp")
		respond(500, { ok = false, error = "The DHCP reservation could not be staged for removal." })
		return
	end
	local commit_ok, committed = pcall(uci.commit, uci, "dhcp")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "dhcp")
		respond(500, { ok = false, error = "The DHCP reservation removal could not be committed; dnsmasq was not restarted." })
		return
	end

	local reload_ok, reload_status = pcall(sys.call, "/etc/init.d/dnsmasq restart >/dev/null 2>&1")
	if not reload_ok or reload_status ~= 0 then
		local restore_ok, restored_section = pcall(uci.section, uci, "dhcp", "host", section, restore_values)
		local restore_commit_ok, restore_committed = false, false
		if restore_ok and restored_section then
			restore_commit_ok, restore_committed = pcall(uci.commit, uci, "dhcp")
		end
		local rollback_reload_ok, rollback_reload_status = false, -1
		if restore_commit_ok and restore_committed == true then
			rollback_reload_ok, rollback_reload_status = pcall(sys.call, "/etc/init.d/dnsmasq restart >/dev/null 2>&1")
		end
		local rolled_back = restore_commit_ok and restore_committed == true
			and rollback_reload_ok and rollback_reload_status == 0
		record_audit(http, "dhcp.reservation.remove", "dhcp-host", "failed")
		respond(502, {
			ok = false,
			error = rolled_back
				and "dnsmasq could not restart. The reservation was restored and the previous service state recovered."
				or "dnsmasq restart failed and the original reservation could not be fully restored. Inspect DHCP configuration and service state locally.",
			rolled_back = rolled_back
		})
		return
	end

	record_audit(http, "dhcp.reservation.remove", "dhcp-host", "success")
	respond(nil, {
		ok = true,
		section = section,
		name = name,
		mac = mac,
		ipv4 = ipv4,
		removed = true,
		restarted = true,
		rolled_back = false
	})
end

function action_remote_syslog_update()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local validator = require "luci.quantumgrid.remote_syslog"
	local host_header = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"
	local tunnel_name = "quantumgrid_syslog"
	local managed_tunnel_options = {
		"enabled", "client", "accept_host", "accept_port", "CAfile",
		"verifyChain", "sslVersion", "TIMEOUTconnect", "retry", "connect", "checkHost", "checkIP", "sni"
	}
	local tunnel_list_options = { connect = true, checkHost = true, checkIP = true, sni = true }
	local system_log_options = { "log_ip", "log_port", "log_proto", "log_remote", "log_hostname", "log_prefix" }

	local function respond(status, payload)
		if status then
			http.status(status, status == 400 and "Bad Request" or
				status == 403 and "Forbidden" or status == 404 and "Not Found" or
				status == 405 and "Method Not Allowed" or status == 502 and "Bad Gateway" or
				status == 503 and "Service Unavailable" or "Internal Server Error")
		end
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json(payload)
	end

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		respond(405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not host_header or origin ~= scheme .. "://" .. host_header then
		respond(403, { ok = false, error = "A same-origin request is required." })
		return
	end
	if fs.access("/etc/config/system") ~= true or fs.access("/etc/init.d/log") ~= true then
		respond(503, { ok = false, error = "Native OpenWrt system logging configuration or service is unavailable." })
		return
	end

	local update, validation_error = validator.validate({
		confirmed = http.formvalue("confirmed", true),
		enabled = http.formvalue("enabled", true),
		host = http.formvalue("host", true) or "",
		port = http.formvalue("port", true) or "",
		protocol = http.formvalue("protocol", true),
		hostname = http.formvalue("hostname", true) or "",
		prefix = http.formvalue("prefix", true) or ""
	})
	if not update then
		respond(400, { ok = false, error = validation_error })
		return
	end

	local section_name = nil
	local section_lookup_ok = pcall(function()
		uci:foreach("system", "system", function(section)
			if not section_name then section_name = section[".name"] end
		end)
	end)
	if not section_lookup_ok or type(section_name) ~= "string" or section_name == "" then
		respond(503, { ok = false, error = "No existing system UCI section is available for remote logging settings." })
		return
	end
	local snapshot_ok, snapshot = pcall(uci.get_all, uci, "system", section_name)
	if not snapshot_ok or type(snapshot) ~= "table" or snapshot[".type"] ~= "system" then
		respond(503, { ok = false, error = "The existing system UCI section could not be read safely." })
		return
	end

	local stunnel_installed = fs.access("/etc/init.d/stunnel") == true
	local stunnel_config_available = fs.access("/etc/config/stunnel") == true
	local ca_bundle_available = fs.access("/etc/ssl/certs/ca-certificates.crt") == true
	if update.tls and (not stunnel_installed or not stunnel_config_available or not ca_bundle_available) then
		respond(503, {
			ok = false,
			error = "Authenticated TLS syslog requires the stunnel service, its UCI configuration and the trusted CA bundle. No logging settings were changed."
		})
		return
	end
	if update.tls then
		local globals_ok, globals = pcall(uci.get_all, uci, "stunnel", "globals")
		if not globals_ok or not validator.has_non_root_privilege_drop(globals) then
			respond(503, {
				ok = false,
				error = "TLS syslog requires stunnel global setuid and setgid options to name non-root identities. No logging settings were changed."
			})
			return
		end
	end

	local tunnel_snapshot = nil
	local tunnel_snapshot_exists = false
	if stunnel_config_available then
		local tunnel_read_ok, tunnel_value = pcall(uci.get_all, uci, "stunnel", tunnel_name)
		if not tunnel_read_ok then
			respond(503, { ok = false, error = "The managed TLS logging section could not be inspected safely." })
			return
		end
		if type(tunnel_value) == "table" then
			if not validator.has_only_managed_service_options(tunnel_value) then
				respond(503, { ok = false, error = "The reserved QuantumGrid TLS logging section has an incompatible type or unmanaged directives. No configuration was changed." })
				return
			end
			tunnel_snapshot_exists = true
			tunnel_snapshot = {}
			for _, option in ipairs(managed_tunnel_options) do
				tunnel_snapshot[option] = tunnel_value[option]
			end
		end
	end

	local previous = {
		log_ip = snapshot.log_ip,
		log_port = snapshot.log_port,
		log_proto = snapshot.log_proto,
		log_remote = snapshot.log_remote,
		log_hostname = snapshot.log_hostname,
		log_prefix = snapshot.log_prefix
	}
	local previous_tunnel_enabled = tunnel_snapshot_exists and tunnel_snapshot.enabled == "1"
	local tunnel_changed = update.tls == true or previous_tunnel_enabled
	local tunnel_restart_required = tunnel_changed and stunnel_installed
	local tunnel_options = update.tls and validator.stunnel_options(update) or nil
	if update.tls and (type(tunnel_options) ~= "table" or type(tunnel_options.scalars) ~= "table" or
		type(tunnel_options.lists) ~= "table") then
		respond(400, { ok = false, error = "The TLS syslog client configuration could not be generated safely." })
		return
	end

	local desired = { log_remote = update.enabled and "1" or "0" }
	if update.enabled then
		if update.tls then
			desired.log_ip = "127.0.0.1"
			desired.log_port = "5514"
			desired.log_proto = "tcp"
		else
			desired.log_ip = update.host
			desired.log_port = update.port
			desired.log_proto = update.protocol
		end
		desired.log_hostname = update.hostname
		desired.log_prefix = update.prefix
	end

	local function set_option(package, section, option, value)
		local ok, result
		if value == nil or value == "" then
			ok, result = pcall(uci.delete, uci, package, section, option)
			return ok and result ~= false
		end
		ok, result = pcall(uci.set, uci, package, section, option, value)
		return ok and result == true
	end

	local function set_list(package, section, option, values)
		if type(values) ~= "table" then return false end
		local ok, result = pcall(uci.set_list, uci, package, section, option, values)
		return ok and result == true
	end

	local function restore_system()
		local restored = true
		for _, option in ipairs(system_log_options) do
			local value = previous[option]
			local option_ok, option_result
			if value == nil then
				option_ok, option_result = pcall(uci.delete, uci, "system", section_name, option)
				if not option_ok or option_result == false then restored = false end
			else
				option_ok, option_result = pcall(uci.set, uci, "system", section_name, option, value)
				if not option_ok or option_result ~= true then restored = false end
			end
		end
		local commit_ok, committed = false, false
		if restored then commit_ok, committed = pcall(uci.commit, uci, "system") end
		return restored and commit_ok and committed == true
	end

	local function restore_stunnel()
		if not tunnel_changed then return true end
		local restored = true
		if not tunnel_snapshot_exists then
			local delete_ok, delete_result = pcall(uci.delete, uci, "stunnel", tunnel_name)
			restored = delete_ok and delete_result ~= false
		else
			for _, option in ipairs(managed_tunnel_options) do
				local value = tunnel_snapshot[option]
				if tunnel_list_options[option] then
					local values = type(value) == "table" and value or
						(type(value) == "string" and { value } or {})
					if not set_list("stunnel", tunnel_name, option, values) then
						restored = false
					end
				else
					if not set_option("stunnel", tunnel_name, option, value) then restored = false end
				end
			end
		end
		local commit_ok, committed = false, false
		if restored then commit_ok, committed = pcall(uci.commit, uci, "stunnel") end
		return restored and commit_ok and committed == true
	end

	local function rollback_all()
		pcall(uci.revert, uci, "system")
		if tunnel_changed then pcall(uci.revert, uci, "stunnel") end
		local tunnel_restored = restore_stunnel()
		local system_restored = restore_system()
		local tunnel_restarted = true
		if tunnel_restart_required then
			local restart_ok, restart_status = pcall(sys.call, "/etc/init.d/stunnel restart >/dev/null 2>&1")
			tunnel_restarted = restart_ok and restart_status == 0
		end
		local log_ok, log_status = pcall(sys.call, "/etc/init.d/log restart >/dev/null 2>&1")
		local log_restarted = log_ok and log_status == 0
		return tunnel_restored and system_restored and tunnel_restarted and log_restarted
	end

	for option, value in pairs(desired) do
		if not set_option("system", section_name, option, value) then
			pcall(uci.revert, uci, "system")
			respond(500, { ok = false, error = "Remote syslog settings could not be staged; services were not restarted." })
			return
		end
	end

	if tunnel_changed then
		if update.tls then
			if not tunnel_snapshot_exists then
				local section_ok, section_result = pcall(uci.section, uci, "stunnel", "service", tunnel_name, {})
				if not section_ok or not section_result then
					pcall(uci.revert, uci, "system")
					pcall(uci.revert, uci, "stunnel")
					respond(500, { ok = false, error = "The managed TLS logging service section could not be created." })
					return
				end
			end
			for option, value in pairs(tunnel_options.scalars) do
				if not set_option("stunnel", tunnel_name, option, value) then
					pcall(uci.revert, uci, "system")
					pcall(uci.revert, uci, "stunnel")
					respond(500, { ok = false, error = "The TLS logging service options could not be staged." })
					return
				end
			end
			for option, values in pairs(tunnel_options.lists) do
				if not set_list("stunnel", tunnel_name, option, values) then
					pcall(uci.revert, uci, "system")
					pcall(uci.revert, uci, "stunnel")
					respond(500, { ok = false, error = "The TLS server identity or connection list could not be staged." })
					return
				end
			end
		else
			if not set_option("stunnel", tunnel_name, "enabled", "0") then
				pcall(uci.revert, uci, "system")
				pcall(uci.revert, uci, "stunnel")
				respond(500, { ok = false, error = "The previous TLS logging tunnel could not be disabled safely." })
				return
			end
		end
	end

	local tunnel_commit_ok, tunnel_committed = true, true
	if tunnel_changed then
		tunnel_commit_ok, tunnel_committed = pcall(uci.commit, uci, "stunnel")
	end
	if not tunnel_commit_ok or tunnel_committed ~= true then
		local rolled_back = rollback_all()
		record_audit(http, "system.syslog.update", "remote-syslog", "failed")
		respond(500, {
			ok = false,
			error = rolled_back and
				"The TLS logging configuration could not be committed. The previous settings were restored."
				or "The TLS logging configuration could not be committed and rollback could not be confirmed. Inspect the system and stunnel UCI configurations locally.",
			rolled_back = rolled_back
		})
		return
	end

	local commit_ok, committed = pcall(uci.commit, uci, "system")
	if not commit_ok or committed ~= true then
		local rolled_back = rollback_all()
		respond(500, {
			ok = false,
			error = rolled_back and
				"The remote logging configuration could not be committed; the previous settings were restored."
				or "The remote logging commit and rollback could not be confirmed. Inspect the system and stunnel UCI configurations locally.",
			rolled_back = rolled_back
		})
		return
	end

	if tunnel_restart_required then
		local restart_ok, restart_status = pcall(sys.call, "/etc/init.d/stunnel restart >/dev/null 2>&1")
		if not restart_ok or restart_status ~= 0 then
			local rolled_back = rollback_all()
			record_audit(http, "system.syslog.update", "remote-syslog", "failed")
			respond(502, {
				ok = false,
				error = rolled_back and
					"The TLS tunnel could not start. The previous remote logging settings were restored."
					or "The TLS tunnel failed to start and rollback could not be confirmed. Inspect the stunnel and system logging services locally.",
				rolled_back = rolled_back
			})
			return
		end
	end

	local restart_ok, restart_status = pcall(sys.call, "/etc/init.d/log restart >/dev/null 2>&1")
	if not restart_ok or restart_status ~= 0 then
		local rolled_back = rollback_all()
		record_audit(http, "system.syslog.update", "remote-syslog", "failed")
		respond(502, {
			ok = false,
			error = rolled_back and
				"The log service could not restart. The previous remote syslog settings were restored."
				or "The log service failed to restart and its previous settings could not be fully restored. Inspect the system and stunnel services locally.",
			rolled_back = rolled_back
		})
		return
	end

	local resulting = remote_syslog_status(uci, fs)
	local tls_ready = true
	if update.tls then
		local nixio = require "nixio"
		resulting, tls_ready = validator.wait_for_ready(
			function() return remote_syslog_status(uci, fs) end,
			function() return nixio.nanosleep(0, 200000000) end,
			update.host, update.port, 10
		)
	end
	if update.tls and (not tls_ready or resulting == nil or resulting.enabled ~= true or
		resulting.tls_status ~= "ready" or resulting.host ~= update.host or
		resulting.port ~= tonumber(update.port)) then
		local rolled_back = rollback_all()
		record_audit(http, "system.syslog.update", "remote-syslog", "failed")
		respond(502, {
			ok = false,
			error = rolled_back and
				"The TLS service restarted but its live process, exact destination or verified trust configuration could not be confirmed. Previous settings were restored."
				or "The TLS service did not reach the required live posture and rollback could not be confirmed. Inspect system and stunnel configuration and services locally.",
			tls_status = type(resulting) == "table" and resulting.tls_status or "unknown",
			rolled_back = rolled_back
		})
		return
	end

	record_audit(http, "system.syslog.update", "remote-syslog", "success")
	respond(nil, {
		ok = true,
		enabled = resulting.enabled,
		host = resulting.host,
		port = resulting.port,
		protocol = resulting.protocol,
		hostname = resulting.hostname,
		prefix = resulting.prefix,
		tls_status = resulting.tls_status,
		restarted = true,
		rolled_back = false
	})
end


function action_audit_log()
	local http = require "luci.http"
	local jsonc = require "luci.jsonc"
	local audit = require "luci.quantumgrid.audit"
	local MAX_SOURCE_BYTES = 512 * 1024

	local function read_audit_tail(path)
		local file = io.open(path, "r")
		if not file then return "", false end
		local size = file:seek("end") or 0
		local truncated = size > MAX_SOURCE_BYTES
		if truncated then file:seek("set", size - MAX_SOURCE_BYTES) end
		local contents = file:read("*a") or ""
		file:close()
		return contents, truncated
	end

	if http.getenv("REQUEST_METHOD") ~= "GET" then
		http.status(405, "Method Not Allowed")
		http.header("Cache-Control", "no-store")
		http.prepare_content("application/json; charset=UTF-8")
		http.write_json({ ok = false, error = "GET is required." })
		return
	end

	local path = audit.log_path()
	local rotated, rotated_truncated = read_audit_tail(path .. ".1")
	local current, current_truncated = read_audit_tail(path)
	local available = rotated ~= "" or current ~= ""
	local parsed = audit.parse_log(rotated .. "\n" .. current, function(line)
		return jsonc.parse(line)
	end)
	http.header("Cache-Control", "no-store")
	http.prepare_content("application/json; charset=UTF-8")
	http.write_json({
		ok = true,
		available = available,
		events = parsed.events,
		count = parsed.count,
		truncated = parsed.truncated or rotated_truncated or current_truncated,
		sampled_at = os.time()
	})
end

function action_api()
	local http = require "luci.http"
	local sys = require "luci.sys"
	local root_hash = sys.user.getpasswd("root")
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
	local mwan3 = mwan3_status(uci, fs)
	local security = security_status(uci, fs)
	local platform = platform_status(fs)
	local conntrack = conntrack_status(fs)
	local route_inventory = default_route_inventory(fs)
	local static_routes = static_route_inventory(uci, fs)
	local rule_inventory = policy_rule_inventory(fs)
	local hardware_io = hardware_io_status(fs)
	local office_networks = office_network_status(uci, fs)
	local remote_syslog = remote_syslog_status(uci, fs)
	local usteer = usteer_status(uci, fs)

	http.prepare_content("application/json; charset=UTF-8")
	http.write_json({
		ok = true,
		root_password_set = type(root_hash) == "string" and root_hash ~= "",
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
		routes_available = route_inventory.available,
		routes = route_inventory.routes,
		static_routes_available = static_routes.available,
		static_routes_count = static_routes.count,
		static_routes_truncated = static_routes.truncated,
		static_routes_invalid_count = static_routes.invalid_count,
		static_routes = static_routes.routes,
		policy_rules_available = rule_inventory.available,
		policy_rules_count = rule_inventory.count,
		policy_rules_truncated = rule_inventory.truncated,
		policy_rules = rule_inventory.rules,
		clients = dhcp_clients(),
		wireless = wireless,
		wireless_configs = wireless_config_inventory(uci, wireless),
		wireless_clients = wireless_clients(wireless),
		sqm = sqm,
		mwan3 = mwan3,
		security = security,
		platform = platform,
		hardware_io = hardware_io,
		office_networks = office_networks,
		remote_syslog = remote_syslog,
		usteer = usteer,
		conntrack = conntrack,
		cellular = cellular,
		phone = {
			service_installed = phone_service,
			enabled = phone_enabled,
			patch_installed = phone_patch
		}
	})
end


local function static_route_write_interfaces(uci)
	local result, names = {}, {}
	local ok = pcall(function()
		uci:foreach("network", "interface", function(section)
			local name = type(section[".name"]) == "string" and section[".name"] or ""
			if name:match("^[%w_.%-]+$") and name ~= "loopback" and not names[name] then
				names[name] = true
				table.insert(result, { name = name })
			end
		end)
	end)
	return ok and result or nil
end

local function static_route_respond(http, status, payload)
	if status then
		http.status(status, status == 400 and "Bad Request" or
			status == 403 and "Forbidden" or status == 404 and "Not Found" or
			status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
			status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
			"Internal Server Error")
	end
	http.header("Cache-Control", "no-store")
	http.prepare_content("application/json; charset=UTF-8")
	http.write_json(payload)
end

local function static_route_request_origin_valid(http)
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"
	return host ~= nil and origin == scheme .. "://" .. host
end

local function static_route_services_ready(fs)
	return fs.access("/etc/config/network") == true and
		fs.access("/etc/init.d/network") == true
end

local function static_route_reload(sys)
	local ok, status = pcall(sys.call, "/etc/init.d/network reload >/dev/null 2>&1")
	return ok and status == 0
end

local function restore_static_route(uci, sys, section, previous)
	if type(section) ~= "string" or type(previous) ~= "table" then return false end
	local restore_ok, restored = pcall(
		uci.section, uci, "network", previous.route_type, section, previous.values)
	if not restore_ok or not restored then return false end
	local commit_ok, committed = pcall(uci.commit, uci, "network")
	if not commit_ok or committed ~= true then return false end
	return static_route_reload(sys)
end

function action_static_route_add()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local routing = require "luci.quantumgrid.routing"

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		static_route_respond(http, 405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not static_route_request_origin_valid(http) then
		static_route_respond(http, 403, { ok = false, error = "A same-origin request is required." })
		return
	end
	if http.formvalue("confirmed", true) ~= "1" then
		static_route_respond(http, 400, { ok = false, error = "Explicit confirmation is required before adding a static route." })
		return
	end
	if not static_route_services_ready(fs) then
		static_route_respond(http, 503, { ok = false, error = "Network configuration or the native network reload service is unavailable." })
		return
	end

	local inventory = static_route_inventory(uci, fs)
	if not inventory.available or inventory.truncated or inventory.invalid_count > 0 then
		static_route_respond(http, 409, {
			ok = false,
			error = "Static route inventory is unavailable, invalid or truncated. Resolve existing route sections before changing them."
		})
		return
	end
	local interfaces = static_route_write_interfaces(uci)
	if not interfaces then
		static_route_respond(http, 409, { ok = false, error = "The network interface inventory could not be read safely." })
		return
	end

	local update, validation_error = routing.validate_static_route(
		http.formvalue("family", true),
		http.formvalue("interface", true),
		http.formvalue("target", true),
		http.formvalue("gateway", true),
		http.formvalue("metric", true),
		http.formvalue("table", true),
		interfaces,
		inventory.routes)
	if not update then
		static_route_respond(http, 400, { ok = false, error = validation_error })
		return
	end

	local remote_ip = http.getenv("REMOTE_ADDR")
	if type(remote_ip) ~= "string" or remote_ip == "" then
		static_route_respond(http, 409, { ok = false, error = "The active administrator address is unavailable. Use an out-of-band management path to manage static routes." })
		return
	end
	local remote_family = routing.ip_address_family(remote_ip)
	if not remote_family then
		static_route_respond(http, 409, { ok = false, error = "The active administrator address cannot be validated as IPv4 or IPv6. Use an out-of-band management path to manage static routes." })
		return
	end
	if remote_family == update.family and routing.static_route_contains_address(update, remote_ip) then
		static_route_respond(http, 409, {
			ok = false,
			error = "This route would cover the active administrator client address. Use an out-of-band management path or manage the route from a different network."
		})
		return
	end

	local options = {
		interface = update.interface,
		target = update.target
	}
	if update.gateway ~= "" then options.gateway = update.gateway end
	if update.metric ~= nil then options.metric = tostring(update.metric) end
	if update.table ~= "" then options.table = update.table end

	local create_ok, section = pcall(uci.section, uci, "network", update.route_type, nil, options)
	if not create_ok or type(section) ~= "string" or section == "" then
		pcall(uci.revert, uci, "network")
		static_route_respond(http, 500, { ok = false, error = "The static route could not be staged in UCI." })
		return
	end
	local commit_ok, committed = pcall(uci.commit, uci, "network")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "network")
		record_audit(http, "network.route.add", section, "failed")
		static_route_respond(http, 500, { ok = false, error = "The static route could not be committed; network reload was not attempted." })
		return
	end

	if not static_route_reload(sys) then
		local delete_ok, deleted = pcall(uci.delete, uci, "network", section)
		local rollback_commit_ok, rollback_committed = false, false
		if delete_ok and deleted == true then
			rollback_commit_ok, rollback_committed = pcall(uci.commit, uci, "network")
		end
		local rollback_reload_ok = false
		if rollback_commit_ok and rollback_committed == true then
			rollback_reload_ok = static_route_reload(sys)
		end
		local rolled_back = delete_ok and deleted == true and
			rollback_commit_ok and rollback_committed == true and rollback_reload_ok
		record_audit(http, "network.route.add", section, "failed")
		static_route_respond(http, 502, {
			ok = false,
			error = rolled_back
				and "Network reload failed. The new static route was removed and the previous network configuration was reloaded."
				or "Network reload failed and static route rollback could not be confirmed. Inspect network configuration and active routing locally.",
			rolled_back = rolled_back
		})
		return
	end

	record_audit(http, "network.route.add", section, "success")
	static_route_respond(http, nil, {
		ok = true,
		section = section,
		family = update.family,
		interface = update.interface,
		requested_target = http.formvalue("target", true),
		target = update.target,
		gateway = update.gateway,
		metric = update.metric ~= nil and tostring(update.metric) or "",
		table = update.table,
		reloaded = true,
		rolled_back = false
	})
end

function action_static_route_remove()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local uci = require("luci.model.uci").cursor()
	local routing = require "luci.quantumgrid.routing"

	if http.getenv("REQUEST_METHOD") ~= "POST" then
		static_route_respond(http, 405, { ok = false, error = "POST is required." })
		return
	end
	if not require_https(http) then return end
	if not static_route_request_origin_valid(http) then
		static_route_respond(http, 403, { ok = false, error = "A same-origin request is required." })
		return
	end
	if http.formvalue("confirmed", true) ~= "1" then
		static_route_respond(http, 400, { ok = false, error = "Explicit confirmation is required before removing a static route." })
		return
	end
	if not static_route_services_ready(fs) then
		static_route_respond(http, 503, { ok = false, error = "Network configuration or the native network reload service is unavailable." })
		return
	end
	local section = http.formvalue("section", true)
	if type(section) ~= "string" or #section < 1 or #section > 64
		or not section:match("^[%w_.%-]+$") or section == "." or section == ".." then
		static_route_respond(http, 400, { ok = false, error = "The static route section identifier is invalid." })
		return
	end

	local snapshot_ok, snapshot = pcall(uci.get_all, uci, "network", section)
	if not snapshot_ok or type(snapshot) ~= "table" or
		(snapshot[".type"] ~= "route" and snapshot[".type"] ~= "route6") then
		static_route_respond(http, 404, { ok = false, error = "The selected static route no longer exists." })
		return
	end
	local route_type = snapshot[".type"]
	local previous, snapshot_error = routing.snapshot_static_route_section(snapshot, route_type)
	if not previous then
		static_route_respond(http, 500, { ok = false, error = snapshot_error or "The original route could not be snapshotted safely." })
		return
	end
	local interfaces = static_route_write_interfaces(uci)
	if not interfaces then
		static_route_respond(http, 409, { ok = false, error = "The network interface inventory could not be read safely." })
		return
	end
	local family = route_type == "route" and "IPv4" or "IPv6"
	local validated, validation_error = routing.validate_static_route(
		family,
		snapshot.interface,
		snapshot.target,
		snapshot.gateway or "",
		snapshot.metric or "",
		snapshot.table or "",
		interfaces,
		{})
	if not validated then
		static_route_respond(http, 409, {
			ok = false,
			error = "This route cannot be safely verified by QuantumGrid (" .. tostring(validation_error) .. "). Inspect or remove it through native LuCI with an out-of-band management path."
		})
		return
	end
	local remote_ip = http.getenv("REMOTE_ADDR")
	if type(remote_ip) ~= "string" or remote_ip == "" then
		static_route_respond(http, 409, { ok = false, error = "The active administrator address is unavailable. Use an out-of-band management path to remove static routes." })
		return
	end
	local remote_family = routing.ip_address_family(remote_ip)
	if not remote_family then
		static_route_respond(http, 409, { ok = false, error = "The active administrator address cannot be validated as IPv4 or IPv6. Use an out-of-band management path to remove static routes." })
		return
	end
	if remote_family == validated.family and routing.static_route_contains_address(validated, remote_ip) then
		static_route_respond(http, 409, {
			ok = false,
			error = "This route covers the active administrator client address and cannot be removed through the current session."
		})
		return
	end

	local delete_ok, deleted = pcall(uci.delete, uci, "network", section)
	if not delete_ok or deleted ~= true then
		pcall(uci.revert, uci, "network")
		static_route_respond(http, 500, { ok = false, error = "The static route could not be staged for removal." })
		return
	end
	local commit_ok, committed = pcall(uci.commit, uci, "network")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "network")
		static_route_respond(http, 500, { ok = false, error = "The static route removal could not be committed; network reload was not attempted." })
		return
	end
	if not static_route_reload(sys) then
		local restored = restore_static_route(uci, sys, section, {
			route_type = route_type,
			values = previous.values
		})
		local rolled_back = restored == true
		record_audit(http, "network.route.remove", section, "failed")
		static_route_respond(http, 502, {
			ok = false,
			error = rolled_back
				and "Network reload failed. The complete static route was restored."
				or "Network reload failed and the static route could not be fully restored. Inspect network configuration and routing locally.",
			rolled_back = rolled_back
		})
		return
	end

	record_audit(http, "network.route.remove", section, "success")
	static_route_respond(http, nil, {
		ok = true,
		section = section,
		family = family,
		removed = true,
		reloaded = true,
		rolled_back = false
	})
end
