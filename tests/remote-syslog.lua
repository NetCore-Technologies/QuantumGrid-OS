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

local managed_stunnel_section = {
  [".name"] = "quantumgrid_syslog",
  [".type"] = "service",
  enabled = "1",
  client = "1",
  accept_host = "127.0.0.1",
  accept_port = "5514",
  CAfile = "/etc/ssl/certs/ca-certificates.crt",
  verifyChain = "1",
  sslVersion = "TLSv1.2",
  TIMEOUTconnect = "10",
  retry = "1",
  connect = { "logs.corp.example:6514" },
  checkHost = { "logs.corp.example" },
  sni = { "logs.corp.example" },
}
assert(remote.has_only_managed_service_options(managed_stunnel_section))
assert(not remote.has_only_managed_service_options({ [".type"] = "globals" }))
assert(not remote.has_only_managed_service_options({
  [".type"] = "service", enabled = "1", exec = "/bin/sh"
}), "unexpected executable stunnel directives must be rejected")
assert(not remote.has_only_managed_service_options({
  [".type"] = "service", enabled = "1", protocol = "smtp"
}), "unmanaged protocol directives must be rejected")

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
  local process = options.process or {
    pid = "1234",
    comm = "stunnel\\n",
    cmdline = "/usr/bin/stunnel\\0/var/etc/stunnel.conf\\0",
  }
  return uci, fs, process
end

local status_uci, status_fs, status_process = status_fixture()
local tls_status = remote.inspect_status(status_uci, status_fs, 123, status_process)
assert(tls_status.available and tls_status.service_installed and tls_status.config_available)
assert(tls_status.protocol == "tls" and tls_status.host == "logs.corp.example" and tls_status.port == 6514)
assert(tls_status.tls_available and tls_status.tls_privilege_drop_configured)
assert(tls_status.tls_configured and tls_status.tls_identity_verified and tls_status.tls_enabled)
assert(tls_status.tls_status == "ready" and tls_status.enabled)
assert(tls_status.sampled_at == 123)

assert(remote.stunnel_process_running("1234\\n", "stunnel\\n", "/usr/bin/stunnel\\0/var/etc/stunnel.conf\\0"))
for _, process in ipairs({
  { pid = nil, comm = "stunnel", cmdline = "/usr/bin/stunnel /var/etc/stunnel.conf" },
  { pid = "0", comm = "stunnel", cmdline = "/usr/bin/stunnel /var/etc/stunnel.conf" },
  { pid = "1", comm = "stunnel", cmdline = "/usr/bin/stunnel /var/etc/stunnel.conf" },
  { pid = "1.2", comm = "stunnel", cmdline = "/usr/bin/stunnel /var/etc/stunnel.conf" },
  { pid = "1234", comm = "dropbear", cmdline = "/usr/bin/stunnel /var/etc/stunnel.conf" },
  { pid = "1234", comm = "stunnel", cmdline = "/usr/bin/stunnel\\0/etc/stunnel/other.conf\\0" },
  { pid = "1234", comm = "stunnel", cmdline = "wrapper\\0/usr/bin/stunnel\\0/var/etc/stunnel.conf\\0" },
  { pid = "1234", comm = "stunnel", cmdline = "/usr/bin/stunnel\\0/var/etc/stunnel.conf\\0--unsafe-option\\0" },
  { pid = "1234", comm = "stunnel", cmdline = nil },
}) do
  assert(not remote.stunnel_process_running(process.pid, process.comm, process.cmdline),
    "missing or mismatched process identity must not be reported as a running managed tunnel")
end

local unencrypted_uci, unencrypted_fs, unencrypted_process = status_fixture({
  system_sections = {{
    [".name"] = "system", [".type"] = "system",
    log_ip = "192.0.2.20", log_port = "514", log_proto = "udp", log_remote = "1",
  }},
})
local unencrypted_status = remote.inspect_status(unencrypted_uci, unencrypted_fs, 456, unencrypted_process)
assert(unencrypted_status.available and unencrypted_status.enabled)
assert(unencrypted_status.protocol == "udp" and unencrypted_status.host == "192.0.2.20")
assert(unencrypted_status.tls_privilege_drop_configured,
  "TLS service prerequisites must be detected even before the administrator enables TLS")
assert(unencrypted_status.tls_status == "unavailable", "plain UDP must not be reported as TLS")

local missing_stunnel_globals_uci, missing_stunnel_globals_fs, missing_stunnel_globals_process = status_fixture({ globals = false })
local missing_stunnel_globals = remote.inspect_status(missing_stunnel_globals_uci, missing_stunnel_globals_fs, 457, missing_stunnel_globals_process)
assert(not missing_stunnel_globals.tls_privilege_drop_configured,
  "a missing stunnel globals section must not be presented as TLS-ready")

local unsafe_globals_uci, unsafe_globals_fs, unsafe_globals_process = status_fixture({
  globals = { [".name"] = "globals", [".type"] = "globals", setuid = "root", setgid = "nogroup" },
})
local unsafe_globals = remote.inspect_status(unsafe_globals_uci, unsafe_globals_fs, 1, unsafe_globals_process)
assert(unsafe_globals.tls_status == "review" and not unsafe_globals.tls_privilege_drop_configured)
assert(not unsafe_globals.enabled)

local alternate_config_uci, alternate_config_fs, alternate_config_process = status_fixture({
  globals = {
    [".name"] = "globals", [".type"] = "globals",
    setuid = "nobody", setgid = "nogroup",
    alt_config_file = "/etc/stunnel/custom.conf",
  },
})
local alternate_config = remote.inspect_status(alternate_config_uci, alternate_config_fs, 2, alternate_config_process)
assert(alternate_config.tls_status == "review" and not alternate_config.enabled,
  "alternate stunnel config must not bypass managed TLS policy")

local unmanaged_service_uci, unmanaged_service_fs, unmanaged_service_process = status_fixture({
  tunnel = {
    [".name"] = "quantumgrid_syslog", [".type"] = "service",
    enabled = "1", client = "1", accept_host = "127.0.0.1", accept_port = "5514",
    CAfile = "/etc/ssl/certs/ca-certificates.crt", verifyChain = "1", sslVersion = "TLSv1.2",
    connect = { "logs.corp.example:6514" }, checkHost = { "logs.corp.example" },
    sni = { "logs.corp.example" }, exec = "/bin/sh",
  },
})
local unmanaged_service = remote.inspect_status(unmanaged_service_uci, unmanaged_service_fs, 3, unmanaged_service_process)
assert(unmanaged_service.tls_status == "review" and not unmanaged_service.enabled,
  "an unmanaged stunnel service directive must invalidate managed TLS posture")

local weak_tls_uci, weak_tls_fs, weak_tls_process = status_fixture({
  tunnel = {
    [".name"] = "quantumgrid_syslog", [".type"] = "service",
    enabled = "1", client = "1", accept_host = "127.0.0.1", accept_port = "5514",
    CAfile = "/etc/ssl/certs/ca-certificates.crt", verifyChain = "1",
    sslVersion = "TLSv1.1", connect = { "logs.corp.example:6514" },
    checkHost = { "logs.corp.example" }, sni = { "logs.corp.example" },
  },
})
local weak_tls_status = remote.inspect_status(weak_tls_uci, weak_tls_fs, 2, weak_tls_process)
assert(weak_tls_status.tls_status == "review" and not weak_tls_status.enabled)

local unverified_identity_uci, unverified_identity_fs, unverified_identity_process = status_fixture({
  tunnel = {
    [".name"] = "quantumgrid_syslog", [".type"] = "service",
    enabled = "1", client = "1", accept_host = "127.0.0.1", accept_port = "5514",
    CAfile = "/etc/ssl/certs/ca-certificates.crt", verifyChain = "1",
    sslVersion = "TLSv1.2", connect = { "logs.corp.example:6514", "backup.corp.example:6514" },
    checkHost = { "logs.corp.example" }, sni = { "logs.corp.example" },
  },
})
local extra_destination = remote.inspect_status(unverified_identity_uci, unverified_identity_fs, 3, unverified_identity_process)
assert(extra_destination.tls_status == "review" and not extra_destination.tls_identity_verified)

local ip_tls_uci, ip_tls_fs, ip_tls_process = status_fixture({
  tunnel = {
    [".name"] = "quantumgrid_syslog", [".type"] = "service",
    enabled = "1", client = "1", accept_host = "127.0.0.1", accept_port = "5514",
    CAfile = "/etc/ssl/certs/ca-certificates.crt", verifyChain = "1",
    sslVersion = "TLSv1.2", connect = { "192.0.2.15:6514" },
    checkIP = { "192.0.2.15" },
  },
})
local ip_tls_status = remote.inspect_status(ip_tls_uci, ip_tls_fs, 4, ip_tls_process)
assert(ip_tls_status.tls_status == "ready" and ip_tls_status.tls_identity_verified)
assert(ip_tls_status.host == "192.0.2.15" and ip_tls_status.port == 6514)

local stopped_tunnel_uci, stopped_tunnel_fs = status_fixture({ process = {
  pid = "1234", comm = "dropbear\\n", cmdline = "/usr/bin/dropbear\\0",
} })
local stopped_tunnel_process = remote.inspect_status(stopped_tunnel_uci, stopped_tunnel_fs, 7, {
  pid = "1234", comm = "dropbear\\n", cmdline = "/usr/bin/dropbear\\0",
})
assert(stopped_tunnel_process.tls_status == "review" and not stopped_tunnel_process.enabled)
assert(stopped_tunnel_process.tls_error ~= nil)

local stale_disabled_uci, stale_disabled_fs, stale_disabled_process = status_fixture({
  system_sections = {{ [".name"] = "system", [".type"] = "system", log_ip = "127.0.0.1", log_port = "5514", log_proto = "tcp", log_remote = "0" }},
})
local stale_disabled = remote.inspect_status(stale_disabled_uci, stale_disabled_fs, 8, stale_disabled_process)
assert(stale_disabled.tls_status == "review" and not stale_disabled.enabled,
  "a running tunnel left behind while disabled must be surfaced for review")

local missing_ca_uci, missing_ca_fs, missing_ca_process = status_fixture({
  files = { ["/etc/ssl/certs/ca-certificates.crt"] = false },
})
local missing_ca = remote.inspect_status(missing_ca_uci, missing_ca_fs, 5, missing_ca_process)
assert(missing_ca.tls_status == "unavailable" and not missing_ca.enabled)

local ambiguous_uci, ambiguous_fs, ambiguous_process = status_fixture({
  system_sections = {
    { [".name"] = "system", [".type"] = "system", log_ip = "127.0.0.1", log_port = "5514", log_proto = "tcp", log_remote = "1" },
    { [".name"] = "system2", [".type"] = "system", log_ip = "192.0.2.10", log_port = "514", log_proto = "udp", log_remote = "1" },
  },
})
local ambiguous_status = remote.inspect_status(ambiguous_uci, ambiguous_fs, 6, ambiguous_process)
assert(not ambiguous_status.available, "ambiguous system UCI sections must not be reported as a verified destination")

print("remote-syslog: destination, transport, sender name, prefix and disabled state validation passed")
