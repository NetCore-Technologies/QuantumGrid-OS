local M = {}

-- The device ID is a stable, public inventory key. It is not a credential.
function M.inspect(value)
  local result = {
    available = false,
    status = "unavailable"
  }
  if type(value) ~= "string" or #value > 33 then
    return result
  end

  local id = value:gsub("\n$", "")
  if #id ~= 32 or not id:match("^[0-9a-f]+$") then
    return result
  end

  result.available = true
  result.status = "available"
  result.id = id
  return result
end

return M
