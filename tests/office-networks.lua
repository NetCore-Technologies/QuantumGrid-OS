package.path = "files/usr/lib/lua/?.lua;" .. package.path
local office = require "luci.quantumgrid.office_networks"

local result = office.build_inventory({
  available = true,
  sampled_at = 1700000000,
  interfaces = {
    { name = "lan", protocol = "static", device = "br-lan", up = true, ipv4 = "192.168.10.1/24" },
    { name = "corp", protocol = "static", device = "br-lan.20", up = true, ipv4 = "192.168.20.1", netmask = "255.255.255.0", ip6assign = "64" },
    { name = "guest", protocol = "static", device = "br-lan.30", up = false, ipv4 = "192.168.30.1/24" },
    { name = "iot", protocol = "static", device = "br-lan.40", up = true, ipv4 = "192.168.40.1/24" },
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
    { name = "invalid_scope", interface = "../lan", start = "1", limit = "999999" },
  },
  static_leases = {
    { name = "Office-Printer", mac = "AA:BB:CC:DD:EE:01", ipv4 = "192.168.20.30" },
    { name = "Meeting-Room", mac = "aa:bb:cc:dd:ee:02", ipv4 = "192.168.20.31" },
    { name = "Bad-MAC", mac = "aa:bb:cc:dd:ee:gg", ipv4 = "192.168.20.32" },
    { name = "Bad-IP", mac = "aa:bb:cc:dd:ee:03", ipv4 = "300.1.2.3" },
  },
  zones = {
    { name = "lan", networks = { "lan" }, input = "ACCEPT", output = "ACCEPT", forward = "ACCEPT" },
    { name = "corp", networks = { "corp" }, input = "ACCEPT", output = "ACCEPT", forward = "REJECT" },
    { name = "guest", networks = { "guest" }, input = "REJECT", output = "ACCEPT", forward = "REJECT", masquerade = true },
    { name = "iot", networks = "iot", input = "REJECT", output = "ACCEPT", forward = "REJECT" },
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
assert(result.dhcp_available and result.dhcp_scope_count == 2, "DHCP scope inventory should reject invalid interface names")
assert(result.static_lease_count == 2, "invalid MAC and IPv4 static leases must be dropped")
assert(result.static_leases[1].mac == "aa:bb:cc:dd:ee:01", "MAC addresses should be normalized")
assert(result.dhcp_scopes[1].limit == 120 and result.dhcp_scopes[1].lease_time == "12h")
assert(result.dhcp_scopes[2].ignore == true and result.dhcp_scopes[2].interface == "guest")

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

print("office-networks: VLANs, bridges, firewall and SSID correlation tests passed")
