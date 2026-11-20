module("luci.quantumgrid.kernel_modules", package.seeall)

local function safe_path(value)
	return type(value) == "string" and #value <= 240
		and value:match("^[%w_./+%-]+$") ~= nil
		and value:sub(1, 1) ~= "/"
		and value:find("..", 1, true) == nil
end

local function module_name(path)
	if not safe_path(path) then return nil end
	local base = path:match("([^/]+)$")
	if not base then return nil end
	base = base:gsub("%.ko%.zst$", "")
		:gsub("%.ko%.xz$", "")
		:gsub("%.ko%.gz$", "")
		:gsub("%.ko$", "")
	if base == "" or not base:match("^[%w_%-]+$") then return nil end
	return base:gsub("%-", "_")
end

function parse(modules_dep, proc_modules, maximum)
	local limit = tonumber(maximum) or 1500
	limit = math.max(1, math.min(3000, math.floor(limit)))
	local loaded = {}
	local loaded_count = 0
	if type(proc_modules) == "string" then
		for line in proc_modules:gmatch("[^\r\n]+") do
			local name = line:match("^%s*([%w_%-]+)%s+%d+")
			if name then
				name = name:gsub("%-", "_")
				if not loaded[name] then
					loaded[name] = true
					loaded_count = loaded_count + 1
				end
			end
		end
	end

	local result = {}
	local by_name = {}
	local seen = {}
	local total = 0
	local function add(name, path)
		if type(name) ~= "string" or not name:match("^[%w_]+$") then return end
		if seen[name] then
			local existing = by_name[name]
			if existing and path and path ~= "" and existing.path == "" then existing.path = path end
			return
		end
		seen[name] = true
		total = total + 1
		if #result < limit then
			local item = {
				name = name,
				path = type(path) == "string" and path:sub(1, 240) or "",
				loaded = loaded[name] == true
			}
			by_name[name] = item
			table.insert(result, item)
		end
	end

	local available = type(modules_dep) == "string" and modules_dep ~= ""
	if available then
		for line in modules_dep:gmatch("[^\r\n]+") do
			local path = line:match("^([^:]+):")
			if path then
				local name = module_name(path)
				if name then add(name, path) end
			end
		end
	end

	-- A loaded module can occasionally be absent from modules.dep after an
	-- out-of-tree driver is inserted. Preserve it as a runtime-only entry.
	for name in pairs(loaded) do
		if not by_name[name] then add(name, "") end
	end

	table.sort(result, function(left, right)
		return left.name < right.name
	end)
	return {
		available = available,
		count = total,
		loaded_count = loaded_count,
		truncated = total > #result,
		modules = result
	}
end

return _M
