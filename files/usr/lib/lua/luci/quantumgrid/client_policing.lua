local M = {}

local validator = require "luci.quantumgrid.qos_policing"

local function rule_key(rule)
	return rule.device .. "|" .. tostring(rule.slot) .. "|" .. rule.direction
end

local function validate_previous_rules(rules)
	if rules == nil then return {} end
	if type(rules) ~= "table" or #rules > 512 then return nil, "The saved TC state file is malformed or oversized." end
	local result, seen = {}, {}
	for _, rule in ipairs(rules) do
		if type(rule) ~= "table" or type(rule.device) ~= "string" or #rule.device > 15 or
			not rule.device:match("^[%w_.:%-]+$") or
			type(rule.slot) ~= "number" or rule.slot ~= math.floor(rule.slot) or rule.slot < 1 or rule.slot > 32 or
			(rule.direction ~= "upload" and rule.direction ~= "download") then
			return nil, "The saved TC state file contains an invalid filter identity."
		end
		local key = rule_key(rule)
		if seen[key] then return nil, "The saved TC state file contains duplicate filter identities." end
		seen[key] = true
		result[#result + 1] = {
			device = rule.device,
			slot = rule.slot,
			direction = rule.direction
		}
	end
	return result
end

function M.reconcile(policies, inventory, previous_rules, deps, sampled_at)
	if type(deps) ~= "table" or type(deps.ensure_clsact) ~= "function" or
		type(deps.device_has_clsact) ~= "function" or
		type(deps.replace_filter) ~= "function" or type(deps.delete_filter) ~= "function" or
		type(deps.write_state) ~= "function" or type(deps.write_status) ~= "function" then
		return nil, "The client policing runtime dependencies are incomplete."
	end
	if type(inventory) ~= "table" or inventory.truncated == true or
		inventory.available ~= true or inventory.firewall_available ~= true or
		inventory.dhcp_available ~= true then
		return nil, "Network, firewall or static reservation inventory is unavailable or truncated."
	end

	local previous, previous_error = validate_previous_rules(previous_rules)
	if not previous then return nil, previous_error end
	local validated, validation_error = validator.validate_saved_policies(
		policies, inventory.zones, inventory.interfaces, inventory.static_leases)
	if not validated then return nil, validation_error end
	local desired, rules_error = validator.build_filter_rules(validated)
	if not desired then return nil, rules_error end

	local desired_by_key, devices = {}, {}
	for _, rule in ipairs(desired) do
		local key = rule_key(rule)
		if desired_by_key[key] then return nil, "The desired TC filter plan contains a duplicate identity." end
		desired_by_key[key] = rule
		devices[rule.device] = true
	end
	for _, old in ipairs(previous) do devices[old.device] = true end

	local device_list = {}
	for device in pairs(devices) do device_list[#device_list + 1] = device end
	table.sort(device_list)

	-- Prepare clsact only on devices that need a new filter. The root qdisc
	-- (including SQM/CAKE) is deliberately never replaced or deleted.
	for _, device in ipairs(device_list) do
		local needs_filters = false
		for _, rule in ipairs(desired) do
			if rule.device == device then needs_filters = true break end
		end
		if needs_filters then
			local ok, err = deps.ensure_clsact(device)
			if not ok then return nil, "Could not prepare clsact on " .. device .. ": " .. tostring(err) end
		end
	end

	local applied = 0
	for _, rule in ipairs(desired) do
		local command, command_error = validator.build_filter_command(rule)
		if not command then return nil, command_error end
		local ok, err = deps.replace_filter(command, rule)
		if not ok then
			return nil, "Could not install the " .. rule.direction .. " cap for " .. rule.client_ip ..
				" on " .. rule.device .. ": " .. tostring(err)
		end
		applied = applied + 1
	end

	local removed = 0
	for _, old in ipairs(previous) do
		if not desired_by_key[rule_key(old)] then
			local has_clsact_ok, has_clsact = pcall(deps.device_has_clsact, old.device)
			if has_clsact_ok and has_clsact == true then
				local ok, err = deps.delete_filter(old.device, old.slot, old.direction)
				if not ok then
					return nil, "Could not remove the retired TC filter on " .. old.device .. ": " .. tostring(err)
				end
			end
			removed = removed + 1
		end
	end

	local state = {}
	for _, rule in ipairs(desired) do
		state[#state + 1] = {
			device = rule.device,
			slot = rule.slot,
			direction = rule.direction
		}
	end
	local state_ok, state_error = deps.write_state(state)
	if not state_ok then
		return nil, "TC rules were installed but the ownership state could not be saved: " .. tostring(state_error)
	end

	local summaries = {}
	for _, policy in ipairs(validated) do
		summaries[#summaries + 1] = {
			section = policy.section,
			slot = policy.slot,
			mac = policy.mac,
			client_ip = policy.client_ip,
			source_zone = policy.source_zone,
			destination_zone = policy.destination_zone,
			upload_kbps = policy.upload_kbps,
			download_kbps = policy.download_kbps,
			devices = policy.devices
		}
	end
	local status = {
		available = true,
		ready = true,
		policing_mode = "drop_excess",
		policy_count = #validated,
		applied_filter_count = applied,
		removed_filter_count = removed,
		sampled_at = sampled_at or os.time(),
		policies = summaries,
		notice = "TC police drops packets above each configured cap; it does not reserve bandwidth or queue excess traffic."
	}
	local status_ok, status_error = deps.write_status(status)
	if not status_ok then
		return nil, "TC rules were installed but runtime status could not be published: " .. tostring(status_error)
	end
	return status
end

return M
