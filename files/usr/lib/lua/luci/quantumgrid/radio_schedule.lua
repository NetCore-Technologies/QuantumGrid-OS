local M = {}
local function valid_radio(v)
	return type(v) == "string" and #v >= 1 and #v <= 32 and v:match("^[%w_%-]+$") ~= nil
end
local function parse_days(v)
	if type(v) ~= "string" or #v < 1 or #v > 32 or v:match("[^1-7,%s]") or
		v:match("^%s*,") or v:match(",%s*$") or v:match(",%s*,") then return nil end
	local seen, days = {}, {}
	for token in v:gmatch("%d+") do
		local d = tonumber(token)
		if not d or d < 1 or d > 7 or seen[d] then return nil end
		seen[d] = true
		days[#days + 1] = d
	end
	if #days == 0 or #days > 7 then return nil end
	table.sort(days)
	return days
end
local function parse_time(v)
	if type(v) ~= "string" or not v:match("^%d%d:%d%d$") then return nil end
	local h, m = v:match("^(%d%d):(%d%d)$")
	h, m = tonumber(h), tonumber(m)
	if not h or not m or h > 23 or m > 59 then return nil end
	return h * 60 + m
end
function M.validate(input)
	if type(input) ~= "table" then return nil, "A radio schedule is required." end
	if not valid_radio(input.radio) then return nil, "Invalid wireless radio section name." end
	if input.enabled ~= "0" and input.enabled ~= "1" then return nil, "Schedule enabled state must be exactly 0 or 1." end
	if input.confirmed ~= "1" then return nil, "Explicit confirmation is required because a schedule can disable the radio and disconnect clients." end
	local days = parse_days(input.days)
	if not days then return nil, "Choose one or more unique weekdays from Monday to Sunday." end
	local start_minutes, end_minutes = parse_time(input.start_time), parse_time(input.end_time)
	if start_minutes == nil or end_minutes == nil then return nil, "Schedule times must use valid 24-hour HH:MM values." end
	if start_minutes == end_minutes then return nil, "The schedule start and end times must differ; 24-hour operation is represented by disabling the schedule." end
	local values = {}
	for _, day in ipairs(days) do values[#values + 1] = tostring(day) end
	return { radio=input.radio, enabled=input.enabled=="1", days=days,
		days_csv=table.concat(values, ","), days_value=table.concat(values, " "),
		start_time=input.start_time, end_time=input.end_time, configured=true, valid=true }
end
function M.from_config(section, radio)
	if type(section) ~= "table" or section[".type"] ~= "schedule" or section.radio ~= radio then return nil end
	return M.validate({radio=radio, enabled=section.enabled, days=section.days,
		start_time=section.start_time, end_time=section.end_time, confirmed="1"})
end
local function selected(schedule, day)
	for _, d in ipairs(schedule.days or {}) do if d == day then return true end end
	return false
end
function M.is_active(schedule, weekday, minute_of_day)
	if type(schedule) ~= "table" or schedule.enabled ~= true or
		type(weekday) ~= "number" or weekday < 1 or weekday > 7 or weekday ~= math.floor(weekday) or
		type(minute_of_day) ~= "number" or minute_of_day < 0 or minute_of_day >= 1440 or minute_of_day ~= math.floor(minute_of_day) then return false end
	local start_minutes, end_minutes = parse_time(schedule.start_time), parse_time(schedule.end_time)
	if start_minutes == nil or end_minutes == nil or start_minutes == end_minutes then return false end
	if start_minutes < end_minutes then
		return selected(schedule, weekday) and minute_of_day >= start_minutes and minute_of_day < end_minutes
	end
	local previous_day = weekday == 1 and 7 or weekday - 1
	return (selected(schedule, weekday) and minute_of_day >= start_minutes) or
		(selected(schedule, previous_day) and minute_of_day < end_minutes)
end
function M.desired_disabled(schedule, weekday, minute_of_day)
	if type(schedule) ~= "table" or schedule.enabled ~= true then return nil end
	return not M.is_active(schedule, weekday, minute_of_day)
end
return M