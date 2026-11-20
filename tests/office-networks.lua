package.path = "files/usr/lib/lua/?.lua;" .. package.path
local office = require "luci.quantumgrid.office_networks"

assert(office.validate_reservation_confirmation("1") == true)
assert(office.validate_reservation_confirmation("0") == nil)
assert(office.validate_reservation_confirmation(nil) == nil)
assert(office.validate_reservation_section("cfg0123ab") == "cfg0123ab")
assert(office.validate_reservation_section("office_printer-1") == "office_printer-1")
assert(office.validate_reservation_section("@host[0]") == nil)
assert(office.validate_reservation_section("../dhcp") == nil)
assert(office.validate_reservation_section("..") == nil)


local reservation, reservation_error = office.validate_reservation(
  "Office-Printer", "AA:BB:CC:DD:EE:01", "192.168.20.30")
assert(reservation and reservation.mac == "aa:bb:cc:dd:ee:01" and reservation.ipv4_number > 0)
assert(office.ipv4_in_subnet(reservation.ipv4, "192.168.20.1", "255.255.255.0"))
assert(not office.ipv4_in_subnet("192.168.21.30", "192.168.20.1", "255.255.255.0"))
assert(not office.ipv4_in_subnet("192.168.20.1", "192.168.20.1", "255.255.255.0"), "the router address cannot be reserved")
assert(not office.ipv4_in_subnet("192.168.20.255", "192.168.20.1", "255.255.255.0"), "the subnet broadcast address cannot be reserved")
assert(not office.ipv4_in_subnet("192.168.20.30", "192.168.20.1", "255.255.0.255"), "non-contiguous netmasks must be rejected")
assert(not office.ipv4_in_subnet("192.168.20.30", "192.168.20.1", "255.255.255.254"), "point-to-point /31 scopes must not accept host reservations")
assert(office.live_lease_conflict(
  "1700000000 aa:bb:cc:dd:ee:02 192.168.20.30 Office-Laptop *\n",
  "192.168.20.30", "aa:bb:cc:dd:ee:01"), "a live lease to a different MAC must block the reservation")
assert(not office.live_lease_conflict(
  "1700000000 aa:bb:cc:dd:ee:01 192.168.20.30 Office-Printer *\n",
  "192.168.20.30", "AA:BB:CC:DD:EE:01"), "the same MAC may keep its current address")
assert(not office.live_lease_conflict("unparseable lease", "192.168.20.30", "aa:bb:cc:dd:ee:01"))


local invalid_reservations = {
  { "bad name", "aa:bb:cc:dd:ee:01", "192.168.20.30" },
  { "../printer", "aa:bb:cc:dd:ee:01", "192.168.20.30" },
  { "Printer", "aa:bb:cc:dd:ee:03", "not-an-ip" },
  { "Printer", "01:bb:cc:dd:ee:03", "192.168.20.30" },
  { "Printer", "00:00:00:00:00:00", "192.168.20.30" },
  { "Printer", "aa:bb:cc:dd:ee:03", "127.0.0.1" },
  { "Printer", "aa:bb:cc:dd:ee:03", "224.0.0.1" },
  { "Printer", "aa:bb:cc:dd:ee:03", "192.168.020.30" },
  { "Printer", "aa:bb:cc:dd:ee:03", "169.254.1.1" },
  { "Printer", "aa:bb:cc:dd:ee:03", "0.1.2.3" },
}
for _, values in ipairs(invalid_reservations) do
  local valid = office.validate_reservation(values[1], values[2], values[3])
  assert(valid == nil, "invalid static reservation input must be rejected")
end

local disabled_scope_state = office.snapshot_dhcp_scope_enabled({
  [".type"] = "dhcp",
  ignore = "1",
})
assert(disabled_scope_state and not disabled_scope_state.enabled and disabled_scope_state.ignore_present
  and disabled_scope_state.ignore_value == "1")
local enabled_scope_state = office.snapshot_dhcp_scope_enabled({ [".type"] = "dhcp" })
assert(enabled_scope_state and enabled_scope_state.enabled and not enabled_scope_state.ignore_present
  and enabled_scope_state.ignore_value == nil)
assert(office.snapshot_dhcp_scope_enabled({ [".type"] = "host" }) == nil,
  "static host reservations cannot be toggled as DHCP scopes")

local full_scope_snapshot = office.snapshot_dhcp_scope_section({
  [".name"] = "cfg0042",
  [".type"] = "dhcp",
  [".anonymous"] = false,
  interface = "guest",
  start = "80",
  limit = "40",
  leasetime = "6h",
  dhcp_option = { "6,192.168.1.1", "15,office.example" },
  ra = "server",
  ra_flags = { "managed-config", "other-config" },
})
assert(full_scope_snapshot and full_scope_snapshot.name == "cfg0042")
assert(full_scope_snapshot.values.interface == "guest")
assert(full_scope_snapshot.values.dhcp_option[2] == "15,office.example")
assert(full_scope_snapshot.values.ra_flags[1] == "managed-config")
assert(full_scope_snapshot.values[".type"] == nil and full_scope_snapshot.values[".name"] == nil,
  "UCI metadata must not be replayed as option data")
assert(office.snapshot_dhcp_scope_section({ [".name"] = "cfg001", [".type"] = "host" }) == nil,
  "host reservations must not be removed as DHCP server scopes")
assert(office.snapshot_dhcp_scope_section({ [".type"] = "dhcp" }) == nil,
  "anonymous or unnamed scopes must not be removed by the UI")

local rollback_snapshot = office.snapshot_dhcp_scope_options({
  [".type"] = "dhcp",
  start = "100",
  leasetime = "12h",
})
assert(rollback_snapshot and #rollback_snapshot == 3)
assert(rollback_snapshot[1].name == "start" and rollback_snapshot[1].present and rollback_snapshot[1].value == "100")
assert(rollback_snapshot[2].name == "limit" and not rollback_snapshot[2].present and rollback_snapshot[2].value == nil,
  "rollback snapshots must preserve the absence of optional UCI values")
assert(rollback_snapshot[3].name == "leasetime" and rollback_snapshot[3].present and rollback_snapshot[3].value == "12h")
local invalid_snapshot = office.snapshot_dhcp_scope_options({ [".type"] = "host" })
assert(invalid_snapshot == nil, "only DHCP server sections may be snapshotted for pool updates")

local host_snapshot = office.snapshot_dhcp_host_options({
  [".type"] = "host",
  name = "Office-Printer",
  mac = "aa:bb:cc:dd:ee:01",
})
assert(host_snapshot and #host_snapshot == 3)
assert(host_snapshot[1].name == "name" and host_snapshot[1].present and host_snapshot[1].value == "Office-Printer")
assert(host_snapshot[2].name == "mac" and host_snapshot[2].present and host_snapshot[2].value == "aa:bb:cc:dd:ee:01")
assert(host_snapshot[3].name == "ip" and not host_snapshot[3].present and host_snapshot[3].value == nil,
  "reservation rollback must preserve an originally absent IP option")
assert(office.snapshot_dhcp_host_options({ [".type"] = "dhcp" }) == nil,
  "DHCP scope sections cannot be edited as static hosts")

local enabled_pool_only, enabled_pool_error = office.validate_dhcp_pool_range(
  "100", "120", "192.168.10.1", "255.255.255.0", {})
assert(enabled_pool_only and enabled_pool_only.pool_start_ip == "192.168.10.100"
  and enabled_pool_only.pool_end_ip == "192.168.10.219",
  "enabling a disabled scope must validate its pool without requiring an explicit lease duration")
local invalid_enabled_pool = office.validate_dhcp_pool_range(
  "100", "120", "192.168.10.1", "255.255.255.0",
  { { start = "192.168.10.150", finish = "192.168.10.180" } })
assert(invalid_enabled_pool == nil, "a disabled scope must not be enabled if its range overlaps another active pool")

local valid_scope, scope_error = office.validate_dhcp_scope_update(
  "100", "120", "12h", "192.168.10.1", "255.255.255.0", {})
assert(valid_scope and valid_scope.pool_start_ip == "192.168.10.100")
assert(valid_scope.pool_end_ip == "192.168.10.219" and valid_scope.lease_seconds == 43200)

local minute_scope = office.validate_dhcp_scope_update(
  "20", "10", "30d", "10.0.0.1", "255.255.255.0", {})
assert(minute_scope and minute_scope.lease_seconds == 2592000)

local invalid_scope_updates = {
  { "0", "20", "12h" },
  { "01", "20", "12h" },
  { "20", "0", "12h" },
  { "20", "10", "5s" },
  { "20", "10", "366d" },
  { "240", "30", "12h" },
}
for _, values in ipairs(invalid_scope_updates) do
  local updated = office.validate_dhcp_scope_update(
    values[1], values[2], values[3], "192.168.10.1", "255.255.255.0", {})
  assert(updated == nil, "invalid DHCP scope updates must be rejected")
end

local overlapping_scope, overlapping_error = office.validate_dhcp_scope_update(
  "100", "120", "12h", "192.168.10.1", "255.255.255.0",
  { { start = "192.168.10.150", finish = "192.168.10.180" } })
assert(overlapping_scope == nil and overlapping_error:find("overlaps", 1, true),
  "new DHCP pool must not overlap an existing enabled scope")

local gateway_scope = office.validate_dhcp_scope_update(
  "1", "120", "12h", "192.168.10.1", "255.255.255.0", {})
assert(gateway_scope == nil, "pool ranges containing the gateway must be rejected")

local policy_zones = {
  { section = "cfg_corp", name = "corp" },
  { section = "cfg_guest", name = "guest" },
  { section = "cfg_wan", name = "wan" },
}
local valid_zone_policy = office.validate_office_zone_policy("cfg_corp", "REJECT", "REJECT", "0", policy_zones)
local unchanged_policy = office.validate_office_zone_policy("cfg_corp", "UNCHANGED", "INHERIT", "0", policy_zones)
assert(unchanged_policy and unchanged_policy.output_write == false and unchanged_policy.forward_write == true)
assert(unchanged_policy.forward == "INHERIT",
  "an explicit inherit choice must remove the zone override while UNCHANGED leaves it as-is")
assert(valid_zone_policy and valid_zone_policy.output == "REJECT" and valid_zone_policy.forward == "REJECT")
assert(valid_zone_policy.masquerade == false and valid_zone_policy.masq_value == "0")
local masquerade_policy = office.validate_office_zone_policy("cfg_guest", "ACCEPT", "DROP", "1", policy_zones)
assert(masquerade_policy and masquerade_policy.masquerade == true and masquerade_policy.forward == "DROP")

local function reject_zone_policy(section, output, forward, masquerade, label)
  local result, err = office.validate_office_zone_policy(section, output, forward, masquerade, policy_zones)
  assert(result == nil, label .. " must be rejected")
  assert(type(err) == "string" and #err > 0, label .. " should explain why it was rejected")
end
reject_zone_policy("../firewall", "REJECT", "REJECT", "0", "path-like zone section")
reject_zone_policy("missing", "REJECT", "REJECT", "0", "unknown zone section")
reject_zone_policy("cfg_corp", "INVALID", "REJECT", "0", "unknown zone output policy")
reject_zone_policy("cfg_corp", "REJECT", "ACCEPT;uci", "0", "injected zone forward policy")
reject_zone_policy("cfg_corp", "UNCHANGED", "DROP;uci", "0", "injected inherited/forward policy value")
reject_zone_policy("cfg_corp", "REJECT", "REJECT", "true", "non-canonical masquerade flag")

local zone_snapshot, zone_snapshot_error = office.snapshot_firewall_zone_policy_options({
  [".name"] = "cfg_corp",
  [".type"] = "zone",
  name = "corp",
  input = "REJECT",
  output = "ACCEPT",
  forward = "DROP",
  network = { "corp", "corp6" },
})
assert(zone_snapshot and zone_snapshot.section == "cfg_corp")
assert(zone_snapshot.options.output.present and zone_snapshot.options.output.value == "ACCEPT")
assert(zone_snapshot.options.forward.present and zone_snapshot.options.forward.value == "DROP")
assert(not zone_snapshot.options.masq.present and zone_snapshot.options.masq.value == nil,
  "absent masquerade options must be preserved as absent during rollback")
assert(office.snapshot_firewall_zone_policy_options({ [".name"] = "bad", [".type"] = "forwarding" }) == nil,
  "forwarding sections cannot be snapshotted as firewall zones")

local forwarding_zones = {
  { name = "lan", networks = { "lan" } },
  { name = "corp", networks = { "corp" } },
  { name = "guest", networks = { "guest" } },
  { name = "wan", networks = { "wan", "wan6" } },
  { name = "custom-internet", networks = { "wwan" } },
}
local valid_forward = office.validate_office_forwarding("corp", "wan", forwarding_zones, {})
assert(valid_forward and valid_forward.source == "corp" and valid_forward.destination == "wan")
local function reject_forward(source, destination, existing, label)
  local value, err = office.validate_office_forwarding(source, destination, forwarding_zones, existing or {})
  assert(value == nil, label .. " must be rejected")
  assert(type(err) == "string" and #err > 0, label .. " should explain why it was rejected")
end
reject_forward("wan", "corp", {}, "external zone as forwarding source")
reject_forward("custom-internet", "corp", {}, "custom external network as forwarding source")
reject_forward("corp", "corp", {}, "same source and destination")
reject_forward("unknown", "wan", {}, "unknown source zone")
reject_forward("corp", "missing", {}, "unknown destination zone")
reject_forward("corp", "wan", {
  { section = "cfg01", source = "corp", destination = "wan" }
}, "duplicate source-to-destination forwarding")

local forwarding_snapshot = office.snapshot_firewall_forwarding_section({
  [".name"] = "cfg0042",
  [".type"] = "forwarding",
  src = "corp",
  dest = "wan",
  family = "ipv4",
  enabled = "1",
})
assert(forwarding_snapshot and forwarding_snapshot.name == "cfg0042")
assert(forwarding_snapshot.values.src == "corp" and forwarding_snapshot.values.dest == "wan")
assert(forwarding_snapshot.values.family == "ipv4" and forwarding_snapshot.values.enabled == "1")
assert(forwarding_snapshot.values[".type"] == nil and forwarding_snapshot.values[".name"] == nil)
assert(office.snapshot_firewall_forwarding_section({ [".type"] = "zone", [".name"] = "wan" }) == nil,
  "firewall zones must not be snapshotted as forwarding sections")

local valid_bridge_vlan, vlan_error = office.validate_bridge_vlan(
  "br-lan", "20", { "lan1:t", "lan2:u*", "lan3:u" },
  { "lan1", "lan2", "lan3", "lan4" }, {
    { section = "vlan10", device = "br-lan", vlan = "10", ports = { "lan1:u*", "lan2:t" } }
  })
assert(valid_bridge_vlan and valid_bridge_vlan.vlan_id == 20)
assert(valid_bridge_vlan.ports[1] == "lan1:t" and valid_bridge_vlan.ports[2] == "lan2:u*")
assert(valid_bridge_vlan.port_count == 3)

local edited_bridge_vlan = office.validate_bridge_vlan(
  "br-lan", "10", { "lan1:t", "lan2:u*" },
  { "lan1", "lan2", "lan3" }, {
    { section = "vlan10", device = "br-lan", vlan = "10", ports = { "lan1:u*", "lan2:t" } }
  }, "vlan10")
assert(edited_bridge_vlan and edited_bridge_vlan.vlan_id == 10,
  "editing an existing VLAN must ignore its own ID and PVID snapshot")

local function reject_bridge_vlan(device, vlan, ports, members, existing, section, label)
  local value, err = office.validate_bridge_vlan(device, vlan, ports, members, existing, section)
  assert(value == nil, label .. " must be rejected")
  assert(type(err) == "string" and #err > 0, label .. " should report why it was rejected")
end
reject_bridge_vlan("br-lan;uci", "20", { "lan1:t" }, { "lan1" }, {}, nil, "injected bridge device")
reject_bridge_vlan("br-lan", "0", { "lan1:t" }, { "lan1" }, {}, nil, "zero VLAN ID")
reject_bridge_vlan("br-lan", "4095", { "lan1:t" }, { "lan1" }, {}, nil, "out-of-range VLAN ID")
reject_bridge_vlan("br-lan", "20", {}, { "lan1" }, {}, nil, "empty VLAN membership")
reject_bridge_vlan("br-lan", "20", { "lan1" }, { "lan1" }, {}, nil, "implicit port mode")
reject_bridge_vlan("br-lan", "20", { "lan9:t" }, { "lan1", "lan2" }, {}, nil, "port outside selected bridge")
reject_bridge_vlan("br-lan", "20", { "lan1:t", "lan1:u*" }, { "lan1" }, {}, nil, "duplicate port entry")
reject_bridge_vlan("br-lan", "20", { "lan1:t", "lan2:u*" }, { "lan1", "lan2" }, {
  { section = "other", device = "br-lan", vlan = "20", ports = { "lan2:t" } }
}, nil, "duplicate bridge VLAN ID")
reject_bridge_vlan("br-lan", "20", { "lan1:t", "lan2:u*" }, { "lan1", "lan2" }, {
  { section = "other", device = "br-lan", vlan = "30", ports = { "lan2:u*" } }
}, nil, "duplicate PVID across VLANs")
reject_bridge_vlan("br-lan", "20", { "lan1:t", "lan2:u" }, { "lan1", "lan2" }, {
  { section = "other", device = "br-lan", vlan = "30", ports = { "lan2:u" } }
}, nil, "duplicate untagged VLAN membership")
reject_bridge_vlan("br-lan", "20", { "lan1:t" }, {}, {}, nil, "bridge without declared ports")

local result = office.build_inventory({
  available = true,
  sampled_at = 1700000000,
  interfaces = {
    { name = "lan", protocol = "static", device = "br-lan", up = true, ipv4 = "192.168.10.1", netmask = "255.255.255.0" },
    { name = "corp", protocol = "static", device = "br-lan.20", up = true, ipv4 = "192.168.20.1", netmask = "255.255.255.0", ip6assign = "64" },
    { name = "guest", protocol = "static", device = "br-lan.30", up = false, ipv4 = "192.168.30.1", netmask = "255.255.255.0" },
    { name = "iot", protocol = "static", device = "br-lan.40", up = true, ipv4 = "192.168.40.1", netmask = "255.255.255.0" },
  },
  bridges = {
    { name = "br-lan", type = "bridge", ports = { "lan1", "lan2", "lan3", "lan4" }, vlan_filtering = true },
  },
  vlans = {
    { name = "vlan20", device = "br-lan", vlan = "20", ports = { "lan1:t", "lan2:t", "lan3:u*", "bad port" } },
    { name = "vlan30", device = "br-lan", vlan = "30", ports = { "lan1:t", "lan2:u*" } },
    { name = "vlan40", device = "br-lan", vlan = 40, ports = { "lan1:t", "lan4:u*" } },
    { name = "invalid", device = "br-lan", vlan = 4095, ports = { "lan1:t" } },
  },
  dhcp_available = true,
  dhcp_scopes = {
    { name = "lan_dhcp", interface = "lan", start = "100", limit = "120", lease_time = "12h", ignore = false, dhcpv6 = "server", ra = "server" },
    { name = "guest_dhcp", interface = "guest", start = "50", limit = "200", lease_time = "4h", ignore = true },
    { name = "corp_dhcp", interface = "corp", start = "150", limit = "20", lease_time = "8h", ignore = false },
    { name = "corp_overlap", interface = "corp", start = "160", limit = "20", lease_time = "8h", ignore = false },
    { name = "iot_invalid", interface = "iot", start = "250", limit = "10", lease_time = "8h", ignore = false },
    { name = "invalid_scope", interface = "../lan", start = "1", limit = "999999" },
  },
  static_leases = {
    { section = "cfg0001", name = "Office-Printer", mac = "AA:BB:CC:DD:EE:01", ipv4 = "192.168.20.30" },
    { name = "Meeting-Room", mac = "aa:bb:cc:dd:ee:02", ipv4 = "192.168.20.31" },
    { name = "Bad-MAC", mac = "aa:bb:cc:dd:ee:gg", ipv4 = "192.168.20.32" },
    { name = "Bad-IP", mac = "aa:bb:cc:dd:ee:03", ipv4 = "300.1.2.3" },
  },
  forwardings = {
    { section = "cfg-corp-printers", name = "corp_to_printers", source = "corp", destination = "printers" },
    { section = "cfg-guest-lan", name = "guest_to_lan", source = "guest", destination = "lan" },
    { name = "../unsafe", source = "corp", destination = "lan" },
  },
  zones = {
    { section = "cfg_lan", name = "lan", networks = { "lan" }, input = "ACCEPT", output = "ACCEPT", forward = "ACCEPT" },
    { section = "cfg_corp", name = "corp", networks = { "corp" }, input = "ACCEPT", output = "ACCEPT", forward = "REJECT" },
    { section = "cfg_guest", name = "guest", networks = { "guest" }, input = "REJECT", output = "ACCEPT", forward = "REJECT", masquerade = true },
    { section = "cfg_iot", name = "iot", networks = "iot", input = "REJECT", output = "ACCEPT", forward = "REJECT" },
  },
  wifi_aps = {
    { section = "corp_ap", mode = "ap", ssid = "Office-Corp", device = "radio1", networks = { "corp" } },
    { section = "guest_ap", mode = "ap", ssid = "Office-Guest", device = "radio0", networks = { "guest" } },
    { section = "iot_ap", mode = "ap", ssid = "Office-IoT", device = "radio0", networks = "iot", disabled = true },
    { section = "client", mode = "sta", ssid = "upstream", device = "radio0", networks = { "wan" } },
  }
})

assert(result.available == true)
assert(result.sampled_at == 1700000000)
assert(result.interface_count == 4 and result.bridge_count == 1)
assert(result.vlan_count == 3, "invalid VLAN IDs must be ignored")
assert(result.vlan_filtering_bridge_count == 1)
assert(result.segmented_interface_count == 3)
assert(result.wifi_ap_count == 3, "only AP sections belong in the SSID inventory")
assert(result.dhcp_available and result.dhcp_scope_count == 5, "DHCP scope inventory should reject invalid interface names")
assert(result.static_lease_count == 2, "invalid MAC and IPv4 static leases must be dropped")
assert(result.static_leases[1].mac == "aa:bb:cc:dd:ee:01", "MAC addresses should be normalized")
assert(result.static_leases[1].section == "cfg0001", "static lease UCI section should be preserved for safe removal")
assert(result.forwarding_count == 2 and result.forwardings[1].source == "corp" and result.forwardings[1].destination == "printers", "explicit firewall zone forwarding should be inventoried")
assert(result.zones[1].section == "cfg_lan", "firewall zone UCI section IDs should be preserved for safe editing")
assert(result.forwardings[1].section == "cfg-corp-printers", "firewall forwarding UCI section IDs must be preserved for safe removal")
assert(result.dhcp_scopes[1].limit == 120 and result.dhcp_scopes[1].lease_time == "12h")
assert(result.dhcp_scopes[2].ignore == true and result.dhcp_scopes[2].interface == "guest")
assert(result.dhcp_scopes[1].section == "lan_dhcp", "DHCP scopes must retain stable UCI section IDs")
assert(result.dhcp_scopes[1].range_valid)
assert(result.dhcp_scopes[1].pool_start_ip == "192.168.10.100" and result.dhcp_scopes[1].pool_end_ip == "192.168.10.219")
assert(not result.dhcp_scopes[2].range_valid and result.dhcp_scopes[2].range_error == "DHCP scope is disabled.")
assert(result.dhcp_scopes[3].overlap and result.dhcp_scopes[4].overlap, "overlapping DHCP pool ranges must be flagged")
assert(not result.dhcp_scopes[5].range_valid and result.dhcp_scopes[5].range_error ~= "", "pools beyond the broadcast address must be rejected")

local corp
for _, iface in ipairs(result.interfaces) do
  if iface.name == "corp" then corp = iface end
end
assert(corp and corp.device == "br-lan.20" and corp.up)
assert(#corp.ipv4 == 1 and corp.ipv4[1] == "192.168.20.1")
assert(corp.netmask == "255.255.255.0" and corp.ip6assign == "64")
assert(#corp.vlan_ids == 1 and corp.vlan_ids[1] == 20)
assert(#corp.firewall_zones == 1 and corp.firewall_zones[1] == "corp")
assert(#corp.wifi_aps == 1 and corp.wifi_aps[1].ssid == "Office-Corp")

local guest
for _, iface in ipairs(result.interfaces) do
  if iface.name == "guest" then guest = iface end
end
assert(guest and guest.up == false and guest.vlan_ids[1] == 30)
assert(guest.wifi_aps[1].disabled == false)
assert(result.vlans[1].ports[1].mode == "tagged")
assert(result.vlans[1].ports[2].mode == "tagged")
assert(result.vlans[1].ports[3].mode == "untagged" and result.vlans[1].ports[3].pvid)
assert(result.vlans[1].ports[4] == nil, "malformed switch ports must be dropped")

local explicitness = office.build_inventory({
  available = true,
  vlans = {
    { name = "vlan70", device = "br-test", vlan = 70, ports = { "lan1", "lan2:t*", "lan3u" } }
  }
})
assert(explicitness.vlans[1].ports[1].mode == "unspecified", "bare port entries must not be guessed as tagged or untagged")
assert(explicitness.vlans[1].ports[2] == nil, "tagged PVID suffixes are invalid")
assert(explicitness.vlans[1].ports[3] == nil, "mode suffixes require a colon")


local iot
for _, iface in ipairs(result.interfaces) do
  if iface.name == "iot" then iot = iface end
end
assert(iot and iot.vlan_ids[1] == 40 and iot.wifi_aps[1].disabled)

local unavailable = office.build_inventory({ available = false })
assert(unavailable.available == false and unavailable.interface_count == 0)

local oversized = { available = true, interfaces = {}, bridges = {}, vlans = {}, zones = {}, wifi_aps = {} }
for index = 1, 70 do
  table.insert(oversized.interfaces, { name = "net" .. tostring(index), protocol = "static" })
end
for index = 1, 70 do
  table.insert(oversized.vlans, { name = "v" .. tostring(index), device = "br-test", vlan = index, ports = {} })
end
local capped = office.build_inventory(oversized)
assert(capped.interface_count == 64 and capped.vlan_count == 64 and capped.truncated)

print("office-networks: VLANs, bridges, DHCP reservation and scope lifecycle validation, firewall forwarding and SSID tests passed")
