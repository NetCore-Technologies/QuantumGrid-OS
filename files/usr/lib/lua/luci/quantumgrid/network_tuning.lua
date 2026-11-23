local M = {}

local QDISCS = {
	{ name = "cake", module = "sch_cake" },
	{ name = "fq", module = "sch_fq" },
	{ name = "fq_codel", module = "sch_fq_codel" },
	{ name = "sfq", module = "sch_sfq" }
}

local function safe_token(value)
	return type(value) == "string" and #value >= 1 and #value <= 32
		and value:match("^[%w_%-]+$") ~= nil
end

function M.parse_algorithms(value, current)
	if type(value) ~= "string" or #value > 1024 then return nil end
	local result, seen = {}, {}
	for token in value:gmatch("%S+") do
		if not safe_token(token) then return nil end
		if not seen[token] then
			seen[token] = true
			if #result < 32 then result[#result + 1] = token end
		else
			-- Duplicate kernel tokens are harmless; keep a unique inventory.
		end
	end
	if safe_token(current) and not seen[current] and #result < 32 then
		result[#result + 1] = current
	end
	table.sort(result)
	if #result == 0 then return nil end
	return result
end

function M.inspect(deps)
	if type(deps) ~= "table" or type(deps.read) ~= "function" or
		type(deps.access) ~= "function" then
		return { available = false, error = "Runtime inspection dependencies are unavailable." }
	end
	local available_text = deps.read("/proc/sys/net/ipv4/tcp_available_congestion_control")
	local current_cc = deps.read("/proc/sys/net/ipv4/tcp_congestion_control")
	local current_qdisc = deps.read("/proc/sys/net/core/default_qdisc")
	local available = M.parse_algorithms(available_text, current_cc)
	if not available or not safe_token(current_cc) or not safe_token(current_qdisc) then
		return { available = false, error = "Kernel networking tuning values are missing or malformed." }
	end

	local modules_dep = ""
	if type(deps.modules_dep) == "string" and #deps.modules_dep <= 4 * 1024 * 1024 then
		modules_dep = deps.modules_dep
	end
	local qdiscs = {}
	for _, item in ipairs(QDISCS) do
		local loaded = deps.access("/sys/module/" .. item.module) == true
		local installed = modules_dep:find("/" .. item.module .. ".ko", 1, true) ~= nil
		if loaded or installed or current_qdisc == item.name then
			qdiscs[#qdiscs + 1] = item.name
		end
	end
	if #qdiscs == 0 then
		return { available = false, error = "No supported default queueing disciplines were found in the running kernel." }
	end
	local current_found = false
	for _, item in ipairs(qdiscs) do
		if item == current_qdisc then current_found = true break end
	end
	if not current_found then
		return { available = false, error = "The current default queueing discipline is outside the managed allow-list." }
	end

	return {
		available = true,
		congestion_controls = available,
		current_congestion_control = current_cc,
		default_qdiscs = qdiscs,
		current_default_qdisc = current_qdisc,
		runtime_only = true
	}
end

function M.validate(input, snapshot)
	if type(input) ~= "table" or type(snapshot) ~= "table" or snapshot.available ~= true then
		return nil, "Kernel networking tuning inventory is unavailable."
	end
	local cc = input.congestion_control
	if not safe_token(cc) then return nil, "Select a valid TCP congestion-control algorithm." end
	local cc_found = false
	for _, value in ipairs(snapshot.congestion_controls or {}) do
		if value == cc then cc_found = true break end
	end
	if not cc_found then return nil, "The selected TCP congestion-control algorithm is not reported by this kernel." end

	local qdisc = input.default_qdisc
	if not safe_token(qdisc) then return nil, "Select a valid default queueing discipline." end
	local qdisc_found = false
	for _, value in ipairs(snapshot.default_qdiscs or {}) do
		if value == qdisc then qdisc_found = true break end
	end
	if not qdisc_found then return nil, "The selected default queueing discipline is not installed or reported by this kernel." end
	if input.confirmed ~= "1" then
		return nil, "Explicit confirmation is required before changing live TCP and network-device defaults."
	end
	return {
		congestion_control = cc,
		default_qdisc = qdisc,
		previous_congestion_control = snapshot.current_congestion_control,
		previous_default_qdisc = snapshot.current_default_qdisc
	}
end

return M