module("luci.quantumgrid.usteer", package.seeall)

local function valid_token(value, maximum)
	return type(value) == "string" and #value >= 1 and #value <= (maximum or 64)
		and value:match("^[%w_.%-]+$") ~= nil and value ~= "." and value ~= ".."
end

local function integer(value, minimum, maximum, label)
	if type(value) ~= "string" or #value > 6 or not value:match("^%d+$") then
		return nil, label .. " must be a whole number."
	end
	local number = tonumber(value)
	if not number or tostring(number) ~= value or number < minimum or number > maximum or number ~= math.floor(number) then
		return nil, label .. " must be between " .. tostring(minimum) .. " and " .. tostring(maximum) .. "."
	end
	return number
end

local function signed_integer(value, minimum, maximum, label)
	if type(value) ~= "string" or #value > 4 or not value:match("^-?%d+$") then
		return nil, label .. " must be a whole-number dBm value."
	end
	local number = tonumber(value)
	if not number or number < minimum or number > maximum or number ~= math.floor(number) then
		return nil, label .. " must be between " .. tostring(minimum) .. " and " .. tostring(maximum) .. " dBm."
	end
	return number
end

local function valid_ssid(value)
	return type(value) == "string" and #value >= 1 and #value <= 32
		and not value:find("[%z\1-\31\127]")
end

local function contains_network(networks, wanted)
	if type(networks) == "string" then
		for item in networks:gmatch("%S+") do if item == wanted then return true end end
	elseif type(networks) == "table" then
		for _, item in ipairs(networks) do if item == wanted then return true end end
	end
	return false
end

local function same_option(left, right, name)
	local a, b = left[name], right[name]
	if a == nil then a = "" end
	if b == nil then b = "" end
	return tostring(a) == tostring(b)
end

local function has_radius_configuration(ap)
	local encryption = type(ap.encryption) == "string" and ap.encryption:lower() or ""
	return encryption:find("eap", 1, true) ~= nil or
		(type(ap.auth_server) == "string" and ap.auth_server ~= "") or
		(type(ap.auth_server2) == "string" and ap.auth_server2 ~= "") or
		(type(ap.auth_secret) == "string" and ap.auth_secret ~= "") or
		(type(ap.acct_server) == "string" and ap.acct_server ~= "")
end

local function valid_radius_endpoint(server, port, secret, required)
	if type(server) ~= "string" or server == "" then return not required end
	local number = tonumber(port)
	return number ~= nil and number >= 1 and number <= 65535 and number == math.floor(number) and
		type(secret) == "string" and #secret >= 16
end

local function same_security(left, right)
	if type(left) ~= "table" or type(right) ~= "table" or
		type(left.encryption) ~= "string" or left.encryption == "none" or
		left.encryption ~= right.encryption then return false end
	for _, field in ipairs({
		"ieee80211w", "dynamic_vlan", "ieee80211r", "mobility_domain",
		"ft_over_ds", "ft_psk_generate_local"
	}) do
		if not same_option(left, right, field) then return false end
	end

	local left_enterprise, right_enterprise = has_radius_configuration(left), has_radius_configuration(right)
	if left_enterprise ~= right_enterprise then return false end
	if left_enterprise then
		local radius_fields = {
			"auth_server", "auth_port", "auth_secret",
			"auth_server2", "auth_port2", "auth_secret2",
			"acct_server", "acct_port", "acct_secret",
			"acct_server2", "acct_port2", "acct_secret2"
		}
		for _, field in ipairs(radius_fields) do
			if not same_option(left, right, field) then return false end
		end
		if not valid_radius_endpoint(left.auth_server, left.auth_port, left.auth_secret, true) then return false end
		if left.auth_server2 ~= nil and left.auth_server2 ~= "" and
			not valid_radius_endpoint(left.auth_server2, left.auth_port2, left.auth_secret2, true) then return false end
		if left.acct_server ~= nil and left.acct_server ~= "" and
			not valid_radius_endpoint(left.acct_server, left.acct_port, left.acct_secret, true) then return false end
		if left.acct_server2 ~= nil and left.acct_server2 ~= "" and
			not valid_radius_endpoint(left.acct_server2, left.acct_port2, left.acct_secret2, true) then return false end
		return true
	end
	for _, field in ipairs({
		"auth_server", "auth_secret", "auth_server2", "auth_secret2",
		"acct_server", "acct_secret", "acct_server2", "acct_secret2"
	}) do
		if not same_option(left, right, field) then return false end
	end
	return type(left.key) == "string" and #left.key >= 8 and left.key == right.key
end

local function normalize_ssids(ssids)
	if type(ssids) ~= "table" or #ssids < 1 or #ssids > 8 then
		return nil, "Choose between one and eight existing SSIDs for roaming."
	end
	local result, seen = {}, {}
	local count = 0
	for key in pairs(ssids) do
		if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
			return nil, "The SSID list must be a JSON array."
		end
		count = count + 1
	end
	if count ~= #ssids then return nil, "The SSID list must be a contiguous JSON array." end
	for _, ssid in ipairs(ssids) do
		if not valid_ssid(ssid) then return nil, "Every selected SSID must be 1–32 bytes and contain no control characters." end
		if seen[ssid] then return nil, "Duplicate SSIDs are not allowed." end
		seen[ssid] = true
		table.insert(result, ssid)
	end
	table.sort(result)
	return result
end

function validate(input, network_binding, access_points)
	if type(input) ~= "table" then return nil, "Roaming settings must be provided." end
	if input.confirmed ~= "1" then return nil, "Explicit confirmation is required before changing roaming policy." end
	if input.enabled ~= "0" and input.enabled ~= "1" then
		return nil, "Roaming enabled state must be exactly 0 or 1."
	end
	if input.enabled == "0" then return { enabled = false } end

	if type(network_binding) ~= "table" or not valid_token(network_binding.network, 64) then
		return nil, "Select one existing trusted internal network for inter-AP communication."
	end
	local ssids, ssid_error = normalize_ssids(input.ssids)
	if not ssids then return nil, ssid_error end

	local aggressiveness, error = integer(input.aggressiveness, 0, 4, "Steering aggressiveness")
	if not aggressiveness then return nil, error end
	local band_interval
	band_interval, error = integer(input.band_steering_interval, 0, 300000, "Band-steering interval")
	if not band_interval then return nil, error end
	local band_snr
	band_snr, error = signed_integer(input.band_steering_min_snr, -90, -35, "Band-steering minimum signal")
	if not band_snr then return nil, error end
	local band_threshold
	band_threshold, error = integer(input.band_steering_threshold, 0, 20, "Band-steering client threshold")
	if not band_threshold then return nil, error end
	local load_threshold
	load_threshold, error = integer(input.load_balancing_threshold, 0, 32, "Load-balancing client threshold")
	if not load_threshold then return nil, error end
	if input.assoc_steering ~= "0" and input.assoc_steering ~= "1" then
		return nil, "Association steering must be exactly 0 or 1."
	end
	if input.probe_steering ~= "0" and input.probe_steering ~= "1" then
		return nil, "Probe steering must be exactly 0 or 1."
	end
	if input.assoc_steering == "1" or input.probe_steering == "1" then
		return nil, "Probe rejection and association steering remain disabled in this release; use BSS-transition requests instead."
	end
	if aggressiveness > 3 then
		return nil, "Forced disassociation aggressiveness is not supported by the QuantumGrid roaming profile."
	end

	local aps = type(access_points) == "table" and access_points or {}
	for _, ssid in ipairs(ssids) do
		local matches = {}
		for _, ap in ipairs(aps) do
			if type(ap) == "table" and ap.mode == "ap" and ap.ssid == ssid then
				table.insert(matches, ap)
			end
		end
		if #matches == 0 then
			return nil, "SSID '" .. ssid .. "' is not present on an existing local AP interface."
		end
		local reference = nil
		local active_count = 0
		for _, ap in ipairs(matches) do
			if ap.disabled ~= true and ap.radio_disabled ~= true then
				active_count = active_count + 1
				if not contains_network(ap.networks, network_binding.network) then
					return nil, "Every active local AP broadcasting '" .. ssid .. "' must use the selected inter-AP network."
				end
				if ap.ieee80211k ~= "1" or ap.ieee80211v ~= "1" then
					return nil, "Enable 802.11k and 802.11v on every active AP broadcasting '" .. ssid .. "' before enabling roaming."
				end
				if not reference then
					reference = ap
				elseif not same_security(reference, ap) then
					return nil, "All local APs broadcasting '" .. ssid .. "' must use identical wireless security credentials."
				end
			end
		end
		if active_count < 1 then
			return nil, "SSID '" .. ssid .. "' has no enabled local AP interface."
		end
	end

	return {
		enabled = true,
		network = network_binding.network,
		ssids = ssids,
		aggressiveness = aggressiveness,
		assoc_steering = false,
		probe_steering = false,
		load_kick_enabled = false,
		min_snr = 0,
		min_connect_snr = 0,
		roam_scan_snr = 0,
		roam_trigger_snr = 0,
		aggressiveness_mac_list = {},
		band_steering_interval = band_interval,
		band_steering_min_snr = band_snr,
		band_steering_threshold = band_threshold,
		load_balancing_threshold = load_threshold,
		syslog = true,
		local_mode = false,
		ipv6 = false
	}
end

local function valid_bssid(value)
	if type(value) ~= "string" or #value ~= 17 or
		not value:match("^(%x%x):(%x%x):(%x%x):(%x%x):(%x%x):(%x%x)$") then return false end
	local first = tonumber(value:sub(1, 2), 16)
	local normalized = value:lower()
	return first ~= nil and first % 2 == 0 and
		normalized ~= "00:00:00:00:00:00" and normalized ~= "ff:ff:ff:ff:ff:ff"
end

local function bounded_integer(value, minimum, maximum)
	local number = tonumber(value)
	if not number or number ~= math.floor(number) or number < minimum or number > maximum then return nil end
	return number
end

local function map_count(value, maximum)
	if type(value) ~= "table" then return 0, {}, false, 0 end
	local total, valid_count, invalid_count = 0, 0, 0
	local rows, seen_bssids = {}, {}
	for key, item in pairs(value) do
		total = total + 1
		local bssid = type(item) == "table" and type(item.bssid) == "string" and item.bssid:lower() or ""
		local ssid = type(item) == "table" and item.ssid or nil
		local frequency = type(item) == "table" and bounded_integer(item.freq, 2300, 7125) or nil
		local clients = type(item) == "table" and bounded_integer(item.n_assoc, 0, 4096) or nil
		local load = type(item) == "table" and bounded_integer(item.load, 0, 255) or nil
		local noise = type(item) == "table" and bounded_integer(item.noise, -127, 0) or nil
		local key_matches = type(key) == "string" and valid_bssid(key) and key:lower() == bssid
		if type(item) ~= "table" or not key_matches or not valid_bssid(bssid) or
			not valid_ssid(ssid) or not frequency or clients == nil or load == nil or
			noise == nil or seen_bssids[bssid] then
			invalid_count = invalid_count + 1
		else
			seen_bssids[bssid] = true
			valid_count = valid_count + 1
			if valid_count <= maximum then
				table.insert(rows, {
					name = bssid, ssid = ssid, bssid = bssid,
					frequency_mhz = frequency, clients = clients,
					channel_load = load, noise_dbm = noise
				})
			end
		end
	end
	table.sort(rows, function(left, right) return left.bssid < right.bssid end)
	return math.min(valid_count, maximum), rows, total > maximum or invalid_count > 0, invalid_count
end

function local_ess_ready(selected_ssids, access_points, runtime)
	if type(selected_ssids) ~= "table" or #selected_ssids < 1 or #selected_ssids > 8 or
		type(access_points) ~= "table" or type(runtime) ~= "table" or
		type(runtime.local_nodes) ~= "table" or runtime.local_nodes_truncated == true or
		(runtime.local_nodes_invalid_count or 0) > 0 then return false end
	local selected, expected, observed, seen_bssids = {}, {}, {}, {}
	for _, ssid in ipairs(selected_ssids) do
		if not valid_ssid(ssid) or selected[ssid] then return false end
		selected[ssid], expected[ssid], observed[ssid] = true, 0, 0
	end
	for _, ap in ipairs(access_points) do
		if type(ap) == "table" and ap.mode == "ap" and selected[ap.ssid] and
			ap.disabled ~= true and ap.radio_disabled ~= true then expected[ap.ssid] = expected[ap.ssid] + 1 end
	end
	for ssid in pairs(selected) do if expected[ssid] < 1 then return false end end
	for _, node in ipairs(runtime.local_nodes) do
		if type(node) ~= "table" or not valid_ssid(node.ssid) or not valid_bssid(node.bssid) then return false end
		local bssid = node.bssid:lower()
		if seen_bssids[bssid] then return false end
		seen_bssids[bssid] = true
		if selected[node.ssid] then observed[node.ssid] = observed[node.ssid] + 1 end
	end
	for ssid in pairs(selected) do if observed[ssid] ~= expected[ssid] then return false end end
	return true
end

local function same_numeric(value, expected)
	local actual = tonumber(value)
	return actual ~= nil and actual == expected
end

local function same_string_list(left, right)
	if type(left) ~= "table" or type(right) ~= "table" or #left ~= #right then return false end
	local a, b = {}, {}
	for _, value in ipairs(left) do
		if type(value) ~= "string" then return false end
		a[#a + 1] = value
	end
	for _, value in ipairs(right) do
		if type(value) ~= "string" then return false end
		b[#b + 1] = value
	end
	table.sort(a)
	table.sort(b)
	for index = 1, #a do if a[index] ~= b[index] then return false end end
	return true
end

function runtime_policy_matches(runtime, persisted)
	if type(runtime) ~= "table" or type(persisted) ~= "table" then return false end
	if runtime.syslog ~= true or runtime.ipv6 ~= false or runtime.local_mode ~= false or
		runtime.assoc_steering ~= false or runtime.probe_steering ~= false or
		runtime.load_kick_enabled ~= false or
		persisted.syslog ~= true or persisted.ipv6 ~= false or persisted.local_mode ~= false or
		persisted.assoc_steering ~= false or persisted.probe_steering ~= false or
		persisted.load_kick_enabled ~= false or persisted.min_snr ~= 0 or
		persisted.min_connect_snr ~= 0 or persisted.roam_scan_snr ~= 0 or
		persisted.roam_trigger_snr ~= 0 or persisted.aggressiveness_override_count ~= 0 then
		return false
	end
	if not same_numeric(runtime.aggressiveness, persisted.aggressiveness) or
		not same_numeric(runtime.band_steering_interval, persisted.band_steering_interval) or
		not same_numeric(runtime.band_steering_min_snr, persisted.band_steering_min_snr) or
		not same_numeric(runtime.band_steering_threshold, persisted.band_steering_threshold) or
		not same_numeric(runtime.load_balancing_threshold, persisted.load_balancing_threshold) then
		return false
	end
	if not same_numeric(runtime.min_snr or 0, 0) or
		not same_numeric(runtime.min_connect_snr or 0, 0) or
		not same_numeric(runtime.roam_scan_snr or 0, 0) or
		not same_numeric(runtime.roam_trigger_snr or 0, 0) then
		return false
	end
	if type(runtime.aggressiveness_mac_list) ~= "table" or #runtime.aggressiveness_mac_list ~= 0 then
		return false
	end
	return same_string_list(runtime.ssid_list, persisted.ssid_list)
end

function summarize_runtime(config, local_nodes, remote_hosts)
	local local_count, nodes, local_truncated, invalid_count = map_count(local_nodes, 32)
	local remote_count = 0
	if type(remote_hosts) == "table" then
		for _ in pairs(remote_hosts) do remote_count = remote_count + 1 end
	end
	local clients = 0
	for _, node in ipairs(nodes) do clients = clients + node.clients end
	return {
		running = type(config) == "table",
		local_node_count = local_count,
		local_nodes_truncated = local_truncated,
		local_nodes_invalid_count = invalid_count,
		remote_host_count = math.min(remote_count, 64),
		remote_hosts_truncated = remote_count > 64,
		associated_clients = clients,
		local_nodes = nodes
	}
end

return _M
