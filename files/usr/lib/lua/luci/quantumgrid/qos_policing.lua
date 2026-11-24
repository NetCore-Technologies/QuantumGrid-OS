local M = {}
local qos = require "luci.quantumgrid.qos"

local MAX_POLICIES, MIN_RATE, MAX_RATE = 32, 64, 1000000
local MIN_BURST, MAX_BURST = 16384, 262144
local PREF_BASE, HANDLE_BASE = 46000, 0x51420000

local function safe_section(value)
	return type(value) == "string" and #value >= 1 and #value <= 32 and value:match("^[%w_%-]+$") ~= nil
end

local function normalize_mac(value)
	if type(value) ~= "string" or #value ~= 17 or not value:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") then return nil end
	local mac = value:lower()
	local first = tonumber(mac:sub(1, 2), 16)
	if not first or first % 2 ~= 0 or mac == "00:00:00:00:00:00" or mac == "ff:ff:ff:ff:ff:ff" then return nil end
	return mac
end

local function parse_rate(value)
	if value == nil or value == "" then return nil end
	if type(value) ~= "string" or #value > 7 or not value:match("^%d+$") then
		return nil, "Rate limits must be whole numbers in kbit/s."
	end
	local rate = tonumber(value)
	if not rate or rate ~= math.floor(rate) or rate < MIN_RATE or rate > MAX_RATE then
		return nil, "Each per-client rate must be between 64 and 1000000 kbit/s."
	end
	return rate
end

local function burst_bytes(rate)
	if type(rate) ~= "number" or rate < MIN_RATE or rate > MAX_RATE then return nil end
	return math.max(MIN_BURST, math.min(MAX_BURST, math.ceil(rate * 1.25)))
end

function M.validate_policy(input, zones, interfaces, static_leases)
	if type(input) ~= "table" then return nil, "A static-reservation client rate policy is required." end
	local mac = normalize_mac(input.mac)
	if not mac then return nil, "Choose one unicast client MAC address in six-octet notation." end
	if not safe_section(input.section) then return nil, "Invalid QuantumGrid client rate policy section." end
	if type(input.slot) ~= "number" or input.slot ~= math.floor(input.slot) or input.slot < 1 or input.slot > MAX_POLICIES then
		return nil, "The client rate policy slot must be between 1 and 32."
	end
	local upload, upload_error = parse_rate(input.upload_kbps)
	if upload_error then return nil, upload_error end
	local download, download_error = parse_rate(input.download_kbps)
	if download_error then return nil, download_error end
	if not upload and not download then return nil, "Set an upload cap, a download cap, or both." end

	-- Reuse the strict reservation/IP/subnet/direction checks used by the
	-- existing downlink policy, but do not create or alter a DSCP rule.
	local binding, binding_error = qos.validate_client_download_policy(
		mac, input.client_ip, input.source_zone, input.destination_zone, "BE",
		zones, interfaces, static_leases)
	if not binding then return nil, binding_error end
	local devices, devices_error = qos.resolve_external_zone_devices(input.source_zone, zones, interfaces)
	if not devices then return nil, devices_error end

	return {
		section = input.section,
		slot = input.slot,
		name = type(input.name) == "string" and input.name:sub(1, 64) or ("Client " .. mac),
		mac = mac,
		client_ip = binding.destination_ip,
		source_zone = binding.source_zone,
		destination_zone = binding.destination_zone,
		upload_kbps = upload,
		download_kbps = download,
		upload_burst_bytes = upload and burst_bytes(upload) or nil,
		download_burst_bytes = download and burst_bytes(download) or nil,
		devices = devices,
		enabled = true,
		policing = true
	}
end

function M.validate_saved_policies(policies, zones, interfaces, static_leases)
	if type(policies) ~= "table" then return nil, "The saved client rate policy inventory is unavailable." end
	if #policies > MAX_POLICIES then return nil, "The saved client rate policy inventory exceeds 32 entries." end
	local sections, slots, identities, result = {}, {}, {}, {}
	for _, policy in ipairs(policies) do
		if type(policy) ~= "table" then return nil, "A saved client rate policy is malformed." end
		local section, slot = policy.section, tonumber(policy.slot)
		if not safe_section(section) or sections[section] then
			return nil, "Saved client rate policy section names are invalid or duplicated."
		end
		if not slot or slot ~= math.floor(slot) or slot < 1 or slot > MAX_POLICIES or slots[slot] then
			return nil, "Saved client rate policy slots are invalid or duplicated."
		end
		if policy.enabled ~= "1" then return nil, "Disabled saved rate policies must be removed before reconciliation." end
		sections[section], slots[slot] = true, true
		local validated, validation_error = M.validate_policy({
			section = section, slot = slot, name = policy.name, mac = policy.mac,
			client_ip = policy.client_ip, source_zone = policy.source_zone,
			destination_zone = policy.destination_zone,
			upload_kbps = policy.upload_kbps, download_kbps = policy.download_kbps
		}, zones, interfaces, static_leases)
		if not validated then return nil, validation_error end
		local identity = validated.mac .. "|" .. validated.client_ip
		if identities[identity] then
			return nil, "Duplicate saved client rate policies exist for the same MAC/IP identity."
		end
		identities[identity] = true
		result[#result + 1] = validated
	end
	table.sort(result, function(left, right) return left.slot < right.slot end)
	return result
end

function M.build_filter_rules(policies)
	if type(policies) ~= "table" or #policies > MAX_POLICIES then return nil, "Invalid client rate policy list." end
	local rules, seen_slots = {}, {}
	for _, policy in ipairs(policies) do
		if type(policy) ~= "table" or type(policy.slot) ~= "number" or
			policy.slot ~= math.floor(policy.slot) or policy.slot < 1 or policy.slot > MAX_POLICIES or
			seen_slots[policy.slot] then
			return nil, "Client rate policy slots must be unique values between 1 and 32."
		end
		seen_slots[policy.slot] = true
		if type(policy.client_ip) ~= "string" or not policy.client_ip:match("^%d+%.%d+%.%d+%.%d+$") then
			return nil, "A valid static client IPv4 address is required for TC matching."
		end
		if type(policy.devices) ~= "table" or #policy.devices < 1 or #policy.devices > 8 then
			return nil, "Each policy must resolve to one or more WAN/WWAN devices."
		end
		for _, device in ipairs(policy.devices) do
			if type(device) ~= "string" or #device > 15 or not device:match("^[%w_.:%-]+$") then
				return nil, "A WAN/WWAN device name is invalid."
			end
			local base = PREF_BASE + (policy.slot - 1) * 2
			if policy.upload_kbps then
				rules[#rules + 1] = {
					device=device, direction="upload", parent="ffff:fff3", pref=base,
					handle=string.format("0x%08x", HANDLE_BASE + policy.slot * 2),
					match="src", client_ip=policy.client_ip,
					rate_kbps=policy.upload_kbps,
					burst_bytes=policy.upload_burst_bytes or burst_bytes(policy.upload_kbps),
					slot=policy.slot
				}
			end
			if policy.download_kbps then
				rules[#rules + 1] = {
					device=device, direction="download", parent="ffff:fff2", pref=base+1,
					handle=string.format("0x%08x", HANDLE_BASE + policy.slot * 2 + 1),
					match="dst", client_ip=policy.client_ip,
					rate_kbps=policy.download_kbps,
					burst_bytes=policy.download_burst_bytes or burst_bytes(policy.download_kbps),
					slot=policy.slot
				}
			end
		end
	end
	table.sort(rules, function(left, right)
		if left.device ~= right.device then return left.device < right.device end
		return left.pref < right.pref
	end)
	return rules
end

function M.build_filter_command(rule)
	if type(rule) ~= "table" or type(rule.device) ~= "string" or #rule.device > 15 or
		not rule.device:match("^[%w_.:%-]+$") or
		(rule.parent ~= "ffff:fff2" and rule.parent ~= "ffff:fff3") or
		(rule.match ~= "src" and rule.match ~= "dst") or
		type(rule.client_ip) ~= "string" or not rule.client_ip:match("^%d+%.%d+%.%d+%.%d+$") or
		type(rule.pref) ~= "number" or rule.pref < PREF_BASE or rule.pref > PREF_BASE + 63 or
		type(rule.handle) ~= "string" or not rule.handle:match("^0x%x%x%x%x%x%x%x%x$") or
		type(rule.rate_kbps) ~= "number" or rule.rate_kbps < MIN_RATE or rule.rate_kbps > MAX_RATE or
		type(rule.burst_bytes) ~= "number" or rule.burst_bytes < MIN_BURST or rule.burst_bytes > MAX_BURST then
		return nil, "Invalid TC policing filter."
	end
	return string.format(
		"/sbin/tc filter replace dev %s parent %s protocol ip pref %d handle %s u32 match ip %s %s/32 police rate %dkbit burst %db mtu 65535 conform-exceed drop/ok",
		rule.device, rule.parent, rule.pref, rule.handle, rule.match, rule.client_ip,
		rule.rate_kbps, rule.burst_bytes
	)
end

function M.build_delete_command(device, parent, slot, direction)
	if type(device) ~= "string" or #device > 15 or not device:match("^[%w_.:%-]+$") or
		(parent ~= "ffff:fff2" and parent ~= "ffff:fff3") or
		type(slot) ~= "number" or slot ~= math.floor(slot) or slot < 1 or slot > MAX_POLICIES or
		(direction ~= "upload" and direction ~= "download") then
		return nil, "Invalid managed TC filter identity."
	end
	local offset = direction == "upload" and 0 or 1
	local pref = PREF_BASE + (slot - 1) * 2 + offset
	local handle = string.format("0x%08x", HANDLE_BASE + slot * 2 + offset)
	return string.format(
		"/sbin/tc filter del dev %s parent %s protocol ip pref %d handle %s u32 >/dev/null 2>&1",
		device, parent, pref, handle
	)
end

function M.get_limits()
	return {
		max_policies=MAX_POLICIES, min_rate_kbps=MIN_RATE, max_rate_kbps=MAX_RATE,
		min_burst_bytes=MIN_BURST, max_burst_bytes=MAX_BURST,
		priority_base=PREF_BASE, reserved_priorities=64
	}
end

return M