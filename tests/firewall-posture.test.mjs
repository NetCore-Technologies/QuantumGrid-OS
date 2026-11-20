import test from "node:test";
import assert from "node:assert/strict";
import { auditFirewallPosture } from "../ui/quantumgrid/src/firewallPosture.ts";

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
  redirects_count: 1,
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
  ...overrides,
});

test("missing telemetry remains unknown instead of being reported secure", () => {
  const result = auditFirewallPosture(null);
  assert.equal(result.reviewCount, 0);
  assert.equal(result.okCount, 0);
  assert.equal(result.unknownCount, 1);
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
