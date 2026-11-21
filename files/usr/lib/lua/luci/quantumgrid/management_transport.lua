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

function M.inspect(uci, fs)
  local service_installed = exists(fs, "/etc/init.d/uhttpd")
  local http_listener_count = listener_count(uci, "listen_http")
  local https_listener_count = listener_count(uci, "listen_https")

  local redirect_ok, redirect_value = pcall(uci.get, uci, "uhttpd", "main", "redirect_https")
  local http_redirect_enabled = redirect_ok and
    (redirect_value == "1" or redirect_value == true)

  local tls_library_available = exists(fs, "/lib/libustream-ssl.so")
  local certificate_available = exists(fs, "/etc/uhttpd.crt") and
    exists(fs, "/etc/uhttpd.key")
  local key_generator_available = exists(fs, "/usr/bin/openssl") or
    exists(fs, "/usr/sbin/px5g")

  local https_ready = service_installed and https_listener_count > 0 and
    tls_library_available and certificate_available
  local plaintext_http_unredirected = http_listener_count > 0 and
    not http_redirect_enabled

  local status = "ready"
  if not https_ready then
    status = "unavailable"
  elseif plaintext_http_unredirected then
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
    https_ready = https_ready,
    plaintext_http_unredirected = plaintext_http_unredirected,
    status = status
  }
end

return M
