package.path = "files/usr/lib/lua/?.lua;" .. package.path
local runtime = require "luci.quantumgrid.firewall_runtime"

local sample = {
  nftables = {
    { metainfo = { version = "1.0" } },
    { table = { family = "inet", name = "fw4" } },
    { chain = {
      family = "inet", table = "fw4", name = "input_wan",
      type = "filter", hook = "input", prio = 0, policy = "drop"
    } },
    { chain = {
      family = "inet", table = "fw4", name = "forward_wan",
      type = "filter", hook = "forward", prio = 0, policy = "reject", dev = "wan"
    } },
    { chain = {
      family = "inet", table = "fw4", name = "dstnat",
      type = "nat", hook = "prerouting", prio = -100, policy = ""
    } },
    { rule = {
      family = "inet", table = "fw4", chain = "input_wan",
      expr = { { match = { left = "192.0.2.1", right = "22" } } }
    } },
    { rule = { family = "inet", table = "fw4", chain = "input_wan", expr = {} } },
    { rule = { family = "inet", table = "fw4", chain = "dstnat", expr = {} } },
    { chain = { family = "ip", table = "fw4", name = "ignored_ipv4", hook = "input", policy = "accept" } },
    { chain = { family = "inet", table = "other", name = "ignored_table", hook = "input", policy = "accept" } },
  }
}
local parsed = runtime.parse(sample, 1700000000)
assert(parsed.available and parsed.table_present)
assert(parsed.chain_count == 3 and #parsed.chains == 3)
assert(parsed.rule_count == 3)
assert(parsed.sampled_at == 1700000000)
assert(parsed.chains[1].name == "input_wan")
assert(parsed.chains[1].hook == "input" and parsed.chains[1].policy == "drop")
assert(parsed.chains[1].type == "filter" and parsed.chains[1].rule_count == 2)
assert(parsed.chains[2].device == "wan" and parsed.chains[2].rule_count == 0)
assert(parsed.chains[3].hook == "prerouting" and parsed.chains[3].type == "nat")
assert(parsed.chains[3].priority == -100 and parsed.chains[3].policy == "unspecified")
for _, chain in ipairs(parsed.chains) do
  for key, value in pairs(chain) do
    assert(key ~= "expr" and key ~= "handle")
    assert(type(value) ~= "string" or
      (value ~= "192.0.2.1" and value ~= "22"),
      "raw nft expressions and address matches must not be exposed")
  end
end

local missing = runtime.parse({ nftables = { { table = { family = "ip", name = "filter" } } } })
assert(not missing.available and not missing.table_present)
assert(not runtime.parse(nil).available)

local many = { nftables = { { table = { family = "inet", name = "fw4" } } } }
for index = 1, 70 do
  many.nftables[#many.nftables + 1] = {
    chain = { family = "inet", table = "fw4", name = "chain" .. index, hook = "forward", policy = "accept" }
  }
end
local capped = runtime.parse(many)
assert(capped.available and capped.chain_count == 70)
assert(#capped.chains == 64 and capped.truncated)

local unavailable = runtime.unavailable(1700000001, true)
assert(not unavailable.available and unavailable.truncated and unavailable.sampled_at == 1700000001)
local unreadable_fw4 = runtime.unavailable(1700000002, false, true)
assert(not unreadable_fw4.available and unreadable_fw4.table_present, "fw4 presence must remain distinct from JSON snapshot availability")

print("firewall-runtime: bounded fw4 chain parsing, isolation and redaction tests passed")
