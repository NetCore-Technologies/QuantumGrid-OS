module("luci.quantumgrid.firewall_inventory", package.seeall)

local function rule_value(value, limit)
	local values = {}
	if type(value) == "string" then
		if value ~= "" then table.insert(values, value) end
	elseif type(value) == "table" then
		for _, item in ipairs(value) do
			if type(item) == "string" and item ~= "" and #values < 8 then
				table.insert(values, item)
			end
		end
	end
	return table.concat(values, " "):gsub("[%c]", " "):sub(1, limit or 96)
end

local function has_value(value)
	return (type(value) == "string" and value ~= "") or
		(type(value) == "table" and #value > 0)
end

function summarize_redirect(section, index)
	if type(section) ~= "table" then return nil end
	local name = rule_value(section.name or section[".name"], 64)
	if name == "" then name = "unnamed-redirect-" .. tostring(index or 1) end
	return {
		section = rule_value(section[".name"], 64),
		name = name,
		source_zone = rule_value(section.src, 48),
		destination_zone = rule_value(section.dest, 48),
		protocol = rule_value(section.proto, 48),
		target = rule_value(section.target, 24):upper(),
		family = rule_value(section.family, 16),
		external_port = rule_value(section.src_dport, 64),
		internal_port = rule_value(section.dest_port, 64),
		enabled = section.enabled ~= "0",
		source_ip_match = has_value(section.src_ip),
		source_mac_match = has_value(section.src_mac),
		destination_ip_match = has_value(section.dest_ip),
		source_destination_ip_match = has_value(section.src_dip)
	}
end

function summarize_redirects(sections, limit)
	local result = { redirects = {}, count = 0, truncated = false }
	if type(sections) ~= "table" then return result end
	local maximum = tonumber(limit) or 64
	if maximum < 1 or maximum ~= math.floor(maximum) or maximum > 256 then maximum = 64 end
	for _, section in ipairs(sections) do
		result.count = result.count + 1
		if #result.redirects < maximum then
			local summary = summarize_redirect(section, result.count)
			if summary then table.insert(result.redirects, summary) end
		else
			result.truncated = true
		end
	end
	return result
end

return _M
