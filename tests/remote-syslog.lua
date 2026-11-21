package.path = "files/usr/lib/lua/?.lua;" .. package.path
local remote = require "luci.quantumgrid.remote_syslog"

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

print("remote-syslog: destination, transport, sender name, prefix and disabled state validation passed")
