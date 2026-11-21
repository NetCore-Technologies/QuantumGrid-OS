package.path = "files/usr/lib/lua/?.lua;" .. package.path
local usteer = require "luci.quantumgrid.usteer"

local binding = { network = "corp20", device = "br-lan.20", zone_name = "corp" }
local aps = {
  {
    section = "ap24", radio = "radio0", mode = "ap", ssid = "Corp",
    networks = { "corp20" }, encryption = "sae", key = "correct-horse-battery", ieee80211w = "2", dynamic_vlan = "0",
    acct_server = "", acct_port = 1813, acct_secret = "", ieee80211k = "1", ieee80211v = "1",
  },
  {
    section = "ap5", radio = "radio1", mode = "ap", ssid = "Corp",
    networks = { "corp20" }, encryption = "sae", key = "correct-horse-battery", ieee80211w = "2", dynamic_vlan = "0",
    acct_server = "", acct_port = 1813, acct_secret = "", ieee80211k = "1", ieee80211v = "1",
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
    encryption = "sae", key = "different-key-value", ieee80211w = "2", dynamic_vlan = "0",
    acct_server = "", acct_port = 1813, acct_secret = "", ieee80211k = "1", ieee80211v = "1" },
}
assert(usteer.validate(input(), binding, different_key) == nil,
  "same-SSID local APs must use identical security credentials")

local different_pmf = {
  aps[1],
  { section = "ap5", radio = "radio1", mode = "ap", ssid = "Corp", networks = { "corp20" },
    encryption = "sae", key = "correct-horse-battery", ieee80211w = "1", dynamic_vlan = "0",
    acct_server = "", acct_port = 1813, acct_secret = "", ieee80211k = "1", ieee80211v = "1" },
}
assert(usteer.validate(input(), binding, different_pmf) == nil,
  "same-SSID local APs must use identical protected-management-frame policy")

local different_vlan_mode = {
  aps[1],
  { section = "ap5", radio = "radio1", mode = "ap", ssid = "Corp", networks = { "corp20" },
    encryption = "sae", key = "correct-horse-battery", ieee80211w = "2", dynamic_vlan = "2",
    acct_server = "", acct_port = 1813, acct_secret = "", ieee80211k = "1", ieee80211v = "1" },
}
assert(usteer.validate(input(), binding, different_vlan_mode) == nil,
  "same-SSID local APs must use the same dynamic VLAN mode")

local different_accounting = {
  aps[1],
  { section = "ap5", radio = "radio1", mode = "ap", ssid = "Corp", networks = { "corp20" },
    encryption = "sae", key = "correct-horse-battery", ieee80211w = "2", dynamic_vlan = "0",
    acct_server = "accounting.corp.example", acct_port = 1813, acct_secret = "secret-value-16-byte",
    ieee80211k = "1", ieee80211v = "1" },
}
assert(usteer.validate(input(), binding, different_accounting) == nil,
  "same-SSID local APs must not silently diverge in accounting destinations or credentials")

local disabled_ap = {
  { section = "ap24", radio = "radio0", mode = "ap", ssid = "Corp", networks = { "corp20" },
    encryption = "sae", key = "correct-horse-battery", ieee80211k = "1", ieee80211v = "1",
    disabled = true, radio_disabled = true },
}
assert(usteer.validate(input(), binding, disabled_ap) == nil,
  "a disabled AP must not satisfy the local ESS prerequisite")

local enterprise_aps = {
  {
    section = "eap24", radio = "radio0", mode = "ap", ssid = "Corp",
    networks = { "corp20" }, encryption = "wpa2",
    key = "", auth_server = "192.0.2.10", auth_port = 1812, auth_secret = "primary-secret-value",
    auth_server2 = "", auth_port2 = 1812, auth_secret2 = "",
    acct_server = "192.0.2.12", acct_port = 1813, acct_secret = "accounting-secret-value",
    acct_server2 = "", acct_port2 = 1813, acct_secret2 = "",
    nasid = "office-ess", ieee80211w = "1", dynamic_vlan = "0",
    ieee80211r = "1", mobility_domain = "a1b2", ft_over_ds = "1",
    ft_psk_generate_local = "0", ieee80211k = "1", ieee80211v = "1",
  },
  {
    section = "eap5", radio = "radio1", mode = "ap", ssid = "Corp",
    networks = { "corp20" }, encryption = "wpa2",
    key = "", auth_server = "192.0.2.10", auth_port = 1812, auth_secret = "primary-secret-value",
    auth_server2 = "", auth_port2 = 1812, auth_secret2 = "",
    acct_server = "192.0.2.12", acct_port = 1813, acct_secret = "accounting-secret-value",
    acct_server2 = "", acct_port2 = 1813, acct_secret2 = "",
    nasid = "office-ess", ieee80211w = "1", dynamic_vlan = "0",
    ieee80211r = "1", mobility_domain = "a1b2", ft_over_ds = "1",
    ft_psk_generate_local = "0", ieee80211k = "1", ieee80211v = "1",
  },
}
assert(usteer.validate(input(), binding, enterprise_aps),
  "identical WPA-EAP APs must compare RADIUS, accounting, 802.11r and MFP settings")
local different_radius_secret = { enterprise_aps[1], {} }
for key, value in pairs(enterprise_aps[2]) do different_radius_secret[2][key] = value end
different_radius_secret[2].auth_secret = "changed-primary-secret"
assert(usteer.validate(input(), binding, different_radius_secret) == nil,
  "same-SSID enterprise APs must have identical RADIUS secrets")
local different_mfp = { enterprise_aps[1], {} }
for key, value in pairs(enterprise_aps[2]) do different_mfp[2][key] = value end
different_mfp[2].ieee80211w = "0"
assert(usteer.validate(input(), binding, different_mfp) == nil,
  "same-SSID APs must use matching management-frame-protection policy")
local different_ft = { enterprise_aps[1], {} }
for key, value in pairs(enterprise_aps[2]) do different_ft[2][key] = value end
different_ft[2].mobility_domain = "c3d4"
assert(usteer.validate(input(), binding, different_ft) == nil,
  "same-SSID APs must use the same 802.11r mobility domain")

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

local expected_policy = {
  syslog = true,
  ipv6 = false,
  local_mode = false,
  assoc_steering = false,
  probe_steering = false,
  load_kick_enabled = false,
  min_snr = 0,
  min_connect_snr = 0,
  roam_scan_snr = 0,
  roam_trigger_snr = 0,
  aggressiveness_override_count = 0,
  aggressiveness = 1,
  assoc_steering = false,
  probe_steering = false,
  band_steering_interval = 30000,
  band_steering_min_snr = -65,
  band_steering_threshold = 5,
  load_balancing_threshold = 0,
  ssid_list = { "Corp" },
}
local live_policy = {
  syslog = true, ipv6 = false, local_mode = false,
  assoc_steering = false, probe_steering = false, load_kick_enabled = false,
  aggressiveness = 1, band_steering_interval = 30000,
  band_steering_min_snr = -65, band_steering_threshold = 5,
  load_balancing_threshold = 0, min_snr = 0, min_connect_snr = 0,
  roam_scan_snr = 0, roam_trigger_snr = 0,
  aggressiveness_mac_list = {}, ssid_list = { "Corp" },
}
assert(usteer.runtime_policy_matches(live_policy, expected_policy),
  "the live daemon must match the complete persisted safe policy")
local unsafe_runtime_changes = {
  { load_kick_enabled = true },
  { min_snr = -70 },
  { min_connect_snr = -70 },
  { roam_scan_snr = -70 },
  { roam_trigger_snr = -70 },
  { aggressiveness_mac_list = { "02:00:00:00:00:01,4" } },
  { assoc_steering = true },
  { probe_steering = true },
  { local_mode = true },
  { ipv6 = true },
  { syslog = false },
  { ssid_list = { "Guest" } },
  { band_steering_interval = 0 },
  { aggressiveness = 4 },
}
for _, change in ipairs(unsafe_runtime_changes) do
  local changed = {}
  for key, value in pairs(live_policy) do changed[key] = value end
  for key, value in pairs(change) do changed[key] = value end
  assert(not usteer.runtime_policy_matches(changed, expected_policy),
    "runtime policy drift must be detected for " .. next(change))
end
local unsafe_persisted = {}
for key, value in pairs(expected_policy) do unsafe_persisted[key] = value end
unsafe_persisted.probe_steering = true
assert(not usteer.runtime_policy_matches(live_policy, unsafe_persisted),
  "persisted probe steering must be treated as unsafe even if the daemon does not expose it")

local local_ess = usteer.summarize_runtime({ aggressiveness = 1 }, nodes, {})
assert(usteer.local_ess_ready({ "Corp" }, aps, local_ess),
  "every active configured BSS in the selected ESS must have a unique live BSSID")
local partial = usteer.summarize_runtime({ aggressiveness = 1 }, {
  ["02:00:00:00:00:01"] = nodes["02:00:00:00:00:01"],
}, {})
assert(not usteer.local_ess_ready({ "Corp" }, aps, partial),
  "one reported BSS must not satisfy a two-AP ESS")
local malformed = usteer.summarize_runtime({ aggressiveness = 1 }, {
  ["02:00:00:00:00:01"] = { ssid = "Corp", bssid = "ff:ff:ff:ff:ff:ff", freq = 5180, n_assoc = 1 },
}, {})
assert(malformed.local_nodes_invalid_count == 1 and malformed.local_nodes_truncated)
assert(not usteer.local_ess_ready({ "Corp" }, aps, malformed),
  "invalid BSSID telemetry must never satisfy ESS readiness")
local duplicate = usteer.summarize_runtime({ aggressiveness = 1 }, {
  ["02:00:00:00:00:01"] = nodes["02:00:00:00:00:01"],
  ["02:00:00:00:00:03"] = { ssid = "Corp", bssid = "02:00:00:00:00:01", freq = 2412, n_assoc = 1 },
}, {})
assert(not usteer.local_ess_ready({ "Corp" }, aps, duplicate),
  "duplicate live BSSIDs must fail ESS readiness")
local truncated = {}
for key, value in pairs(local_ess) do truncated[key] = value end
truncated.local_nodes_truncated = true
assert(not usteer.local_ess_ready({ "Corp" }, aps, truncated),
  "truncated local BSS inventory must not satisfy ESS readiness")

local offline = usteer.summarize_runtime(nil, nil, nil)
assert(not offline.running and offline.local_node_count == 0 and offline.remote_host_count == 0)

print("usteer: trusted network binding, SSID membership, k/v readiness, policy bounds and runtime summaries passed")
