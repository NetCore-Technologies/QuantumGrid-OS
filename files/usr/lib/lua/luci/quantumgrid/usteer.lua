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

local function same_security(left, right)
	if left.encryption ~= right.encryption or
		left.ieee80211w ~= right.ieee80211w or
		left.dynamic_vlan ~= right.dynamic_vlan then
		return false
	end
	if (left.acct_server or "") ~= (right.acct_server or "") or
		(left.acct_port or 1813) ~= (right.acct_port or 1813) or
		(left.acct_secret or "") ~= (right.acct_secret or "") then
		return false
	end
	if left.encryption == "none" then return false end
	if left.encryption == "wpa2" or left.encryption == "wpa3" then
		return type(left.auth_server) == "string" and left.auth_server ~= "" and
			left.auth_server == right.auth_server and left.auth_port == right.auth_port and
			type(left.auth_secret) == "string" and #left.auth_secret >= 16 and
			left.auth_secret == right.auth_secret
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

local function map_count(value, maximum)
	if type(value) ~= "table" then return 0, {}, false end
	local total = 0
	local rows = {}
	for key, item in pairs(value) do
		total = total + 1
		if #rows < maximum and type(item) == "table" then
				local row = {
					name = type(key) == "string" and key or "",
					ssid = type(item.ssid) == "string" and item.ssid or "",
					bssid = type(item.bssid) == "string" and item.bssid:lower() or "",
					frequency_mhz = tonumber(item.freq),
					clients = tonumber(item.n_assoc) or 0,
					channel_load = tonumber(item.load),
					noise_dbm = tonumber(item.noise)
				}
			table.insert(rows, row)
		end
	end
	table.sort(rows, function(left, right) return left.name < right.name end)
	return math.min(total, maximum), rows, total > maximum
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
		runtime.assoc_steering ~= false or runtime.load_kick_enabled ~= false or
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
	local local_count, nodes, local_truncated = map_count(local_nodes, 32)
	local remote_count = 0
	if type(remote_hosts) == "table" then
		for _ in pairs(remote_hosts) do remote_count = remote_count + 1 end
	end
	local clients = 0
	for _, node in ipairs(nodes) do clients = clients + math.max(0, node.clients) end
	return {
		running = type(config) == "table",
		local_node_count = local_count,
		local_nodes_truncated = local_truncated,
		remote_host_count = math.min(remote_count, 64),
		remote_hosts_truncated = remote_count > 64,
		associated_clients = clients,
		local_nodes = nodes
	}
end

return _M
