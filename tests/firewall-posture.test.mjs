import test from "node:test";
import assert from "node:assert/strict";
import { auditFirewallPosture } from "../ui/quantumgrid/src/firewallPosture.ts";

const managementTransport = {
  service_installed: true,
  http_listener_count: 0,
  https_listener_count: 1,
  tls_library_available: true,
  certificate_available: true,
  key_generator_available: true,
  private_key: { available: true, path: "/etc/uhttpd.key", status: "present" },
  certificate_fingerprint: { available: false, algorithm: "SHA-256" },
  http_redirect_enabled: false,
  https_configured: true,
  plaintext_http_unredirected: false,
  ssh_service_installed: true,
  ssh_config_available: true,
  ssh_instance_count: 1,
  ssh_enabled_instance_count: 1,
  ssh_truncated: false,
  ssh_instances: [{
    name: "main",
    enabled: true,
    interface: "lan",
    interface_bound: true,
    interface_zone_status: "internal",
    port: 22,
    port_valid: true,
    password_auth_enabled: false,
    root_password_auth_enabled: false,
    gateway_ports_enabled: false,
  }],
  ssh_status: "ready",
  status: "ready",
};

const security = (overrides = {}) => ({
  firewall_installed: true,
  firewall_config_available: true,
  firewall_config_readable: true,
  zones: [{
    name: "wan",
    networks: ["wan", "wan6"],
    input: "REJECT",
    output: "ACCEPT",
    forward: "REJECT",
    masquerade: true,
  }],
  rules: [],
  rules_count: 12,
  redirects: [],
  redirects_count: 1,
  redirects_truncated: false,
  nft_available: true,
  nft_tables: ["inet/fw4"],
  adblock_fast: {
    installed: true,
    config_available: true,
    configured_enabled: true,
  },
  vpn: {
    wireguard_tool_installed: true,
    openvpn_service_installed: true,
    wireguard_interfaces: [],
    openvpn_enabled_instances: 0,
  },
  management_transport: managementTransport,
  ...overrides,
});

test("missing telemetry remains unknown instead of being reported secure", () => {
  const result = auditFirewallPosture(null);
  assert.equal(result.reviewCount, 0);
  assert.equal(result.okCount, 0);
  assert.equal(result.unknownCount, 1);
});

test("HTTPS and key-only SSH on a uniquely mapped internal zone pass management checks", () => {
  const result = auditFirewallPosture(security());
  assert.equal(result.checks.find((item) => item.id === "management-https")?.status, "ok");
  assert.equal(result.checks.find((item) => item.id === "ssh-authentication")?.status, "ok");
  assert.equal(result.checks.find((item) => item.id === "ssh-management-zone:main")?.status, "ok");
});

test("unredirected plaintext HTTP and unsafe HTTPS key metadata require review", () => {
  const result = auditFirewallPosture(security({
    management_transport: {
      ...managementTransport,
      plaintext_http_unredirected: true,
      private_key: { available: true, path: "/etc/uhttpd.key", status: "review" },
    },
  }));
  assert.equal(result.checks.find((item) => item.id === "management-https")?.status, "review");
});

test("SSH mapped to an external WAN firewall zone is a management-plane exposure", () => {
  const result = auditFirewallPosture(security({
    management_transport: {
      ...managementTransport,
      ssh_status: "review",
      status: "review",
      ssh_instances: [{ ...managementTransport.ssh_instances[0], interface: "wan", interface_zone_status: "external" }],
    },
  }));
  assert.equal(result.checks.find((item) => item.id === "ssh-management-zone:main")?.status, "review");
  assert.match(result.checks.find((item) => item.id === "ssh-management-zone:main")?.detail ?? "", /external WAN\/WWAN/i);
});

test("custom or ambiguous SSH zone mappings remain unknown rather than trusted", () => {
  const result = auditFirewallPosture(security({
    management_transport: {
      ...managementTransport,
      ssh_status: "review",
      ssh_instances: [{ ...managementTransport.ssh_instances[0], interface: "uplink", interface_zone_status: "unknown" }],
    },
  }));
  assert.equal(result.checks.find((item) => item.id === "ssh-management-zone:main")?.status, "unknown");
});

test("missing management transport telemetry cannot imply a hardened administrator plane", () => {
  const result = auditFirewallPosture(security({ management_transport: undefined }));
  assert.equal(result.checks.find((item) => item.id === "management-https")?.status, "unknown");
  assert.equal(result.checks.find((item) => item.id === "ssh-authentication")?.status, "unknown");
  assert.equal(result.checks.find((item) => item.id === "ssh-management-zone")?.status, "unknown");
});

test("missing firewall service and configuration require review", () => {
  const result = auditFirewallPosture(security({
    firewall_installed: false,
    firewall_config_available: false,
    firewall_config_readable: false,
  }));
  assert.equal(result.checks.find((item) => item.id === "firewall-service")?.status, "review");
  assert.equal(result.checks.find((item) => item.id === "firewall-config")?.status, "review");
});

test("unreadable configuration and unavailable nftables inventory remain unknown", () => {
  const result = auditFirewallPosture(security({
    firewall_config_readable: false,
    nft_available: false,
  }));
  assert.equal(result.checks.find((item) => item.id === "firewall-config")?.status, "unknown");
  assert.equal(result.checks.find((item) => item.id === "fw4-runtime")?.status, "unknown");
  assert.equal(result.checks.find((item) => item.id === "external-zones")?.status, "unknown");
});

test("WAN ACCEPT defaults are flagged for review without claiming exploitability", () => {
  const result = auditFirewallPosture(security({
    zones: [{
      name: "wan",
      networks: ["wan"],
      input: "ACCEPT",
      output: "ACCEPT",
      forward: "ACCEPT",
      masquerade: false,
    }],
  }));
  const input = result.checks.find((item) => item.id === "wan:input");
  const forward = result.checks.find((item) => item.id === "wan:forward");
  assert.equal(input?.status, "review");
  assert.equal(forward?.status, "review");
  assert.match(input?.detail ?? "", /confirm|inspect/i);
});

test("restrictive WAN defaults pass this limited policy check", () => {
  const result = auditFirewallPosture(security());
  assert.equal(result.checks.find((item) => item.id === "wan:input")?.status, "ok");
  assert.equal(result.checks.find((item) => item.id === "wan:forward")?.status, "ok");
});

test("WAN6 and WWAN interface zone names are recognised", () => {
  const result = auditFirewallPosture(security({
    zones: [
      { name: "internet-v6", networks: ["wan6"], input: "DROP", output: "ACCEPT", forward: "DROP", masquerade: false },
      { name: "mobile", networks: ["wwan0"], input: "ACCEPT", output: "ACCEPT", forward: "DROP", masquerade: true },
    ],
  }));
  assert.equal(result.checks.find((item) => item.id === "internet-v6:input")?.status, "ok");
  assert.equal(result.checks.find((item) => item.id === "internet-v6:forward")?.status, "ok");
  assert.equal(result.checks.find((item) => item.id === "mobile:input")?.status, "review");
});

test("LAN ACCEPT policy is not misclassified as external", () => {
  const result = auditFirewallPosture(security({
    zones: [{ name: "lan", networks: ["lan"], input: "ACCEPT", output: "ACCEPT", forward: "ACCEPT", masquerade: false }],
  }));
  assert.equal(result.checks.some((item) => item.scope === "Zone lan" && item.status === "review"), false);
  assert.equal(result.checks.find((item) => item.id === "external-zones")?.status, "unknown");
});

test("custom rules are always marked unknown because counts are not rule evaluation", () => {
  const result = auditFirewallPosture(security());
  const rules = result.checks.find((item) => item.id === "rule-evaluation");
  assert.equal(rules?.status, "unknown");
  assert.match(rules?.detail ?? "", /not been evaluated/);
});

test("enabled ACCEPT rules sourced from WAN-like zones are flagged for review", () => {
  const result = auditFirewallPosture(security({
    rules: [{
      name: "allow-admin",
      source_zone: "wan",
      destination_zone: "lan",
      protocol: "tcp",
      target: "ACCEPT",
      family: "ipv4",
      source_port: "",
      destination_port: "8443",
      enabled: true,
      source_ip_match: false,
      destination_ip_match: false,
      source_mac_match: false,
    }],
  }));
  const finding = result.checks.find((item) => item.id === "external-allow-rule:allow-admin");
  assert.equal(finding?.status, "review");
  assert.match(finding?.detail ?? "", /does not prove public reachability/i);
});

test("disabled and LAN-origin ACCEPT rules are not classified as external allow rules", () => {
  const result = auditFirewallPosture(security({
    rules: [
      {
        name: "disabled-wan",
        source_zone: "wan",
        destination_zone: "lan",
        protocol: "tcp",
        target: "ACCEPT",
        family: "ipv4",
        source_port: "",
        destination_port: "8443",
        enabled: false,
        source_ip_match: false,
        destination_ip_match: false,
        source_mac_match: false,
      },
      {
        name: "lan-dns",
        source_zone: "lan",
        destination_zone: "",
        protocol: "udp",
        target: "ACCEPT",
        family: "ipv4",
        source_port: "",
        destination_port: "53",
        enabled: true,
        source_ip_match: false,
        destination_ip_match: false,
        source_mac_match: false,
      },
    ],
  }));
  assert.equal(result.checks.some((item) => item.id.startsWith("external-allow-rule:")), false);
});

test("multiple source zones are checked for WAN-like sources", () => {
  const result = auditFirewallPosture(security({
    rules: [{
      name: "wan-and-lan",
      source_zone: "lan wan6",
      destination_zone: "",
      protocol: "tcp",
      target: "ACCEPT",
      family: "ipv6",
      source_port: "",
      destination_port: "443",
      enabled: true,
      source_ip_match: false,
      destination_ip_match: false,
      source_mac_match: false,
    }],
  }));
  assert.equal(result.checks.some((item) => item.id === "external-allow-rule:wan-and-lan"), true);
});


test("parsed fw4 chain snapshot is reported separately from security verdicts", () => {
  const result = auditFirewallPosture(security({
    nft_runtime: {
      available: true,
      table_present: true,
      chains: [],
      chain_count: 4,
      rule_count: 31,
      truncated: false,
      sampled_at: 1700000000,
    },
  }));
  const snapshot = result.checks.find((item) => item.id === "fw4-chain-snapshot");
  assert.equal(snapshot?.status, "ok");
  assert.match(snapshot?.detail ?? "", /metadata snapshot/i);
});

test("unavailable and truncated fw4 chain snapshots remain unknown", () => {
  const unavailable = auditFirewallPosture(security({
    nft_runtime: {
      available: false,
      table_present: true,
      chains: [],
      chain_count: 0,
      rule_count: 0,
      truncated: false,
      sampled_at: 1700000000,
    },
  }));
  assert.equal(unavailable.checks.find((item) => item.id === "fw4-chain-snapshot")?.status, "unknown");

  const truncated = auditFirewallPosture(security({
    nft_runtime: {
      available: true,
      table_present: true,
      chains: [],
      chain_count: 70,
      rule_count: 400,
      truncated: true,
      sampled_at: 1700000000,
    },
  }));
  assert.equal(truncated.checks.find((item) => item.id === "fw4-chain-snapshot")?.status, "unknown");
});

test("WAN port forwards are listed for manual review and unscoped forwards are highlighted", () => {
  const result = auditFirewallPosture(security({
    redirects: [{
      name: "wan-to-office-ssh",
      source_zone: "wan",
      destination_zone: "lan",
      protocol: "tcp",
      target: "DNAT",
      family: "ipv4",
      external_port: "",
      internal_port: "22",
      enabled: true,
      source_ip_match: false,
      source_mac_match: false,
      destination_ip_match: true,
      source_destination_ip_match: false,
    }],
  }));
  assert.equal(result.checks.find((item) => item.id === "external-redirect:wan-to-office-ssh")?.status, "review");
  assert.equal(result.checks.find((item) => item.id === "external-redirect-any-port:wan-to-office-ssh")?.status, "review");
  const service = result.checks.find((item) => item.id === "external-redirect-admin-service:wan-to-office-ssh");
  assert.equal(service?.status, "review");
  assert.match(service?.detail ?? "", /SSH/);
  assert.match(service?.detail ?? "", /not proof|proof that a service is listening/i);
});

test("remapped internal management ports are identified even when external ports differ", () => {
  const result = auditFirewallPosture(security({
    redirects: [{
      name: "remote-vnc",
      source_zone: "wan6",
      destination_zone: "lan",
      protocol: "tcp",
      target: "DNAT",
      family: "ipv6",
      external_port: "15900",
      internal_port: "5900-5901",
      enabled: true,
      source_ip_match: true,
      source_mac_match: false,
      destination_ip_match: true,
      source_destination_ip_match: false,
    }],
  }));
  const service = result.checks.find((item) => item.id === "external-redirect-admin-service:remote-vnc");
  assert.equal(service?.status, "review");
  assert.match(service?.detail ?? "", /VNC/);
  assert.equal(result.checks.some((item) => item.id === "external-redirect-any-port:remote-vnc"), false);
});

test("disabled and LAN-only NAT redirects are not classified as external", () => {
  const result = auditFirewallPosture(security({
    redirects: [
      {
        name: "disabled-wan",
        source_zone: "wan",
        destination_zone: "lan",
        protocol: "tcp",
        target: "DNAT",
        family: "ipv4",
        external_port: "",
        internal_port: "22",
        enabled: false,
        source_ip_match: false,
        source_mac_match: false,
        destination_ip_match: true,
        source_destination_ip_match: false,
      },
      {
        name: "lan-to-printer",
        source_zone: "lan",
        destination_zone: "lan",
        protocol: "tcp",
        target: "DNAT",
        family: "ipv4",
        external_port: "9100",
        internal_port: "9100",
        enabled: true,
        source_ip_match: false,
        source_mac_match: false,
        destination_ip_match: true,
        source_destination_ip_match: false,
      },
    ],
  }));
  assert.equal(result.checks.some((item) => item.id.startsWith("external-redirect:")), false);
});

test("wildcard redirect sources are reviewed as potentially external", () => {
  const result = auditFirewallPosture(security({
    redirects: [{
      name: "any-zone-forward",
      source_zone: "*",
      destination_zone: "lan",
      protocol: "tcp",
      target: "DNAT",
      family: "",
      external_port: "8080",
      internal_port: "8080",
      enabled: true,
      source_ip_match: false,
      source_mac_match: false,
      destination_ip_match: true,
      source_destination_ip_match: false,
    }],
  }));
  assert.equal(result.checks.find((item) => item.id === "external-redirect:any-zone-forward")?.status, "review");
});

test("unconstrained WAN ACCEPT rules are separately highlighted", () => {
  const result = auditFirewallPosture(security({
    rules: [{
      name: "wide-wan-accept",
      source_zone: "wan",
      destination_zone: "",
      protocol: "all",
      target: "ACCEPT",
      family: "",
      source_port: "",
      destination_port: "",
      enabled: true,
      source_ip_match: false,
      destination_ip_match: false,
      source_mac_match: false,
    }],
  }));
  assert.equal(result.checks.find((item) => item.id === "unconstrained-external-allow:wide-wan-accept")?.status, "review");
});

test("duplicate display names retain distinct UCI redirect finding identifiers", () => {
  const result = auditFirewallPosture(security({
    redirects: [
      {
        section: "cfg1001",
        name: "remote-admin",
        source_zone: "wan",
        destination_zone: "lan",
        protocol: "tcp",
        target: "DNAT",
        family: "ipv4",
        external_port: "2222",
        internal_port: "22",
        enabled: true,
        source_ip_match: false,
        source_mac_match: false,
        destination_ip_match: true,
        source_destination_ip_match: false,
      },
      {
        section: "cfg1002",
        name: "remote-admin",
        source_zone: "wan6",
        destination_zone: "lan",
        protocol: "tcp",
        target: "DNAT",
        family: "ipv6",
        external_port: "2223",
        internal_port: "22",
        enabled: true,
        source_ip_match: true,
        source_mac_match: false,
        destination_ip_match: true,
        source_destination_ip_match: false,
      },
    ],
  }));
  assert.equal(result.checks.find((item) => item.id === "external-redirect:cfg1001")?.status, "review");
  assert.equal(result.checks.find((item) => item.id === "external-redirect:cfg1002")?.status, "review");
});

test("truncated NAT redirect inventories remain unknown and cannot imply complete review", () => {
  const result = auditFirewallPosture(security({
    redirects_truncated: true,
    redirects: [{
      name: "first-page-forward",
      source_zone: "wan",
      destination_zone: "lan",
      protocol: "tcp",
      target: "DNAT",
      family: "ipv4",
      external_port: "80",
      internal_port: "8080",
      enabled: true,
      source_ip_match: false,
      source_mac_match: false,
      destination_ip_match: true,
      source_destination_ip_match: false,
    }],
  }));
  const incomplete = result.checks.find((item) => item.id === "redirect-inventory-truncated");
  assert.equal(incomplete?.status, "unknown");
  assert.match(incomplete?.detail ?? "", /first 64|additional configured forwards/i);
});

test("port-range analysis ignores malformed port expressions", () => {
  const result = auditFirewallPosture(security({
    redirects: [{
      name: "malformed-forward",
      source_zone: "wan",
      destination_zone: "lan",
      protocol: "tcp",
      target: "DNAT",
      family: "ipv4",
      external_port: "not-a-port",
      internal_port: "99999-100000",
      enabled: true,
      source_ip_match: false,
      source_mac_match: false,
      destination_ip_match: true,
      source_destination_ip_match: false,
    }],
  }));
  assert.equal(result.checks.some((item) => item.id === "external-redirect-admin-service:malformed-forward"), false);
  assert.equal(result.checks.some((item) => item.id === "external-redirect:any-port:malformed-forward"), false);
});

test("source-unrestricted ACCEPT rules are flagged for manual review", () => {
  const result = auditFirewallPosture(security({
    rules: [{
      name: "all-zones-accept",
      source_zone: "",
      destination_zone: "",
      protocol: "tcp",
      target: "ACCEPT",
      family: "",
      source_port: "",
      destination_port: "8443",
      enabled: true,
      source_ip_match: false,
      destination_ip_match: false,
      source_mac_match: false,
    }],
  }));
  const finding = result.checks.find((item) => item.id === "external-allow-rule:all-zones-accept");
  assert.equal(finding?.status, "review");
  assert.match(finding?.detail ?? "", /no explicit source-zone restriction/i);
});
