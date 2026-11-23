local M = {}

local function listener_count(uci, option)
  local ok, value = false, nil
  if type(uci.get_list) == "function" then
    ok, value = pcall(uci.get_list, uci, "uhttpd", "main", option)
  end
  if not ok or value == nil then
    if type(uci.get) == "function" then
      ok, value = pcall(uci.get, uci, "uhttpd", "main", option)
    end
  end
  if not ok then return 0 end

  if type(value) == "string" then
    return value ~= "" and 1 or 0
  end
  if type(value) ~= "table" then return 0 end

  local count = 0
  for _, listener in ipairs(value) do
    if type(listener) == "string" and listener ~= "" then
      count = count + 1
    end
  end
  return count
end

local function exists(fs, path)
  local ok, value = pcall(fs.access, path)
  return ok and value == true
end

local function nonempty_file(fs, path)
  if type(fs.stat) == "function" then
    local ok, stat = pcall(fs.stat, path)
    return ok and type(stat) == "table" and
      type(stat.size) == "number" and stat.size > 0
  end
  return exists(fs, path)
end

local function boolean_option(value, default)
  if value == nil then return default end
  if value == true then return true end
  if value == false then return false end
  if type(value) ~= "string" then return nil end

  local normalized = value:lower()
  if normalized == "1" or normalized == "on" or normalized == "true" then
    return true
  end
  if normalized == "0" or normalized == "off" or normalized == "false" then
    return false
  end
  return nil
end

local EXTERNAL_MANAGEMENT_ZONES = {
  wan = true, wan6 = true, wwan = true, cellular = true, lte = true, ["5g"] = true
}

local INTERNAL_MANAGEMENT_ZONES = {
  lan = true, mgmt = true, management = true, corp = true,
  office = true, home = true, trusted = true, internal = true
}

local function normalized_name(value)
  return type(value) == "string" and value:lower():match("^%s*(.-)%s*$") or ""
end

local function management_zone_kind(name)
  local normalized = normalized_name(name)
  if EXTERNAL_MANAGEMENT_ZONES[normalized] or
    normalized:match("^wan%d+$") or normalized:match("^wwan%d+$") then
    return "external"
  end
  if INTERNAL_MANAGEMENT_ZONES[normalized] then return "internal" end
  return "unknown"
end

local function add_zone_networks(index, value, kind)
  local function add(network)
    if type(network) ~= "string" or network == "" then return end
    index[network] = index[network] or {}
    table.insert(index[network], kind)
  end

  if type(value) == "string" then
    for token in value:gmatch("%S+") do add(token) end
  elseif type(value) == "table" then
    for _, network in ipairs(value) do add(network) end
  end
end

function M.classify_firewall_zone_name(name)
  return management_zone_kind(name)
end

local function management_zone_index(uci)
  if type(uci) ~= "table" or type(uci.foreach) ~= "function" then return nil end
  local index = {}
  local ok = pcall(function()
    uci:foreach("firewall", "zone", function(zone)
      if type(zone) == "table" then
        local name = zone.name or zone[".name"]
        add_zone_networks(index, zone.network or zone.networks, management_zone_kind(name))
      end
    end)
  end)
  if not ok then return nil end
  return index
end

local function management_interface_zone(index, interface)
  local direct_kind = management_zone_kind(interface)
  if direct_kind == "external" then return direct_kind end
  if type(index) ~= "table" or interface == "" then return "unknown" end
  local matches = index[interface]
  if type(matches) ~= "table" or #matches ~= 1 then return "unknown" end
  return matches[1]
end

local function permission_bits(stat)
  local mode = type(stat) == "table" and tonumber(stat.modedec or stat.mode) or nil
  if not mode then return nil end
  return mode % 512
end

local function file_type_matches(stat, expected, mode_number)
  if type(stat) == "table" and type(stat.type) == "string" then
    return stat.type == expected
  end
  local mode = type(stat) == "table" and tonumber(stat.modedec or stat.mode) or nil
  if not mode then return nil end
  return math.floor(mode / 4096) % 16 == mode_number
end

local function lstat(fs, path)
  if type(fs) ~= "table" or type(fs.lstat) ~= "function" then
    return false, nil
  end
  local ok, stat = pcall(fs.lstat, path)
  return ok and type(stat) == "table", stat
end

local BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local BASE64_LOOKUP = {}
for index = 1, #BASE64_ALPHABET do
  BASE64_LOOKUP[BASE64_ALPHABET:sub(index, index)] = index - 1
end

local SUPPORTED_SSH_KEY_TYPES = {
  ["ssh-ed25519"] = true,
  ["ssh-rsa"] = true,
  ["ecdsa-sha2-nistp256"] = true,
  ["ecdsa-sha2-nistp384"] = true,
  ["ecdsa-sha2-nistp521"] = true,
  ["sk-ssh-ed25519@openssh.com"] = true,
  ["sk-ecdsa-sha2-nistp256@openssh.com"] = true
}

local function decode_public_key_blob(encoded)
  if type(encoded) ~= "string" or #encoded < 44 or #encoded > 16384 or #encoded % 4 ~= 0 then
    return nil
  end
  local output = {}
  for offset = 1, #encoded, 4 do
    local a = BASE64_LOOKUP[encoded:sub(offset, offset)]
    local b = BASE64_LOOKUP[encoded:sub(offset + 1, offset + 1)]
    local third = encoded:sub(offset + 2, offset + 2)
    local fourth = encoded:sub(offset + 3, offset + 3)
    local c = third == "=" and 0 or BASE64_LOOKUP[third]
    local d = fourth == "=" and 0 or BASE64_LOOKUP[fourth]
    local last = offset + 3 == #encoded
    if a == nil or b == nil or c == nil or d == nil then return nil end
    if third == "=" then
      if not last or fourth ~= "=" or b % 16 ~= 0 then return nil end
    elseif fourth == "=" then
      if not last or c % 4 ~= 0 then return nil end
    end
    if not last and (third == "=" or fourth == "=") then return nil end

    local first_byte = a * 4 + math.floor(b / 16)
    local second_byte = (b % 16) * 16 + math.floor(c / 4)
    local third_byte = (c % 4) * 64 + d
    table.insert(output, string.char(first_byte))
    if third ~= "=" then table.insert(output, string.char(second_byte)) end
    if fourth ~= "=" then table.insert(output, string.char(third_byte)) end
  end
  return table.concat(output)
end

local function read_ssh_u32(blob, offset)
  if type(blob) ~= "string" or offset < 1 or offset + 3 > #blob then return nil end
  local a, b, c, d = blob:byte(offset, offset + 3)
  return ((a * 256 + b) * 256 + c) * 256 + d, offset + 4
end

local function read_ssh_string(blob, offset)
  local length, start = read_ssh_u32(blob, offset)
  if not length or length > #blob - start + 1 then return nil end
  return blob:sub(start, start + length - 1), start + length
end

local function valid_ssh_key_blob(algorithm, encoded)
  if not SUPPORTED_SSH_KEY_TYPES[algorithm] then return false end
  local blob = decode_public_key_blob(encoded)
  if not blob then return false end
  local embedded_algorithm, offset = read_ssh_string(blob, 1)
  if embedded_algorithm ~= algorithm or not offset then return false end

  if algorithm == "ssh-ed25519" then
    local public_key, next_offset = read_ssh_string(blob, offset)
    return type(public_key) == "string" and #public_key == 32 and next_offset == #blob + 1
  elseif algorithm == "ssh-rsa" then
    local exponent, next_offset = read_ssh_string(blob, offset)
    local modulus, final_offset = next_offset and read_ssh_string(blob, next_offset) or nil, nil
    if next_offset and type(exponent) == "string" then
      modulus, final_offset = read_ssh_string(blob, next_offset)
    end
    return type(exponent) == "string" and #exponent >= 1 and #exponent <= 8 and
      type(modulus) == "string" and #modulus >= 256 and final_offset == #blob + 1
  elseif algorithm:match("^ecdsa%-sha2%-") then
    local expected_curve = algorithm:match("^ecdsa%-sha2%-(nistp%d+)$")
    local curve, next_offset = read_ssh_string(blob, offset)
    local point, final_offset = next_offset and read_ssh_string(blob, next_offset) or nil, nil
    if next_offset and type(curve) == "string" then point, final_offset = read_ssh_string(blob, next_offset) end
    local expected_length = expected_curve == "nistp256" and 65 or
      expected_curve == "nistp384" and 97 or expected_curve == "nistp521" and 133 or nil
    return curve == expected_curve and type(point) == "string" and #point == expected_length and
      point:byte(1) == 4 and final_offset == #blob + 1
  elseif algorithm == "sk-ssh-ed25519@openssh.com" then
    local public_key, next_offset = read_ssh_string(blob, offset)
    local application, final_offset = next_offset and read_ssh_string(blob, next_offset) or nil, nil
    if next_offset and type(public_key) == "string" then application, final_offset = read_ssh_string(blob, next_offset) end
    return type(public_key) == "string" and #public_key == 32 and
      type(application) == "string" and #application > 0 and final_offset == #blob + 1
  elseif algorithm == "sk-ecdsa-sha2-nistp256@openssh.com" then
    local curve, next_offset = read_ssh_string(blob, offset)
    local point, point_offset = next_offset and read_ssh_string(blob, next_offset) or nil, nil
    if next_offset and type(curve) == "string" then point, point_offset = read_ssh_string(blob, next_offset) end
    local application, final_offset = point_offset and read_ssh_string(blob, point_offset) or nil, nil
    if point_offset and type(point) == "string" then application, final_offset = read_ssh_string(blob, point_offset) end
    return curve == "nistp256" and type(point) == "string" and #point == 65 and point:byte(1) == 4 and
      type(application) == "string" and #application > 0 and final_offset == #blob + 1
  end
  return false
end

local function authorized_key_tokens(line)
  local tokens, current = {}, {}
  local in_quotes, escaped = false, false
  for index = 1, #line do
    local character = line:sub(index, index)
    if escaped then
      table.insert(current, character)
      escaped = false
    elseif in_quotes and character == "\\" then
      escaped = true
    elseif character == '"' then
      in_quotes = not in_quotes
    elseif character:match("%s") and not in_quotes then
      if #current > 0 then
        table.insert(tokens, table.concat(current))
        current = {}
      end
    else
      table.insert(current, character)
    end
  end
  if in_quotes or escaped then return nil end
  if #current > 0 then table.insert(tokens, table.concat(current)) end
  return tokens
end

local function parse_authorized_key_line(line)
  if type(line) ~= "string" or #line > 16384 then return nil end
  local trimmed = line:match("^%s*(.-)%s*$")
  if not trimmed or trimmed == "" or trimmed:sub(1, 1) == "#" then return "comment" end
  local tokens = authorized_key_tokens(trimmed)
  if not tokens then return nil end
  local algorithm_index = SUPPORTED_SSH_KEY_TYPES[tokens[1]] and 1 or
    SUPPORTED_SSH_KEY_TYPES[tokens[2]] and 2 or nil
  if not algorithm_index then return nil end
  local algorithm = tokens[algorithm_index]
  local encoded = tokens[algorithm_index + 1]
  if not valid_ssh_key_blob(algorithm, encoded) then return nil end
  return algorithm
end

local function inspect_authorized_keys(fs, path, size_bytes)
  local result = { available = false, key_count = 0, invalid_line_count = 0, key_algorithms = {} }
  if type(fs) ~= "table" or type(fs.readfile) ~= "function" or
    type(size_bytes) ~= "number" or size_bytes < 0 or size_bytes > 65536 then
    return result
  end
  local ok, contents = pcall(fs.readfile, path)
  if not ok or type(contents) ~= "string" or #contents ~= size_bytes then return result end
  result.available = true
  local algorithms = {}
  for line in (contents .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    local algorithm = parse_authorized_key_line(line)
    if algorithm == "comment" then
      -- Blank and comment lines are harmless and do not count as malformed keys.
    elseif algorithm then
      result.key_count = result.key_count + 1
      algorithms[algorithm] = true
    elseif line ~= "" then
      result.invalid_line_count = result.invalid_line_count + 1
    end
  end
  for algorithm in pairs(algorithms) do table.insert(result.key_algorithms, algorithm) end
  table.sort(result.key_algorithms)
  return result
end

local function authorized_keys_status(fs)
  local result = {
    available = false,
    path = "",
    directory = "",
    size_bytes = nil,
    root_owned = nil,
    regular_file = nil,
    owner_readable = nil,
    group_writable = nil,
    other_writable = nil,
    directory_root_owned = nil,
    directory_valid = nil,
    directory_group_writable = nil,
    directory_other_writable = nil,
    key_inventory_available = false,
    key_count = 0,
    invalid_line_count = 0,
    key_algorithms = {},
    status = "missing"
  }

  if type(fs) ~= "table" or type(fs.access) ~= "function" then
    result.status = "unavailable"
    return result
  end

  local candidates = {
    { path = "/etc/dropbear/authorized_keys", directory = "/etc/dropbear" },
    { path = "/root/.ssh/authorized_keys", directory = "/root/.ssh" }
  }
  local selected = nil
  for _, candidate in ipairs(candidates) do
    if exists(fs, candidate.path) then
      selected = candidate
      break
    end
  end

  if not selected then return result end
  result.available = true
  result.path = selected.path
  result.directory = selected.directory

  local ok, stat = lstat(fs, selected.path)
  if not ok then
    result.status = "unknown"
    return result
  end

  if type(stat.size) == "number" and stat.size >= 0 then
    result.size_bytes = stat.size
  end
  if type(stat.uid) == "number" then
    result.root_owned = stat.uid == 0
  end
  local permissions = permission_bits(stat)
  result.regular_file = file_type_matches(stat, "reg", 8)
  if permissions then
    result.owner_readable = math.floor(permissions / 256) % 2 == 1
    result.group_writable = math.floor(permissions / 16) % 2 == 1
    result.other_writable = math.floor(permissions / 2) % 2 == 1
  end

  -- Never follow a symlink or special file while inspecting authorised keys.
  -- A known non-regular file is a review finding, not an unavailable/unknown result.
  if result.regular_file == true then
    local key_inventory = inspect_authorized_keys(fs, selected.path, result.size_bytes)
    result.key_inventory_available = key_inventory.available
    result.key_count = key_inventory.key_count
    result.invalid_line_count = key_inventory.invalid_line_count
    result.key_algorithms = key_inventory.key_algorithms
  end

  local directory_ok, directory_stat = lstat(fs, selected.directory)
  if directory_ok then
    if type(directory_stat.uid) == "number" then
      result.directory_root_owned = directory_stat.uid == 0
    end
    local directory_permissions = permission_bits(directory_stat)
    result.directory_valid = file_type_matches(directory_stat, "dir", 4)
    if directory_permissions then
      result.directory_group_writable = math.floor(directory_permissions / 16) % 2 == 1
      result.directory_other_writable = math.floor(directory_permissions / 2) % 2 == 1
    end
  end

  local known_unsafe = result.size_bytes == 0 or
    (type(result.size_bytes) == "number" and result.size_bytes > 65536) or
    result.root_owned == false or result.regular_file == false or
    result.owner_readable == false or result.group_writable == true or
    result.other_writable == true or result.directory_root_owned == false or
    result.directory_valid == false or result.directory_group_writable == true or
    result.directory_other_writable == true or
    (result.regular_file == true and
      (result.size_bytes == 0 or result.key_count == 0 or result.invalid_line_count > 0))
  local evidence_incomplete = result.size_bytes == nil or result.root_owned == nil or
    result.regular_file == nil or result.owner_readable == nil or
    result.group_writable == nil or result.other_writable == nil or
    result.directory_root_owned == nil or result.directory_valid == nil or
    result.directory_group_writable == nil or result.directory_other_writable == nil or
    (result.regular_file == true and not result.key_inventory_available)

  if known_unsafe then
    result.status = "review"
  elseif evidence_incomplete then
    result.status = "unknown"
  else
    result.status = "present"
  end

  return result
end

local function https_private_key_status(fs)
  local result = {
    available = false,
    path = "/etc/uhttpd.key",
    size_bytes = nil,
    root_owned = nil,
    regular_file = nil,
    owner_readable = nil,
    group_access = nil,
    other_access = nil,
    status = "missing"
  }

  if not exists(fs, result.path) then return result end
  result.available = true
  local ok, stat = lstat(fs, result.path)
  if not ok then
    result.status = "unknown"
    return result
  end
  if type(stat.size) == "number" and stat.size >= 0 then
    result.size_bytes = stat.size
  end
  if type(stat.uid) == "number" then
    result.root_owned = stat.uid == 0
  end
  local permissions = permission_bits(stat)
  result.regular_file = file_type_matches(stat, "reg", 8)
  if permissions then
    result.owner_readable = math.floor(permissions / 256) % 2 == 1
    result.group_access = math.floor(permissions / 8) % 8 ~= 0
    result.other_access = permissions % 8 ~= 0
  end

  if result.size_bytes == nil or result.root_owned == nil or
    result.regular_file == nil or result.owner_readable == nil or
    result.group_access == nil or result.other_access == nil then
    result.status = "unknown"
  elseif result.size_bytes == 0 or result.size_bytes > 65536 or
    not result.root_owned or not result.regular_file or not result.owner_readable or
    result.group_access or result.other_access then
    result.status = "review"
  else
    result.status = "present"
  end
  return result
end

function M.parse_certificate_fingerprint(output)
  local result = {
    available = false,
    algorithm = "SHA-256",
    value = nil
  }
  if type(output) ~= "string" or #output > 4096 then return result end

  local lower = output:lower()
  local _, finish = lower:find("sha256%s+fingerprint%s*=%s*")
  if not finish then return result end

  local raw = output:sub(finish + 1):match("^([%x:]+)")
  if not raw then return result end
  local compact = raw:gsub(":", "")
  if #compact ~= 64 or not compact:match("^[%x]+$") then return result end

  local bytes = {}
  for index = 1, #compact, 2 do
    table.insert(bytes, compact:sub(index, index + 1):upper())
  end
  result.available = true
  result.value = table.concat(bytes, ":")
  return result
end

local function dropbear_status(uci, fs)
  local result = {
    ssh_service_installed = exists(fs, "/etc/init.d/dropbear"),
    ssh_config_available = false,
    ssh_instance_count = 0,
    ssh_enabled_instance_count = 0,
    ssh_truncated = false,
    ssh_instances = {},
    ssh_status = "disabled",
    ssh_authorized_keys = authorized_keys_status(fs)
  }

  if not result.ssh_service_installed then
    return result
  end

  local secure = true
  local has_unknown_enable = false
  local zone_index = management_zone_index(uci)
  local config_ok = type(uci) == "table" and type(uci.foreach) == "function"
  if config_ok then
    config_ok = pcall(function()
      uci:foreach("dropbear", "dropbear", function(section)
        if type(section) ~= "table" then
          error("Dropbear configuration section is malformed")
        end

        result.ssh_instance_count = result.ssh_instance_count + 1
        local name = section[".name"]
        if type(name) ~= "string" or name == "" then
          name = "dropbear-" .. tostring(result.ssh_instance_count)
        end
        name = name:gsub("[^%w_.%-]", ""):sub(1, 64)
        if name == "" then name = "dropbear-" .. tostring(result.ssh_instance_count) end

        local interface = section.Interface
        local interface_valid = type(interface) == "string" and
          #interface > 0 and #interface <= 64 and
          interface:match("^[%w_.%-]+$") ~= nil
        if not interface_valid then interface = "" end

        local port = 22
        local port_valid = true
        if section.Port ~= nil then
          port = tonumber(section.Port)
          port_valid = port ~= nil and port >= 1 and port <= 65535 and
            port == math.floor(port)
          if not port_valid then port = nil end
        end

        local enabled = boolean_option(section.enable, true)
        local password_auth_enabled = boolean_option(section.PasswordAuth, true)
        local root_password_auth_enabled = boolean_option(section.RootPasswordAuth, true)
        local gateway_ports_enabled = boolean_option(section.GatewayPorts, false)
        local interface_zone_status = management_interface_zone(zone_index, interface)

        if enabled == true then
          result.ssh_enabled_instance_count = result.ssh_enabled_instance_count + 1
          if not interface_valid or not port_valid or interface_zone_status ~= "internal" or
            password_auth_enabled ~= false or
            root_password_auth_enabled ~= false or
            gateway_ports_enabled == true or
            (password_auth_enabled == false and root_password_auth_enabled == false
              and result.ssh_authorized_keys.status ~= "present") then
            secure = false
          end
        elseif enabled == nil then
          secure = false
          has_unknown_enable = true
        end

        if #result.ssh_instances < 8 then
          table.insert(result.ssh_instances, {
            name = name,
            enabled = enabled,
            interface = interface,
            interface_bound = interface_valid,
            interface_zone_status = interface_zone_status,
            port = port,
            port_valid = port_valid,
            password_auth_enabled = password_auth_enabled,
            root_password_auth_enabled = root_password_auth_enabled,
            gateway_ports_enabled = gateway_ports_enabled
          })
        else
          result.ssh_truncated = true
        end
      end)
    end)
  end

  result.ssh_config_available = config_ok
  if not config_ok then
    result.ssh_status = "unavailable"
  elseif result.ssh_instance_count == 0 then
    result.ssh_status = "unavailable"
  elseif result.ssh_enabled_instance_count == 0 and not has_unknown_enable then
    result.ssh_status = "disabled"
  elseif result.ssh_enabled_instance_count == 0 then
    result.ssh_status = "review"
  elseif result.ssh_truncated or not secure then
    result.ssh_status = "review"
  else
    result.ssh_status = "ready"
  end

  return result
end

function M.require_https(http)
  if type(http) ~= "table" or type(http.getenv) ~= "function" then
    return false
  end
  if http.getenv("HTTPS") == "on" then
    return true
  end

  if type(http.status) == "function" then
    http.status(403, "Forbidden")
  end
  if type(http.header) == "function" then
    http.header("Cache-Control", "no-store")
  end
  if type(http.prepare_content) == "function" then
    http.prepare_content("application/json; charset=UTF-8")
  end
  if type(http.write_json) == "function" then
    http.write_json({
      ok = false,
      error = "HTTPS is required for administrator requests."
    })
  end
  return false
end

function M.inspect(uci, fs, certificate_fingerprint_output)
  local service_installed = exists(fs, "/etc/init.d/uhttpd")
  local http_listener_count = listener_count(uci, "listen_http")
  local https_listener_count = listener_count(uci, "listen_https")

  local redirect_ok, redirect_value = pcall(uci.get, uci, "uhttpd", "main", "redirect_https")
  local http_redirect_enabled = redirect_ok and
    (redirect_value == "1" or redirect_value == true)

  local tls_library_available = exists(fs, "/lib/libustream-ssl.so")
  local certificate_available = nonempty_file(fs, "/etc/uhttpd.crt") and
    nonempty_file(fs, "/etc/uhttpd.key")
  local key_generator_available = exists(fs, "/usr/bin/openssl") or
    exists(fs, "/usr/sbin/px5g")
  local private_key = https_private_key_status(fs)
  local certificate_fingerprint = M.parse_certificate_fingerprint(certificate_fingerprint_output)

  local https_configured = service_installed and https_listener_count > 0 and
    tls_library_available and certificate_available
  local plaintext_http_unredirected = http_listener_count > 0 and
    not http_redirect_enabled
  local ssh = dropbear_status(uci, fs)

  local status = "ready"
  if not https_configured then
    status = "unavailable"
  elseif plaintext_http_unredirected or private_key.status ~= "present" or
    ssh.ssh_status == "review" or ssh.ssh_status == "unavailable" then
    status = "review"
  end

  return {
    service_installed = service_installed,
    http_listener_count = http_listener_count,
    https_listener_count = https_listener_count,
    tls_library_available = tls_library_available,
    certificate_available = certificate_available,
    key_generator_available = key_generator_available,
    private_key = private_key,
    certificate_fingerprint = certificate_fingerprint,
    http_redirect_enabled = http_redirect_enabled,
    https_configured = https_configured,
    plaintext_http_unredirected = plaintext_http_unredirected,
    ssh_service_installed = ssh.ssh_service_installed,
    ssh_config_available = ssh.ssh_config_available,
    ssh_instance_count = ssh.ssh_instance_count,
    ssh_enabled_instance_count = ssh.ssh_enabled_instance_count,
    ssh_truncated = ssh.ssh_truncated,
    ssh_instances = ssh.ssh_instances,
    ssh_status = ssh.ssh_status,
    ssh_authorized_keys = ssh.ssh_authorized_keys,
    status = status
  }
end

return M
