package.path = "files/usr/lib/lua/?.lua;" .. package.path
local config = require "luci.quantumgrid.mwan3_config"

local valid = {
  section = "wan",
  enabled = "1",
  track_ips = { "1.1.1.1", "2606:4700:4700::1111" },
  reliability = "2",
  count = "2",
  timeout = "3",
  interval = "5",
  down = "3",
  up = "5",
  initial_state = "online"
}
local update, validation_error = config.validate_update(valid)
assert(update, validation_error)
assert(update.section == "wan" and update.enabled == "1")
assert(#update.track_ips == 2 and update.track_ips[2] == "2606:4700:4700::1111")
assert(update.reliability == "2" and update.interval == "5")
assert(update.initial_state == "online")

local ipv4_only = {}
for key, value in pairs(valid) do ipv4_only[key] = value end
ipv4_only.track_ips = { "192.0.2.10" }
ipv4_only.reliability = "1"
local ipv4_update = config.validate_update(ipv4_only)
assert(ipv4_update and #ipv4_update.track_ips == 1)

local ipv6_only = {}
for key, value in pairs(valid) do ipv6_only[key] = value end
ipv6_only.track_ips = { "2001:db8:1234::1" }
ipv6_only.reliability = "1"
local ipv6_update = config.validate_update(ipv6_only)
assert(ipv6_update and ipv6_update.track_ips[1] == "2001:db8:1234::1")

local invalid_addresses = {
  "256.1.1.1",
  "1.1.1",
  "01.2.3.4",
  "1.1.1.1/32",
  "1.1.1.1;touch",
  "2001:::1",
  "2001:db8::1::2",
  "2001:db8:zzzz::1",
  ":2001:db8::1",
  "2001:db8::1:",
  "fe80::1%eth0",
  "2001:db8:1:2:3:4:5:6:7"
}
for _, address in ipairs(invalid_addresses) do
  local candidate = {}
  for key, value in pairs(valid) do candidate[key] = value end
  candidate.track_ips = { address }
  candidate.reliability = "1"
  local rejected = config.validate_update(candidate)
  assert(rejected == nil, "invalid address was accepted: " .. address)
end

local function rejected(candidate, expected)
  local value, err = config.validate_update(candidate)
  assert(value == nil, "invalid Multi-WAN configuration was accepted")
  if expected then assert(err:find(expected, 1, true), "unexpected validation error: " .. tostring(err)) end
end

local too_many = {}
for key, value in pairs(valid) do too_many[key] = value end
too_many.track_ips = {
  "192.0.2.1", "192.0.2.2", "192.0.2.3", "192.0.2.4",
  "192.0.2.5", "192.0.2.6", "192.0.2.7", "192.0.2.8", "192.0.2.9"
}
rejected(too_many, "between 1 and 8")

local duplicate = {}
for key, value in pairs(valid) do duplicate[key] = value end
duplicate.track_ips = { "1.1.1.1", "1.1.1.1" }
rejected(duplicate, "unique")
local bad_reliability = {}
for key, value in pairs(valid) do bad_reliability[key] = value end
bad_reliability.reliability = "3"
rejected(bad_reliability, "Reliability")
local bad_timeout = {}
for key, value in pairs(valid) do bad_timeout[key] = value end
bad_timeout.timeout = "0"
rejected(bad_timeout, "timeout")
local bad_interval = {}
for key, value in pairs(valid) do bad_interval[key] = value end
bad_interval.interval = "61"
rejected(bad_interval, "interval")
local bad_down = {}
for key, value in pairs(valid) do bad_down[key] = value end
bad_down.down = "2.5"
rejected(bad_down, "Failure threshold")
local bad_state = {}
for key, value in pairs(valid) do bad_state[key] = value end
bad_state.initial_state = "unknown"
rejected(bad_state, "Initial state")
local bad_section = {}
for key, value in pairs(valid) do bad_section[key] = value end
bad_section.section = "wan;touch /tmp/pwned"
rejected(bad_section, "existing mwan3 interface")

local projected = config.project_section("wan", {
  enabled = "1",
  track_ip = { "1.1.1.1", "2606:4700:4700::1111" },
  reliability = "2",
  count = "2",
  timeout = "3",
  interval = "5",
  down = "3",
  up = "5",
  initial_state = "offline"
})
assert(projected and projected.valid)
assert(projected.enabled and projected.initial_state == "offline")
assert(#projected.track_ips == 2)

local invalid_projection = config.project_section("wan", {
  enabled = "1",
  track_ip = { "bad address" },
  reliability = "9"
})
assert(invalid_projection and not invalid_projection.valid)
assert(not invalid_projection.track_targets_valid)

local original = {
  enabled = "1",
  track_ip = { "1.1.1.1", "9.9.9.9" },
  reliability = "2",
  count = "2",
  timeout = "2",
  interval = "5",
  down = "3",
  up = "3",
  initial_state = "online",
  flush_conntrack = "never",
  family = "ipv4"
}
local stored = {}
for key, value in pairs(original) do stored[key] = value end
local uci = {}
function uci:set(package, section, option, value)
  assert(package == "mwan3" and section == "wan")
  stored[option] = value
  return true
end
function uci:set_list(package, section, option, values)
  assert(package == "mwan3" and section == "wan")
  local copy = {}
  for index, value in ipairs(values) do copy[index] = value end
  stored[option] = copy
  return true
end
function uci:delete(package, section, option)
  assert(package == "mwan3" and section == "wan")
  stored[option] = nil
  return true
end
function uci:commit(package)
  assert(package == "mwan3")
  self.commits = (self.commits or 0) + 1
  return true
end

local snapshot = config.snapshot(original)
assert(snapshot and snapshot.flush_conntrack == nil)
assert(snapshot.enabled == "1" and #snapshot.track_ip == 2)
assert(config.stage_update(uci, "wan", update))
assert(stored.enabled == "1" and stored.timeout == "3")
assert(#stored.track_ip == 2 and stored.initial_state == "online")
assert(stored.flush_conntrack == "never" and stored.family == "ipv4",
  "unrelated mwan3 options must be preserved")
assert(config.restore(uci, "wan", snapshot))
assert(stored.enabled == "1" and stored.timeout == "2")
assert(#stored.track_ip == 2 and stored.track_ip[2] == "9.9.9.9")
assert(stored.flush_conntrack == "never" and stored.family == "ipv4")
assert(uci.commits == 1)

print("mwan3-config: validation, projection and rollback snapshot tests passed")


local member_interfaces = { wan = true, wwan = true }
local member_update, member_error = config.validate_member_update({
  section = "wan_m1_w3", interface = "wan", metric = "1", weight = "3"
}, member_interfaces)
assert(member_update, member_error)
assert(member_update.section == "wan_m1_w3" and member_update.interface == "wan")
assert(member_update.metric == "1" and member_update.weight == "3")
local projected_member = config.project_member_section("wan_m1_w3", {
  [".type"] = "member", interface = "wan", metric = "1", weight = "3"
}, member_interfaces, { wan_m1_w3 = { "balanced", "wan_only" } })
assert(projected_member and projected_member.valid)
assert(projected_member.policies[1] == "balanced" and projected_member.policies[2] == "wan_only")

for _, bad in ipairs({
  { section = "../member", interface = "wan", metric = "1", weight = "1" },
  { section = "wan_m1_w3", interface = "unknown", metric = "1", weight = "1" },
  { section = "wan_m1_w3", interface = "wan", metric = "0", weight = "1" },
  { section = "wan_m1_w3", interface = "wan", metric = "256", weight = "1" },
  { section = "wan_m1_w3", interface = "wan", metric = "1.5", weight = "1" },
  { section = "wan_m1_w3", interface = "wan", metric = "1", weight = "0" },
  { section = "wan_m1_w3", interface = "wan", metric = "1", weight = "101" },
}) do
  assert(config.validate_member_update(bad, member_interfaces) == nil,
    "invalid member metric, weight, interface or section was accepted")
end
local invalid_member_projection = config.project_member_section("bad_member", {
  [".type"] = "member", interface = "unknown", metric = "0", weight = "999"
}, member_interfaces)
assert(invalid_member_projection and not invalid_member_projection.valid)

local member_original = {
  [".type"] = "member", interface = "wan", metric = "2", weight = "4",
  custom_option = "keep-me"
}
local member_snapshot = config.snapshot_member(member_original)
assert(member_snapshot and member_snapshot.interface == "wan")
local member_stored = {}
for key, value in pairs(member_original) do member_stored[key] = value end
local member_uci = {}
function member_uci:set(package, section, option, value)
  assert(package == "mwan3" and section == "wan_m1_w3")
  member_stored[option] = value
  return true
end
function member_uci:delete(package, section, option)
  assert(package == "mwan3" and section == "wan_m1_w3")
  member_stored[option] = nil
  return true
end
function member_uci:commit(package)
  assert(package == "mwan3")
  self.commits = (self.commits or 0) + 1
  return true
end
assert(config.stage_member_update(member_uci, "wan_m1_w3", member_update))
assert(member_stored.interface == "wan" and member_stored.metric == "1" and member_stored.weight == "3")
assert(member_stored.custom_option == "keep-me", "unmanaged member options must remain untouched")
assert(config.restore_member(member_uci, "wan_m1_w3", member_snapshot))
assert(member_stored.interface == "wan" and member_stored.metric == "2" and member_stored.weight == "4")
assert(member_stored.custom_option == "keep-me")
assert(member_uci.commits == 1)
