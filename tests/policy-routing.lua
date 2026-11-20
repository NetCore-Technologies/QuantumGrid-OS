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
equal(rules[4].action, "blackhole", "terminal action")
equal(rules[4].table, "", "terminal action has no lookup table")

local ipv6 = routing.parse_policy_rules("100: from 2001:db8::/32 lookup main", "IPv6")
equal(ipv6[1].family, "IPv6", "IPv6 family")
equal(ipv6[1].source, "2001:db8::/32", "IPv6 source selector")
local invalid = routing.parse_policy_rules("10: from all lookup main", "other")
equal(#invalid, 0, "unsupported family is rejected")

local many = {}
for priority = 1, 70 do
	table.insert(many, tostring(priority) .. ": from all lookup " .. tostring(priority))
end
local limited, total, was_truncated = routing.parse_policy_rules(table.concat(many, "\\n"), "IPv4")
equal(#limited, 64, "inventory limit")
equal(total, 70, "complete match count")
equal(was_truncated, true, "truncation flag")

print("policy-routing: all parser tests passed")
