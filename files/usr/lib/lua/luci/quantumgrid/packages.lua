module("luci.quantumgrid.packages", package.seeall)

local function safe_text(value, limit)
	if type(value) ~= "string" then return "" end
	return value:gsub("[%c]", " "):sub(1, limit or 160)
end

local function parse_apk_line(line)
	local name, version = line:match("^([%w%+_.%-]+)%-(%d[%w%.%+~:_%-]*)$")
	if not name or not version then return nil end
	return { name = name, version = version, manager = "apk" }
end

local function parse_opkg_line(line)
	local name, version = line:match("^([%w%+_.%-]+)%s+%-%s+(%S+)")
	if not name or not version then return nil end
	return { name = name, version = version, manager = "opkg" }
end

function parse(manager, output, maximum)
	if manager ~= "apk" and manager ~= "opkg" then
		return { available = false, manager = tostring(manager or "unknown"), count = 0, truncated = false, packages = {} }
	end
	if type(output) ~= "string" then
		return { available = false, manager = manager, count = 0, truncated = false, packages = {} }
	end

	local limit = tonumber(maximum) or 1200
	limit = math.max(1, math.min(2000, math.floor(limit)))
	local packages = {}
	local seen = {}
	local count = 0
	local truncated = false
	for line in output:gmatch("[^\r\n]+") do
		local item = manager == "apk" and parse_apk_line(line) or parse_opkg_line(line)
		if item and not seen[item.name] then
			seen[item.name] = true
			count = count + 1
			if #packages < limit then
				item.name = safe_text(item.name, 96)
				item.version = safe_text(item.version, 96)
				table.insert(packages, item)
			else
				truncated = true
			end
		end
	end

	table.sort(packages, function(left, right)
		return left.name < right.name
	end)
	return {
		available = true,
		manager = manager,
		count = count,
		truncated = truncated,
		packages = packages
	}
end

return _M
