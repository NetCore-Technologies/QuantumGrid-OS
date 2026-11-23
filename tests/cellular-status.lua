package.path = "files/usr/lib/lua/?.lua;" .. package.path

local cellular = require "luci.quantumgrid.cellular"

local unavailable = cellular.normalize_status(nil)
assert(unavailable.modem_present == false and unavailable.qmi_available == false)
assert(unavailable.device == "" and unavailable.sampled_at == 0)
assert(unavailable.registration == nil and unavailable.roaming == nil)

local active = cellular.normalize_status({
	modem_present = true,
	qmi_available = true,
	sampled_at = 1790000000,
	serving = {
		registration = "registered",
		plmn_description = "  Example Mobile  ",
		plmn_mcc = "505",
		plmn_mnc = 1,
		roaming = false,
		radio_interface = { "LTE", "nr5g", "lte", "WCDMA", "bad radio", "gsm" }
	},
	signal = {
		type = "NR5G",
		rssi = "-70.5",
		rsrp = -92,
		rsrq = -11,
		snr = 17
	},
	data_status = "connected"
})
assert(active.modem_present and active.qmi_available)
assert(active.device == "/dev/cdc-wdm0")
assert(active.registration == "registered" and active.registered == true)
assert(active.operator == "Example Mobile")
assert(active.mcc == 505 and active.mnc == 1)
assert(active.roaming == false, "an explicit non-roaming result must be preserved")
assert(active.signal_type == "nr5g" and active.rssi_dbm == -70.5)
assert(active.rsrp_dbm == -92 and active.rsrq_db == -11 and active.snr_db == 17)
assert(active.data_status == "connected")
assert(#active.radio_interfaces == 4)
assert(active.radio_interfaces[1] == "lte" and active.radio_interfaces[2] == "nr5g")
assert(active.radio_interfaces[3] == "wcdma" and active.radio_interfaces[4] == "gsm")

local incomplete = cellular.normalize_status({
	modem_present = true,
	qmi_available = true,
	sampled_at = "not-a-time",
	serving = {
		registration = "provisioning-injected",
		plmn_description = "Operator\nName",
		plmn_mcc = 0,
		plmn_mnc = 1000,
		roaming = "false",
		radio_interface = { "LTE; reboot", "valid_radio" }
	},
	signal = {
		type = "bad type",
		rssi = -151,
		rsrp = 1,
		rsrq = -41,
		snr = 101
	},
	data_status = "connected; reboot"
})
assert(incomplete.sampled_at == 0)
assert(incomplete.registration == nil and incomplete.registered == nil)
assert(incomplete.operator == "OperatorName")
assert(incomplete.mcc == nil and incomplete.mnc == nil)
assert(incomplete.roaming == nil, "non-boolean roaming input must remain unknown")
assert(#incomplete.radio_interfaces == 1 and incomplete.radio_interfaces[1] == "valid_radio")
assert(incomplete.signal_type == nil)
assert(incomplete.rssi_dbm == nil and incomplete.rsrp_dbm == nil)
assert(incomplete.rsrq_db == nil and incomplete.snr_db == nil)
assert(incomplete.data_status == nil)

local bounded = {}
for index = 1, 16 do bounded[index] = "radio" .. tostring(index) end
local radios = cellular.normalize_status({
	modem_present = true, qmi_available = true,
	serving = { radio_interface = bounded }
})
assert(#radios.radio_interfaces == 8, "radio interface output must be capped")

local no_qmi = cellular.normalize_status({
	modem_present = false, qmi_available = true,
	serving = { registration = "registered" },
	signal = { rsrp = -90 },
	data_status = "connected"
})
assert(not no_qmi.modem_present and not no_qmi.qmi_available and no_qmi.device == "")
assert(no_qmi.registration == nil and no_qmi.rsrp_dbm == nil and no_qmi.data_status == nil)

local impossible = cellular.normalize_status({
	modem_present = true, qmi_available = true,
	sampled_at = math.huge,
	signal = { rssi = math.huge, rsrp = -math.huge, snr = 0/0 }
})
assert(impossible.sampled_at == 0)
assert(impossible.rssi_dbm == nil and impossible.rsrp_dbm == nil and impossible.snr_db == nil)

print("cellular-status: QMI telemetry normalization, privacy bounds and unavailable-state tests passed")