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

## Static IPv4 and IPv6 routes

The Network control centre also manages persistent unicast routes on existing logical interfaces. It supports explicit destination CIDRs for IPv4 and IPv6, an optional next-hop gateway, metric and numeric routing-table ID. The main table is used when no custom table is supplied. Default routes are deliberately excluded; WAN defaults, policy-routing rules and Multi-WAN policy have separate controls.

The firmware validates canonical network prefixes (host bits must be zero), unicast gateways, address family, interface existence, metric bounds and routing-table IDs. It rejects duplicate destinations in the same family/table and does not silently create policy rules, firewall forwarding, DNS settings or source-based routing. IPv6 link-local gateways are permitted for next-hop use; IPv6 link-local destination prefixes and multicast/unspecified destinations are rejected.

Before writing or removing a route, QuantumGrid checks the current browser administrator's client address against the destination prefix. It refuses the operation if that route would cover the active management client, and it fails closed when the client address or route inventory is unavailable, truncated or contains unsupported/malformed sections. This is a safety guard, not a substitute for an out-of-band management path. Do not use remote route changes to modify the path currently carrying the administrator session.

Routes are persisted in the OpenWrt network UCI configuration. A network reload is required after commit. If reload fails, QuantumGrid attempts to remove the added section or restore the complete removed section, commits the previous configuration and reloads it; the API reports whether rollback was confirmed. The static-route list shows configured route sections, not proof that a route is installed in the live kernel or that its next hop is reachable. Validate live IPv4/IPv6 route tables and client reachability separately.

## IPv4 WAN port-forward lifecycle

The WAN port-forward inventory reports each validated IPv4 DNAT redirect as enabled or disabled. Administrators can enable or disable a redirect without deleting its configuration. Each state change requires an authenticated HTTPS, same-origin POST and explicit confirmation. The service snapshots the full redirect before changing only its enabled option; if the firewall reload fails, it restores the exact previous value, including an originally absent option, and attempts a second reload. Repeating the already-active state is an idempotent no-op and does not reload the firewall. A successful configuration reload is not proof of Internet reachability; verify the WAN path from an independent network.

## IPv6 WAN pinholes (not NAT)

Office Networks can add and remove **QuantumGrid-managed IPv6 pinholes** for services hosted on a LAN device that is currently visible in the router's IPv6 neighbour-discovery (NDP) table. The controller reads `ip -6 neigh show dev <interface>` only for an active kernel L3 device and exposes valid global-unicast neighbours with a unicast MAC and a usable kernel neighbour state (`REACHABLE`, `STALE`, `DELAY`, `PROBE` or `PERMANENT`). A firewall pinhole is eligible only when the address is observed exactly once across the active L3 inventory and that interface belongs to the selected internal firewall zone; down, unbound or ambiguous observations fail closed. IPv6 is routed end-to-end; this is a firewall allowance, not IPv4-style address/port translation.

A pinhole is limited to:
- One existing external WAN/WWAN source zone.
- One existing internal destination zone.
- One exact, unambiguous, currently observed global-unicast IPv6 NDP neighbour on a single active L3 device attached to that destination zone; the neighbour must have a valid unicast MAC and a usable state.
- TCP, UDP or TCP+UDP and one destination port (1–65535).

The validator rejects ULA, link-local, multicast, unspecified, documentation and other IPv6 special-purpose addresses; malformed IPv6; neighbours on a different interface; invalid/multicast/zero MAC addresses; down or unbound interfaces; duplicate/ambiguous NDP observations; failed or incomplete NDP entries; unsupported protocols; invalid ports; duplicate names; and overlapping zone/address/port/protocol allowances. The controller re-reads the live network, neighbour and firewall inventory on every request and refuses changes if inventory is unavailable or truncated.

The generated rule is an IPv6 firewall rule with the explicit source zone, destination zone, destination host, protocol, destination port, IPv6 family and ACCEPT target. It does **not** add an IPv6 redirect/NAT rule, change zone INPUT/OUTPUT/FORWARD defaults, open all ports, add ICMP-wide access, or create inter-zone forwarding. Existing default-deny policy remains in control of all unrelated traffic.

Create, enable, disable and remove operations require an authenticated HTTPS, same-origin administrator POST and explicit confirmation. Enable/disable updates only the managed rule's enabled option; an already-matching state is treated as an idempotent no-op. A firewall reload is checked; failure triggers an attempted restoration of the previous UCI value (including restoring an originally absent option) and a second reload. The API verifies the exact section, desired state and reload result before the control centre reports success. Only rules bearing QuantumGrid's managed marker and expected IPv6 rule structure are shown as managed pinholes or eligible for state changes/removal; administrator-created firewall rules remain outside this lifecycle. Create/state-change/remove successes and failures are written to the bounded local audit log.

**An observed NDP entry is not proof of public reachability.** The selected host must have a delegated or otherwise correctly routed global IPv6 address, the upstream network must carry inbound IPv6, and host firewall/service policy must allow the selected traffic. Sleeping or offline devices may not appear in the live neighbour inventory until they communicate again; wake the target host and refresh the router inventory before creating its pinhole. Test from a separate external IPv6 network. The UI inventory and a successful firewall reload are not proof that an ISP route, remote peer, host service or end-to-end connection is working.

## Transaction and recovery

Provisioning uses an authenticated, same-origin HTTPS POST and requires explicit confirmation. QuantumGrid snapshots the selected zone's existing network list, stages network/DHCP/firewall UCI changes, commits all three configuration packages and reloads the affected services. If staging, commit or a required reload fails, it removes the partial segment, restores the previous zone attachment and attempts to commit and reload the previous state. The API reports whether rollback was confirmed; a failed rollback must be investigated locally.

The IPv4-only transaction installs three firewall rules. Dual-stack installs seven. The control centre verifies the server response against the requested IPv6 mode, prefix length, rule count and service-reload results rather than displaying an unverified success.

## Deployment validation

CI covers Lua validation, API request/response contracts, the control-centre TypeScript build and firmware smoke checks. CI does not replace physical validation. Before selling or deploying an AW1000 image, test the exact firmware on the target hardware with the intended switch/AP VLAN path, IPv4 and IPv6 clients, ISP prefix delegation, firewall packet paths, reconnect/recovery behaviour and a separate management path. Do not claim IPv6 service is operational solely because the configuration transaction succeeded.
