local M = {}

local schedule_config = require "luci.quantumgrid.radio_schedule"

local function log(deps, message)
	if type(deps.log) == "function" then pcall(deps.log, message) end
end

local function valid_radio(value)
	return type(value) == "string" and #value >= 1 and #value <= 32
		and value:match("^[%w_%-]+$") ~= nil
end

local function verify_runtime(changes, previous_state, deps)
	for attempt = 1, 12 do
		local ok, status = pcall(deps.runtime_status)
		local matches = ok and type(status) == "table"
		if matches then
			for _, change in ipairs(changes) do
				local expected_up
				if previous_state then expected_up = change.previous_up
				else expected_up = not change.desired_disabled end
				local radio = status[change.radio]
				if type(radio) ~= "table" or radio.up ~= expected_up then
					matches = false
					break
				end
			end
		end
		if matches then return true end
		if attempt < 12 and type(deps.sleep) == "function" then
			pcall(deps.sleep, 0.25)
		end
	end
	return false
end

local function restore_changes(uci, changes, deps)
	for _, change in ipairs(changes) do
		local ok, result
		if change.previous_disabled == nil then
			ok, result = pcall(uci.delete, uci, "wireless", change.radio, "disabled")
		else
			ok, result = pcall(uci.set, uci, "wireless", change.radio, "disabled", change.previous_disabled)
		end
		if not ok or result ~= true then
			pcall(uci.revert, uci, "wireless")
			return false
		end
	end
	local commit_ok, committed = pcall(uci.commit, uci, "wireless")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "wireless")
		return false
	end
	local reload_ok, reloaded = pcall(deps.reload)
	if not reload_ok or reloaded ~= true then return false end
	return verify_runtime(changes, true, deps)
end

local function clear_restored_baselines(uci, radios, deps)
	local seen = {}
	for _, radio in ipairs(radios) do
		if not seen[radio] then
			seen[radio] = true
			local ok, result = pcall(uci.delete, uci, "quantumgrid-radio", radio, "base_disabled")
			if not ok or result ~= true then
				pcall(uci.revert, uci, "quantumgrid-radio")
				log(deps, "manual radio-state baseline cleanup could not be staged; it will retry")
				return false
			end
		end
	end
	local commit_ok, committed = pcall(uci.commit, uci, "quantumgrid-radio")
	if not commit_ok or committed ~= true then
		pcall(uci.revert, uci, "quantumgrid-radio")
		log(deps, "manual radio-state baseline cleanup failed; it will retry")
		return false
	end
	return true
end

function M.run_once(uci, deps, now)
	if type(uci) ~= "table" or type(deps) ~= "table" or
		type(deps.runtime_status) ~= "function" or type(deps.reload) ~= "function" or
		type(now) ~= "table" or type(now.wday) ~= "number" or
		type(now.hour) ~= "number" or type(now.min) ~= "number" then
		return false, "invalid_scheduler_dependencies"
	end

	local weekday = ((now.wday + 5) % 7) + 1
	local minute_of_day = now.hour * 60 + now.min
	if now.hour < 0 or now.hour > 23 or now.min < 0 or now.min > 59 then
		return false, "invalid_router_local_time"
	end

	local schedules, invalid, counts = {}, {}, {}
	local inventory_ok = pcall(function()
		uci:foreach("quantumgrid-radio", "schedule", function(section)
			if type(section) ~= "table" then return end
			local radio = section.radio
			if not valid_radio(radio) then return end
			counts[radio] = (counts[radio] or 0) + 1
			if section[".name"] ~= radio then invalid[radio] = true; return end
			local parsed = schedule_config.from_config(section, radio)
			if not parsed then invalid[radio] = true; return end
			schedules[radio] = parsed
		end)
	end)
	if not inventory_ok then
		log(deps, "schedule inventory could not be read; no radio changes were made")
		return false, "schedule_inventory_unavailable"
	end

	local runtime_ok, runtime = pcall(deps.runtime_status)
	if not runtime_ok or type(runtime) ~= "table" then
		log(deps, "wireless runtime inventory is unavailable; no radio changes were made")
		return false, "wireless_runtime_unavailable"
	end

	local changes, clear_baselines = {}, {}
	for radio, schedule in pairs(schedules) do
		if counts[radio] == 1 and not invalid[radio] then
			local desired_disabled = schedule_config.desired_disabled(schedule, weekday, minute_of_day)
			if desired_disabled ~= nil then
				local config_ok, wireless = pcall(uci.get_all, uci, "wireless", radio)
				local live = runtime[radio]
				if config_ok and type(wireless) == "table" and wireless[".type"] == "wifi-device" and
					type(live) == "table" and type(live.up) == "boolean" then
					local previous_disabled = wireless.disabled
					local config_change = desired_disabled ~= (previous_disabled == "1") or
						(not desired_disabled and previous_disabled ~= nil)
					local runtime_change = live.up ~= (not desired_disabled)
					if config_change or runtime_change then
						changes[#changes + 1] = {
							radio = radio,
							previous_disabled = previous_disabled,
							previous_up = live.up,
							desired_disabled = desired_disabled
						}
					end
					if not schedule.enabled and schedule.base_disabled_present then
						clear_baselines[#clear_baselines + 1] = radio
					end
				else
					log(deps, "a scheduled radio does not resolve to a verifiable live wifi-device; it was skipped")
				end
			end
		elseif counts[radio] ~= 1 or invalid[radio] then
			log(deps, "a duplicate or invalid radio schedule was skipped")
		end
	end

	if #changes > 0 then
		for _, change in ipairs(changes) do
			local ok, result
			if change.desired_disabled then
				ok, result = pcall(uci.set, uci, "wireless", change.radio, "disabled", "1")
			else
				ok, result = pcall(uci.delete, uci, "wireless", change.radio, "disabled")
			end
			if not ok or result ~= true then
				pcall(uci.revert, uci, "wireless")
				log(deps, "radio schedule changes could not be staged; no reload was attempted")
				return false, "wireless_stage_failed"
			end
		end

		local commit_ok, committed = pcall(uci.commit, uci, "wireless")
		if not commit_ok or committed ~= true then
			pcall(uci.revert, uci, "wireless")
			log(deps, "radio schedule changes could not be committed; no reload was attempted")
			return false, "wireless_commit_failed"
		end

		local reload_ok, reloaded = pcall(deps.reload)
		if not reload_ok or reloaded ~= true or not verify_runtime(changes, false, deps) then
			local restored = restore_changes(uci, changes, deps)
			if restored then
				log(deps, "scheduled Wi-Fi reload/runtime verification failed; previous configuration and runtime were restored")
			else
				log(deps, "scheduled Wi-Fi reload failed and automatic configuration/runtime rollback could not be confirmed")
			end
			return false, restored and "wireless_runtime_rolled_back" or "wireless_rollback_unverified"
		end
		log(deps, "scheduled radio state applied and live runtime state verified")
	end

	if #clear_baselines > 0 then
		if not clear_restored_baselines(uci, clear_baselines, deps) then
			return false, "baseline_cleanup_failed"
		end
	end
	return true, {
		changed_radios = #changes,
		restored_baselines = #clear_baselines,
	}
end

return M
