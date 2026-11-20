package.path = "files/usr/lib/lua/?.lua;" .. package.path
local wireguard = require "luci.quantumgrid.wireguard"

local now = 1700000000
local dump = table.concat({
	"wg0\\tPRIVATE_INTERFACE_KEY\\tPUBLIC_INTERFACE_KEY\\t51820\\toff",
	"wg0\\tPEER_PUBLIC_KEY_1\\tPRESHARED_KEY_1\\t192.0.2.1:51820\\t10.0.0.0/24,192.0.2.0/24\\t1699999900\\t1024\\t2048\\t25",
	"wg0\\tPEER_PUBLIC_KEY_2\\t\\t\\t10.1.0.0/24\\t0\\t0\\t0\\t0",
	"wg1\\tPEER_PUBLIC_KEY_3\\t\\t[2001:db8::1]:51820\\t2001:db8:1::/64\\t1699990000\\t4096\\t8192\\t0",
}, "\\n")
local result = wireguard.parse_dump(dump, now)
assert(result.available == true, "valid wg dump is available")
assert(result.count == 3 and #result.peers == 3, "all peer rows are parsed")
assert(result.peers[1].interface == "wg0" and result.peers[1].handshake_age_seconds == 100, "recent handshake age")
assert(result.peers[1].receive_bytes == 1024 and result.peers[1].transmit_bytes == 2048, "transfer counters")
assert(#result.peers[1].allowed_ips == 2 and result.peers[1].allowed_ips[1] == "10.0.0.0/24", "allowed IPs are sorted")
assert(result.peers[2].handshake_seen == false and result.peers[2].handshake_age_seconds == nil, "zero handshake is never")
assert(result.peers[3].interface == "wg1" and result.peers[3].handshake_age_seconds == 10000, "IPv6 peer is retained")

local malformed = wireguard.parse_dump(table.concat({
	"wg0\\tPRIVATE\\tPUBLIC\\t51820\\t0",
	"bad interface;cmd\\tPUBLIC\\tPSK\\t\\t0.0.0.0/0\\t1699999990\\t1\\t1\\t0",
	"wg0\\tPUBLIC\\tPSK\\t\\t0.0.0.0/0\\t-1\\t1\\t1\\t0",
	"wg0\\tPUBLIC\\tPSK\\t\\t0.0.0.0/0\\t1699999990\\t-1\\t1\\t0",
	"wg0\\tPUBLIC\\tPSK\\t\\tbad network;command\\t1699999990\\t1\\t1\\t0",
}, "\\n"), now)
assert(malformed.count == 2 and #malformed.peers == 2, "invalid interfaces and counters are rejected")
assert(malformed.peers[1].handshake_seen == false, "negative handshake is not treated as valid")
assert(#malformed.peers[2].allowed_ips == 0, "unsafe allowed-IP text is rejected")

local many = {}
for index = 1, 70 do
	table.insert(many, table.concat({
		"wg0", "PUBLIC" .. tostring(index), "", "", "10.0.0.0/24",
		"1699999990", tostring(index), tostring(index), "0"
}, "\\t"))
end
local bounded = wireguard.parse_dump(table.concat(many, "\\n"), now)
assert(bounded.count == 70 and #bounded.peers == 64, "peer inventory is bounded")
assert(bounded.truncated == true, "peer truncation is reported")

local allowed_many = {}
for index = 1, 20 do table.insert(allowed_many, "10.0." .. tostring(index) .. ".0/24") end
local allowed_result = wireguard.parse_dump(table.concat({
	"wg0\\tPUBLIC\\tPSK\\t\\t" .. table.concat(allowed_many, ",") ..
	"\\t1699999990\\t1\\t1\\t0"
}, ""), now)
assert(#allowed_result.peers[1].allowed_ips == 16, "allowed IP inventory is bounded")

local missing = wireguard.parse_dump(nil, now)
assert(missing.available == false and #missing.peers == 0, "missing wg command output remains unavailable")

print("wireguard-status: all peer telemetry tests passed")
