package.path = "files/usr/lib/lua/?.lua;" .. package.path
local remote = require "luci.quantumgrid.remote_syslog"

assert(remote.has_non_root_privilege_drop({
  [".type"] = "globals", setuid = "nobody", setgid = "nogroup"
}), "the package's non-root stunnel identities must be accepted")
assert(remote.has_non_root_privilege_drop({
  [".type"] = "globals", setuid = "65534", setgid = "65534"
}), "explicit non-zero numeric user and group IDs may be used")
for _, globals in ipairs({
  {},
  { [".type"] = "globals", setuid = "root", setgid = "nogroup" },
  { [".type"] = "globals", setuid = "nobody", setgid = "root" },
  { [".type"] = "globals", setuid = "0", setgid = "nogroup" },
  { [".type"] = "globals", setuid = "nobody" },
  { [".type"] = "globals", setuid = "   ", setgid = "nogroup" },
  { [".type"] = "globals", setuid = "nobody", setgid = "bad group" },
  { [".type"] = "globals", setuid = "nobody", setgid = "name;id" },
  { [".type"] = "service", setuid = "nobody", setgid = "nogroup" },
}) do
  assert(not remote.has_non_root_privilege_drop(globals),
    "missing, root or malformed stunnel privilege settings must be rejected")
end

local valid = remote.validate({
  confirmed = "1",
  enabled = "1",
  host = "192.0.2.15",
  port = "514",
  protocol = "udp",
  hostname = "qg-office-router",
  prefix = "office-site1"
})
assert(valid and valid.enabled and valid.host == "192.0.2.15" and valid.port == "514")
assert(valid.protocol == "udp" and valid.hostname == "qg-office-router" and valid.prefix == "office-site1")

local tcp = remote.validate({
  confirmed = "1",
  enabled = "1", host = "syslog.office.example", port = "6514",
  protocol = "tcp", hostname = "", prefix = ""
})
assert(tcp and tcp.protocol == "tcp" and tcp.port == "6514")

local tls_hostname = remote.validate({
  confirmed = "1",
  enabled = "1",
  host = "logs.corp.example",
  port = "6514",
  protocol = "tls",
  hostname = "qg-office-router",
  prefix = "office-site1"
})
assert(tls_hostname and tls_hostname.protocol == "tls" and tls_hostname.port == "6514")
assert(tls_hostname.tls.verify_chain == true)
assert(tls_hostname.tls.local_host == "127.0.0.1" and tls_hostname.tls.local_port == "5514")
assert(tls_hostname.tls.connect == "logs.corp.example:6514")
assert(tls_hostname.tls.ca_file == "/etc/ssl/certs/ca-certificates.crt")
assert(tls_hostname.tls.check_host == "logs.corp.example" and tls_hostname.tls.sni == "logs.corp.example")
assert(tls_hostname.tls.check_ip == nil)
local tunnel_options = remote.stunnel_options(tls_hostname)
assert(tunnel_options.section == "quantumgrid_syslog")
assert(tunnel_options.scalars.enabled == "1" and tunnel_options.scalars.client == "1")
assert(tunnel_options.scalars.verifyChain == "1")
assert(tunnel_options.scalars.sslVersion == "TLSv1.2")
assert(tunnel_options.scalars.CAfile == "/etc/ssl/certs/ca-certificates.crt")
assert(tunnel_options.scalars.accept_host == "127.0.0.1")
assert(tunnel_options.scalars.accept_port == "5514")
assert(tunnel_options.scalars.retry == "1")
assert(#tunnel_options.lists.connect == 1 and tunnel_options.lists.connect[1] == "logs.corp.example:6514")
assert(tunnel_options.lists.checkHost[1] == "logs.corp.example")
assert(tunnel_options.lists.sni[1] == "logs.corp.example")
assert(#tunnel_options.lists.checkIP == 0)
assert(remote.stunnel_options({ enabled = false, protocol = "tls" }) == nil)

local tls_ip = remote.validate({
  confirmed = "1",
  enabled = "1",
  host = "192.0.2.15",
  port = "6514",
  protocol = "tls"
})
assert(tls_ip and tls_ip.tls.check_ip == "192.0.2.15")
assert(tls_ip.tls.check_host == nil and tls_ip.tls.sni == nil,
  "IPv4 destinations must use IP SAN validation rather than hostname/SNI validation")
local ip_tunnel_options = remote.stunnel_options(tls_ip)
assert(ip_tunnel_options.lists.checkIP[1] == "192.0.2.15")
assert(#ip_tunnel_options.lists.checkHost == 0 and #ip_tunnel_options.lists.sni == 0)

local disabled = remote.validate({ confirmed = "1", enabled = "0" })
assert(remote.validate({ enabled = "0" }) == nil, "missing explicit confirmation must be rejected")
assert(disabled and disabled.enabled == false, "remote logging may be disabled without a destination")

local invalid = {
  { confirmed = "1", enabled = "2", host = "192.0.2.15", port = "514", protocol = "udp" },
  { confirmed = "1", enabled = "1", host = "192.0.2.999", port = "514", protocol = "udp" },
  { confirmed = "1", enabled = "1", host = "bad host", port = "514", protocol = "udp" },
  { confirmed = "1", enabled = "1", host = "../syslog", port = "514", protocol = "udp" },
  { confirmed = "1", enabled = "1", host = "syslog..office", port = "514", protocol = "udp" },
  { confirmed = "1", enabled = "1", host = "syslog.office", port = "0", protocol = "udp" },
  { confirmed = "1", enabled = "1", host = "syslog.office", port = "65536", protocol = "udp" },
  { confirmed = "1", enabled = "1", host = "syslog.office", port = "514", protocol = "sctp" },
  { confirmed = "1", enabled = "1", host = "syslog.office", port = "514", protocol = "udp", hostname = "invalid host" },
  { confirmed = "1", enabled = "1", host = "syslog.office", port = "514", protocol = "udp", prefix = "bad prefix" },
  { confirmed = "1", enabled = "1", host = "syslog.office", port = "514", protocol = "udp", prefix = string.rep("x", 33) },
}
for _, input in ipairs(invalid) do
  local result = remote.validate(input)
  assert(result == nil, "invalid remote syslog configuration must be rejected")
end

local function status_fixture(options)
  options = options or {}
  local files = {
    ["/etc/init.d/log"] = true,
    ["/etc/config/system"] = true,
    ["/etc/init.d/stunnel"] = true,
    ["/etc/config/stunnel"] = true,
    ["/etc/ssl/certs/ca-certificates.crt"] = true,
  }
  for path, value in pairs(options.files or {}) do files[path] = value end
  local system_sections = options.system_sections or {{
    [".name"] = "system",
    [".type"] = "system",
    log_ip = "127.0.0.1",
    log_port = "5514",
    log_proto = "tcp",
    log_remote = "1",
    log_hostname = "qg-office-router",
    log_prefix = "office-site1",
  }}
  local globals = {
    [".name"] = "globals",
    [".type"] = "globals",
    setuid = "nobody",
    setgid = "nogroup",
  }
  if options.globals == false then globals = nil
  elseif type(options.globals) == "table" then globals = options.globals end
  local sections = {
    globals = globals,
    quantumgrid_syslog = options.tunnel or {
      [".name"] = "quantumgrid_syslog",
      [".type"] = "service",
      enabled = "1",
      client = "1",
      accept_host = "127.0.0.1",
      accept_port = "5514",
      CAfile = "/etc/ssl/certs/ca-certificates.crt",
      verifyChain = "1",
      sslVersion = "TLSv1.2",
      connect = { "logs.corp.example:6514" },
      checkHost = { "logs.corp.example" },
      sni = { "logs.corp.example" },
    },
  }
  local uci = {}
  function uci:foreach(package, section_type, callback)
    if package == "system" and section_type == "system" then
      for _, section in ipairs(system_sections) do callback(section) end
    end
  end
  function uci.get_all(_, package, section)
    if package == "stunnel" then return sections[section] end
    return nil
  end
  local fs = { access = function(path) return files[path] == true end }
  return uci, fs
end

local status_uci, status_fs = status_fixture()
local tls_status = remote.inspect_status(status_uci, status_fs, 123)
assert(tls_status.available and tls_status.service_installed and tls_status.config_available)
assert(tls_status.protocol == "tls" and tls_status.host == "logs.corp.example" and tls_status.port == 6514)
assert(tls_status.tls_available and tls_status.tls_privilege_drop_configured)
assert(tls_status.tls_configured and tls_status.tls_identity_verified and tls_status.tls_enabled)
assert(tls_status.tls_status == "ready" and tls_status.enabled)
assert(tls_status.sampled_at == 123)

local unencrypted_uci, unencrypted_fs = status_fixture({
  system_sections = {{
    [".name"] = "system", [".type"] = "system",
    log_ip = "192.0.2.20", log_port = "514", log_proto = "udp", log_remote = "1",
  }},
})
local unencrypted_status = remote.inspect_status(unencrypted_uci, unencrypted_fs, 456)
assert(unencrypted_status.available and unencrypted_status.enabled)
assert(unencrypted_status.protocol == "udp" and unencrypted_status.host == "192.0.2.20")
assert(unencrypted_status.tls_privilege_drop_configured,
  "TLS service prerequisites must be detected even before the administrator enables TLS")
assert(unencrypted_status.tls_status == "unavailable", "plain UDP must not be reported as TLS")

local missing_stunnel_globals_uci, missing_stunnel_globals_fs = status_fixture({ globals = false })
local missing_stunnel_globals = remote.inspect_status(missing_stunnel_globals_uci, missing_stunnel_globals_fs, 457)
assert(not missing_stunnel_globals.tls_privilege_drop_configured,
  "a missing stunnel globals section must not be presented as TLS-ready")

local unsafe_globals_uci, unsafe_globals_fs = status_fixture({
  globals = { [".name"] = "globals", [".type"] = "globals", setuid = "root", setgid = "nogroup" },
})
local unsafe_globals = remote.inspect_status(unsafe_globals_uci, unsafe_globals_fs, 1)
assert(unsafe_globals.tls_status == "review" and not unsafe_globals.tls_privilege_drop_configured)
assert(not unsafe_globals.enabled)

local weak_tls_uci, weak_tls_fs = status_fixture({
  tunnel = {
    [".name"] = "quantumgrid_syslog", [".type"] = "service",
    enabled = "1", client = "1", accept_host = "127.0.0.1", accept_port = "5514",
    CAfile = "/etc/ssl/certs/ca-certificates.crt", verifyChain = "1",
    sslVersion = "TLSv1.1", connect = { "logs.corp.example:6514" },
    checkHost = { "logs.corp.example" }, sni = { "logs.corp.example" },
  },
})
local weak_tls_status = remote.inspect_status(weak_tls_uci, weak_tls_fs, 2)
assert(weak_tls_status.tls_status == "review" and not weak_tls_status.enabled)

local unverified_identity_uci, unverified_identity_fs = status_fixture({
  tunnel = {
    [".name"] = "quantumgrid_syslog", [".type"] = "service",
    enabled = "1", client = "1", accept_host = "127.0.0.1", accept_port = "5514",
    CAfile = "/etc/ssl/certs/ca-certificates.crt", verifyChain = "1",
    sslVersion = "TLSv1.2", connect = { "logs.corp.example:6514", "backup.corp.example:6514" },
    checkHost = { "logs.corp.example" }, sni = { "logs.corp.example" },
  },
})
local extra_destination = remote.inspect_status(unverified_identity_uci, unverified_identity_fs, 3)
assert(extra_destination.tls_status == "review" and not extra_destination.tls_identity_verified)

local ip_tls_uci, ip_tls_fs = status_fixture({
  tunnel = {
    [".name"] = "quantumgrid_syslog", [".type"] = "service",
    enabled = "1", client = "1", accept_host = "127.0.0.1", accept_port = "5514",
    CAfile = "/etc/ssl/certs/ca-certificates.crt", verifyChain = "1",
    sslVersion = "TLSv1.2", connect = { "192.0.2.15:6514" },
    checkIP = { "192.0.2.15" },
  },
})
local ip_tls_status = remote.inspect_status(ip_tls_uci, ip_tls_fs, 4)
assert(ip_tls_status.tls_status == "ready" and ip_tls_status.tls_identity_verified)
assert(ip_tls_status.host == "192.0.2.15" and ip_tls_status.port == 6514)

local missing_ca_uci, missing_ca_fs = status_fixture({
  files = { ["/etc/ssl/certs/ca-certificates.crt"] = false },
})
local missing_ca = remote.inspect_status(missing_ca_uci, missing_ca_fs, 5)
assert(missing_ca.tls_status == "unavailable" and not missing_ca.enabled)

local ambiguous_uci, ambiguous_fs = status_fixture({
  system_sections = {
    { [".name"] = "system", [".type"] = "system", log_ip = "127.0.0.1", log_port = "5514", log_proto = "tcp", log_remote = "1" },
    { [".name"] = "system2", [".type"] = "system", log_ip = "192.0.2.10", log_port = "514", log_proto = "udp", log_remote = "1" },
  },
})
local ambiguous_status = remote.inspect_status(ambiguous_uci, ambiguous_fs, 6)
assert(not ambiguous_status.available, "ambiguous system UCI sections must not be reported as a verified destination")

print("remote-syslog: destination, transport, sender name, prefix and disabled state validation passed")
