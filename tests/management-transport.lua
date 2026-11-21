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
    ["/etc/dropbear"] = true,
    ["/root/.ssh"] = true,
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
  local firewall_zones = {
    { [".name"] = "lan", network = { "lan" } },
    { [".name"] = "wan", network = { "wan", "wan6" } }
  }
  local empty_files = {}
  for key, value in pairs(overrides or {}) do
    if key == "lists" then lists = value
    elseif key == "values" then values = value
    elseif key == "files" then files = value
    elseif key == "empty_files" then empty_files = value
    elseif key == "stat_overrides" then stat_overrides = value
    elseif key == "dropbear_sections" then dropbear_sections = value
    elseif key == "firewall_zones" then firewall_zones = value
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
    elseif package == "firewall" and section_type == "zone" then
      for _, section in ipairs(firewall_zones) do callback(section) end
    end
  end
  local function stat(path)
    if files[path] ~= true then return nil end
    local override = stat_overrides[path]
    if override then return override end
    if path == "/etc/dropbear" or path == "/root/.ssh" then
      return { size = 0, uid = 0, mode = 16832, type = "dir" }
    end
    return {
      size = empty_files[path] and 0 or 128,
      uid = 0,
      mode = 33152,
      type = "reg"
    }
  end
  local fs = {
    access = function(path) return files[path] == true end,
    stat = stat,
    lstat = stat
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
assert(https_only.ssh_instances[1].interface_zone_status == "internal")
assert(not https_only.ssh_instances[1].password_auth_enabled)
assert(not https_only.ssh_instances[1].root_password_auth_enabled)
assert(https_only.ssh_authorized_keys.available)
assert(https_only.ssh_authorized_keys.status == "present")
assert(https_only.ssh_authorized_keys.root_owned)
assert(https_only.ssh_authorized_keys.directory_root_owned)
assert(https_only.ssh_authorized_keys.directory_valid)
assert(not https_only.ssh_authorized_keys.directory_group_writable)
assert(not https_only.ssh_authorized_keys.directory_other_writable)
assert(https_only.ssh_authorized_keys.regular_file)
assert(https_only.ssh_authorized_keys.owner_readable)
assert(not https_only.ssh_authorized_keys.group_writable)
assert(not https_only.ssh_authorized_keys.other_writable)

-- HTTPS private keys must be root-owned, regular and inaccessible to group/other users.
local private_key = https_only.private_key
assert(private_key.available and private_key.status == "present")
assert(private_key.root_owned and private_key.regular_file and private_key.owner_readable)
assert(not private_key.group_access and not private_key.other_access)

-- OpenWrt nixio.fs metadata uses type and modedec; both are handled directly.
uci, fs = fixture("1", {
  stat_overrides = {
    ["/etc/uhttpd.key"] = { size = 512, uid = 0, modedec = 33152, type = "reg" }
  }
})
local nixio_metadata_key = transport.inspect(uci, fs)
assert(nixio_metadata_key.private_key.status == "present")

-- lstat must reject a symlink even when its target metadata appears private.
uci, fs = fixture("1", {
  stat_overrides = {
    ["/etc/uhttpd.key"] = { size = 512, uid = 0, mode = 33152, type = "lnk" }
  }
})
local symlink_key = transport.inspect(uci, fs)
assert(symlink_key.private_key.regular_file == false)
assert(symlink_key.private_key.status == "review")

uci, fs = fixture("1", {
  stat_overrides = {
    ["/etc/dropbear/authorized_keys"] = { size = 128, uid = 0, mode = 33152, type = "lnk" }
  }
})
local symlink_authorized_keys = transport.inspect(uci, fs)
assert(symlink_authorized_keys.ssh_authorized_keys.regular_file == false)
assert(symlink_authorized_keys.ssh_authorized_keys.status == "review")
assert(symlink_authorized_keys.ssh_status == "review")

uci, fs = fixture("1", {
  stat_overrides = {
    ["/etc/uhttpd.key"] = { size = 512, uid = 0, mode = 33188 }
  }
})
local exposed_key = transport.inspect(uci, fs)
assert(exposed_key.private_key.status == "review")
assert(exposed_key.private_key.group_access or exposed_key.private_key.other_access)
assert(exposed_key.status == "review")

uci, fs = fixture("1", {
  stat_overrides = {
    ["/etc/uhttpd.key"] = { size = 512, uid = 1000, mode = 33152 }
  }
})
local unowned_key = transport.inspect(uci, fs)
assert(unowned_key.private_key.status == "review")
assert(not unowned_key.private_key.root_owned)
assert(unowned_key.status == "review")

uci, fs = fixture("1", {
  stat_overrides = {
    ["/etc/uhttpd.key"] = { size = 70000, uid = 0, mode = 33152 }
  }
})
local oversized_key = transport.inspect(uci, fs)
assert(oversized_key.private_key.status == "review")

-- Fingerprints expose only a normalized SHA-256 digest, never certificate or key contents.
local expected_fingerprint = string.rep("AA:", 31) .. "AA"
local parsed_fingerprint = transport.parse_certificate_fingerprint(
  "sha256 Fingerprint=" .. expected_fingerprint .. "\n")
assert(parsed_fingerprint.available)
assert(parsed_fingerprint.algorithm == "SHA-256")
assert(parsed_fingerprint.value == expected_fingerprint)
local upper_prefix_fingerprint = transport.parse_certificate_fingerprint(
  "SHA256 Fingerprint=" .. expected_fingerprint)
assert(upper_prefix_fingerprint.available)
assert(upper_prefix_fingerprint.value == expected_fingerprint)
assert(not transport.parse_certificate_fingerprint("sha256 Fingerprint=AA:BB").available)
assert(not transport.parse_certificate_fingerprint("MD5 Fingerprint=" .. expected_fingerprint).available)
assert(not transport.parse_certificate_fingerprint(string.rep("A", 4097)).available)

uci, fs = fixture("1")
local with_fingerprint = transport.inspect(uci, fs, "sha256 Fingerprint=" .. expected_fingerprint)
assert(with_fingerprint.certificate_fingerprint.available)
assert(with_fingerprint.certificate_fingerprint.value == expected_fingerprint)

uci, fs = fixture("1", {
  files = {
    ["/etc/init.d/uhttpd"] = true,
    ["/etc/init.d/dropbear"] = true,
    ["/etc/dropbear"] = true,
    ["/root/.ssh"] = true,
    ["/etc/dropbear/authorized_keys"] = true,
    ["/lib/libustream-ssl.so"] = true,
    ["/etc/uhttpd.crt"] = true,
    ["/etc/uhttpd.key"] = false,
    ["/usr/bin/openssl"] = true
  }
})
local missing_key = transport.inspect(uci, fs)
assert(missing_key.private_key.status == "missing")
assert(missing_key.status == "unavailable")

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

-- The alternate root-owned Dropbear key location is recognised when the standard file is absent.
uci, fs = fixture("1", {
  files = {
    ["/etc/init.d/uhttpd"] = true,
    ["/etc/init.d/dropbear"] = true,
    ["/root/.ssh"] = true,
    ["/root/.ssh/authorized_keys"] = true,
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
local alternate_authorized_keys = transport.inspect(uci, fs)
assert(alternate_authorized_keys.ssh_authorized_keys.path == "/root/.ssh/authorized_keys")
assert(alternate_authorized_keys.ssh_authorized_keys.status == "present")
assert(alternate_authorized_keys.ssh_status == "ready")

-- Other-writable authorized-keys files are also rejected.
uci, fs = fixture("1", {
  stat_overrides = {
    ["/etc/dropbear/authorized_keys"] = { size = 128, uid = 0, mode = 33154 }
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
local other_writable_authorized_keys = transport.inspect(uci, fs)
assert(other_writable_authorized_keys.ssh_authorized_keys.other_writable)
assert(other_writable_authorized_keys.ssh_authorized_keys.status == "review")
assert(other_writable_authorized_keys.ssh_status == "review")

-- A group-writable parent directory can replace an otherwise secure key file.
uci, fs = fixture("1", {
  stat_overrides = {
    ["/etc/dropbear"] = { size = 0, uid = 0, mode = 16848 }
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
local writable_key_directory = transport.inspect(uci, fs)
assert(writable_key_directory.ssh_authorized_keys.directory_group_writable)
assert(writable_key_directory.ssh_authorized_keys.status == "review")
assert(writable_key_directory.ssh_status == "review")

-- A non-root-owned parent directory cannot protect root's SSH trust list.
uci, fs = fixture("1", {
  stat_overrides = {
    ["/etc/dropbear"] = { size = 0, uid = 1000, mode = 16832 }
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
local unowned_key_directory = transport.inspect(uci, fs)
assert(not unowned_key_directory.ssh_authorized_keys.directory_root_owned)
assert(unowned_key_directory.ssh_authorized_keys.status == "review")
assert(unowned_key_directory.ssh_status == "review")

-- A present file with incomplete metadata is unknown, not ready.
uci, fs = fixture("1", {
  stat_overrides = {
    ["/etc/dropbear/authorized_keys"] = { size = 128, uid = 0 }
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
local unknown_key_permissions = transport.inspect(uci, fs)
assert(unknown_key_permissions.ssh_authorized_keys.status == "unknown")
assert(unknown_key_permissions.ssh_status == "review")

-- Directories must not be accepted as authorized-keys files.
uci, fs = fixture("1", {
  stat_overrides = {
    ["/etc/dropbear/authorized_keys"] = { size = 128, uid = 0, mode = 16832 }
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
local directory_authorized_keys = transport.inspect(uci, fs)
assert(not directory_authorized_keys.ssh_authorized_keys.regular_file)
assert(directory_authorized_keys.ssh_authorized_keys.status == "review")
assert(directory_authorized_keys.ssh_status == "review")

-- A key file that the Dropbear process cannot read is not a ready posture.
uci, fs = fixture("1", {
  stat_overrides = {
    ["/etc/dropbear/authorized_keys"] = { size = 128, uid = 0, mode = 32896 }
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
local unreadable_authorized_keys = transport.inspect(uci, fs)
assert(not unreadable_authorized_keys.ssh_authorized_keys.owner_readable)
assert(unreadable_authorized_keys.ssh_authorized_keys.status == "review")
assert(unreadable_authorized_keys.ssh_status == "review")

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

-- SSH must not be considered hardened when bound to an external firewall zone.
uci, fs = fixture("1", {
  dropbear_sections = {{
    [".name"] = "wan-ssh",
    enable = "1",
    Interface = "wan",
    Port = "22",
    PasswordAuth = "off",
    RootPasswordAuth = "off",
    GatewayPorts = "off"
  }}
})
local external_ssh = transport.inspect(uci, fs)
assert(external_ssh.ssh_instances[1].interface_zone_status == "external")
assert(external_ssh.ssh_status == "review", "SSH bound to the WAN zone must require review")
assert(external_ssh.status == "review")

-- Custom zone names are not assumed to be trusted merely because they are not named WAN.
uci, fs = fixture("1", {
  dropbear_sections = {{
    [".name"] = "uplink-ssh",
    enable = "1",
    Interface = "uplink",
    Port = "2222",
    PasswordAuth = "off",
    RootPasswordAuth = "off",
    GatewayPorts = "off"
  }},
  firewall_zones = {{ [".name"] = "internet-edge", network = { "uplink" } }}
})
local custom_zone_ssh = transport.inspect(uci, fs)
assert(custom_zone_ssh.ssh_instances[1].interface_zone_status == "unknown")
assert(custom_zone_ssh.ssh_status == "review", "unrecognised SSH firewall zones must fail closed")

-- An interface assigned to multiple firewall zones is ambiguous even if one is named LAN.
uci, fs = fixture("1", {
  dropbear_sections = {{
    [".name"] = "ambiguous-ssh",
    enable = "1",
    Interface = "lan",
    Port = "22",
    PasswordAuth = "off",
    RootPasswordAuth = "off",
    GatewayPorts = "off"
  }},
  firewall_zones = {
    { [".name"] = "lan", network = { "lan" } },
    { [".name"] = "wan", network = { "lan" } }
  }
})
local ambiguous_zone_ssh = transport.inspect(uci, fs)
assert(ambiguous_zone_ssh.ssh_instances[1].interface_zone_status == "unknown")
assert(ambiguous_zone_ssh.ssh_status == "review", "ambiguous zone membership must not pass the SSH posture check")

-- Missing or ambiguous firewall bindings cannot be interpreted as a trusted management network.
uci, fs = fixture("1", {
  dropbear_sections = {{
    [".name"] = "unmapped-ssh",
    enable = "1",
    Interface = "lan",
    Port = "22",
    PasswordAuth = "off",
    RootPasswordAuth = "off",
    GatewayPorts = "off"
  }},
  firewall_zones = {}
})
local unmapped_zone_ssh = transport.inspect(uci, fs)
assert(unmapped_zone_ssh.ssh_instances[1].interface_zone_status == "unknown")
assert(unmapped_zone_ssh.ssh_status == "review")

print("management-transport: HTTPS and SSH management-plane posture tests passed")
