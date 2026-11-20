package.path = "files/usr/lib/lua/?.lua;" .. package.path
local conntrack = require "luci.quantumgrid.conntrack"

local normal = conntrack.summarize("150\n", "1000\n")
assert(normal.available == true)
assert(normal.count == 150 and normal.maximum == 1000 and normal.free == 850)
assert(math.abs(normal.used_percent - 15) < 0.0001)
assert(normal.status == "normal")

local warning = conntrack.summarize("750", "1000")
assert(warning.available == true and warning.status == "warning")
assert(warning.free == 250 and warning.used_percent == 75)

local critical = conntrack.summarize("900", "1000")
assert(critical.status == "critical" and critical.free == 100)

local full = conntrack.summarize("1000", "1000")
assert(full.status == "critical" and full.free == 0)

-- Preserve unexpected over-capacity readings for diagnosis; never wrap headroom.
local over = conntrack.summarize("1024", "1000")
assert(over.status == "critical" and over.free == 0)
assert(over.used_percent > 100)

assert(conntrack.summarize(nil, "1000").available == false)
assert(conntrack.summarize("10", nil).available == false)
assert(conntrack.summarize("not-a-number", "1000").available == false)
assert(conntrack.summarize("-1", "1000").available == false)
assert(conntrack.summarize("1.5", "1000").available == false)
assert(conntrack.summarize("10", "0").available == false)

print("conntrack-status: all parser and threshold tests passed")
