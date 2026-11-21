local M = {}

local function bounded_string(value, maximum, pattern)
  if type(value) ~= "string" or #value < 1 or #value > maximum then
    return nil
  end
  if pattern and not value:match(pattern) then return nil end
  if value:find("[%c]") then return nil end
  return value
end

function M.inspect(profile, observed_board_name)
  local result = {
    available = false,
    status = "unavailable",
    profile_id = nil,
    vendor = nil,
    model = nil,
    openwrt_device = nil,
    openwrt_target = nil,
    openwrt_subtarget = nil,
    board_compatible = {},
    observed_board_name = nil
  }

  if type(profile) ~= "table" or type(profile.platform) ~= "table" then
    return result
  end
  if type(profile.schema_version) ~= "number" or profile.schema_version ~= 1 then
    return result
  end

  local platform = profile.platform
  local profile_id = bounded_string(platform.id, 64, "^[a-z0-9][a-z0-9%-]*$")
  local vendor = bounded_string(platform.vendor, 64)
  local model = bounded_string(platform.model, 64)
  local device = bounded_string(platform.openwrt_device, 64, "^[a-z0-9][a-z0-9_%-]*$")
  local target = bounded_string(platform.openwrt_target, 64, "^[a-z0-9][a-z0-9_%-]*$")
  local subtarget = bounded_string(platform.openwrt_subtarget, 64, "^[a-z0-9][a-z0-9_%-]*$")
  local board_ids = platform.board_compatible
  if not profile_id or not vendor or not model or not device or not target or
    not subtarget or type(board_ids) ~= "table" then
    return result
  end

  local ids = {}
  local count = 0
  for index, value in ipairs(board_ids) do
    count = count + 1
    if count > 16 then return result end
    local board_id = bounded_string(value, 64, "^[a-z0-9][a-z0-9,._%-]*$")
    if not board_id or ids[board_id] then return result end
    ids[board_id] = true
    table.insert(result.board_compatible, board_id)
  end
  if count == 0 then return result end

  for key in pairs(board_ids) do
    if type(key) ~= "number" or key < 1 or key > count or key ~= math.floor(key) then
      return result
    end
  end

  result.available = true
  result.profile_id = profile_id
  result.vendor = vendor
  result.model = model
  result.openwrt_device = device
  result.openwrt_target = target
  result.openwrt_subtarget = subtarget

  local observed = bounded_string(observed_board_name, 128, "^[%w,._%-]+$")
  if not observed then
    result.status = "unknown"
    return result
  end
  result.observed_board_name = observed
  result.status = ids[observed] and "matched" or "mismatch"
  return result
end

return M
