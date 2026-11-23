package.path = "files/usr/lib/lua/?.lua;" .. package.path
local wireless = require "luci.quantumgrid.wireless"

local radio_enable = wireless.validate_radio_toggle("radio0", "1", "1", "1")
assert(radio_enable and radio_enable.enabled == true and radio_enable.expected_disabled == true)
assert(radio_enable.desired_disabled == false)
local radio_disable = wireless.validate_radio_toggle("radio1", "0", "0", "1")
assert(radio_disable and radio_disable.enabled == false and radio_disable.desired_disabled == true)
assert(radio_disable.expected_disabled == false)
for _, request in ipairs({
	{ "../radio0", "1", "1", "1" },
	{ "radio0", "true", "1", "1" },
	{ "radio0", "1", "true", "1" },
	{ "radio0", "1", "1", "0" },
	{ "radio0", "0", nil, "1" },
	{ "radio0", "1;uci", "0", "1" },
}) do
	local result, err = wireless.validate_radio_toggle(request[1], request[2], request[3], request[4])
	assert(result == nil and type(err) == "string" and #err > 0,
		"invalid or unconfirmed radio state change must be rejected")
end

local valid = wireless.validate_update(
	"radio0", "default_radio0", "QuantumGrid", "sae-mixed", "strong-password-123",
	"0", "auto", "HE80", "18", "0", "1"
)
assert(valid ~= nil, "valid WPA2/WPA3 AP settings should pass")
assert(valid.radio == "radio0" and valid.section == "default_radio0")
assert(valid.ssid == "QuantumGrid" and valid.encryption == "sae-mixed")
assert(valid.key_supplied == true and valid.hidden == "0" and valid.channel == "auto")
assert(valid.htmode == "HE80" and valid.txpower == "18")

local preserve = wireless.validate_update(
	"radio0", "default_radio0", "QuantumGrid 2", "psk2", "",
	"1", "36", "HE40", "auto", "0", "1"
)
assert(preserve ~= nil and preserve.key_supplied == false,
	"blank key must be representable for preserving an existing passphrase")
assert(preserve.htmode == "HE40" and preserve.txpower == "auto")

local open = wireless.validate_update(
	"radio0", "default_radio0", "Guest", "none", "",
	"0", "auto", "auto", "auto", "1", "1"
)
assert(open ~= nil and open.allow_open == true, "explicit open-network confirmation should pass")

local enterprise = wireless.validate_update(
	"radio0", "default_radio0", "Staff", "wpa2", "",
	"0", "auto", "auto", "auto", "0", "1",
	"radius.example.com", "1812", "a-strong-radius-shared-secret",
	"", "1813", ""
)
assert(enterprise ~= nil, "WPA2-Enterprise with an external RADIUS server should pass")
assert(enterprise.encryption == "wpa2" and enterprise.key_supplied == false)
assert(enterprise.radius_server == "radius.example.com" and enterprise.radius_port == "1812")
assert(enterprise.radius_secret_supplied == true and enterprise.radius_secret == "a-strong-radius-shared-secret")

local enterprise_preserve = wireless.validate_update(
	"radio0", "default_radio0", "Staff", "wpa2", "",
	"0", "auto", "auto", "auto", "0", "1",
	"192.0.2.10", "1812", "",
	"", "1813", ""
)
assert(enterprise_preserve ~= nil and enterprise_preserve.radius_secret_supplied == false,
	"blank RADIUS secret must be representable so an existing secret can be preserved")

local function rejected_enterprise(server, port, secret, label)
	local result, err = wireless.validate_update(
		"radio0", "default_radio0", "Staff", "wpa2", "",
		"0", "auto", "auto", "auto", "0", "1", server, port, secret, "", "1813", ""
	)
	assert(result == nil, label .. " should be rejected")
	assert(type(err) == "string" and #err > 0, label .. " should explain the rejection")
end
rejected_enterprise("https://radius.example.com", "1812", "a-strong-radius-shared-secret", "RADIUS URL instead of hostname")
rejected_enterprise("999.1.1.1", "1812", "a-strong-radius-shared-secret", "invalid IPv4 RADIUS address")
rejected_enterprise("radius.example.com", "0", "a-strong-radius-shared-secret", "zero RADIUS port")
rejected_enterprise("radius.example.com", "65536", "a-strong-radius-shared-secret", "out-of-range RADIUS port")
rejected_enterprise("radius.example.com", "1812;uci", "a-strong-radius-shared-secret", "injected RADIUS port")
rejected_enterprise("radius.example.com", "1812", "short", "weak RADIUS shared secret")
rejected_enterprise("radius.example.com", "1812", string.rep("s", 129), "oversized RADIUS shared secret")
rejected_enterprise("radius.example.com", "1812", "a-strong-radius-secret\n", "control character in RADIUS shared secret")

local enterprise_missing_accounting_field, accounting_field_error = wireless.validate_update(
	"radio0", "default_radio0", "Staff", "wpa2", "",
	"0", "auto", "auto", "auto", "0", "1",
	"radius.example.com", "1812", "a-strong-radius-shared-secret"
)
assert(enterprise_missing_accounting_field == nil and
	type(accounting_field_error) == "string" and
	accounting_field_error:find("empty value to disable accounting", 1, true),
	"a missing accounting field must not silently disable existing accounting")

local wpa3_enterprise = wireless.validate_update(
	"radio0", "default_radio0", "Secure Staff", "wpa3", "",
	"0", "auto", "auto", "auto", "0", "1",
	"radius.example.com", "1812", "a-strong-radius-shared-secret",
	"", "1813", ""
)
assert(wpa3_enterprise ~= nil, "WPA3-Enterprise with RADIUS authentication should pass")
assert(wpa3_enterprise.encryption == "wpa3" and wpa3_enterprise.key_supplied == false)
assert(wpa3_enterprise.radius_server == "radius.example.com")
assert(wpa3_enterprise.accounting_server == "")

local wpa3_personal_key = wireless.validate_update(
	"radio0", "default_radio0", "Secure Staff", "wpa3", "personal-password-123",
	"0", "auto", "auto", "auto", "0", "1",
	"radius.example.com", "1812", "a-strong-radius-shared-secret",
	"", "1813", ""
)
assert(wpa3_personal_key == nil, "WPA3-Enterprise must not accept a personal passphrase")

local enterprise_accounting = wireless.validate_update(
	"radio0", "default_radio0", "Staff", "wpa2", "",
	"0", "auto", "auto", "auto", "0", "1",
	"radius.example.com", "1812", "a-strong-radius-shared-secret",
	"accounting.example.com", "1813", "another-long-radius-secret"
)
assert(enterprise_accounting ~= nil, "valid RADIUS accounting configuration should pass")
assert(enterprise_accounting.accounting_server == "accounting.example.com")
assert(enterprise_accounting.accounting_port == "1813")
assert(enterprise_accounting.accounting_secret_supplied == true)

local enterprise_accounting_defaults = wireless.validate_update(
	"radio0", "default_radio0", "Staff", "wpa2", "",
	"0", "auto", "auto", "auto", "0", "1",
	"radius.example.com", "1812", "a-strong-radius-shared-secret",
	"", "1813", ""
)
assert(enterprise_accounting_defaults ~= nil and enterprise_accounting_defaults.accounting_server == "")
assert(enterprise_accounting_defaults.accounting_secret_supplied == false,
	"an empty accounting server should disable accounting and not request a secret")

local function rejected_accounting(server, port, secret, label)
	local result, err = wireless.validate_update(
		"radio0", "default_radio0", "Staff", "wpa2", "",
		"0", "auto", "auto", "auto", "0", "1",
		"radius.example.com", "1812", "a-strong-radius-shared-secret",
		server, port, secret
	)
	assert(result == nil, label .. " should be rejected")
	assert(type(err) == "string" and #err > 0, label .. " should explain the rejection")
end
rejected_accounting("https://accounting.example.com", "1813", "another-long-radius-secret", "RADIUS accounting URL")
rejected_accounting("accounting.example.com", "0", "another-long-radius-secret", "zero RADIUS accounting port")
rejected_accounting("accounting.example.com", "65536", "another-long-radius-secret", "out-of-range RADIUS accounting port")
rejected_accounting("accounting.example.com", "1813;uci", "another-long-radius-secret", "injected RADIUS accounting port")
rejected_accounting("accounting.example.com", "1813", "short", "short RADIUS accounting secret")
rejected_accounting("accounting.example.com", "1813", string.rep("s", 129), "oversized RADIUS accounting secret")
rejected_accounting("accounting.example.com", "1813", "secret-with-control\n", "control character in RADIUS accounting secret")

local enterprise_with_psk = wireless.validate_update(
	"radio0", "default_radio0", "Staff", "wpa2", "personal-password-123",
	"0", "auto", "auto", "auto", "0", "1",
	"radius.example.com", "1812", "a-strong-radius-shared-secret",
	"", "1813", ""
)
assert(enterprise_with_psk == nil, "WPA2-Enterprise must not accept a personal passphrase as a RADIUS secret")

local function rejected(radio, section, ssid, encryption, key, hidden, channel, htmode, txpower, allow_open, confirmed, label)
	local result, err = wireless.validate_update(
		radio, section, ssid, encryption, key, hidden, channel, htmode, txpower, allow_open, confirmed
	)
	assert(result == nil, label .. " should be rejected")
	assert(type(err) == "string" and #err > 0, label .. " should explain the rejection")
end

rejected("../network", "default_radio0", "Test", "psk2", "password123", "0", "auto", "auto", "auto", "0", "1", "path-like radio section")
rejected("radio0", "wireless;uci", "Test", "psk2", "password123", "0", "auto", "auto", "auto", "0", "1", "command-like interface section")
rejected("radio0", "default_radio0", "", "psk2", "password123", "0", "auto", "auto", "auto", "0", "1", "empty SSID")
rejected("radio0", "default_radio0", string.rep("x", 33), "psk2", "password123", "0", "auto", "auto", "auto", "0", "1", "oversized SSID")
rejected("radio0", "default_radio0", "Bad\nSSID", "psk2", "password123", "0", "auto", "auto", "auto", "0", "1", "control character in SSID")
rejected("radio0", "default_radio0", "Test", "wpa3-mixed", "password123", "0", "auto", "auto", "auto", "0", "1", "unsupported enterprise transition mode")
rejected("radio0", "default_radio0", "Test", "sae", "short", "0", "auto", "auto", "auto", "0", "1", "short passphrase")
rejected("radio0", "default_radio0", "Test", "psk2", "password123", "yes", "auto", "auto", "auto", "0", "1", "non-canonical hidden flag")
rejected("radio0", "default_radio0", "Test", "psk2", "password123", "0", "1.5", "auto", "auto", "0", "1", "fractional channel")
rejected("radio0", "default_radio0", "Test", "psk2", "password123", "0", "234", "auto", "auto", "0", "1", "out-of-range channel")
rejected("radio0", "default_radio0", "Guest", "none", "", "0", "auto", "auto", "auto", "0", "1", "unconfirmed open network")
rejected("radio0", "default_radio0", "Guest", "none", "password123", "0", "auto", "auto", "auto", "1", "1", "open network with passphrase")
rejected("radio0", "default_radio0", "Test", "psk2", "password123", "0", "auto", "auto", "auto", "0", "0", "missing disconnect acknowledgement")
rejected("radio0", "default_radio0", "Test", "psk2", "password123", "0", "auto", "not a width", "auto", "0", "1", "invalid width")
rejected("radio0", "default_radio0", "Test", "psk2", "password123", "0", "auto", "HE80;uci", "auto", "0", "1", "injected width")
rejected("radio0", "default_radio0", "Test", "psk2", "password123", "0", "auto", "HE80", "18.5", "0", "1", "fractional power")
rejected("radio0", "default_radio0", "Test", "psk2", "password123", "0", "auto", "HE80", "101", "0", "1", "out-of-range power")

local roaming = wireless.validate_roaming_features("sae", "1", "1")
assert(roaming and roaming.ieee80211k == "1" and roaming.ieee80211v == "1")
assert(wireless.validate_roaming_features("sae", "0", "1") == nil,
  "802.11v must require 802.11k")
assert(wireless.validate_roaming_features("none", "1", "0") == nil,
  "802.11k must not be enabled on an open network")
assert(wireless.validate_roaming_features("psk2", "2", "0") == nil)
assert(wireless.validate_roaming_features("psk2", "1", "yes") == nil)
assert(wireless.validate_roaming_features("psk2", "0", "0"))

assert(wireless.validate_expected_current_channel(nil, "auto") == true,
  "legacy wireless updates without a channel precondition must remain supported")
assert(wireless.validate_expected_current_channel("auto", "auto") == true)
assert(wireless.validate_expected_current_channel("36", "36") == true)
local stale_channel, stale_channel_error, stale_channel_status =
  wireless.validate_expected_current_channel("36", "44")
assert(stale_channel == nil and stale_channel_status == 409)
assert(stale_channel_error:find("changed after the scan", 1, true))
for _, expected in ipairs({ "", "0", "234", "001", "1.5", "../wifi", "1;uci" }) do
  local result, err, status = wireless.validate_expected_current_channel(expected, "1")
  assert(result == nil and type(err) == "string" and status == 400,
    "invalid expected channel must be rejected: " .. expected)
end


local create_ap = wireless.validate_create(
	"radio0", "QuantumGrid Guest", "sae-mixed", "secure-guest-passphrase", "0", "1")
assert(create_ap and create_ap.radio == "radio0" and create_ap.ssid == "QuantumGrid Guest")
assert(create_ap.encryption == "sae-mixed" and create_ap.key == "secure-guest-passphrase")
assert(create_ap.ieee80211k == "0" and create_ap.ieee80211v == "0")
assert(wireless.validate_create("radio0", "Hidden", "sae", "valid-passphrase-123", "1", "1").hidden == "1")

local function reject_create(radio, ssid, encryption, key, hidden, confirmed, label)
	local result, err = wireless.validate_create(radio, ssid, encryption, key, hidden, confirmed)
	assert(result == nil, label .. " should be rejected")
	assert(type(err) == "string" and #err > 0, label .. " should explain the rejection")
end
reject_create("../radio0", "Guest", "psk2", "valid-passphrase-123", "0", "1", "path-like radio")
reject_create("radio0", "", "psk2", "valid-passphrase-123", "0", "1", "empty SSID")
reject_create("radio0", string.rep("x", 33), "psk2", "valid-passphrase-123", "0", "1", "oversized SSID")
reject_create("radio0", "Bad\nSSID", "psk2", "valid-passphrase-123", "0", "1", "control character in SSID")
reject_create("radio0", "Guest", "none", "", "0", "1", "open network")
reject_create("radio0", "Guest", "wpa2", "", "0", "1", "enterprise security without RADIUS configuration")
reject_create("radio0", "Guest", "psk2", "short", "0", "1", "short passphrase")
reject_create("radio0", "Guest", "psk2", string.rep("x", 64), "0", "1", "oversized passphrase")
reject_create("radio0", "Guest", "psk2", "valid-passphrase-123\n", "0", "1", "control character in passphrase")
reject_create("radio0", "Guest", "psk2", "valid-passphrase-123", "true", "1", "non-canonical hidden flag")
reject_create("radio0", "Guest", "psk2", "valid-passphrase-123", "0", "0", "missing disconnect acknowledgement")

print("wireless-controls: all validation tests passed")
