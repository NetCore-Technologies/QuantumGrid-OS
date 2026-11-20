package.path = "files/usr/lib/lua/?.lua;" .. package.path
local firewall = require "luci.quantumgrid.firewall_inventory"

local redirect = firewall.summarize_redirect({
  [".name"] = "cfg0031",
  name = "Office HTTPS",
  src = { "wan", "wan6" },
  dest = "lan",
  proto = { "tcp", "udp" },
  target = "dnat",
  family = "ipv4",
  src_dport = { "443", "8443-8445" },
  dest_port = "443",
  enabled = "1",
  src_ip = "203.0.113.10",
  src_mac = "aa:bb:cc:dd:ee:ff",
  dest_ip = "192.168.20.45",
  src_dip = "198.51.100.7",
  extra_secret = "must-not-be-copied"
}, 1)

assert(redirect.name == "Office HTTPS")
assert(redirect.section == "cfg0031", "stable UCI section IDs should be preserved")
assert(redirect.source_zone == "wan wan6")
assert(redirect.destination_zone == "lan")
assert(redirect.protocol == "tcp udp")
assert(redirect.target == "DNAT")
assert(redirect.external_port == "443 8443-8445")
assert(redirect.internal_port == "443")
assert(redirect.enabled)
assert(redirect.source_ip_match and redirect.source_mac_match)
assert(redirect.destination_ip_match and redirect.source_destination_ip_match)
for key, value in pairs(redirect) do
  assert(type(value) ~= "string" or
    (value ~= "203.0.113.10" and value ~= "aa:bb:cc:dd:ee:ff" and
      value ~= "192.168.20.45" and value ~= "198.51.100.7" and
      value ~= "must-not-be-copied"),
    "raw IP, MAC or unrecognised section values must never be returned")
end
assert(redirect.src_ip == nil and redirect.src_mac == nil and redirect.dest_ip == nil)
assert(firewall.summarize_redirect({ [".name"] = "cfg0032", enabled = "0" }, 2).enabled == false)
assert(firewall.summarize_redirect({ [".name"] = "cfg0033" }, 3).name == "unnamed-redirect-3")
assert(firewall.summarize_redirect("not a section", 4) == nil)

local sections = {}
for index = 1, 70 do
  sections[index] = {
    [".name"] = "cfg" .. tostring(index),
    src = "wan",
    dest = "lan",
    proto = "tcp",
    src_dport = tostring(1000 + index),
    dest_port = tostring(1000 + index),
    enabled = "1",
    dest_ip = "192.168.20.2"
  }
end
local inventory = firewall.summarize_redirects(sections, 64)
assert(inventory.count == 70)
assert(#inventory.redirects == 64 and inventory.truncated)
assert(inventory.redirects[64].name == "cfg64")
assert(firewall.summarize_redirects(sections, 0).truncated == true or
  #firewall.summarize_redirects(sections, 0).redirects == 64)
assert(#firewall.summarize_redirects(nil).redirects == 0)

print("firewall-inventory: redaction, bounded projection, defaults and truncation tests passed")
