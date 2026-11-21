# Office network provisioning

QuantumGrid Office Networks provisions a routed L3 interface on an **existing VLAN-filtered bridge VLAN**. It does not silently change switch membership, create an SSID, or add inter-zone forwarding.

## Prerequisites

- An existing bridge with VLAN filtering enabled.
- An existing VLAN on that bridge with explicit, validated switch-port membership.
- An internal firewall zone whose router **INPUT** and inter-zone **FORWARD** policies are **REJECT** or **DROP**.
- A working network, firewall and DHCP configuration.
- An out-of-band management path before applying changes that may interrupt the current session.

The selected firewall zone and VLAN are re-read from router inventory during the administrator POST. Provisioning refuses a truncated or unavailable inventory, missing VLAN, invalid DHCP range, overlapping static IPv4 subnet, duplicate interface/device, external firewall zone, or unsafe policy.

## IPv4-only segment (default)

The control centre creates:

- A static network interface on the selected bridge.vlan device with the chosen RFC1918 gateway and subnet mask.
- A DHCPv4 scope whose calculated pool stays inside the subnet and does not contain the gateway or overlap another enabled pool.
- An attachment to the selected internal firewall zone.
- Three firewall input rules for DHCPv4 and DNS (UDP/TCP). DNS is restricted to the new IPv4 subnet and gateway.

DHCPv6, Router Advertisements and NDP are explicitly disabled for this default mode. The selected zone's INPUT, OUTPUT and FORWARD policy values are not rewritten by the provisioner.

## Optional dual-stack IPv6

Enable **Enable IPv6 on this VLAN** only when the upstream WAN is configured to obtain and delegate IPv6 prefixes.

The provisioner requests a separate /64 from OpenWrt prefix delegation by setting ip6assign=64 on the VLAN interface and enabling prefix delegation on that interface. It configures the DHCP scope with:

- DHCPv6 server mode, with managed-address and other-configuration flags advertised in Router Advertisements.
- SLAAC prefix advertisements enabled for clients such as Android that do not use DHCPv6 for address assignment.
- Router Advertisement DNS announcements enabled, with a medium default router preference and 2700-second lifetime.
- DHCPv6 IA_NA host address assignment enabled.
- DHCPv6 prefix delegation to downstream clients and automatic assign-all disabled; clients receive addresses, not additional routed prefixes.
- NDP proxy disabled.

It also creates four additional IPv6-scoped firewall input rules: DHCPv6 client-to-server traffic (UDP 546 to 547), DNS over UDP/TCP 53, and the ICMPv6 router-solicitation/neighbour-solicitation/neighbour-advertisement messages required for local IPv6 control-plane operation. No IPv6 WAN forwarding, permissive INPUT policy, or inter-zone forwarding is added.

Dual-stack provisioning requires the selected zone's OUTPUT policy to be ACCEPT, because the router must emit Router Advertisements into that VLAN. The provisioner will not change this policy to make IPv6 work. It also requires the odhcpd service; network, firewall, dnsmasq and odhcpd are checked after configuration and restarted as part of the transaction.

**A /64 request is not proof that a prefix has been delegated.** The upstream ISP/mobile network must actually supply IPv6-PD. Without an upstream delegated prefix, the interface may not receive a usable global IPv6 prefix and clients will not have working routed IPv6 internet access. QuantumGrid does not invent a global prefix or present a requested prefix as live telemetry.

Useful checks on the router after provisioning:

```sh
ifstatus wan6
ip -6 addr show
ip -6 route show
logread -e odhcpd
```

Use the actual upstream IPv6 interface name if it is not wan6. Confirm that a delegated prefix appears in the upstream interface status, that the new VLAN interface receives its own /64, that Router Advertisements reach a client, and that the client's IPv6 route and DNS work before enabling production workloads.

## Transaction and recovery

Provisioning uses an authenticated, same-origin HTTPS POST and requires explicit confirmation. QuantumGrid snapshots the selected zone's existing network list, stages network/DHCP/firewall UCI changes, commits all three configuration packages and reloads the affected services. If staging, commit or a required reload fails, it removes the partial segment, restores the previous zone attachment and attempts to commit and reload the previous state. The API reports whether rollback was confirmed; a failed rollback must be investigated locally.

The IPv4-only transaction installs three firewall rules. Dual-stack installs seven. The control centre verifies the server response against the requested IPv6 mode, prefix length, rule count and service-reload results rather than displaying an unverified success.

## Deployment validation

CI covers Lua validation, API request/response contracts, the control-centre TypeScript build and firmware smoke checks. CI does not replace physical validation. Before selling or deploying an AW1000 image, test the exact firmware on the target hardware with the intended switch/AP VLAN path, IPv4 and IPv6 clients, ISP prefix delegation, firewall packet paths, reconnect/recovery behaviour and a separate management path. Do not claim IPv6 service is operational solely because the configuration transaction succeeded.
