module("luci.quantumgrid.packages", package.seeall)

local function safe_text(value, limit)
	if type(value) ~= "string" then return "" end
	return value:gsub("[%c]", " "):sub(1, limit or 160)
end

local function valid_name(value)
	return type(value) == "string"
		and #value >= 1 and #value <= 128
		and value:match("^[%w][%w%+_.%-]*$") ~= nil
end

local function package_category(name)
	local lower = name:lower()
	if lower:match("^luci%-app%-") then return "LuCI applications" end
	if lower:match("^luci%-proto%-") then return "Network protocols" end
	if lower:match("^kmod%-") or lower:match("^kernel%-") then return "Kernel modules" end
	if lower:match("wireguard") or lower:match("openvpn") or lower:match("tailscale")
		or lower:match("strongswan") or lower:match("ipsec") then return "VPN and tunnels" end
	if lower:match("dns") or lower:match("unbound") or lower:match("odhcp")
		or lower:match("dnsmasq") or lower:match("smartdns") then return "DNS and DHCP" end
	if lower:match("firewall") or lower:match("banip") or lower:match("adblock")
		or lower:match("nft") or lower:match("suricata") then return "Security" end
	if lower:match("mwan") or lower:match("route") or lower:match("bird")
		or lower:match("babeld") or lower:match("batman") then return "Routing" end
	if lower:match("sqm") or lower:match("qos") or lower:match("cake") then return "Quality of service" end
	if lower:match("^luci%-") then return "LuCI components" end
	return "System and networking"
end

local function parse_apk_line(line)
	local name, version = line:match("^([%w%+_.%-]+)%-(%d[%w%.%+~:_%-]*)%s*")
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

local function installed_names(inventory)
	local result = {}
	if type(inventory) == "table" and type(inventory.packages) == "table" then
		for _, item in ipairs(inventory.packages) do
			if type(item) == "table" and valid_name(item.name) then
				result[item.name] = true
			end
		end
	end
	return result
end

local function matches_query(name, version, description, query)
	if query == "" then return true end
	local haystack = (name .. " " .. version .. " " .. description):lower()
	for term in query:lower():gmatch("%S+") do
		if not haystack:find(term, 1, true) then return false end
	end
	return true
end

-- Parse repository data returned by the native APK query interface or OPKG feed list.
-- Filtering and paging happen here, never by interpolating browser input into a command.
function parse_available(manager, source, installed_inventory, maximum, offset, query)
	if manager ~= "apk" and manager ~= "opkg" then
		return { available = false, manager = tostring(manager or "unknown"), count = 0, offset = 0, limit = 0, packages = {} }
	end
	if manager == "apk" and type(source) ~= "table" then
		return { available = false, manager = manager, count = 0, offset = 0, limit = 0, packages = {} }
	end
	if manager == "opkg" and type(source) ~= "string" then
		return { available = false, manager = manager, count = 0, offset = 0, limit = 0, packages = {} }
	end

	local limit = tonumber(maximum) or 40
	limit = math.max(1, math.min(100, math.floor(limit)))
	local page_offset = tonumber(offset) or 0
	page_offset = math.max(0, math.min(5000, math.floor(page_offset)))
	local search = type(query) == "string" and query:sub(1, 64) or ""
	local installed = installed_names(installed_inventory)
	local packages = {}
	local seen = {}
	local count = 0

	local function add(name, version, description, metadata)
		if not valid_name(name) or seen[name] then return end
		version = safe_text(version, 96)
		description = safe_text(description, 320)
		if not matches_query(name, version, description, search) then return end
		seen[name] = true
		count = count + 1
		if count <= page_offset or #packages >= limit then return end

		metadata = type(metadata) == "table" and metadata or {}
		local item = {
			name = safe_text(name, 96),
			version = version,
			description = description,
			manager = manager,
			category = package_category(name),
			installed = installed[name] == true
		}
		local architecture = metadata.arch or metadata.architecture
		if type(architecture) == "string" then item.architecture = safe_text(architecture, 48) end
		local license = metadata.license
		if type(license) == "string" then item.license = safe_text(license, 96) end
		local size = tonumber(metadata["file-size"] or metadata.size)
		if size and size >= 0 and size <= 2147483647 then item.size = math.floor(size) end
		local installed_size = tonumber(metadata["installed-size"] or metadata.installsize)
		if installed_size and installed_size >= 0 and installed_size <= 4294967295 then
			item.installed_size = math.floor(installed_size)
		end
		table.insert(packages, item)
	end

	if manager == "apk" then
		for _, item in ipairs(source) do
			if type(item) == "table" then
				add(item.name, item.version, item.description, item)
			end
		end
	else
		for line in source:gmatch("[^\r\n]+") do
			local name, version, description = line:match("^([%w%+_.%-]+)%s+%-%s+(%S+)%s+%-%s+(.*)$")
			if not name then
				name, version = line:match("^([%w%+_.%-]+)%s+%-%s+(%S+)")
				description = ""
			end
			add(name, version, description, {})
		end
	end

	table.sort(packages, function(left, right)
		return left.name < right.name
	end)
	return {
		available = true,
		manager = manager,
		count = count,
		offset = page_offset,
		limit = limit,
		truncated = page_offset + #packages < count,
		packages = packages
	}
end

return _M
