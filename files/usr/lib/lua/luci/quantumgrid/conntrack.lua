module("luci.quantumgrid.conntrack", package.seeall)

local function parse_counter(value)
	if type(value) ~= "string" or not value:match("^%s*%d+%s*$") then
		return nil
	end
	local parsed = tonumber(value)
	if not parsed or parsed < 0 or parsed ~= math.floor(parsed) then
		return nil
	end
	return parsed
end

-- Summarise the kernel's read-only conntrack counters. Missing or malformed
-- values stay unavailable rather than being interpreted as an empty table.
function summarize(count_raw, maximum_raw)
	local count = parse_counter(count_raw)
	local maximum = parse_counter(maximum_raw)
	if count == nil or maximum == nil or maximum < 1 then
		return { available = false }
	end

	local used_percent = count / maximum * 100
	local status = "normal"
	if used_percent >= 90 then
		status = "critical"
	elseif used_percent >= 75 then
		status = "warning"
	end

	return {
		available = true,
		count = count,
		maximum = maximum,
		free = math.max(0, maximum - count),
		used_percent = used_percent,
		status = status
	}
end
