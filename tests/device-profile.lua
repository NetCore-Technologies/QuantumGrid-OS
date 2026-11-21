package.path = "files/usr/lib/lua/?.lua;" .. package.path
local profile = require "luci.quantumgrid.device_profile"

local aw1000 = {
  schema_version = 1,
  platform = {
    id = "arcadyan-aw1000",
    vendor = "Arcadyan",
    model = "AW1000",
    openwrt_device = "arcadyan_aw1000",
    openwrt_target = "qualcommax",
    openwrt_subtarget = "ipq807x",
    board_compatible = { "arcadyan,aw1000" }
  }
}

local matched = profile.inspect(aw1000, "arcadyan,aw1000")
assert(matched.available)
assert(matched.status == "matched")
assert(matched.profile_id == "arcadyan-aw1000")
assert(matched.model == "AW1000")
assert(matched.openwrt_device == "arcadyan_aw1000")
assert(matched.observed_board_name == "arcadyan,aw1000")
assert(#matched.board_compatible == 1)

local mismatch = profile.inspect(aw1000, "vendor,other-board")
assert(mismatch.available)
assert(mismatch.status == "mismatch")
assert(mismatch.observed_board_name == "vendor,other-board")

local unknown = profile.inspect(aw1000, nil)
assert(unknown.available)
assert(unknown.status == "unknown")
assert(unknown.observed_board_name == nil)

local unavailable = profile.inspect(nil, "arcadyan,aw1000")
assert(not unavailable.available)
assert(unavailable.status == "unavailable")

local invalid_schema = {
  schema_version = 2,
  platform = aw1000.platform
}
assert(profile.inspect(invalid_schema, "arcadyan,aw1000").status == "unavailable")

local bool_schema = {
  schema_version = true,
  platform = aw1000.platform
}
assert(profile.inspect(bool_schema, "arcadyan,aw1000").status == "unavailable")

local missing_platform = profile.inspect({ schema_version = 1 }, "arcadyan,aw1000")
assert(not missing_platform.available and missing_platform.status == "unavailable")

local empty_board_allowlist = {
  schema_version = 1,
  platform = {
    id = "invalid", vendor = "Vendor", model = "Model",
    openwrt_device = "device", openwrt_target = "target",
    openwrt_subtarget = "subtarget", board_compatible = {}
  }
}
assert(profile.inspect(empty_board_allowlist, "arcadyan,aw1000").status == "unavailable")

local duplicate_board_ids = {
  schema_version = 1,
  platform = {
    id = "invalid", vendor = "Vendor", model = "Model",
    openwrt_device = "device", openwrt_target = "target",
    openwrt_subtarget = "subtarget",
    board_compatible = { "arcadyan,aw1000", "arcadyan,aw1000" }
  }
}
assert(profile.inspect(duplicate_board_ids, "arcadyan,aw1000").status == "unavailable")

local unsafe_observed = profile.inspect(aw1000, "arcadyan,aw1000\nattacker")
assert(unsafe_observed.status == "unknown")
assert(unsafe_observed.observed_board_name == nil)

local too_many_ids = {
  schema_version = 1,
  platform = {
    id = "invalid", vendor = "Vendor", model = "Model",
    openwrt_device = "device", openwrt_target = "target",
    openwrt_subtarget = "subtarget",
    board_compatible = {
      "vendor,board1", "vendor,board2", "vendor,board3", "vendor,board4",
      "vendor,board5", "vendor,board6", "vendor,board7", "vendor,board8",
      "vendor,board9", "vendor,board10", "vendor,board11", "vendor,board12",
      "vendor,board13", "vendor,board14", "vendor,board15", "vendor,board16",
      "vendor,board17"
    }
  }
}
assert(profile.inspect(too_many_ids, "vendor,board1").status == "unavailable")

print("device-profile: runtime identity checks passed")
