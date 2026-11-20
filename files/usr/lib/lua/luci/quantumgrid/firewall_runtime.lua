module("luci.quantumgrid.firewall_runtime", package.seeall)

local MAX_CHAINS = 64
local MAX_NAME = 64
local ALLOWED_HOOKS = {
	input = true,
	output = true,
	forward = true,
	prerouting = true,
	postrouting = true,
	ingress = true
}
local ALLOWED_POLICIES = {
	accept = true,
	drop = true,
	reject = true
}
local ALLOWED_TYPES = {
	filter = true,
	nat = true,
	route = true
}

local function clean(value, limit)
	if type(value) ~= "string" then return "" end
	return value:gsub("[%c]", " "):sub(1, limit or MAX_NAME)
end

local function token(value)
	local result = clean(value, MAX_NAME)
	if result == "" or not result:match("^[%w_.%-]+$") then return nil end
	return result
end

local function initial(sampled_at)
	return {
		available = false,
		table_present = false,
		chains = {},
		chain_count = 0,
		rule_count = 0,
		truncated = false,
		sampled_at = tonumber(sampled_at) or os.time()
	}
end

function parse(payload, sampled_at)
	local result = initial(sampled_at)
	if type(payload) ~= "table" or type(payload.nftables) ~= "table" then
		return result
	end

	local chains = {}
	local chain_by_name = {}
	local rules_by_chain = {}
	local total_chains = 0

	for _, entry in ipairs(payload.nftables) do
		if type(entry) == "table" then
			local table_info = entry.table
			if type(table_info) == "table" and table_info.family == "inet"
				and table_info.name == "fw4" then
				result.table_present = true
			end

			local chain = entry.chain
			if type(chain) == "table" and chain.family == "inet" and chain.table == "fw4" then
				local name = token(chain.name)
				if name then
					total_chains = total_chains + 1
					local hook = clean(chain.hook, 16):lower()
					if not ALLOWED_HOOKS[hook] then hook = "" end
					local policy = clean(chain.policy, 16):lower()
					if not ALLOWED_POLICIES[policy] then policy = "unspecified" end
					local chain_type = clean(chain.type, 16):lower()
					if not ALLOWED_TYPES[chain_type] then chain_type = "unspecified" end
					local priority = tonumber(chain.prio)
					if priority and (priority ~= math.floor(priority) or priority < -100000 or priority > 100000) then
						priority = nil
					end
					if #chains < MAX_CHAINS then
						local summary = {
							name = name,
						hook = hook,
							policy = policy,
							type = chain_type,
							priority = priority,
							device = token(chain.dev) or "",
							rule_count = 0
						}
						table.insert(chains, summary)
						chain_by_name[name] = summary
					end
				end
			end

			local rule = entry.rule
			if type(rule) == "table" and rule.family == "inet" and rule.table == "fw4" then
				local chain_name = token(rule.chain)
				if chain_name then
					rules_by_chain[chain_name] = (rules_by_chain[chain_name] or 0) + 1
					result.rule_count = result.rule_count + 1
				end
			end
		end
	end

	result.chain_count = total_chains
	result.chains = chains
	result.truncated = total_chains > MAX_CHAINS
	if not result.table_present then
		return result
	end
	for name, chain in pairs(chain_by_name) do
		chain.rule_count = rules_by_chain[name] or 0
	end
	result.available = true
	return result
end

function unavailable(sampled_at, truncated)
	local result = initial(sampled_at)
	result.truncated = truncated == true
	return result
end

return _M
