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

local function dropbear_status(uci, fs)
  local result = {
    ssh_service_installed = exists(fs, "/etc/init.d/dropbear"),
    ssh_config_available = false,
    ssh_instance_count = 0,
    ssh_enabled_instance_count = 0,
    ssh_truncated = false,
    ssh_instances = {},
    ssh_status = "disabled"
  }

  if not result.ssh_service_installed then
    return result
  end

  local secure = true
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

        if enabled == true then
          result.ssh_enabled_instance_count = result.ssh_enabled_instance_count + 1
          if not interface_valid or not port_valid or
            password_auth_enabled ~= false or
            root_password_auth_enabled ~= false or
            gateway_ports_enabled == true then
            secure = false
          end
        elseif enabled == nil then
          secure = false
        end

        if #result.ssh_instances < 8 then
          table.insert(result.ssh_instances, {
            name = name,
            enabled = enabled,
            interface = interface,
            interface_bound = interface_valid,
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
  elseif result.ssh_enabled_instance_count == 0 then
    result.ssh_status = "disabled"
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

function M.inspect(uci, fs)
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

  local https_configured = service_installed and https_listener_count > 0 and
    tls_library_available and certificate_available
  local plaintext_http_unredirected = http_listener_count > 0 and
    not http_redirect_enabled
  local ssh = dropbear_status(uci, fs)

  local status = "ready"
  if not https_configured then
    status = "unavailable"
  elseif plaintext_http_unredirected or ssh.ssh_status == "review" or
    ssh.ssh_status == "unavailable" then
    status = "review"
  end

  return {
    service_installed = service_installed,
    http_listener_count = http_listener_count,
    https_listener_count = https_listener_count,
    tls_library_available = tls_library_available,
    certificate_available = certificate_available,
    key_generator_available = key_generator_available,
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
    status = status
  }
end

return M
