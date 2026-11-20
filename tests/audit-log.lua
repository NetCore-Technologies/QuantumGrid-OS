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
  return { timestamp = 3, action = "untrusted.action", outcome = "success" }
end
local parsed = audit.parse_log("one\nbad\ntwo\ninvalid-action", decode)
assert(parsed.available and parsed.count == 4)
assert(#parsed.events == 2 and parsed.events[1].timestamp == 2 and parsed.events[2].timestamp == 1, "events must be returned newest first and invalid rows skipped")
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

print("audit: allowlist, secret exclusion, escaping, validation and bounded parsing passed")
