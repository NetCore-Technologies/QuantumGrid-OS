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

function validate_queue_update(section, enabled, download, upload)
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

	return {
		section = section,
		enabled = enabled,
		download = tostring(download_rate),
		upload = tostring(upload_rate)
	}
end

