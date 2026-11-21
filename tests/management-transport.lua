package.path = "files/usr/lib/lua/?.lua;" .. package.path
local transport = require "luci.quantumgrid.management_transport"

local function fixture(redirect, overrides)
  local lists = {
    listen_http = { "0.0.0.0:80", "[::]:80" },
    listen_https = { "0.0.0.0:443", "[::]:443" }
  }
  local values = { redirect_https = redirect }
  local files = {
    ["/etc/init.d/uhttpd"] = true,
    ["/lib/libustream-ssl.so"] = true,
    ["/etc/uhttpd.crt"] = true,
    ["/etc/uhttpd.key"] = true,
    ["/usr/bin/openssl"] = true
  }
  local empty_files = {}
  for key, value in pairs(overrides or {}) do
    if key == "lists" then lists = value
    elseif key == "values" then values = value
    elseif key == "files" then files = value
    elseif key == "empty_files" then empty_files = value
    end
  end

  local uci = {}
  function uci:get(package, section, option)
    if package == "uhttpd" and section == "main" then return values[option] end
    return nil
  end
  function uci:get_list(package, section, option)
    if package == "uhttpd" and section == "main" then return lists[option] end
    return nil
  end
  local fs = {
    access = function(path) return files[path] == true end,
    stat = function(path)
      if files[path] ~= true then return nil end
      return { size = empty_files[path] and 0 or 128 }
    end
  }
  return uci, fs
end

local uci, fs = fixture("0")
local review = transport.inspect(uci, fs)
assert(review.service_installed)
assert(review.http_listener_count == 2 and review.https_listener_count == 2)
assert(review.tls_library_available and review.certificate_available)
assert(review.key_generator_available and review.https_configured)
assert(not review.http_redirect_enabled and review.plaintext_http_unredirected)
assert(review.status == "review", "an HTTP listener without HTTPS redirect must require review")

uci, fs = fixture("1")
local ready = transport.inspect(uci, fs)
assert(ready.http_redirect_enabled and ready.https_configured)
assert(not ready.plaintext_http_unredirected and ready.status == "ready")

uci, fs = fixture("0", {
  lists = { listen_http = {}, listen_https = { "0.0.0.0:443" } }
})
local https_only = transport.inspect(uci, fs)
assert(https_only.status == "ready", "HTTPS-only listeners do not require an HTTP redirect")
assert(https_only.http_listener_count == 0 and not https_only.plaintext_http_unredirected)

uci, fs = fixture("1", {
  files = {
    ["/etc/init.d/uhttpd"] = true,
    ["/lib/libustream-ssl.so"] = false,
    ["/etc/uhttpd.crt"] = true,
    ["/etc/uhttpd.key"] = true,
    ["/usr/bin/openssl"] = true
  }
})
local missing_tls = transport.inspect(uci, fs)
assert(not missing_tls.https_configured and missing_tls.status == "unavailable")

uci, fs = fixture("1", {
  files = {
    ["/etc/init.d/uhttpd"] = true,
    ["/lib/libustream-ssl.so"] = true,
    ["/etc/uhttpd.crt"] = false,
    ["/etc/uhttpd.key"] = true,
    ["/usr/bin/openssl"] = true
  }
})
local missing_certificate = transport.inspect(uci, fs)
assert(not missing_certificate.https_configured and missing_certificate.status == "unavailable")

uci, fs = fixture("1", {
  empty_files = { ["/etc/uhttpd.crt"] = true }
})
local empty_certificate = transport.inspect(uci, fs)
assert(not empty_certificate.certificate_available and not empty_certificate.https_configured)

uci, fs = fixture("1", {
  lists = { listen_http = { "0.0.0.0:80" }, listen_https = {} }
})
local missing_listener = transport.inspect(uci, fs)
assert(not missing_listener.https_configured and missing_listener.status == "unavailable")

uci, fs = fixture("1", {
  files = {
    ["/etc/init.d/uhttpd"] = false,
    ["/lib/libustream-ssl.so"] = true,
    ["/etc/uhttpd.crt"] = true,
    ["/etc/uhttpd.key"] = true,
    ["/usr/bin/openssl"] = true
  }
})
local missing_service = transport.inspect(uci, fs)
assert(not missing_service.service_installed and missing_service.status == "unavailable")

-- Malformed UCI list entries are ignored instead of being counted as listeners.
uci, fs = fixture("1", {
  lists = { listen_http = { "", false, "0.0.0.0:80" }, listen_https = { "0.0.0.0:443" } }
})
local malformed = transport.inspect(uci, fs)
assert(malformed.http_listener_count == 1 and malformed.https_listener_count == 1)

print("management-transport: HTTPS readiness and plaintext HTTP posture tests passed")
