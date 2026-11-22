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
local uci_zones = {
  { [".name"] = "mgmt", name = "mgmt", network = { "lan" } },
  { [".name"] = "wan", name = "wan", network = { "wan" } },
}
local zone_uci = {}
function zone_uci:foreach(package, section_type, callback)
  if package == "firewall" and section_type == "zone" then
    for _, zone in ipairs(uci_zones) do callback(zone) end
  end
end
local networks = snmp.trusted_zone_networks(zone_uci, "mgmt")
assert(networks and #networks == 1 and networks[1] == "lan")
assert(snmp.trusted_zone_networks(zone_uci, "wan") == nil,
  "WAN zones must never be trusted SNMP sources")

local ambiguous_zone_uci = {}
function ambiguous_zone_uci:foreach(package, section_type, callback)
  if package == "firewall" and section_type == "zone" then
    callback({ [".name"] = "mgmt", name = "mgmt", network = { "lan" } })
    callback({ [".name"] = "corp", name = "corp", network = { "lan" } })
  end
end
assert(snmp.trusted_zone_networks(ambiguous_zone_uci, "mgmt") == nil,
  "a network attached to multiple zones must be rejected")

local managed_user = {
  [".name"] = "quantumgrid", [".type"] = "v3",
  username = "quantumgrid-nms", auth_type = "SHA",
  auth_pass = "StrongAuthPassphrase-2026!",
  privacy_type = "AES", privacy_pass = "StrongPrivacySecret-2026!",
  allow_write = "0", RestrictedOID = ".1.3.6.1.2.1",
  source_zone = "mgmt",
}
assert(snmp.has_only_managed_user_options(managed_user))
managed_user.exec = "/bin/sh"
assert(not snmp.has_only_managed_user_options(managed_user),
  "unmanaged user directives must never be treated as a managed SNMPv3 user")

local managed_rule = {
  [".name"] = "quantumgrid_snmpv3", [".type"] = "rule",
  name = "QuantumGrid SNMPv3 management access", src = "mgmt",
  proto = "udp", dest_port = "161", target = "ACCEPT", family = "any",
}
assert(snmp.has_only_managed_firewall_options(managed_rule))
managed_rule.dest = "wan"
assert(not snmp.has_only_managed_firewall_options(managed_rule),
  "a managed SNMP rule must not contain an unexpected destination zone")

local function firewall_rule_fixture(section)
  local fake = {}
  function fake:foreach(package, section_type, callback)
    if package == "firewall" and section_type == "rule" then callback(section) end
  end
  return fake
end
assert(snmp.has_conflicting_firewall_rule(firewall_rule_fixture({
  [".name"] = "legacy-open-snmp", target = "ACCEPT", proto = "udp", dest_port = "161"
})), "another UDP/161 ACCEPT rule must block enabling SNMPv3")
assert(not snmp.has_conflicting_firewall_rule(firewall_rule_fixture({
  [".name"] = "dns-accept", target = "ACCEPT", proto = "udp", dest_port = "53"
})), "unrelated firewall rules must not conflict with SNMPv3")
assert(not snmp.has_conflicting_firewall_rule(firewall_rule_fixture({
  [".name"] = "quantumgrid_snmpv3", target = "ACCEPT", proto = "udp", dest_port = "161"
})), "the reserved QuantumGrid SNMPv3 rule is excluded from its own conflict scan")

assert(snmp.credentials_file_private({ uid = 0, modedec = 384 }),
  "root-owned 0600 SNMP credential files are accepted")
assert(not snmp.credentials_file_private({ uid = 0, modedec = 420 }),
  "group/world-readable SNMP credential files are rejected")
assert(not snmp.credentials_file_private({ uid = 1000, modedec = 384 }),
  "non-root-owned SNMP credential files are rejected")
assert(not snmp.credentials_file_private({ uid = 0, modedec = 416 }),
  "group-writable SNMP credential files are rejected")

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
  source_zone = "mgmt",
  user_source_zone = "mgmt",
  network_membership_verified = true,
  firewall_rule_configured = true,
  legacy_network_firewall = false,
  firewall_perimeter_safe = true,
  firewall_conflict = false,
  managed_user_section = true,
  managed_firewall_rule = true,
  private_config_permissions = true,
  runtime_credentials_private = true,
  process_running = true,
})
assert(ready_status == "ready")
for _, overrides in ipairs({
  { user_source_zone = "wan" },
  { network_membership_verified = false },
  { legacy_network_firewall = true },
  { firewall_perimeter_safe = false },
  { firewall_conflict = true },
  { managed_user_section = false },
  { managed_firewall_rule = false },
  { private_config_permissions = false },
  { runtime_credentials_private = false },
  { process_running = false },
}) do
  local candidate = {}
  for key, value in pairs({
    available = true, enabled = true, snmp_version = "v3",
    username = "quantumgrid-nms", auth_type = "SHA", privacy_type = "AES",
    allow_write = "0", restricted_oid = ".1.3.6.1.2.1",
    source_zone = "mgmt", user_source_zone = "mgmt",
    source_zone_class = "internal", network_membership_verified = true,
    firewall_rule_configured = true, legacy_network_firewall = false,
    firewall_perimeter_safe = true, firewall_conflict = false,
    managed_user_section = true, managed_firewall_rule = true,
    private_config_permissions = true, runtime_credentials_private = true,
    process_running = true,
  }) do candidate[key] = value end
  for key, value in pairs(overrides) do candidate[key] = value end
  assert(snmp.classify_status(candidate) == "review",
    "incomplete SNMP security or runtime posture must be review, not ready")
end
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
