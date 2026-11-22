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

local function membership_fixture(network)
  local fake = {}
  function fake:foreach(package, section_type, callback)
    if package == "firewall" and section_type == "zone" then
      callback({ [".name"] = "mgmt", name = "mgmt", network = { network } })
    end
  end
  return fake
end
for _, external_network in ipairs({ "wan", "wan6", "wwan", "wwan0", "cellular", "lte", "5g" }) do
  assert(snmp.trusted_zone_networks(membership_fixture(external_network), "mgmt") == nil,
    "an internal zone must not trust external logical network " .. external_network)
end

local ambiguous_zone_uci = {}
function ambiguous_zone_uci:foreach(package, section_type, callback)
  if package == "firewall" and section_type == "zone" then
    callback({ [".name"] = "mgmt", name = "mgmt", network = { "lan" } })
    callback({ [".name"] = "corp", name = "corp", network = { "lan" } })
  end
end
assert(snmp.trusted_zone_networks(ambiguous_zone_uci, "mgmt") == nil,
  "a network attached to multiple zones must be rejected")

local function legacy_fixture(section_type, sections)
  local fake = {}
  function fake:foreach(package, requested_type, callback)
    if package == "snmpd" and requested_type == section_type then
      for _, section in ipairs(sections or {}) do callback(section) end
    end
  end
  function fake.get_all(_, package, section)
    if package == "snmpd" and section == "general" then
      return { [".name"] = "general", [".type"] = "snmpd" }
    end
    return nil
  end
  return fake
end
for _, section_type in ipairs({
  "com2sec", "com2sec6", "access", "access_default",
  "access_HostName", "access_HostIP", "trap_HostName", "trap_HostIP",
}) do
  assert(snmp.legacy_access_configured(legacy_fixture(section_type, { { version = "v2c" } })) == true,
    "unmanaged " .. section_type .. " configuration must block QuantumGrid SNMPv3")
end
assert(snmp.legacy_access_configured(legacy_fixture("com2sec", {})) == false)
assert(snmp.legacy_access_configured(legacy_fixture("group", {
  { version = "v1" }
})) == true)
assert(snmp.legacy_access_configured(legacy_fixture("group", {
  { version = "v2c" }
})) == true)
assert(snmp.legacy_access_configured(legacy_fixture("group", {
  { version = "any" }
})) == true)
assert(snmp.legacy_access_configured(legacy_fixture("group", {
  { version = "usm" }
})) == false)

local general_trap = legacy_fixture("unmanaged", {})
function general_trap.get_all(_, package, section)
  if package == "snmpd" and section == "general" then
    return { [".name"] = "general", [".type"] = "snmpd", trapcommunity = "legacy-secret" }
  end
end
assert(snmp.legacy_access_configured(general_trap) == true,
  "a general-section SNMP trap community must block the managed authPriv profile")

local outgoing_sink = legacy_fixture("trapsink", { { community = "legacy-secret" } })
assert(snmp.legacy_access_configured(outgoing_sink) == true,
  "outgoing community-based trap destinations must be treated as unmanaged SNMP configuration")

local executable_extension = legacy_fixture("extend", { { name = "custom", command = "/bin/sh" } })
assert(snmp.legacy_access_configured(executable_extension) == true,
  "unmanaged executable SNMP extensions must not coexist with the constrained system view")

local expected_snmpd_argv = table.concat({
  "/usr/sbin/snmpd", "-f", "-r", "-p", "/var/run/snmpd.pid",
  "-C", "-c", "/var/run/snmpd.conf",
}, "\0")
assert(snmp.snmpd_process_running("1234\n", "snmpd\n", expected_snmpd_argv))
assert(snmp.snmpd_process_running("1234\n", "snmpd\n",
  expected_snmpd_argv .. "\0-Ls\0d\0"))
assert(snmp.snmpd_process_running("1234\n", "snmpd\n",
  expected_snmpd_argv .. "\0-LF\0i /var/log/snmpd.log\0"))
assert(snmp.snmpd_process_running("1234\n", "snmpd\n",
  expected_snmpd_argv .. "\0-Lf\0/dev/null\0"))
for _, process in ipairs({
  { pid = "1", comm = "snmpd\n", argv = expected_snmpd_argv },
  { pid = "1234", comm = "dropbear\n", argv = expected_snmpd_argv },
  { pid = "1234", comm = "snmpd\n", argv = "wrapper\0" .. expected_snmpd_argv },
  { pid = "1234", comm = "snmpd\n", argv = expected_snmpd_argv .. "\0--agentaddress\0UDP:162\0" },
  { pid = "1234", comm = "snmpd\n", argv = expected_snmpd_argv .. "\0-a\0UDP:162\0" },
  { pid = "1234", comm = "snmpd\n", argv = expected_snmpd_argv .. "\0-c\0/etc/snmp/snmpd.conf\0" },
  { pid = "1234", comm = "snmpd\n", argv = expected_snmpd_argv .. "\0-Ls\0d\0--agentaddress\0UDP:162\0" },
  { pid = "1234", comm = "snmpd\n", argv = expected_snmpd_argv .. "\0-Ls\0invalid\0" },
  { pid = "1234", comm = "snmpd\n", argv = expected_snmpd_argv .. "\0-Lf\0/tmp/snmp.log\0" },
}) do
  assert(not snmp.snmpd_process_running(process.pid, process.comm, process.argv),
    "nonstandard Net-SNMP invocation or listener override must not be ready")
end

local managed_persistent = "usmUser 3 3 0x0102 0x71672d636f6c6c6563746f72 0x71672d636f6c6c6563746f72 .1.3.6.1.6.3.10.1.1.3 0x010203 0x010203 .1.3.6.1.6.3.10.1.2.4 0x040506 0x040506 \"\\n"
local other_persistent = "usmUser 3 3 0x0102 \"otheruser\" \"otheruser\" .1.3.6.1.6.3.10.1.1.3 0x010203 0x010203 .1.3.6.1.6.3.10.1.2.4 0x040506 0x040506 \"\\n"
local persistent_db = "# Net-SNMP persistent state\\nengineBoots 7\\n" .. managed_persistent .. other_persistent
local inventory = snmp.inspect_persistent_usm_users(persistent_db)
assert(inventory and inventory.total == 2)
local present, matches, total = snmp.persistent_user_matches(persistent_db, "qg-collector")
assert(present and matches == 1 and total == 2)
local no_user, no_matches, no_total = snmp.persistent_user_matches(persistent_db, "missing-nms")
assert(not no_user and no_matches == 0 and no_total == 2)
local scrubbed, removed = snmp.strip_persistent_usm_users(persistent_db, { "qg-collector" })
assert(scrubbed and removed == 1)
assert(not snmp.persistent_user_matches(scrubbed, "qg-collector"))
assert(snmp.persistent_user_matches(scrubbed, "otheruser"))
assert(scrubbed:find("# Net%-SNMP persistent state"))
assert(scrubbed:find("engineBoots 7"))
assert(not scrubbed:find(managed_persistent, 1, true))
assert(scrubbed:find(other_persistent, 1, true))
local removed_all, removed_count = snmp.strip_persistent_usm_users(persistent_db, { "qg-collector", "otheruser" })
assert(removed_count == 2 and removed_all == "# Net-SNMP persistent state\\nengineBoots 7\\n")
assert(snmp.strip_persistent_usm_users(persistent_db, {}) == persistent_db)
assert(snmp.inspect_persistent_usm_users("usmUser malformed\\n") == nil,
  "malformed persistent usmUser records must fail closed")
assert(snmp.inspect_persistent_usm_users(string.rep("x", 4 * 1024 * 1024 + 1)) == nil,
  "oversized persistent Net-SNMP state must fail closed")
assert(snmp.strip_persistent_usm_users(persistent_db, { "../unsafe" }) == nil,
  "invalid managed usernames must not be accepted by the persistent-store filter")

local function agent_fixture(sections)
  local fake = {}
  function fake:foreach(package, section_type, callback)
    if package == "snmpd" and section_type == "agent" then
      for _, section in ipairs(sections) do callback(section) end
    end
  end
  return fake
end
local good_agent = {
  [".name"] = "agent", [".type"] = "agent",
  agentaddress = "UDP:161,UDP6:161",
}
assert(snmp.has_expected_agent_listener(agent_fixture({ good_agent })),
  "the exact UDP/161 IPv4 and IPv6 listener profile is accepted")
assert(not snmp.has_expected_agent_listener(agent_fixture({
  { [".name"] = "agent", [".type"] = "agent", agentaddress = "UDP:161,UDP6:162" },
})), "custom listener ports must not be reported as the managed SNMP endpoint")
assert(not snmp.has_expected_agent_listener(agent_fixture({
  { [".name"] = "agent", [".type"] = "agent", agentaddress = "UDP:161,UDP6:161", extra = "unexpected" },
})), "additional agent options must not bypass the managed listener contract")
assert(not snmp.has_expected_agent_listener(agent_fixture({
  good_agent,
  { [".name"] = "agent6", [".type"] = "agent", agentaddress = "UDP:161" },
})), "multiple agent address sections must be rejected")
assert(not snmp.has_expected_agent_listener(agent_fixture({})),
  "missing SNMP listener configuration must fail closed")

local managed_user = {
  [".name"] = "quantumgrid", [".type"] = "v3",
  username = "quantumgrid-nms", auth_type = "SHA",
  auth_pass = "StrongAuthPassphrase-2026!",
  privacy_type = "AES", privacy_pass = "StrongPrivacySecret-2026!",
  allow_write = "0", RestrictedOID = ".1.3.6.1.2.1.1",
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
assert(snmp.private_root_regular_file({ uid = 0, type = "reg", modedec = 33152 }),
  "the persistent SNMP database must be a root-owned regular file with mode 0600")
assert(not snmp.private_root_regular_file({ uid = 0, type = "lnk", modedec = 41471 }),
  "persistent SNMP database symlinks must be rejected")
assert(not snmp.private_root_regular_file({ uid = 1000, type = "reg", modedec = 33152 }))
assert(not snmp.private_root_regular_file({ uid = 0, type = "reg", modedec = 33188 }))
assert(snmp.private_root_directory({ uid = 0, type = "dir", modedec = 16877 }),
  "a root-owned, non-group/world-writable persistent directory is safe")
assert(not snmp.private_root_directory({ uid = 0, type = "dir", modedec = 16895 }),
  "a world-writable persistent directory must be rejected")
assert(not snmp.private_root_directory({ uid = 1000, type = "dir", modedec = 16877 }))
assert(not snmp.private_root_directory({ uid = 0, type = "reg", modedec = 33152 }))
assert(not snmp.credentials_file_private({ uid = 0, modedec = 416 }),
  "group-writable SNMP credential files are rejected")

local function persistent_file_fixture(stat, content, read_failure, directory_stat)
  directory_stat = directory_stat or { uid = 0, type = "dir", modedec = 16877 }
  local fs = { lstat = function(path)
    if path == "/usr/lib/snmp" then return directory_stat end
    assert(path == "/usr/lib/snmp/snmpd.conf")
    return stat
  end }
  local reader = function(path)
    assert(path == "/usr/lib/snmp/snmpd.conf")
    if read_failure then error("read failed") end
    return content
  end
  return fs, reader
end
local persistent_stat = {
  uid = 0, type = "reg", modedec = 33152, size = #persistent_db
}
local persistent_fs, persistent_reader = persistent_file_fixture(persistent_stat, persistent_db)
local persistent_state = snmp.inspect_persistent_usm_file(
  persistent_fs, "/usr/lib/snmp/snmpd.conf", "qg-collector", persistent_reader)
assert(persistent_state and persistent_state.available and persistent_state.present)
assert(persistent_state.total == 2 and persistent_state.matches == 1 and persistent_state.user_present)
local absent_fs, absent_reader = persistent_file_fixture(nil, nil)
local absent_state = snmp.inspect_persistent_usm_file(
  absent_fs, "/usr/lib/snmp/snmpd.conf", "qg-collector", absent_reader)
assert(absent_state and absent_state.available and not absent_state.present and absent_state.total == 0)
local other_user_state = snmp.inspect_persistent_usm_file(
  persistent_fs, "/usr/lib/snmp/snmpd.conf", "missing-nms", persistent_reader)
assert(other_user_state and not other_user_state.user_present and other_user_state.total == 2)
local all_users_state = snmp.inspect_persistent_usm_file(
  persistent_fs, "/usr/lib/snmp/snmpd.conf", nil, persistent_reader)
assert(all_users_state and all_users_state.user_present and all_users_state.matches == 2)
for _, bad_stat in ipairs({
  { uid = 0, type = "lnk", modedec = 41471, size = #persistent_db },
  { uid = 1000, type = "reg", modedec = 33152, size = #persistent_db },
  { uid = 0, type = "reg", modedec = 33188, size = #persistent_db },
  { uid = 0, type = "reg", modedec = 33152, size = 4 * 1024 * 1024 + 1 },
}) do
  local bad_fs, bad_reader = persistent_file_fixture(bad_stat, persistent_db)
  assert(snmp.inspect_persistent_usm_file(
    bad_fs, "/usr/lib/snmp/snmpd.conf", "qg-collector", bad_reader) == nil,
    "symlinked, public, non-root or oversized persistent databases must be rejected")
end
local malformed_fs, malformed_reader = persistent_file_fixture(
  { uid = 0, type = "reg", modedec = 33152, size = 20 }, "usmUser malformed\\n")
assert(snmp.inspect_persistent_usm_file(
  malformed_fs, "/usr/lib/snmp/snmpd.conf", "qg-collector", malformed_reader) == nil)
for _, unsafe_directory in ipairs({
  { uid = 0, type = "lnk", modedec = 41471 },
  { uid = 0, type = "dir", modedec = 16895 },
  { uid = 1000, type = "dir", modedec = 16877 },
}) do
  local unsafe_dir_fs, unsafe_dir_reader = persistent_file_fixture(
    persistent_stat, persistent_db, false, unsafe_directory)
  assert(snmp.inspect_persistent_usm_file(
    unsafe_dir_fs, "/usr/lib/snmp/snmpd.conf", "qg-collector", unsafe_dir_reader) == nil,
    "symlinked, non-root or writable persistent directories must be rejected")
end
local unreadable_fs, unreadable_reader = persistent_file_fixture(persistent_stat, nil, true)
assert(snmp.inspect_persistent_usm_file(
  unreadable_fs, "/usr/lib/snmp/snmpd.conf", "qg-collector", unreadable_reader) == nil)

local valid = snmp.validate(input, zones)
assert(valid and valid.enabled)
assert(valid.username == "quantumgrid-nms")
assert(valid.auth_type == "SHA" and valid.privacy_type == "AES")
assert(valid.allow_write == "0" and valid.security_level == "authPriv")
assert(valid.restricted_oid == ".1.3.6.1.2.1.1")
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
  agent_listener_configured = true,
  username = "quantumgrid-nms",
  auth_type = "SHA",
  privacy_type = "AES",
  allow_write = "0",
  restricted_oid = ".1.3.6.1.2.1.1",
  source_zone_class = "internal",
  firewall_inventory_available = true,
  firewall_rule_present = true,
  runtime_credentials_present = true,
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
  persistent_inventory_available = true,
  persistent_user_present = true,
  persistent_user_matches = 1,
  persistent_usm_user_count = 1,
  process_running = true,
})
assert(ready_status == "ready")
for _, overrides in ipairs({
  { user_source_zone = "wan" },
  { agent_listener_configured = false },
  { network_membership_verified = false },
  { legacy_network_firewall = true },
  { firewall_perimeter_safe = false },
  { firewall_conflict = true },
  { managed_user_section = false },
  { managed_firewall_rule = false },
  { private_config_permissions = false },
  { runtime_credentials_private = false },
  { process_running = false },
  { persistent_inventory_available = false },
  { persistent_user_present = false },
  { persistent_user_matches = 0 },
  { persistent_usm_user_count = 2 },
}) do
  local candidate = {}
  for key, value in pairs({
    available = true, enabled = true, snmp_version = "v3",
    agent_listener_configured = true,
    username = "quantumgrid-nms", auth_type = "SHA", privacy_type = "AES",
    allow_write = "0", restricted_oid = ".1.3.6.1.2.1.1",
    source_zone = "mgmt", user_source_zone = "mgmt",
    source_zone_class = "internal", firewall_inventory_available = true,
    firewall_rule_present = true, runtime_credentials_present = true,
    network_membership_verified = true,
    firewall_rule_configured = true, legacy_network_firewall = false,
    firewall_perimeter_safe = true, firewall_conflict = false,
    managed_user_section = true, managed_firewall_rule = true,
    private_config_permissions = true, runtime_credentials_private = true,
    persistent_inventory_available = true, persistent_user_present = true,
    persistent_user_matches = 1, persistent_usm_user_count = 1,
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
assert(snmp.classify_status({
  available = true, enabled = false, firewall_inventory_available = true,
  firewall_rule_present = false, firewall_conflict = false,
  process_running = false, runtime_credentials_present = false,
  persistent_inventory_available = true, persistent_user_present = false,
  persistent_user_matches = 0, persistent_usm_user_count = 0,
}) == "disabled")
for _, disabled_state in ipairs({
  { firewall_inventory_available = false },
  { firewall_rule_present = true },
  { firewall_conflict = true },
  { process_running = true },
  { runtime_credentials_present = true },
  { persistent_inventory_available = false },
  { persistent_user_present = true },
  { persistent_usm_user_count = 1 },
}) do
  local candidate = {
    available = true, enabled = false, firewall_inventory_available = true,
    firewall_rule_present = false, firewall_conflict = false,
    process_running = false, runtime_credentials_present = false,
    persistent_inventory_available = true, persistent_user_present = false,
    persistent_user_matches = 0, persistent_usm_user_count = 0,
  }
  for key, value in pairs(disabled_state) do candidate[key] = value end
  assert(snmp.classify_status(candidate) == "review",
    "disabled SNMP must be review while residual firewall, process, credential or unknown firewall state remains")
end

local samples = {
  { enabled = true, status = "disabled", process_running = false, username = "", source_zone = "" },
  { enabled = true, status = "review", process_running = true, username = "quantumgrid-nms", source_zone = "mgmt" },
  { enabled = true, status = "ready", process_running = true, username = "quantumgrid-nms", source_zone = "mgmt" },
}
local sample_calls, sleeps = 0, 0
local polled, ready = snmp.wait_for_state(function()
  sample_calls = sample_calls + 1
  return samples[sample_calls]
end, function() sleeps = sleeps + 1 end, true, "quantumgrid-nms", "mgmt", 5)
assert(ready and polled.status == "ready" and sample_calls == 3 and sleeps == 2,
  "SNMP enablement should tolerate daemon startup delay but return only on exact ready state")

local disable_samples = {
  { enabled = false, status = "review", process_running = true,
    runtime_credentials_present = true, persistent_inventory_available = true,
    persistent_user_present = true, persistent_usm_user_count = 1 },
  { enabled = false, status = "disabled", process_running = false,
    runtime_credentials_present = false, persistent_inventory_available = true,
    persistent_user_present = false, persistent_usm_user_count = 0 },
}
local disable_calls = 0
local disabled_state, disable_ready = snmp.wait_for_state(function()
  disable_calls = disable_calls + 1
  return disable_samples[disable_calls]
end, function() end, false, nil, nil, 4)
assert(disable_ready and disabled_state.process_running == false and disable_calls == 2,
  "SNMP disablement waits until the managed daemon process has stopped even when legacy config remains")

local persistent_left_samples = {
  { enabled = false, status = "review", process_running = false,
    runtime_credentials_present = false, persistent_inventory_available = true,
    persistent_user_present = true, persistent_usm_user_count = 1 },
  { enabled = false, status = "disabled", process_running = false,
    runtime_credentials_present = false, persistent_inventory_available = true,
    persistent_user_present = false, persistent_usm_user_count = 0 },
}
local persistent_left_calls = 0
local clean_state, persistent_clean = snmp.wait_for_state(function()
  persistent_left_calls = persistent_left_calls + 1
  return persistent_left_samples[persistent_left_calls]
end, function() end, false, nil, nil, 3)
assert(persistent_clean and clean_state.status == "disabled" and persistent_left_calls == 2,
  "SNMP disablement must wait for persistent localized USM keys to be removed")

local retry_count, sleep_count = 0, 0
local last_state, exhausted = snmp.wait_for_state(function()
  retry_count = retry_count + 1
  return { enabled = true, status = "review", process_running = true }
end, function() sleep_count = sleep_count + 1 end, true, "quantumgrid-nms", "mgmt", 3)
assert(not exhausted and last_state.status == "review" and retry_count == 3 and sleep_count == 2,
  "SNMP readiness polling must be bounded and report the final observation")

local nil_state, nil_ready = snmp.wait_for_state(function() error("telemetry failed") end, function() end, true, "nms", "mgmt", 2)
assert(nil_state == nil and not nil_ready, "failed status reads must not be treated as ready")

print("snmpv3: authPriv credentials, read-only access, trusted zone and posture validation passed")
