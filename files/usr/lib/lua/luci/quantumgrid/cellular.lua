local M = {}

local REGISTRATION_STATES = {
	registered = true,
	not_registered = true,
	searching = true,
	denied = true,
	unknown = true
}

local DATA_STATES = {
	connected = true,
	disconnected = true,
	suspended = true,
	unknown = true
}

local function finite_number(value, minimum, maximum)
	local number = tonumber(value)
	if not number or number ~= number or number == math.huge or number == -math.huge then
		return nil
	end
	if number < minimum or number > maximum then return nil end
	return number
end

local function bounded_integer(value, minimum, maximum)
	local number = finite_number(value, minimum, maximum)
	if number == nil or number ~= math.floor(number) then return nil end
	return number
end

local function safe_token(value, maximum)
	if type(value) ~= "string" or #value < 1 or #value > maximum then return nil end
	local normalized = value:lower()
	if not normalized:match("^[a-z0-9][a-z0-9_-]*$") then return nil end
	return normalized
end

local function safe_text(value, maximum)
	if type(value) ~= "string" then return nil end
	local normalized = value:gsub("[%z\1-\31\127]", "")
	normalized = normalized:match("^%s*(.-)%s*$") or ""
	if #normalized < 1 or #normalized > maximum then return nil end
	return normalized
end

local function normalize_radios(value)
	if type(value) ~= "table" then return nil end
	local output, seen = {}, {}
	for index = 1, 64 do
		local radio = value[index]
		if radio == nil then break end
		local token = safe_token(radio, 16)
		if token and not seen[token] and #output < 8 then
			seen[token] = true
			output[#output + 1] = token
		end
	end
	return output
end

function M.normalize_status(input)
	if type(input) ~= "table" then input = {} end
	local modem_present = input.modem_present == true
	local qmi_available = modem_present and input.qmi_available == true
	local sampled_at = bounded_integer(input.sampled_at, 0, 4102444800) or 0
	local result = {
		modem_present = modem_present,
		qmi_available = qmi_available,
		device = qmi_available and "/dev/cdc-wdm0" or "",
		sampled_at = sampled_at
	}

	if not qmi_available then return result end

	local serving = type(input.serving) == "table" and input.serving or nil
	if serving then
		local registration = safe_token(serving.registration, 32)
		if registration and REGISTRATION_STATES[registration] then
			result.registration = registration
			result.registered = registration == "registered"
		end

		local operator = safe_text(serving.plmn_description, 96)
		if operator then result.operator = operator end

		local mcc = bounded_integer(serving.plmn_mcc, 1, 999)
		if mcc then result.mcc = mcc end
		local mnc = bounded_integer(serving.plmn_mnc, 0, 999)
		if mnc then result.mnc = mnc end

		if type(serving.roaming) == "boolean" then
			result.roaming = serving.roaming
		end

		local radios = normalize_radios(serving.radio_interface)
		if radios then result.radio_interfaces = radios end
	end

	local signal = type(input.signal) == "table" and input.signal or nil
	if signal then
		local signal_type = safe_token(signal.type, 16)
		if signal_type then result.signal_type = signal_type end
		local rssi = finite_number(signal.rssi, -150, 0)
		if rssi then result.rssi_dbm = rssi end
		local rsrp = finite_number(signal.rsrp, -160, 0)
		if rsrp then result.rsrp_dbm = rsrp end
		local rsrq = finite_number(signal.rsrq, -40, 0)
		if rsrq then result.rsrq_db = rsrq end
		local snr = finite_number(signal.snr, -100, 100)
		if snr then result.snr_db = snr end
	end

	local data_status = safe_token(input.data_status, 16)
	if data_status and DATA_STATES[data_status] then
		result.data_status = data_status
	end
	return result
end

return M