module("luci.quantumgrid.routing", package.seeall)

local MAX_POLICY_RULES = 64

local function safe_token(value)
	if type(value) ~= "string" or #value == 0 or #value > 96 then
		return nil
	end
	if not value:match("^[%w_.:%-/%+]+$") then
		return nil
	end
	return value
end

local function selector_value(selectors, name, fallback)
	local value
	if name == "from" and selectors:match("^from%s+") then
		value = selectors:match("^from%s+(%S+)")
	else
		value = selectors:match("%s" .. name .. "%s+(%S+)")
	end
	return safe_token(value) or fallback
end

local function clean_selectors(value)
	return value:gsub("[%c]", " "):gsub("%s+", " "):sub(1, 192)
end

function parse_policy_rules(output, family)
	local rules = {}
	local count = 0
	local truncated = false
	if type(output) ~= "string" or (family ~= "IPv4" and family ~= "IPv6") then
		return rules, count, truncated
	end

	for line in output:gmatch("[^\\r\\n]+") do
		local priority_text, selectors = line:match("^%s*(%d+):%s*(.-)%s*$")
		local priority = tonumber(priority_text)
		if priority and priority >= 0 and priority <= 4294967295 and priority == math.floor(priority) then
			count = count + 1
			if #rules < MAX_POLICY_RULES then
				local table_name = selectors:match("%slookup%s+(%S+)") or selectors:match("%stable%s+(%S+)")
				table_name = safe_token(table_name) or ""
				local action = "lookup"
				if table_name == "" then
					action = selectors:match("%s(blackhole)%s*$")
						or selectors:match("%s(unreachable)%s*$")
						or selectors:match("%s(prohibit)%s*$")
						or selectors:match("%s(goto)%s+[%d]+%s*$")
						or "other"
				end

				table.insert(rules, {
					family = family,
					priority = priority,
					source = selector_value(selectors, "from", "all"),
					destination = selector_value(selectors, "to", "all"),
					fwmark = selector_value(selectors, "fwmark", ""),
					input_interface = selector_value(selectors, "iif", ""),
					output_interface = selector_value(selectors, "oif", ""),
					protocol = selector_value(selectors, "ipproto", ""),
					uid_range = selector_value(selectors, "uidrange", ""),
					table = table_name,
					action = action,
					selectors = clean_selectors(selectors)
				})
			else
				truncated = true
			end
		end
	end

	table.sort(rules, function(left, right)
		if left.priority ~= right.priority then
			return left.priority < right.priority
		end
		return left.selectors < right.selectors
	end)
	return rules, count, truncated
end
