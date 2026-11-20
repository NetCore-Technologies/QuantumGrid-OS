package.path = "files/usr/lib/lua/?.lua;" .. package.path
local wireless = require "luci.quantumgrid.wireless"

local valid = wireless.validate_update(
	"radio0", "default_radio0", "QuantumGrid", "sae-mixed", "strong-password-123",
	"0", "auto", "0", "1"
)
assert(valid ~= nil, "valid WPA2/WPA3 AP settings should pass")
assert(valid.radio == "radio0" and valid.section == "default_radio0")
assert(valid.ssid == "QuantumGrid" and valid.encryption == "sae-mixed")
assert(valid.key_supplied == true and valid.hidden == "0" and valid.channel == "auto")

local preserve = wireless.validate_update(
	"radio0", "default_radio0", "QuantumGrid 2", "psk2", "",
	"1", "36", "0", "1"
)
assert(preserve ~= nil and preserve.key_supplied == false,
	"blank key must be representable for preserving an existing passphrase")

local open = wireless.validate_update(
	"radio0", "default_radio0", "Guest", "none", "",
	"0", "auto", "1", "1"
)
assert(open ~= nil and open.allow_open == true, "explicit open-network confirmation should pass")

local function rejected(radio, section, ssid, encryption, key, hidden, channel, allow_open, confirmed, label)
	local result, err = wireless.validate_update(radio, section, ssid, encryption, key, hidden, channel, allow_open, confirmed)
	assert(result == nil, label .. " should be rejected")
	assert(type(err) == "string" and #err > 0, label .. " should explain the rejection")
end

rejected("../network", "default_radio0", "Test", "psk2", "password123", "0", "auto", "0", "1", "path-like radio section")
rejected("radio0", "wireless;uci", "Test", "psk2", "password123", "0", "auto", "0", "1", "command-like interface section")
rejected("radio0", "default_radio0", "", "psk2", "password123", "0", "auto", "0", "1", "empty SSID")
rejected("radio0", "default_radio0", string.rep("x", 33), "psk2", "password123", "0", "auto", "0", "1", "oversized SSID")
rejected("radio0", "default_radio0", "Bad\nSSID", "psk2", "password123", "0", "auto", "0", "1", "control character in SSID")
rejected("radio0", "default_radio0", "Test", "wpa3", "password123", "0", "auto", "0", "1", "unsupported encryption string")
rejected("radio0", "default_radio0", "Test", "sae", "short", "0", "auto", "0", "1", "short passphrase")
rejected("radio0", "default_radio0", "Test", "psk2", "password123", "yes", "auto", "0", "1", "non-canonical hidden flag")
rejected("radio0", "default_radio0", "Test", "psk2", "password123", "0", "1.5", "0", "1", "fractional channel")
rejected("radio0", "default_radio0", "Test", "psk2", "password123", "0", "234", "0", "1", "out-of-range channel")
rejected("radio0", "default_radio0", "Guest", "none", "", "0", "auto", "0", "1", "unconfirmed open network")
rejected("radio0", "default_radio0", "Guest", "none", "password123", "0", "auto", "1", "1", "open network with passphrase")
rejected("radio0", "default_radio0", "Test", "psk2", "password123", "0", "auto", "0", "0", "missing disconnect acknowledgement")

print("wireless-controls: all validation tests passed")
