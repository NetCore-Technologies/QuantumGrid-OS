package.path = "files/usr/lib/lua/?.lua;" .. package.path
local identity = require "luci.quantumgrid.device_identity"

local generated = "0123456789abcdef0123456789abcdef"
local valid = identity.inspect(generated .. "\n")
assert(valid.available)
assert(valid.status == "available")
assert(valid.id == generated)

local without_newline = identity.inspect(generated)
assert(without_newline.available and without_newline.id == generated)

local malformed = identity.inspect("0123456789abcdef0123456789abcdeZ\n")
assert(not malformed.available and malformed.status == "unavailable")
assert(malformed.id == nil)

local uppercase = identity.inspect("0123456789ABCDEF0123456789ABCDEF\n")
assert(not uppercase.available)

local extra_line = identity.inspect(generated .. "\n\n")
assert(not extra_line.available)

local oversized = identity.inspect(generated .. string.rep("x", 2))
assert(not oversized.available)

assert(not identity.inspect(nil).available)
assert(not identity.inspect({}).available)

print("device-identity: persistent identifier validation tests passed")
