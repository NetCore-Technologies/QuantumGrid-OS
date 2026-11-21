module("luci.quantumgrid.sqm", package.seeall)

local MIN_RATE_KBPS = 64
local MAX_RATE_KBPS = 1000000

local function parse_rate(value, label)
	if type(value) ~= "string" or not value:match("^%d+$") then
		return nil, label .. " must be a whole number of kbit/s."
	end
	local rate = tonumber(value)
	if not rate or rate < MIN_RATE_KBPS or rate > MAX_RATE_KBPS then
		return nil, label .. " must be between 64 and 1000000 kbit/s."
	end
	return rate
end

local function parse_integer(value, label, minimum, maximum)
	if type(value) ~= "string" or not value:match("^-?%d+$") then
		return nil, label .. " must be a whole number."
	end
	local parsed = tonumber(value)
	if not parsed or parsed < minimum or parsed > maximum then
		return nil, label .. " must be between " .. minimum .. " and " .. maximum .. "."
	end
	return parsed
end

function validate_queue_update(section, enabled, download, upload, linklayer, overhead, tc_mpu)
	if type(section) ~= "string" or #section < 1 or #section > 32
		or not section:match("^[%w_%-]+$") then
		return nil, "Invalid SQM queue section name."
	end
	if enabled ~= "0" and enabled ~= "1" then
		return nil, "Enabled must be exactly 0 or 1."
	end

	local download_rate, download_error = parse_rate(download, "Download rate")
	if not download_rate then return nil, download_error end
	local upload_rate, upload_error = parse_rate(upload, "Upload rate")
	if not upload_rate then return nil, upload_error end

	local update = {
		section = section,
		enabled = enabled,
		download = tostring(download_rate),
		upload = tostring(upload_rate)
	}
	if linklayer ~= nil or overhead ~= nil or tc_mpu ~= nil then
		local allowed_linklayers = { none = true, ethernet = true, atm = true, ptm = true }
		if type(linklayer) ~= "string" or not allowed_linklayers[linklayer] then
			return nil, "Link layer must be none, ethernet, atm or ptm."
		end
		local overhead_value, overhead_error = parse_integer(overhead, "Packet overhead", -64, 256)
		if overhead_value == nil then return nil, overhead_error end
		local mpu_value, mpu_error = parse_integer(tc_mpu, "Minimum packet unit", 0, 256)
		if mpu_value == nil then return nil, mpu_error end
		update.linklayer = linklayer
		update.overhead = tostring(overhead_value)
		update.tc_mpu = tostring(mpu_value)
	end
	return update
end


local MAX_QDISCS = 64

-- Parse the fixed, read-only output of "tc -s qdisc show". Unrecognised or
-- empty output is not reported as a successful runtime inventory.
function parse_qdisc_inventory(output)
	local qdiscs, current = {}, nil
	local header_count, truncated = 0, false
	if type(output) ~= "string" then return false, qdiscs, false end

	for line in output:gmatch("[^\\r\\n]+") do
		local kind, handle, details = line:match("^qdisc%s+(%S+)%s+(%S+)%s*(.*)$")
		if kind then
			header_count = header_count + 1
			if #qdiscs < MAX_QDISCS then
				current = {
					kind = kind,
					handle = handle,
					device = details:match("dev%s+(%S+)"),
					parent = details:match("parent%s+(%S+)"),
					root = details:match("%f[%a]root%f[%A]") ~= nil
				}
				table.insert(qdiscs, current)
			else
				truncated = true
				current = nil
			end
		elseif current then
			local bytes, packets, dropped, overlimits, requeues =
				line:match("Sent%s+(%d+)%s+bytes%s+(%d+)%s+pkt%s+%(%s*dropped%s+(%d+),%s*overlimits%s+(%d+)%s+requeues%s+(%d+)%)")
			if bytes then
				current.bytes = tonumber(bytes)
				current.packets = tonumber(packets)
				current.dropped = tonumber(dropped)
				current.overlimits = tonumber(overlimits)
				current.requeues = tonumber(requeues)
			end
			local backlog_bytes, backlog_packets = line:match("backlog%s+(%d+)b%s+(%d+)p")
			if backlog_bytes then
				current.backlog_bytes = tonumber(backlog_bytes)
				current.backlog_packets = tonumber(backlog_packets)
			end
		end
	end

	return header_count > 0, qdiscs, truncated
end

-- Compare an enabled queue's configured root discipline with the live kernel
-- inventory. This is deliberately an observation, not a claim that ingress
-- shaping or end-to-end bandwidth/latency behaviour has been verified.
function queue_runtime_state(queue, qdiscs, runtime_available, inventory_truncated)
	if type(queue) ~= "table" then return "unconfigured" end
	if queue.enabled ~= true then return "disabled" end
	if runtime_available ~= true then return "unavailable" end
	local expected_kind = type(queue.qdisc) == "string" and queue.qdisc:lower() or ""
	local expected_device = type(queue.interface) == "string" and queue.interface or ""
	if expected_kind == "" or expected_device == "" then return "unconfigured" end
	for _, qdisc in ipairs(type(qdiscs) == "table" and qdiscs or {}) do
		if type(qdisc) == "table" and qdisc.root == true
			and type(qdisc.kind) == "string" and qdisc.kind:lower() == expected_kind
			and qdisc.device == expected_device then
			return "observed"
		end
	end
	if inventory_truncated == true then return "inventory_truncated" end
	return "not_observed"
end
