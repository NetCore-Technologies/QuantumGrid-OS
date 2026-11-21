package.path = "files/usr/lib/lua/?.lua;" .. package.path
local routing = require "luci.quantumgrid.routing"

local function equal(actual, expected, message)
	assert(actual == expected, (message or "value mismatch") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local sample = [[
32766: from all lookup main
1000: from 192.0.2.0/24 to 198.51.100.0/24 fwmark 0x2a/0xff iif br-lan oif eth1 ipproto tcp uidrange 1000-2000 lookup 201
0: from all lookup local
2000: from all blackhole
not-a-rule
]]
local rules, count, truncated = routing.parse_policy_rules(sample, "IPv4")
equal(count, 4, "recognized policy rule count")
equal(#rules, 4, "returned rule count")
equal(truncated, false, "small inventory truncation")
equal(rules[1].priority, 0, "priority sort")
equal(rules[1].table, "local", "local table")
equal(rules[2].priority, 1000, "second priority")
equal(rules[2].family, "IPv4", "address family")
equal(rules[2].source, "192.0.2.0/24", "source selector")
equal(rules[2].destination, "198.51.100.0/24", "destination selector")
equal(rules[2].fwmark, "0x2a/0xff", "firewall mark")
equal(rules[2].input_interface, "br-lan", "input interface")
equal(rules[2].output_interface, "eth1", "output interface")
equal(rules[2].protocol, "tcp", "IP protocol selector")
equal(rules[2].uid_range, "1000-2000", "UID range selector")
equal(rules[2].table, "201", "policy lookup table")
equal(rules[2].action, "lookup", "lookup action")
equal(rules[3].action, "blackhole", "terminal action")
equal(rules[3].table, "", "terminal action has no lookup table")

local ipv6 = routing.parse_policy_rules("100: from 2001:db8::/32 lookup main", "IPv6")
equal(ipv6[1].family, "IPv6", "IPv6 family")
equal(ipv6[1].source, "2001:db8::/32", "IPv6 source selector")
local invalid = routing.parse_policy_rules("10: from all lookup main", "other")
equal(#invalid, 0, "unsupported family is rejected")

local many = {}
for priority = 1, 70 do
	table.insert(many, tostring(priority) .. ": from all lookup " .. tostring(priority))
end
local limited, total, was_truncated = routing.parse_policy_rules(table.concat(many, string.char(10)), "IPv4")
equal(#limited, 64, "inventory limit")
equal(total, 70, "complete match count")
equal(was_truncated, true, "truncation flag")


local route_interfaces = {
  { name = "lan" },
  { name = "wan" },
  { name = "wg0" },
}
local ipv4_route, ipv4_route_error = routing.validate_static_route(
  "IPv4", "lan", "10.20.0.0/16", "192.168.1.2", "20", "100",
  route_interfaces, {})
assert(ipv4_route, ipv4_route_error)
equal(ipv4_route.route_type, "route", "IPv4 route section type")
equal(ipv4_route.target, "10.20.0.0/16", "IPv4 route target")
equal(ipv4_route.gateway, "192.168.1.2", "IPv4 route gateway")
equal(ipv4_route.metric, 20, "IPv4 route metric")
equal(ipv4_route.table, "100", "IPv4 route table")
assert(routing.static_route_contains_address(ipv4_route, "10.20.20.5"))
assert(not routing.static_route_contains_address(ipv4_route, "10.21.20.5"))

local ipv6_route, ipv6_route_error = routing.validate_static_route(
  "IPv6", "wg0", "2001:db8:1200::/56", "fe80::1", "5", "200",
  route_interfaces, {})
assert(ipv6_route, ipv6_route_error)
equal(ipv6_route.route_type, "route6", "IPv6 route section type")
equal(ipv6_route.target, "2001:db8:1200:0:0:0:0:0/56", "IPv6 target normalization")
equal(ipv6_route.gateway, "fe80:0:0:0:0:0:0:1", "IPv6 link-local gateway normalization")
equal(ipv6_route.metric, 5, "IPv6 route metric")
assert(routing.static_route_contains_address(ipv6_route, "2001:db8:1200:0:ffff::10"))
assert(not routing.static_route_contains_address(ipv6_route, "2001:db8:1200:100::10"))

local duplicate_route, duplicate_error = routing.validate_static_route(
  "IPv4", "wan", "10.20.0.0/16", "192.0.2.1", "", "100",
  route_interfaces, { ipv4_route })
assert(duplicate_route == nil and duplicate_error:find("already exists", 1, true))

local invalid_routes = {
  { "IPv4", "lan", "10.20.1.0/16", "", "", "", "canonical network" },
  { "IPv4", "lan", "10.20.0.0/0", "", "", "", "default route" },
  { "IPv4", "lan", "10.20.0.0/16", "192.168.001.1", "", "", "noncanonical gateway" },
  { "IPv4", "lan", "10.20.0.0/16", "224.0.0.1", "", "", "multicast gateway" },
  { "IPv4", "../wan", "10.20.0.0/16", "", "", "", "unsafe interface" },
  { "IPv4", "missing", "10.20.0.0/16", "", "", "", "missing interface" },
  { "IPv4", "lan", "10.20.0.0/16", "", "65536", "", "oversized metric" },
  { "IPv4", "lan", "10.20.0.0/16", "", "", "253", "reserved route table" },
  { "IPv6", "wg0", "2001:db8:1::1/64", "", "", "", "IPv6 host bits" },
  { "IPv6", "wg0", "2001:db8:gg::/64", "", "", "", "invalid IPv6 syntax" },
  { "IPv6", "wg0", "ff00::/8", "", "", "", "multicast prefix" },
  { "IPv6", "wg0", "fe80::/10", "", "", "", "link-local destination prefix" },
  { "IPv6", "wg0", "2001:db8:1::/64", "::", "", "", "unspecified IPv6 gateway" },
}
for _, item in ipairs(invalid_routes) do
  local route = routing.validate_static_route(
    item[1], item[2], item[3], item[4], item[5], item[6], route_interfaces, {})
  assert(route == nil, item[7] .. " must be rejected")
end

local route_snapshot = routing.snapshot_static_route_section({
  [".type"] = "route6", [".name"] = "cfg_remote6",
  interface = "wg0", target = "2001:db8:1200::/56",
  gateway = "fe80::1", metric = "5", table = "200",
}, "route6")
assert(route_snapshot and route_snapshot.name == "cfg_remote6")
equal(route_snapshot.values.table, "200", "static route rollback preserves custom table")
assert(routing.snapshot_static_route_section({
  [".type"] = "interface", [".name"] = "lan",
}, "route") == nil)

print("policy-routing: all parser tests passed")
