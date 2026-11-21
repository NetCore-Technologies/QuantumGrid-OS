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
    ["/etc/init.d/dropbear"] = true,
    ["/etc/dropbear/authorized_keys"] = true,
    ["/lib/libustream-ssl.so"] = true,
    ["/etc/uhttpd.crt"] = true,
    ["/etc/uhttpd.key"] = true,
    ["/usr/bin/openssl"] = true
  }
  local stat_overrides = {}
  local dropbear_sections = {
    {
      [".name"] = "main",
      enable = "1",
      Interface = "lan",
      Port = "22",
      PasswordAuth = "off",
      RootPasswordAuth = "off",
      GatewayPorts = "off"
    }
  }
  local empty_files = {}
  for key, value in pairs(overrides or {}) do
    if key == "lists" then lists = value
    elseif key == "values" then values = value
    elseif key == "files" then files = value
    elseif key == "empty_files" then empty_files = value
    elseif key == "stat_overrides" then stat_overrides = value
    elseif key == "dropbear_sections" then dropbear_sections = value
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
  function uci:foreach(package, section_type, callback)
    if package == "dropbear" and section_type == "dropbear" then
      for _, section in ipairs(dropbear_sections) do callback(section) end
    end
  end
  local fs = {
    access = function(path) return files[path] == true end,
    stat = function(path)
      if files[path] ~= true then return nil end
      local override = stat_overrides[path]
      if override then return override end
      return {
        size = empty_files[path] and 0 or 128,
        uid = 0,
        mode = 33152
      }
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

assert(https_only.ssh_service_installed and https_only.ssh_config_available)
assert(https_only.ssh_instance_count == 1 and https_only.ssh_enabled_instance_count == 1)
assert(https_only.ssh_status == "ready")
assert(https_only.ssh_instances[1].interface == "lan")
assert(https_only.ssh_instances[1].interface_bound)
assert(not https_only.ssh_instances[1].password_auth_enabled)
assert(not https_only.ssh_instances[1].root_password_auth_enabled)
assert(https_only.ssh_authorized_keys.available)
assert(https_only.ssh_authorized_keys.status == "present")
assert(https_only.ssh_authorized_keys.root_owned)
assert(not https_only.ssh_authorized_keys.group_writable)
assert(not https_only.ssh_authorized_keys.other_writable)

-- Key-only access with no authorized-keys file is not a ready management posture.
uci, fs = fixture("1", {
  files = {
    ["/etc/init.d/uhttpd"] = true,
    ["/etc/init.d/dropbear"] = true,
    ["/lib/libustream-ssl.so"] = true,
    ["/etc/uhttpd.crt"] = true,
    ["/etc/uhttpd.key"] = true,
    ["/usr/bin/openssl"] = true
  },
  dropbear_sections = {{
    [".name"] = "main",
    enable = "1",
    Interface = "lan",
    Port = "22",
    PasswordAuth = "off",
    RootPasswordAuth = "off",
    GatewayPorts = "off"
  }}
})
local missing_authorized_keys = transport.inspect(uci, fs)
assert(missing_authorized_keys.ssh_authorized_keys.status == "missing")
assert(missing_authorized_keys.ssh_status == "review")
assert(missing_authorized_keys.status == "review")

-- Group-writable authorized-keys files require remediation.
uci, fs = fixture("1", {
  stat_overrides = {
    ["/etc/dropbear/authorized_keys"] = { size = 128, uid = 0, mode = 33168 }
  },
  dropbear_sections = {{
    [".name"] = "main",
    enable = "1",
    Interface = "lan",
    Port = "22",
    PasswordAuth = "off",
    RootPasswordAuth = "off",
    GatewayPorts = "off"
  }}
})
local writable_authorized_keys = transport.inspect(uci, fs)
assert(writable_authorized_keys.ssh_authorized_keys.group_writable)
assert(writable_authorized_keys.ssh_authorized_keys.status == "review")
assert(writable_authorized_keys.ssh_status == "review")

-- Non-root-owned authorized-keys files are not accepted as hardened.
uci, fs = fixture("1", {
  stat_overrides = {
    ["/etc/dropbear/authorized_keys"] = { size = 128, uid = 1000, mode = 33152 }
  },
  dropbear_sections = {{
    [".name"] = "main",
    enable = "1",
    Interface = "lan",
    Port = "22",
    PasswordAuth = "off",
    RootPasswordAuth = "off",
    GatewayPorts = "off"
  }}
})
local unowned_authorized_keys = transport.inspect(uci, fs)
assert(not unowned_authorized_keys.ssh_authorized_keys.root_owned)
assert(unowned_authorized_keys.ssh_authorized_keys.status == "review")
assert(unowned_authorized_keys.ssh_status == "review")

-- Oversized authorized-keys files fail closed rather than reading unbounded data.
uci, fs = fixture("1", {
  stat_overrides = {
    ["/etc/dropbear/authorized_keys"] = { size = 65537, uid = 0, mode = 33152 }
  },
  dropbear_sections = {{
    [".name"] = "main",
    enable = "1",
    Interface = "lan",
    Port = "22",
    PasswordAuth = "off",
    RootPasswordAuth = "off",
    GatewayPorts = "off"
  }}
})
local oversized_authorized_keys = transport.inspect(uci, fs)
assert(oversized_authorized_keys.ssh_authorized_keys.status == "review")
assert(oversized_authorized_keys.ssh_status == "review")

-- The shipped AW1000 Dropbear defaults allow password and root-password login.
uci, fs = fixture("1", {
  dropbear_sections = {{
    [".name"] = "main",
    enable = "1",
    Interface = "lan",
    Port = "22",
    PasswordAuth = "on",
    RootPasswordAuth = "on",
    GatewayPorts = "off"
  }}
})
local password_ssh = transport.inspect(uci, fs)
assert(password_ssh.ssh_status == "review")
assert(password_ssh.status == "review", "password-enabled SSH must lower the management posture")
assert(password_ssh.ssh_instances[1].password_auth_enabled)
assert(password_ssh.ssh_instances[1].root_password_auth_enabled)

-- Key-only authentication is not sufficient when the daemon is unbound to an interface.
uci, fs = fixture("1", {
  dropbear_sections = {{
    [".name"] = "main",
    enable = "1",
    Port = "22",
    PasswordAuth = "off",
    RootPasswordAuth = "off",
    GatewayPorts = "off"
  }}
})
local unbound_ssh = transport.inspect(uci, fs)
assert(unbound_ssh.ssh_status == "review")
assert(not unbound_ssh.ssh_instances[1].interface_bound)
assert(unbound_ssh.status == "review")

-- Unknown authentication values fail closed instead of being treated as disabled.
uci, fs = fixture("1", {
  dropbear_sections = {{
    [".name"] = "main",
    enable = "1",
    Interface = "lan",
    Port = "22",
    PasswordAuth = "maybe",
    RootPasswordAuth = "off"
  }}
})
local unknown_auth = transport.inspect(uci, fs)
assert(unknown_auth.ssh_status == "review")
assert(unknown_auth.ssh_instances[1].password_auth_enabled == nil)

-- An invalid enable flag must not be mistaken for a disabled daemon.
uci, fs = fixture("1", {
  dropbear_sections = {{
    [".name"] = "main",
    enable = "maybe",
    Interface = "lan",
    Port = "22",
    PasswordAuth = "off",
    RootPasswordAuth = "off",
    GatewayPorts = "off"
  }}
})
local unknown_enable = transport.inspect(uci, fs)
assert(unknown_enable.ssh_enabled_instance_count == 0)
assert(unknown_enable.ssh_status == "review")
assert(unknown_enable.status == "review")

-- Gateway port forwarding is a review item even with key-only authentication.
uci, fs = fixture("1", {
  dropbear_sections = {{
    [".name"] = "main",
    enable = "1",
    Interface = "lan",
    Port = "22",
    PasswordAuth = "off",
    RootPasswordAuth = "off",
    GatewayPorts = "on"
  }}
})
local gateway_ports = transport.inspect(uci, fs)
assert(gateway_ports.ssh_status == "review")
assert(gateway_ports.ssh_instances[1].gateway_ports_enabled)

-- Invalid listener ports are never treated as a valid SSH endpoint.
uci, fs = fixture("1", {
  dropbear_sections = {{
    [".name"] = "main",
    enable = "1",
    Interface = "lan",
    Port = "70000",
    PasswordAuth = "off",
    RootPasswordAuth = "off",
    GatewayPorts = "off"
  }}
})
local invalid_port = transport.inspect(uci, fs)
assert(invalid_port.ssh_status == "review")
assert(not invalid_port.ssh_instances[1].port_valid)

-- Inventory truncation is visible and cannot be reported as ready.
local many_dropbear_instances = {}
for index = 1, 9 do
  many_dropbear_instances[index] = {
    [".name"] = "instance" .. tostring(index),
    enable = "1",
    Interface = "lan",
    Port = tostring(2200 + index),
    PasswordAuth = "off",
    RootPasswordAuth = "off",
    GatewayPorts = "off"
  }
end
uci, fs = fixture("1", { dropbear_sections = many_dropbear_instances })
local truncated_ssh = transport.inspect(uci, fs)
assert(truncated_ssh.ssh_instance_count == 9)
assert(#truncated_ssh.ssh_instances == 8 and truncated_ssh.ssh_truncated)
assert(truncated_ssh.ssh_status == "review")
assert(truncated_ssh.status == "review")

-- An intentionally disabled Dropbear service does not create a false warning.
uci, fs = fixture("1", {
  files = {
    ["/etc/init.d/uhttpd"] = true,
    ["/lib/libustream-ssl.so"] = true,
    ["/etc/uhttpd.crt"] = true,
    ["/etc/uhttpd.key"] = true,
    ["/usr/bin/openssl"] = true
  }
})
local ssh_not_installed = transport.inspect(uci, fs)
assert(not ssh_not_installed.ssh_service_installed)
assert(ssh_not_installed.ssh_status == "disabled")
assert(ssh_not_installed.status == "ready")

-- An installed daemon without a readable instance inventory is unknown.
uci, fs = fixture("1", { dropbear_sections = {} })
local missing_ssh_config = transport.inspect(uci, fs)
assert(missing_ssh_config.ssh_service_installed)
assert(not missing_ssh_config.ssh_config_available or missing_ssh_config.ssh_instance_count == 0)
assert(missing_ssh_config.ssh_status == "unavailable")
assert(missing_ssh_config.status == "review")

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

local https_http = {
  getenv = function(name) return name == "HTTPS" and "on" or nil end
}
assert(transport.require_https(https_http) == true, "HTTPS administrator requests must be accepted")

local response = { headers = {}, body = nil, status = nil, content_type = nil }
local plaintext_http = {
  getenv = function(name) return name == "HTTPS" and nil or nil end,
  status = function(code, reason) response.status = code; response.reason = reason end,
  header = function(name, value) response.headers[name] = value end,
  prepare_content = function(value) response.content_type = value end,
  write_json = function(value) response.body = value end
}
assert(transport.require_https(plaintext_http) == false, "plaintext HTTP administrator requests must be rejected")
assert(response.status == 403 and response.reason == "Forbidden")
assert(response.headers["Cache-Control"] == "no-store")
assert(response.content_type == "application/json; charset=UTF-8")
assert(response.body.ok == false and response.body.error:find("HTTPS", 1, true))

print("management-transport: HTTPS and SSH management-plane posture tests passed")
