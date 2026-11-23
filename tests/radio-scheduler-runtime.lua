package.path = "files/usr/lib/lua/?.lua;" .. package.path

local scheduler = require "luci.quantumgrid.radio_scheduler"

local function clone(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, item in pairs(value) do result[key] = clone(item) end
	return result
end

local function fixture(schedule, disabled, runtime_up)
	local uci = {
		packages = {
			wireless = { radio0 = { [".type"] = "wifi-device", disabled = disabled } },
			["quantumgrid-radio"] = { radio0 = schedule },
		},
		commits = {},
		reverts = {},
	}
	function uci:foreach(package, section_type, callback)
		local sections = self.packages[package] or {}
		for name, value in pairs(sections) do
			if value[".type"] == section_type then
				local item = clone(value)
				item[".name"] = name
				callback(item)
			end
		end
		return true
	end
	function uci:get_all(package, section)
		local value = self.packages[package] and self.packages[package][section]
		return value and clone(value) or nil
	end
	function uci:set(package, section, option, value)
		local target = self.packages[package] and self.packages[package][section]
		if not target then return false end
		target[option] = value
		return true
	end
	function uci:delete(package, section, option)
		local target = self.packages[package] and self.packages[package][section]
		if not target then return false end
		target[option] = nil
		return true
	end
	function uci:commit(package)
		self.commits[#self.commits + 1] = package
		return true
	end
	function uci:revert(package)
		self.reverts[#self.reverts + 1] = package
		return true
	end

	local runtime = { radio0 = { up = runtime_up } }
	local state = { reloads = 0, fail_first_reload = false, logs = {} }
	local deps = {
		runtime_status = function() return clone(runtime) end,
		reload = function()
			state.reloads = state.reloads + 1
			local wireless = uci.packages.wireless.radio0
			if not (state.fail_first_reload and state.reloads == 1) then
				runtime.radio0.up = wireless.disabled ~= "1"
			end
			return not (state.fail_first_reload and state.reloads == 1)
		end,
		sleep = function() end,
		log = function(message) state.logs[#state.logs + 1] = message end,
	}
	return uci, deps, runtime, state
end

local enabled_schedule = {
	[".type"] = "schedule", radio = "radio0", enabled = "1", base_disabled = "0",
	days = "1 2 3 4 5", start_time = "08:00", end_time = "22:00",
}

-- Before the active window the radio is disabled, and live state is verified.
do
	local uci, deps, runtime, state = fixture(enabled_schedule, nil, true)
	local ok, result = scheduler.run_once(uci, deps, { wday = 2, hour = 7, min = 59 })
	assert(ok and result.changed_radios == 1)
	assert(uci.packages.wireless.radio0.disabled == "1")
	assert(runtime.radio0.up == false and state.reloads == 1)
end

-- At the inclusive start boundary it is enabled again.
do
	local uci, deps, runtime, state = fixture(enabled_schedule, "1", false)
	local ok, result = scheduler.run_once(uci, deps, { wday = 2, hour = 8, min = 0 })
	assert(ok and result.changed_radios == 1)
	assert(uci.packages.wireless.radio0.disabled == nil)
	assert(runtime.radio0.up == true and state.reloads == 1)
end

-- Disabling the schedule restores the saved manual state and clears its baseline.
do
	local disabled_schedule = clone(enabled_schedule)
	disabled_schedule.enabled = "0"
	local uci, deps, runtime, state = fixture(disabled_schedule, "1", false)
	local ok, result = scheduler.run_once(uci, deps, { wday = 2, hour = 3, min = 0 })
	assert(ok and result.changed_radios == 1 and result.restored_baselines == 1)
	assert(uci.packages.wireless.radio0.disabled == nil)
	assert(uci.packages["quantumgrid-radio"].radio0.base_disabled == nil)
	assert(runtime.radio0.up == true and state.reloads == 1)
end

-- If Wi-Fi reload fails, both saved configuration and live radio state are restored.
do
	local uci, deps, runtime, state = fixture(enabled_schedule, nil, true)
	state.fail_first_reload = true
	local ok, err = scheduler.run_once(uci, deps, { wday = 2, hour = 7, min = 59 })
	assert(not ok and err == "wireless_runtime_rolled_back")
	assert(uci.packages.wireless.radio0.disabled == nil)
	assert(runtime.radio0.up == true and state.reloads == 2)
end

-- Unexpected UCI disabled values are not coerced into an enabled/disabled state.
do
	local uci, deps, runtime, state = fixture(enabled_schedule, "unexpected", true)
	local ok, result = scheduler.run_once(uci, deps, { wday = 2, hour = 7, min = 0 })
	assert(ok and result.changed_radios == 0)
	assert(uci.packages.wireless.radio0.disabled == "unexpected" and state.reloads == 0)
	assert(#state.logs > 0)
end

-- Unavailable runtime telemetry must not trigger a UCI write or reload.
do
	local uci, deps, runtime, state = fixture(enabled_schedule, nil, true)
	deps.runtime_status = function() return nil end
	local ok, err = scheduler.run_once(uci, deps, { wday = 2, hour = 7, min = 0 })
	assert(not ok and err == "wireless_runtime_unavailable")
	assert(uci.packages.wireless.radio0.disabled == nil and state.reloads == 0)
end

print("radio-scheduler: runtime transitions, restore, rollback and unavailable-state tests passed")