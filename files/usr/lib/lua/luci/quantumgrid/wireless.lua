module("luci.quantumgrid.wireless", package.seeall)

local function valid_section(value)
	return type(value) == "string"
		and #value >= 1 and #value <= 32
		and value:match("^[%w_%-]+$") ~= nil
end

local function valid_text(value, minimum, maximum, label)
	if type(value) ~= "string" or #value < minimum or #value > maximum then
		return nil, label .. " must be " .. tostring(minimum) .. "–" .. tostring(maximum) .. " bytes."
	end
	if value:find("[%z\1-\31\127]") then
		return nil, label .. " cannot contain control characters."
	end
	return value
end

function validate_update(radio, section, ssid, encryption, key, hidden, channel, htmode, txpower, allow_open, confirmed)
	if not valid_section(radio) then
		return nil, "Invalid radio section name."
	end
	if not valid_section(section) then
		return nil, "Invalid wireless interface section name."
	end

	local valid_ssid, ssid_error = valid_text(ssid, 1, 32, "SSID")
	if not valid_ssid then return nil, ssid_error end

	local supported_encryption = {
		psk2 = true,
		sae = true,
		["sae-mixed"] = true,
		none = true
	}
	if type(encryption) ~= "string" or not supported_encryption[encryption] then
		return nil, "Choose WPA2-PSK, WPA3-SAE, WPA2/WPA3 mixed or explicitly open security."
	end

	if type(key) ~= "string" then
		return nil, "Wireless passphrase must be text."
	end
	if key ~= "" then
		local valid_key, key_error = valid_text(key, 8, 63, "Wireless passphrase")
		if not valid_key then return nil, key_error end
	end

	if hidden ~= "0" and hidden ~= "1" then
		return nil, "Hidden SSID must be exactly 0 or 1."
	end

	if type(channel) ~= "string" then
		return nil, "Channel must be Auto or a numeric channel."
	end
	if channel ~= "auto" then
		if not channel:match("^%d+$") then
			return nil, "Channel must be Auto or a whole-number channel."
		end
		local number = tonumber(channel)
		if not number or number < 1 or number > 233 then
			return nil, "Channel must be between 1 and 233."
		end
	end

	if type(htmode) ~= "string" or #htmode > 16 or
		(htmode ~= "auto" and not htmode:match("^[A-Z0-9+]+$")) then
		return nil, "Wireless width/PHY mode must be Auto or a driver-reported mode."
	end
	if type(txpower) ~= "string" then
		return nil, "Transmit power must be Auto or a driver-reported dBm value."
	end
	if txpower ~= "auto" then
		if not txpower:match("^%d+$") then
			return nil, "Transmit power must be Auto or a whole-number dBm value."
		end
		local dbm = tonumber(txpower)
		if not dbm or dbm < 0 or dbm > 100 then
			return nil, "Transmit power must be between 0 and 100 dBm."
		end
	end

	if confirmed ~= "1" then
		return nil, "Confirm that applying Wi-Fi settings may disconnect wireless clients."
	end

	if encryption == "none" then
		if key ~= "" then return nil, "An open network cannot have a passphrase." end
		if allow_open ~= "1" then
			return nil, "Explicitly confirm that you intend to create an unencrypted network."
		end
	elseif key == "" then
		-- The handler may preserve an existing key when the security mode is
		-- unchanged. It must reject a blank key when switching to protected mode.
		return {
			radio = radio,
			section = section,
			ssid = valid_ssid,
			encryption = encryption,
			key = "",
			key_supplied = false,
			hidden = hidden,
			channel = channel,
			htmode = htmode,
			txpower = txpower,
			allow_open = false
		}
	end

	return {
		radio = radio,
		section = section,
		ssid = valid_ssid,
		encryption = encryption,
		key = key,
		key_supplied = key ~= "",
		hidden = hidden,
		channel = channel,
		htmode = htmode,
		txpower = txpower,
		allow_open = encryption == "none"
	}
end
