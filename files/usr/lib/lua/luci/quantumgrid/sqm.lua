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

