package.path = "files/usr/lib/lua/?.lua;" .. package.path
local snmp = require "luci.quantumgrid.snmpv3"

local zones = { lan = true, mgmt = true, wan = false, guest = false }
local input = {
  confirmed = "1",
  enabled = "1",
  username = "quantumgrid-nms",
  auth_pass = "StrongAuthPassphrase-2026!",
  privacy_pass = "StrongPrivacySecret-2026!",
  source_zone = "mgmt"
}
local valid = snmp.validate(input, zones)
assert(valid and valid.enabled)
assert(valid.username == "quantumgrid-nms")
assert(valid.auth_type == "SHA" and valid.privacy_type == "AES")
assert(valid.allow_write == "0" and valid.security_level == "authPriv")
assert(valid.restricted_oid == ".1.3.6.1.2.1")
assert(valid.source_zone == "mgmt")
assert(valid.auth_pass == input.auth_pass and valid.privacy_pass == input.privacy_pass)

local disabled = snmp.validate({ confirmed = "1", enabled = "0" }, zones)
assert(disabled and disabled.enabled == false)
assert(snmp.validate({ enabled = "0" }, zones) == nil,
  "changing SNMP configuration must require explicit confirmation")

local invalid = {
  { username = "root" },
  { username = "../nms" },
  { username = "1nms" },
  { username = string.rep("a", 33) },
  { auth_pass = "short" },
  { auth_pass = string.rep("a", 129) },
  { auth_pass = "StrongPassphraseWith\"Quote" },
  { auth_pass = "StrongPassphraseWith\\Slash" },
  { auth_pass = "StrongPassphraseWith Space" },
  { privacy_pass = "short" },
  { privacy_pass = "StrongPrivacySecret-2026!" },
  { source_zone = "wan" },
  { source_zone = "guest" },
  { source_zone = "custom-edge" }
}
for _, overrides in ipairs(invalid) do
  local candidate = {}
  for key, value in pairs(input) do candidate[key] = value end
  for key, value in pairs(overrides) do candidate[key] = value end
  local result = snmp.validate(candidate, zones)
  assert(result == nil, "unsafe SNMPv3 settings must be rejected")
end

local ready_status = snmp.classify_status({
  available = true,
  enabled = true,
  snmp_version = "v3",
  username = "quantumgrid-nms",
  auth_type = "SHA",
  privacy_type = "AES",
  allow_write = "0",
  restricted_oid = ".1.3.6.1.2.1",
  source_zone_class = "internal",
  firewall_rule_configured = true,
  process_running = true,
})
assert(ready_status == "ready")
local weak_status = snmp.classify_status({
  available = true,
  enabled = true,
  snmp_version = "v2c",
  username = "quantumgrid-nms",
  auth_type = "MD5",
  privacy_type = "DES",
  allow_write = "1",
  restricted_oid = ".1",
  source_zone_class = "external",
  firewall_rule_configured = false,
  process_running = false,
})
assert(weak_status == "review")
local community_status = snmp.classify_status({
  available = true,
  enabled = false,
  legacy_community_configured = true
})
assert(community_status == "review",
  "legacy community strings must be flagged even while the daemon is disabled")
assert(snmp.classify_status({ available = false }) == "unavailable")
assert(snmp.classify_status({ available = true, enabled = false }) == "disabled")

print("snmpv3: authPriv credentials, read-only access, trusted zone and posture validation passed")
