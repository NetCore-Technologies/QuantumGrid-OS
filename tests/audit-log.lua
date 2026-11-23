package.path = "files/usr/lib/lua/?.lua;" .. package.path
local audit = require "luci.quantumgrid.audit"

local encoded = audit.encode_event({
  timestamp = 1700000000,
  actor = "root",
  remote_ip = "192.0.2.15",
  action = "wireless.update",
  target = "radio0/ap_main",
  outcome = "success",
  password = "must-not-be-serialized",
  private_key = "must-not-be-serialized"
})
assert(type(encoded) == "string")
assert(encoded:find('"action":"wireless.update"', 1, true))
assert(encoded:find('"target":"radio0/ap_main"', 1, true))
assert(not encoded:find("must-not-be-serialized", 1, true), "unrecognised secret fields must never be serialized")

local escaped = audit.encode_event({
  timestamp = 1700000001,
  action = "sqm.update",
  target = 'wan "uplink" \\ queue',
  outcome = "failed"
})
assert(escaped and escaped:find('\\"uplink\\"', 1, true), "quotes must be JSON escaped")
assert(escaped:find("\\\\", 1, true), "backslashes must be JSON escaped")
assert(audit.encode_event({ timestamp = 3, action = "package.feed.update", target = "opkg", outcome = "success" }) ~= nil, "package feed updates should be allowlisted")
assert(audit.encode_event({ timestamp = 4, action = "sqm.cake-profile", target = "wan_main", outcome = "success" }) ~= nil, "CAKE profile changes should be allowlisted")
assert(audit.encode_event({ timestamp = 5, action = "sqm.client-qos.add", target = "cfg_client_1", outcome = "success" }) ~= nil, "client QoS additions should be allowlisted")
assert(audit.encode_event({ timestamp = 5, action = "sqm.client-qos.download.add", target = "cfg_client_download_1", outcome = "success" }) ~= nil, "client download QoS additions should be allowlisted")
assert(audit.encode_event({ timestamp = 6, action = "system.config.restore", target = "arcadyan-aw1000", outcome = "success" }) ~= nil, "configuration restore events should be allowlisted")
assert(audit.encode_event({ timestamp = 6, action = "sqm.client-qos.remove", target = "cfg_client_1", outcome = "success" }) ~= nil, "client QoS removals should be allowlisted")
assert(audit.encode_event({ timestamp = 7, action = "mwan3.member.update", target = "wan_m1_w3", outcome = "success" }) ~= nil, "mwan3 member changes should be allowlisted")

local function expect_invalid(event, label)
  local result, err = audit.encode_event(event)
  assert(result == nil, label .. " must be rejected")
  assert(type(err) == "string" and #err > 0, label .. " must explain rejection")
end
expect_invalid(nil, "missing event")
expect_invalid({ action = "arbitrary.shell", outcome = "success" }, "unknown action")
expect_invalid({ action = "wireless.update", outcome = "pending" }, "unknown outcome")
expect_invalid({ action = "wireless.update", outcome = "success", timestamp = -1 }, "negative timestamp")

local function decode(line)
  if line == "bad" then error("invalid JSON") end
  if line == "one" then
    return { timestamp = 1, actor = "root", remote_ip = "192.0.2.1", action = "wireless.update", target = "radio0", outcome = "success" }
  end
  if line == "two" then
    return { timestamp = 2, actor = "root", remote_ip = "192.0.2.2", action = "system.config.backup", target = "sysupgrade", outcome = "success" }
  end
  if line == "three" then
    return { timestamp = 3, actor = "root", remote_ip = "192.0.2.3", action = "mwan3.member.update", target = "wan_m1_w3", outcome = "success" }
  end
  return { timestamp = 3, action = "untrusted.action", outcome = "success" }
end
local parsed = audit.parse_log("one\nbad\ntwo\nthree\ninvalid-action", decode)
assert(parsed.available and parsed.count == 5)
assert(#parsed.events == 3 and parsed.events[1].timestamp == 3 and parsed.events[2].timestamp == 2 and parsed.events[3].timestamp == 1, "events must be returned newest first and invalid rows skipped; mwan3 member change must be retained")
assert(audit.parse_log(nil, decode).available == false, "missing log should be unavailable")

local long = {}
for index = 1, 205 do table.insert(long, "one") end
local capped = audit.parse_log(table.concat(long, "\n"), decode)
assert(capped.count == 205 and #capped.events == 200 and capped.truncated, "audit history should be capped at 200 records")

for _, action in ipairs({
  "office.vlan.update",
  "office.vlan.remove",
  "office.forwarding.add",
  "office.forwarding.remove",
}) do
  local event = audit.encode_event({
    timestamp = 1700000000,
    actor = "root",
    remote_ip = "192.0.2.10",
    action = action,
    target = "cfg-office",
    outcome = "success",
  })
  assert(type(event) == "string" and event:find(action, 1, true),
    "office network write actions must be accepted by the redacted audit log")
end

local zone_event = audit.encode_event({
  timestamp = 1700000002,
  actor = "root",
  remote_ip = "192.0.2.10",
  action = "office.zone.update",
  target = "cfg_corp",
  outcome = "success",
})
assert(type(zone_event) == "string" and zone_event:find('"action":"office.zone.update"', 1, true),
  "firewall zone policy updates should be allowlisted and auditable")

local wifi_binding_event = audit.encode_event({
  timestamp = 1700000003,
  actor = "root",
  remote_ip = "192.0.2.10",
  action = "office.wifi.network.update",
  target = "corp_ap",
  outcome = "success",
})
assert(type(wifi_binding_event) == "string" and
  wifi_binding_event:find('"action":"office.wifi.network.update"', 1, true),
  "SSID-to-network binding events must be accepted by the redacted audit log")

for _, action in ipairs({ "office.port-forward.add", "office.port-forward.remove" }) do
  local event = audit.encode_event({
    timestamp = 1700000004,
    actor = "root",
    remote_ip = "192.0.2.10",
    action = action,
    target = "cfg443",
    outcome = "success",
  })
  assert(type(event) == "string" and event:find('"action":"' .. action .. '"', 1, true),
    "WAN port-forward changes must be accepted by the redacted audit log")
end

print("audit: allowlist, secret exclusion, escaping, validation and bounded parsing passed")
