package.path = "files/usr/lib/lua/?.lua;" .. package.path
local remote = require "luci.quantumgrid.remote_syslog"

local valid = remote.validate({
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
  enabled = "1", host = "syslog.office.example", port = "6514",
  protocol = "tcp", hostname = "", prefix = ""
})
assert(tcp and tcp.protocol == "tcp" and tcp.port == "6514")

local disabled = remote.validate({ enabled = "0" })
assert(disabled and disabled.enabled == false, "remote logging may be disabled without a destination")

local invalid = {
  { enabled = "2", host = "192.0.2.15", port = "514", protocol = "udp" },
  { enabled = "1", host = "192.0.2.999", port = "514", protocol = "udp" },
  { enabled = "1", host = "bad host", port = "514", protocol = "udp" },
  { enabled = "1", host = "../syslog", port = "514", protocol = "udp" },
  { enabled = "1", host = "syslog..office", port = "514", protocol = "udp" },
  { enabled = "1", host = "syslog.office", port = "0", protocol = "udp" },
  { enabled = "1", host = "syslog.office", port = "65536", protocol = "udp" },
  { enabled = "1", host = "syslog.office", port = "514", protocol = "tls" },
  { enabled = "1", host = "syslog.office", port = "514", protocol = "udp", hostname = "invalid host" },
  { enabled = "1", host = "syslog.office", port = "514", protocol = "udp", prefix = "bad prefix" },
  { enabled = "1", host = "syslog.office", port = "514", protocol = "udp", prefix = string.rep("x", 33) },
}
for _, input in ipairs(invalid) do
  local result = remote.validate(input)
  assert(result == nil, "invalid remote syslog configuration must be rejected")
end

print("remote-syslog: destination, transport, sender name, prefix and disabled state validation passed")
