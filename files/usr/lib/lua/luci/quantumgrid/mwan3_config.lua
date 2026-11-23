local M = {}

local MAX_TRACK_TARGETS = 8
local SNAPSHOT_OPTIONS = {
  "enabled", "track_ip", "reliability", "count", "timeout",
  "interval", "down", "up", "initial_state"
}

local function bounded_integer(value, minimum, maximum)
  local number = tonumber(value)
  if not number or number ~= math.floor(number) or
    number < minimum or number > maximum then
    return nil
  end
  return number
end

local function ipv4(value)
  if type(value) ~= "string" or #value < 7 or #value > 15 then return false end
  local count = 0
  for part in value:gmatch("[^.]+") do
    count = count + 1
    if #part > 3 or not part:match("^%d+$") then return false end
    if #part > 1 and part:sub(1, 1) == "0" then return false end
    local octet = tonumber(part)
    if not octet or octet < 0 or octet > 255 then return false end
  end
  return count == 4 and value:match("^%d+%.%d+%.%d+%.%d+$") ~= nil
end

local function ipv6_groups(value)
  local groups = {}
  if value == "" then return groups end
  for group in value:gmatch("[^:]+") do
    if #group < 1 or #group > 4 or not group:match("^[%x]+$") then
      return nil
    end
    table.insert(groups, group)
  end
  return groups
end

local function ipv6(value)
  if type(value) ~= "string" or #value < 2 or #value > 39 then return false end
  if not value:match("^[%x:]+$") then return false end
  -- A single leading/trailing colon is never valid; only the two-character
  -- compression marker may touch either address boundary.
  if value:sub(1, 1) == ":" and value:sub(1, 2) ~= "::" then return false end
  if value:sub(-1) == ":" and value:sub(-2) ~= "::" then return false end

  local double = value:find("::", 1, true)
  if double then
    if value:find("::", double + 2, true) then return false end
    local left_text = value:sub(1, double - 1)
    local right_text = value:sub(double + 2)
    if left_text:sub(-1) == ":" or right_text:sub(1, 1) == ":" then return false end
    local left = ipv6_groups(left_text)
    local right = ipv6_groups(right_text)
    if not left or not right then return false end
    return #left + #right < 8
  end

  if value:sub(1, 1) == ":" or value:sub(-1) == ":" then return false end
  local groups = ipv6_groups(value)
  return groups ~= nil and #groups == 8
end

local function valid_ip(value)
  return ipv4(value) or ipv6(value)
end

local function valid_section(section)
  return type(section) == "string" and #section >= 1 and #section <= 32
    and section:match("^[%w_%-]+$") ~= nil
end

local function list_values(value)
  local result = {}
  if type(value) == "string" then
    for item in value:gmatch("%S+") do table.insert(result, item) end
  elseif type(value) == "table" then
    for _, item in ipairs(value) do
      if type(item) ~= "string" then return nil end
      table.insert(result, item)
    end
    for key in pairs(value) do
      if type(key) ~= "number" or key < 1 or key > #result or key ~= math.floor(key) then
        return nil
      end
    end
  elseif value ~= nil then
    return nil
  end
  return result
end

function M.validate_update(input)
  if type(input) ~= "table" then return nil, "Multi-WAN settings must be an object." end
  if not valid_section(input.section) then
    return nil, "Choose an existing mwan3 interface section."
  end

  local enabled = input.enabled
  if enabled ~= "0" and enabled ~= "1" then
    return nil, "Interface enable state must be explicitly enabled or disabled."
  end

  local track_ips = list_values(input.track_ips)
  if not track_ips or #track_ips < 1 or #track_ips > MAX_TRACK_TARGETS then
    return nil, "Enter between 1 and 8 tracking IP addresses."
  end

  local seen = {}
  for index, address in ipairs(track_ips) do
    if #address > 39 or not valid_ip(address) then
      return nil, "Tracking target " .. tostring(index) .. " must be a valid IPv4 or IPv6 address."
    end
    if seen[address] then
      return nil, "Tracking target addresses must be unique."
    end
    seen[address] = true
  end

  local reliability = bounded_integer(input.reliability, 1, #track_ips)
  local count = bounded_integer(input.count, 1, 10)
  local timeout = bounded_integer(input.timeout, 1, 10)
  local interval = bounded_integer(input.interval, 1, 60)
  local down = bounded_integer(input.down, 1, 20)
  local up = bounded_integer(input.up, 1, 20)
  if not reliability then return nil, "Reliability must be 1 to the number of tracking targets." end
  if not count then return nil, "Probe count must be a whole number from 1 to 10." end
  if not timeout then return nil, "Probe timeout must be a whole number from 1 to 10 seconds." end
  if not interval then return nil, "Probe interval must be a whole number from 1 to 60 seconds." end
  if not down then return nil, "Failure threshold must be a whole number from 1 to 20." end
  if not up then return nil, "Recovery threshold must be a whole number from 1 to 20." end

  local initial_state = input.initial_state
  if initial_state ~= "online" and initial_state ~= "offline" then
    return nil, "Initial state must be online or offline."
  end

  return {
    section = input.section,
    enabled = enabled,
    track_ips = track_ips,
    reliability = tostring(reliability),
    count = tostring(count),
    timeout = tostring(timeout),
    interval = tostring(interval),
    down = tostring(down),
    up = tostring(up),
    initial_state = initial_state
  }
end

function M.project_section(name, section)
  if not valid_section(name) or type(section) ~= "table" then return nil end
  local track_ips = list_values(section.track_ip)
  local targets_valid = track_ips ~= nil and #track_ips > 0 and #track_ips <= MAX_TRACK_TARGETS
  if not track_ips then track_ips = {} end
  local seen = {}
  for _, address in ipairs(track_ips) do
    if not valid_ip(address) or seen[address] then targets_valid = false end
    seen[address] = true
  end

  local function projected_integer(value, minimum, maximum, fallback)
    if value == nil or value == "" then return fallback, true end
    local number = bounded_integer(value, minimum, maximum)
    return number or fallback, number ~= nil
  end

  local enabled = section.enabled
  if enabled == nil then enabled = "1" end
  local enabled_valid = enabled == "0" or enabled == "1"

  local reliability, reliability_valid = projected_integer(section.reliability, 1, MAX_TRACK_TARGETS, 1)
  local count, count_valid = projected_integer(section.count, 1, 10, 1)
  local timeout, timeout_valid = projected_integer(section.timeout, 1, 10, 2)
  local interval, interval_valid = projected_integer(section.interval, 1, 60, 5)
  local down, down_valid = projected_integer(section.down, 1, 20, 3)
  local up, up_valid = projected_integer(section.up, 1, 20, 3)
  local initial_state = section.initial_state
  if initial_state == nil or initial_state == "" then initial_state = "online" end
  local initial_state_valid = initial_state == "online" or initial_state == "offline"

  local valid = enabled_valid and targets_valid and reliability_valid and
    reliability <= #track_ips and count_valid and timeout_valid and
    interval_valid and down_valid and up_valid and initial_state_valid
  return {
    section = name,
    enabled = enabled == "1",
    track_ips = track_ips,
    track_targets_valid = targets_valid,
    reliability = reliability,
    count = count,
    timeout = timeout,
    interval = interval,
    down = down,
    up = up,
    initial_state = initial_state_valid and initial_state or "unknown",
    valid = valid
  }
end

function M.snapshot(section)
  if type(section) ~= "table" then return nil end
  local result = {}
  for _, option in ipairs(SNAPSHOT_OPTIONS) do
    local value = section[option]
    if value == nil then
      result[option] = false
    elseif type(value) == "table" then
      local copy = {}
      for index, item in ipairs(value) do
        if type(item) ~= "string" then return nil end
        copy[index] = item
      end
      result[option] = copy
    elseif type(value) == "string" or type(value) == "boolean" or type(value) == "number" then
      result[option] = value
    else
      return nil
    end
  end
  return result
end

function M.stage_update(uci, section, update)
  if type(uci) ~= "table" or not valid_section(section) or
    type(update) ~= "table" or update.section ~= section then
    return false
  end
  local values = {
    enabled = update.enabled,
    track_ip = update.track_ips,
    reliability = update.reliability,
    count = update.count,
    timeout = update.timeout,
    interval = update.interval,
    down = update.down,
    up = update.up,
    initial_state = update.initial_state
  }
  for _, option in ipairs(SNAPSHOT_OPTIONS) do
    local value = values[option]
    local ok, result
    if option == "track_ip" then
      ok, result = pcall(uci.set_list, uci, "mwan3", section, option, value)
    else
      ok, result = pcall(uci.set, uci, "mwan3", section, option, value)
    end
    if not ok or result ~= true then return false end
  end
  return true
end

function M.restore(uci, section, snapshot)
  if type(uci) ~= "table" or not valid_section(section) or type(snapshot) ~= "table" then
    return false
  end
  for _, option in ipairs(SNAPSHOT_OPTIONS) do
    local previous = snapshot[option]
    local ok, result
    if previous == false then
      ok, result = pcall(uci.delete, uci, "mwan3", section, option)
    elseif option == "track_ip" and type(previous) == "table" then
      ok, result = pcall(uci.set_list, uci, "mwan3", section, option, previous)
    else
      ok, result = pcall(uci.set, uci, "mwan3", section, option, previous)
    end
    if not ok or result ~= true then return false end
  end
  local commit_ok, committed = pcall(uci.commit, uci, "mwan3")
  return commit_ok and committed == true
end

local MEMBER_OPTIONS = { "interface", "metric", "weight" }

function M.validate_member_update(input, interfaces)
  if type(input) ~= "table" then return nil, "Multi-WAN member settings must be an object." end
  if not valid_section(input.section) then
    return nil, "Choose an existing mwan3 member section."
  end
  if not valid_section(input.interface) or type(interfaces) ~= "table" or interfaces[input.interface] ~= true then
    return nil, "Choose an existing mwan3 interface for this member."
  end
  local metric = bounded_integer(input.metric, 1, 255)
  local weight = bounded_integer(input.weight, 1, 100)
  if not metric then return nil, "Member metric must be a whole number from 1 to 255." end
  if not weight then return nil, "Member weight must be a whole number from 1 to 100." end
  return {
    section = input.section,
    interface = input.interface,
    metric = tostring(metric),
    weight = tostring(weight),
  }
end

function M.project_member_section(name, section, interfaces, policy_membership)
  if not valid_section(name) or type(section) ~= "table" or section[".type"] ~= "member" then
    return nil
  end
  local interface = type(section.interface) == "string" and section.interface or ""
  local metric = bounded_integer(section.metric == nil and "1" or section.metric, 1, 255)
  local weight = bounded_integer(section.weight == nil and "1" or section.weight, 1, 100)
  local policies = {}
  if type(policy_membership) == "table" and type(policy_membership[name]) == "table" then
    local seen = {}
    for _, policy in ipairs(policy_membership[name]) do
      if valid_section(policy) and not seen[policy] then
        seen[policy] = true
        policies[#policies + 1] = policy
      end
    end
  end
  table.sort(policies)
  return {
    section = name,
    interface = interface,
    metric = metric or 1,
    weight = weight or 1,
    policies = policies,
    valid = valid_section(interface) and type(interfaces) == "table" and
      interfaces[interface] == true and metric ~= nil and weight ~= nil,
  }
end

function M.snapshot_member(section)
  if type(section) ~= "table" or section[".type"] ~= "member" then return nil end
  local result = {}
  for _, option in ipairs(MEMBER_OPTIONS) do
    local value = section[option]
    if value == nil then
      result[option] = false
    elseif type(value) == "string" or type(value) == "number" then
      result[option] = tostring(value)
    else
      return nil
    end
  end
  return result
end

function M.stage_member_update(uci, section, update)
  if type(uci) ~= "table" or not valid_section(section) or
    type(update) ~= "table" or update.section ~= section then return false end
  local values = {
    interface = update.interface,
    metric = update.metric,
    weight = update.weight,
  }
  for _, option in ipairs(MEMBER_OPTIONS) do
    local ok, result = pcall(uci.set, uci, "mwan3", section, option, values[option])
    if not ok or result ~= true then return false end
  end
  return true
end

function M.restore_member(uci, section, snapshot)
  if type(uci) ~= "table" or not valid_section(section) or type(snapshot) ~= "table" then
    return false
  end
  for _, option in ipairs(MEMBER_OPTIONS) do
    local previous = snapshot[option]
    local ok, result
    if previous == false then
      ok, result = pcall(uci.delete, uci, "mwan3", section, option)
    else
      ok, result = pcall(uci.set, uci, "mwan3", section, option, previous)
    end
    if not ok or result ~= true then return false end
  end
  local commit_ok, committed = pcall(uci.commit, uci, "mwan3")
  return commit_ok and committed == true
end

return M
