package.path = "files/usr/lib/lua/?.lua;" .. package.path
local usteer = require "luci.quantumgrid.usteer"

local binding = { network = "corp20", device = "br-lan.20", zone_name = "corp" }
local aps = {
  {
    section = "ap24", radio = "radio0", mode = "ap", ssid = "Corp",
    networks = { "corp20" }, encryption = "sae", key = "correct-horse-battery",
    ieee80211k = "1", ieee80211v = "1",
  },
  {
    section = "ap5", radio = "radio1", mode = "ap", ssid = "Corp",
    networks = { "corp20" }, encryption = "sae", key = "correct-horse-battery",
    ieee80211k = "1", ieee80211v = "1",
  },
  {
    section = "guest24", radio = "radio0", mode = "ap", ssid = "Guest",
    networks = { "guest20" }, encryption = "psk2", key = "different-guest-key",
    ieee80211k = "1", ieee80211v = "1",
  },
}

local function input(overrides)
  local value = {
    confirmed = "1",
    enabled = "1",
    ssids = { "Corp" },
    aggressiveness = "1",
    assoc_steering = "0",
    probe_steering = "0",
    band_steering_interval = "30000",
    band_steering_min_snr = "-65",
    band_steering_threshold = "5",
    load_balancing_threshold = "0",
  }
  for key, item in pairs(overrides or {}) do value[key] = item end
  return value
end

local valid, validation_error = usteer.validate(input(), binding, aps)
assert(valid and valid.enabled and valid.network == "corp20")
assert(#valid.ssids == 1 and valid.ssids[1] == "Corp")
assert(valid.local_mode == false and valid.ipv6 == false and valid.syslog == true)
assert(valid.assoc_steering == false and valid.probe_steering == false)
assert(valid.load_kick_enabled == false and valid.min_snr == 0 and valid.min_connect_snr == 0)
assert(valid.roam_scan_snr == 0 and valid.roam_trigger_snr == 0)
assert(type(valid.aggressiveness_mac_list) == "table" and #valid.aggressiveness_mac_list == 0)
assert(valid.aggressiveness == 1 and valid.band_steering_interval == 30000)
assert(valid.band_steering_min_snr == -65 and valid.band_steering_threshold == 5)
assert(valid.load_balancing_threshold == 0)

local disabled = usteer.validate(input({ enabled = "0" }), nil, {})
assert(disabled and disabled.enabled == false, "disabling roaming must not need AP or network inventory")
assert(usteer.validate(input({ confirmed = "0" }), binding, aps) == nil,
  "roaming changes require explicit confirmation")

local invalid_settings = {
  { enabled = "yes" },
  { aggressiveness = "4" },
  { aggressiveness = "01" },
  { aggressiveness = "-1" },
  { band_steering_interval = "300001" },
  { band_steering_interval = "-1" },
  { band_steering_min_snr = "-91" },
  { band_steering_min_snr = "-34" },
  { band_steering_threshold = "21" },
  { load_balancing_threshold = "33" },
  { assoc_steering = "1" },
  { probe_steering = "1" },
  { assoc_steering = "true" },
}
for _, overrides in ipairs(invalid_settings) do
  local value, err = usteer.validate(input(overrides), binding, aps)
  assert(value == nil and type(err) == "string", "unsafe roaming configuration must be rejected")
end

local invalid_inputs = {
  { { "Unknown" }, binding, aps, "unknown SSID" },
  { { "Corp", "Corp" }, binding, aps, "duplicate SSIDs" },
  { { string.rep("x", 33) }, binding, aps, "oversized SSID" },
  { { "Bad\nSSID" }, binding, aps, "control character SSID" },
  { { "Corp", [3] = "Guest" }, binding, aps, "sparse SSID array" },
  { { "Corp" }, { network = "wan" }, aps, "external network binding" },
}
for _, case in ipairs(invalid_inputs) do
  local value, err = usteer.validate(input({ ssids = case[1] }), case[2], case[3])
  assert(value == nil and type(err) == "string", case[4] .. " must be rejected")
end

local no_11k = {
  aps[1],
  { section = "ap5", radio = "radio1", mode = "ap", ssid = "Corp", networks = { "corp20" },
    encryption = "sae", key = "correct-horse-battery", ieee80211k = "0", ieee80211v = "1" },
}
assert(usteer.validate(input(), binding, no_11k) == nil,
  "all local BSSs in the steering ESS must enable 802.11k and 802.11v")

local different_network = {
  aps[1],
  { section = "ap5", radio = "radio1", mode = "ap", ssid = "Corp", networks = { "guest20" },
    encryption = "sae", key = "correct-horse-battery", ieee80211k = "1", ieee80211v = "1" },
}
assert(usteer.validate(input(), binding, different_network) == nil,
  "same-SSID local APs cannot be bridged to different routed networks")

local different_key = {
  aps[1],
  { section = "ap5", radio = "radio1", mode = "ap", ssid = "Corp", networks = { "corp20" },
    encryption = "sae", key = "different-key-value", ieee80211k = "1", ieee80211v = "1" },
}
assert(usteer.validate(input(), binding, different_key) == nil,
  "same-SSID local APs must use identical security credentials")

local disabled_ap = {
  { section = "ap24", radio = "radio0", mode = "ap", ssid = "Corp", networks = { "corp20" },
    encryption = "sae", key = "correct-horse-battery", ieee80211k = "1", ieee80211v = "1",
    disabled = true, radio_disabled = true },
}
assert(usteer.validate(input(), binding, disabled_ap) == nil,
  "a disabled AP must not satisfy the local ESS prerequisite")

local nodes = {
  ["02:00:00:00:00:01"] = { ssid = "Corp", bssid = "02:00:00:00:00:01", freq = 5180, n_assoc = 4, load = 32, noise = -96 },
  ["02:00:00:00:00:02"] = { ssid = "Corp", bssid = "02:00:00:00:00:02", freq = 2412, n_assoc = 3, load = 20, noise = -95 },
}
local runtime = usteer.summarize_runtime({ aggressiveness = 1 }, nodes, {
  ["192.0.2.20"] = { id = 20 },
  ["192.0.2.21"] = { id = 21 },
})
assert(runtime.running and runtime.local_node_count == 2 and runtime.remote_host_count == 2)
assert(runtime.associated_clients == 7 and not runtime.local_nodes_truncated)
assert(runtime.local_nodes[1].ssid == "Corp" and runtime.local_nodes[1].clients >= 0)

local offline = usteer.summarize_runtime(nil, nil, nil)
assert(not offline.running and offline.local_node_count == 0 and offline.remote_host_count == 0)

print("usteer: trusted network binding, SSID membership, k/v readiness, policy bounds and runtime summaries passed")
