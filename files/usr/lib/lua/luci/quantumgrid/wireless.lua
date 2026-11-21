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

local function valid_radius_host(value)
	if type(value) ~= "string" or #value < 1 or #value > 253
		or value:find("[^%w%.%-]") or value:sub(1, 1) == "."
		or value:sub(-1) == "." or value:find("..", 1, true) then
		return false
	end

	local labels = {}
	for label in value:gmatch("[^.]+") do table.insert(labels, label) end
	if #labels == 4 then
		local ipv4 = true
		for _, label in ipairs(labels) do
			if not label:match("^%d+$") then ipv4 = false break end
			local octet = tonumber(label)
			if not octet or octet > 255 then return false end
		end
		if ipv4 then return true end
	end

	for _, label in ipairs(labels) do
		if #label > 63 or not label:match("^[%w][%w%-]*[%w]$") and #label > 1
			or not label:match("^[%w]$") and #label == 1 then
			return false
		end
	end
	return #labels > 0
end

function validate_roaming_features(encryption, ieee80211k, ieee80211v)
	if ieee80211k ~= "0" and ieee80211k ~= "1" then
		return nil, "802.11k neighbor-report support must be exactly 0 or 1."
	end
	if ieee80211v ~= "0" and ieee80211v ~= "1" then
		return nil, "802.11v BSS-transition support must be exactly 0 or 1."
	end
	if ieee80211v == "1" and ieee80211k ~= "1" then
		return nil, "802.11v BSS transitions require 802.11k neighbor reports."
	end
	if (ieee80211k == "1" or ieee80211v == "1") and encryption == "none" then
		return nil, "802.11k/v roaming features require an encrypted Wi-Fi network."
	end
	return { ieee80211k = ieee80211k, ieee80211v = ieee80211v }
end

function validate_expected_current_channel(expected, current)
	if expected == nil then return true end
	if type(expected) ~= "string" or
		(expected ~= "auto" and (not expected:match("^[1-9]%d?%d?$") or
			not tonumber(expected) or tonumber(expected) > 233)) then
		return nil, "The expected current radio channel must be Auto or a valid channel number.", 400
	end
	if type(current) ~= "string" or expected ~= current then
		return nil, "The radio channel changed after the scan. Re-scan and review a fresh recommendation before applying it.", 409
	end
	return true
end

function validate_update(radio, section, ssid, encryption, key, hidden, channel, htmode, txpower, allow_open, confirmed, radius_server, radius_port, radius_secret, accounting_server, accounting_port, accounting_secret)
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
		wpa2 = true,
		wpa3 = true,
		none = true
	}
	if type(encryption) ~= "string" or not supported_encryption[encryption] then
		return nil, "Choose WPA2-Personal, WPA3-Personal, WPA2/WPA3 mixed, WPA2-Enterprise, WPA3-Enterprise or explicitly open security."
	end
	local enterprise_mode = encryption == "wpa2" or encryption == "wpa3"

	local valid_radius_server, valid_radius_port, valid_radius_secret = "", "1812", ""
	local radius_secret_supplied = false
	if enterprise_mode then
		if not valid_radius_host(radius_server) then
			return nil, "RADIUS server must be an IPv4 address or valid DNS hostname."
		end
		if type(radius_port) ~= "string" or not radius_port:match("^%d+$") then
			return nil, "RADIUS authentication port must be a whole number from 1 to 65535."
		end
		local port_number = tonumber(radius_port)
		if not port_number or port_number < 1 or port_number > 65535 then
			return nil, "RADIUS authentication port must be a whole number from 1 to 65535."
		end
		if type(radius_secret) ~= "string" then
			return nil, "RADIUS shared secret must be text."
		end
		if radius_secret ~= "" then
			local secret, secret_error = valid_text(radius_secret, 16, 128, "RADIUS shared secret")
			if not secret then return nil, secret_error end
			valid_radius_secret = secret
			radius_secret_supplied = true
		end
		valid_radius_server = radius_server
		valid_radius_port = tostring(port_number)
	end

	local valid_accounting_server, valid_accounting_port, valid_accounting_secret = "", "1813", ""
	local accounting_secret_supplied = false
	if enterprise_mode then
		if type(accounting_server) ~= "string" then
			return nil, "RADIUS accounting server must be supplied as a string; use an empty value to disable accounting."
		end
		if accounting_server ~= "" then
			if not valid_radius_host(accounting_server) then
				return nil, "RADIUS accounting server must be an IPv4 address or valid DNS hostname."
			end
			if type(accounting_port) ~= "string" or not accounting_port:match("^%d+$") then
				return nil, "RADIUS accounting port must be a whole number from 1 to 65535."
			end
			local port_number = tonumber(accounting_port)
			if not port_number or port_number < 1 or port_number > 65535 then
				return nil, "RADIUS accounting port must be a whole number from 1 to 65535."
			end
			if type(accounting_secret) ~= "string" then
				return nil, "RADIUS accounting shared secret must be text."
			end
			if accounting_secret ~= "" then
				local secret, secret_error = valid_text(accounting_secret, 16, 128, "RADIUS accounting shared secret")
				if not secret then return nil, secret_error end
				valid_accounting_secret = secret
				accounting_secret_supplied = true
			end
			valid_accounting_server = accounting_server
			valid_accounting_port = tostring(port_number)
		end
	end

	if type(key) ~= "string" then
		return nil, "Wireless passphrase must be text."
	end
	if enterprise_mode and key ~= "" then
		return nil, "WPA2-Enterprise uses the RADIUS shared secret, not a personal Wi-Fi passphrase."
	elseif key ~= "" then
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
			radius_server = valid_radius_server,
			radius_port = valid_radius_port,
			radius_secret = valid_radius_secret,
			radius_secret_supplied = radius_secret_supplied,
			accounting_server = valid_accounting_server,
			accounting_port = valid_accounting_port,
			accounting_secret = valid_accounting_secret,
			accounting_secret_supplied = accounting_secret_supplied,
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
			radius_server = valid_radius_server,
			radius_port = valid_radius_port,
			radius_secret = valid_radius_secret,
			radius_secret_supplied = radius_secret_supplied,
		accounting_server = valid_accounting_server,
		accounting_port = valid_accounting_port,
		accounting_secret = valid_accounting_secret,
		accounting_secret_supplied = accounting_secret_supplied,
		hidden = hidden,
		channel = channel,
		htmode = htmode,
		txpower = txpower,
		allow_open = encryption == "none"
	}
end
