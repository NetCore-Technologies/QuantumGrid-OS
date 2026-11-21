import type { RouterFirewallRedirect, RouterManagementTransport, RouterSecurityStatus } from "./routerApi.js";

export type FirewallPostureStatus = "review" | "ok" | "unknown";

export type FirewallPostureCheck = {
  id: string;
  title: string;
  scope: string;
  status: FirewallPostureStatus;
  detail: string;
};

export type FirewallPostureReport = {
  checks: FirewallPostureCheck[];
  reviewCount: number;
  okCount: number;
  unknownCount: number;
};

const EXTERNAL_ZONE_NAMES = new Set([
  "wan",
  "wan6",
  "wwan",
  "cellular",
  "lte",
  "5g",
]);

function normalizeName(value: string): string {
  return value.trim().toLowerCase();
}

function looksLikeExternalName(value: string): boolean {
  const name = normalizeName(value);
  return EXTERNAL_ZONE_NAMES.has(name) || /^wwan\d+$/.test(name) || /^wan\d+$/.test(name);
}

function hasPotentialExternalSource(sourceZone: string): boolean {
  const names = normalizeName(sourceZone).split(/\s+/).filter(Boolean);
  // An omitted source zone is an unrestricted source match and therefore needs review.
  return names.length === 0 || names.some((name) => name === "*" || looksLikeExternalName(name));
}

const SENSITIVE_SERVICE_PORTS = new Map<number, string>([
  [22, "SSH"],
  [23, "Telnet"],
  [445, "SMB"],
  [3389, "RDP"],
  [5900, "VNC"],
  [2375, "Docker API"],
  [2376, "Docker TLS API"],
  [3306, "MySQL"],
  [5432, "PostgreSQL"],
  [6443, "Kubernetes API"],
  [9200, "Elasticsearch"],
  [27017, "MongoDB"],
]);

function containsPort(value: string, wanted: number): boolean {
  for (const raw of value.trim().split(/[\s,]+/).filter(Boolean)) {
    const match = /^(\d+)(?:-(\d+))?$/.exec(raw);
    if (!match) continue;
    const start = Number(match[1]);
    const end = match[2] === undefined ? start : Number(match[2]);
    if (!Number.isInteger(start) || !Number.isInteger(end) ||
        start < 1 || end > 65535 || end < start) continue;
    if (wanted >= start && wanted <= end) return true;
  }
  return false;
}

function redirectReviewChecks(redirect: RouterFirewallRedirect): FirewallPostureCheck[] {
  const redirectId = redirect.section || redirect.name;
  if (!redirect.enabled || !hasPotentialExternalSource(redirect.source_zone)) return [];
  const checks: FirewallPostureCheck[] = [{
    id: "external-redirect:" + redirectId,
    title: "Enabled external NAT redirect",
    scope: "Redirect " + redirect.name,
    status: "review",
    detail: "This enabled redirect uses a WAN/WWAN or unrestricted source-zone selector. Review the external and internal port mapping, destination host and source-address restrictions. The private destination address is deliberately not collected; this check does not prove that the service is reachable from the Internet.",
  }];

  if (!redirect.external_port.trim()) {
    checks.push({
      id: "external-redirect-any-port:" + redirectId,
      title: "External redirect has no port constraint",
      scope: "Redirect " + redirect.name,
      status: "review",
      detail: "No external source-port constraint (src_dport) was reported. OpenWrt documents that a redirect without src_dport can match traffic on any port that satisfies its other selectors. Inspect the rule before leaving it enabled.",
    });
  }

  const destinationPort = redirect.internal_port.trim() || redirect.external_port.trim();
  const exposedServices = [...SENSITIVE_SERVICE_PORTS.entries()]
    .filter(([port]) => containsPort(destinationPort, port))
    .map(([, name]) => name);
  if (exposedServices.length > 0) {
    checks.push({
      id: "external-redirect-admin-service:" + redirectId,
      title: "External redirect maps to an administrative or data service port",
      scope: "Redirect " + redirect.name,
      status: "review",
      detail: "The reported destination-port mapping includes " + exposedServices.join(", ") +
        ". Confirm that remote access is required, source addresses are constrained, and the service itself is hardened. A port match is a review signal, not proof that a service is listening or exploitable.",
    });
  }

  if (!redirect.source_ip_match && !redirect.source_zone.trim()) {
    checks.push({
      id: "external-redirect-unrestricted-source:" + redirectId,
      title: "External redirect has no reported source restriction",
      scope: "Redirect " + redirect.name,
      status: "review",
      detail: "No source IP restriction or explicit source zone was reported. Check the native UCI section and active firewall rules before assuming the forward is restricted.",
    });
  }
  return checks;
}

function policyCheck(
  zoneName: string,
  policyName: "input" | "forward",
  rawPolicy: string,
): FirewallPostureCheck {
  const policy = rawPolicy.trim().toUpperCase();
  const title = policyName === "input" ? "Incoming traffic policy" : "Forwarding policy";
  const scope = "Zone " + zoneName;
  if (policy === "ACCEPT") {
    return {
      id: zoneName + ":" + policyName,
      title,
      scope,
      status: "review",
      detail: policyName === "input"
        ? "The zone accepts traffic addressed to the router by default. Confirm this is intentional for the external network and inspect the individual allow rules."
        : "The zone accepts forwarding by default. Confirm the forwarding topology and inspect the individual rules before exposing this interface.",
    };
  }
  if (policy === "REJECT" || policy === "DROP") {
    return {
      id: zoneName + ":" + policyName,
      title,
      scope,
      status: "ok",
      detail: "The zone has a restrictive default policy for this direction. Individual rules and runtime behaviour are not evaluated here.",
    };
  }
  return {
    id: zoneName + ":" + policyName,
    title,
    scope,
    status: "unknown",
    detail: "The default policy was not reported in a recognised form; it is not treated as safe or unsafe.",
  };
}

function managementPlaneChecks(
  management: RouterManagementTransport | undefined,
): FirewallPostureCheck[] {
  if (!management) {
    return [
      {
        id: "management-https",
        title: "Administrator HTTPS transport",
        scope: "Management plane",
        status: "unknown",
        detail: "HTTPS listener, TLS and private-key posture were not reported. Do not assume the administrator plane is encrypted.",
      },
      {
        id: "ssh-authentication",
        title: "SSH authentication posture",
        scope: "Dropbear",
        status: "unknown",
        detail: "SSH configuration and authentication controls were not reported.",
      },
      {
        id: "ssh-management-zone",
        title: "SSH management-network binding",
        scope: "Dropbear",
        status: "unknown",
        detail: "The firewall-zone binding of enabled SSH listeners was not reported. An interface name alone is not proof of a trusted management network.",
      },
    ];
  }

  const checks: FirewallPostureCheck[] = [];
  const privateKeyStatus = management.private_key?.status;
  if (!management.https_configured || !management.service_installed || management.plaintext_http_unredirected) {
    checks.push({
      id: "management-https",
      title: "Administrator HTTPS transport",
      scope: "uHTTPd",
      status: "review",
      detail: !management.service_installed || !management.https_configured
        ? "The HTTPS service, listener, TLS runtime or non-empty certificate/key pair is not fully configured. Keep administrator access off unencrypted HTTP until HTTPS is available."
        : "An HTTP listener is active without an HTTPS redirect. Use HTTPS for every administrator session and remove or redirect plaintext listeners.",
    });
  } else if (privateKeyStatus === "present") {
    checks.push({
      id: "management-https",
      title: "Administrator HTTPS transport",
      scope: "uHTTPd",
      status: "ok",
      detail: "HTTPS listeners, TLS runtime and a root-owned private key with restrictive file permissions are configured; this does not validate certificate trust, hostname coverage or live socket reachability.",
    });
  } else {
    checks.push({
      id: "management-https",
      title: "Administrator HTTPS transport",
      scope: "uHTTPd",
      status: privateKeyStatus === "review" || privateKeyStatus === "missing" ? "review" : "unknown",
      detail: privateKeyStatus === "review" || privateKeyStatus === "missing"
        ? "The HTTPS private-key file is missing or its ownership, type, size or permissions require review."
        : "HTTPS is configured, but private-key metadata could not be fully verified.",
    });
  }

  if (management.ssh_service_installed === false || management.ssh_status === "disabled") {
    checks.push({
      id: "ssh-authentication",
      title: "SSH authentication posture",
      scope: "Dropbear",
      status: "ok",
      detail: "Dropbear is not installed or has no enabled listener; no active SSH authentication posture is claimed.",
    });
  } else if (management.ssh_status === "ready") {
    checks.push({
      id: "ssh-authentication",
      title: "SSH authentication posture",
      scope: "Dropbear",
      status: "ok",
      detail: "The bounded Dropbear configuration review passed its authentication, key-file, listener and gateway-port checks. This does not establish live reachability or prove that an administrator can authenticate successfully.",
    });
  } else if (management.ssh_status === "review") {
    checks.push({
      id: "ssh-authentication",
      title: "SSH authentication posture",
      scope: "Dropbear",
      status: "review",
      detail: "One or more enabled Dropbear listeners have an unsafe or incomplete authentication, key-file, port or interface configuration. Review each reported instance before production use.",
    });
  } else {
    checks.push({
      id: "ssh-authentication",
      title: "SSH authentication posture",
      scope: "Dropbear",
      status: "unknown",
      detail: "Dropbear configuration could not be completely inspected; missing telemetry is not treated as a hardened state.",
    });
  }

  if (management.ssh_service_installed === false || management.ssh_status === "disabled") {
    checks.push({
      id: "ssh-management-zone",
      title: "SSH management-network binding",
      scope: "Dropbear",
      status: "ok",
      detail: "No enabled SSH listener was reported.",
    });
  } else if (management.ssh_config_available !== true || !management.ssh_instances) {
    checks.push({
      id: "ssh-management-zone",
      title: "SSH management-network binding",
      scope: "Dropbear",
      status: "unknown",
      detail: "The enabled SSH listener inventory or firewall-zone mapping is unavailable.",
    });
  } else {
    const enabledInstances = management.ssh_instances.filter((instance) => instance.enabled === true);
    if (enabledInstances.length === 0) {
      checks.push({
        id: "ssh-management-zone",
        title: "SSH management-network binding",
        scope: "Dropbear",
        status: "unknown",
        detail: "No enabled SSH listener could be correlated with a trusted management zone.",
      });
    }
    for (const instance of enabledInstances) {
      const zoneStatus = instance.interface_zone_status;
      checks.push({
        id: "ssh-management-zone:" + instance.name,
        title: "SSH management-network binding",
        scope: "Dropbear " + instance.name,
        status: zoneStatus === "internal" ? "ok" : zoneStatus === "external" ? "review" : "unknown",
        detail: zoneStatus === "internal"
          ? "The listener interface maps uniquely to a recognised internal firewall zone. Validate the management VLAN and its effective firewall policy separately."
          : zoneStatus === "external"
            ? "The listener interface maps to an external WAN/WWAN firewall zone. Do not expose administrator SSH directly on the external network; move it to a dedicated trusted management network."
            : "The listener interface could not be mapped uniquely to a recognised internal or external firewall zone. Custom, missing or ambiguous mappings fail closed and require manual review.",
      });
    }
    if (management.ssh_truncated) {
      checks.push({
        id: "ssh-management-zone-truncated",
        title: "SSH management-network inventory is incomplete",
        scope: "Dropbear",
        status: "unknown",
        detail: "The SSH instance list is truncated. Additional listeners were not classified and must be reviewed in the native Dropbear configuration.",
      });
    }
  }

  return checks;
}

function report(checks: FirewallPostureCheck[]): FirewallPostureReport {
  return {
    checks,
    reviewCount: checks.filter((check) => check.status === "review").length,
    okCount: checks.filter((check) => check.status === "ok").length,
    unknownCount: checks.filter((check) => check.status === "unknown").length,
  };
}

export function auditFirewallPosture(
  security: RouterSecurityStatus | null | undefined,
): FirewallPostureReport {
  if (!security) {
    return report([{
      id: "security-telemetry",
      title: "Security telemetry",
      scope: "Router API",
      status: "unknown",
      detail: "Waiting for authenticated security telemetry. No posture conclusion is available.",
    }]);
  }

  const checks: FirewallPostureCheck[] = [];
  checks.push(...managementPlaneChecks(security.management_transport));
  checks.push({
    id: "firewall-service",
    title: "Firewall service",
    scope: "Router",
    status: security.firewall_installed ? "ok" : "review",
    detail: security.firewall_installed
      ? "The firewall init service is present. This does not prove that every configured rule is correct."
      : "The firewall init service was not found. Confirm that the intended firewall is installed and enabled.",
  });

  if (!security.firewall_config_available) {
    checks.push({
      id: "firewall-config",
      title: "Firewall configuration",
      scope: "UCI",
      status: "review",
      detail: "The firewall configuration file was not found.",
    });
  } else if (!security.firewall_config_readable) {
    checks.push({
      id: "firewall-config",
      title: "Firewall configuration",
      scope: "UCI",
      status: "unknown",
      detail: "The firewall configuration exists but could not be read; policies cannot be reviewed.",
    });
  } else {
    checks.push({
      id: "firewall-config",
      title: "Firewall configuration",
      scope: "UCI",
      status: "ok",
      detail: "The firewall configuration was readable.",
    });
  }

  if (!security.nft_available) {
    checks.push({
      id: "fw4-runtime",
      title: "Firewall runtime table",
      scope: "nftables",
      status: "unknown",
      detail: "The nftables table inventory is unavailable.",
    });
  } else if (security.nft_tables.includes("inet/fw4")) {
    checks.push({
      id: "fw4-runtime",
      title: "Firewall runtime table",
      scope: "nftables",
      status: "ok",
      detail: "The inet/fw4 table is present in the runtime table inventory.",
    });
  } else {
    checks.push({
      id: "fw4-runtime",
      title: "Firewall runtime table",
      scope: "nftables",
      status: "review",
      detail: "The inet/fw4 table was not present in the returned runtime inventory. Confirm the active firewall backend and service state.",
    });
  }

  const runtime = security.nft_runtime;
  if (runtime?.available && !runtime.truncated) {
    checks.push({
      id: "fw4-chain-snapshot",
      title: "Live fw4 chain snapshot",
      scope: "inet/fw4",
      status: "ok",
      detail: "The active fw4 table was parsed into a bounded chain inventory. This confirms only that a metadata snapshot was collected; it does not validate rule semantics or packet behaviour.",
    });
  } else {
    checks.push({
      id: "fw4-chain-snapshot",
      title: "Live fw4 chain snapshot",
      scope: "inet/fw4",
      status: "unknown",
      detail: runtime?.truncated
        ? "The fw4 chain inventory exceeded its 64-chain limit or the JSON snapshot exceeded its byte cap. The visible chain list is incomplete."
        : runtime?.table_present
          ? "The fw4 table is present, but its JSON chain inventory could not be parsed."
          : "A live fw4 chain snapshot is not available. Table presence and detailed runtime availability are not treated as equivalent.",
    });
  }

  const externalAllowRules = (security.rules ?? []).filter((rule) =>
    rule.enabled === true &&
    rule.target.trim().toUpperCase() === "ACCEPT" &&
    hasPotentialExternalSource(rule.source_zone),
  );
  for (const rule of externalAllowRules) {
    checks.push({
      id: "external-allow-rule:" + rule.name,
      title: "Enabled external allow rule",
      scope: "Rule " + rule.name,
      status: "review",
      detail: rule.source_zone.trim()
        ? "This enabled ACCEPT rule names a standard WAN/WWAN source zone. Review its protocol, port constraints and address-match conditions. Raw address values are not collected; this check does not prove public reachability."
        : "This enabled ACCEPT rule has no explicit source-zone restriction and may match more than WAN traffic. Review its protocol, port constraints and address-match conditions. Raw address values are not collected; this check does not prove public reachability.",
    });
  }

  const broadExternalAllowRules = (security.rules ?? []).filter((rule) => {
    const protocol = rule.protocol.trim().toLowerCase();
    const broadProtocol = !protocol || protocol === "all" || protocol === "0";
    const hasPortScope = Boolean(rule.source_port.trim() || rule.destination_port.trim());
    const hasAddressScope = rule.source_ip_match || rule.destination_ip_match || rule.source_mac_match;
    return rule.enabled === true &&
      rule.target.trim().toUpperCase() === "ACCEPT" &&
      hasPotentialExternalSource(rule.source_zone) &&
      broadProtocol && !hasPortScope && !hasAddressScope;
  });
  for (const rule of broadExternalAllowRules) {
    checks.push({
      id: "unconstrained-external-allow:" + rule.name,
      title: "Broad external ACCEPT rule",
      scope: "Rule " + rule.name,
      status: "review",
      detail: "This enabled ACCEPT rule has a WAN/WWAN or unrestricted source selector, no reported port constraint and no reported source/destination IP or source MAC match. Verify the full UCI rule and runtime packet path; the summary deliberately omits raw addresses.",
    });
  }

  for (const redirect of security.redirects ?? []) {
    checks.push(...redirectReviewChecks(redirect));
  }
  if (security.redirects_truncated) {
    checks.push({
      id: "redirect-inventory-truncated",
      title: "NAT redirect inventory is incomplete",
      scope: "Firewall redirects",
      status: "unknown",
      detail: "The API returned only the first 64 redirects. Additional configured forwards were not reviewed and may contain further exposure paths; inspect the full native firewall configuration.",
    });
  }

  if (!security.firewall_config_readable) {
    checks.push({
      id: "external-zones",
      title: "External-zone default policies",
      scope: "Firewall zones",
      status: "unknown",
      detail: "External-zone policies could not be assessed because the configuration was not readable.",
    });
  } else {
    const externalZones = security.zones.filter((zone) =>
      looksLikeExternalName(zone.name) || zone.networks.some(looksLikeExternalName),
    );
    if (externalZones.length === 0) {
      checks.push({
        id: "external-zones",
        title: "External-zone default policies",
        scope: "Firewall zones",
        status: "unknown",
        detail: "No standard WAN/WWAN zone name was identified. Custom external-zone names may not be recognised; confirm the router's WAN topology manually.",
      });
    } else {
      for (const zone of externalZones) {
        checks.push(policyCheck(zone.name || "unnamed", "input", zone.input));
        checks.push(policyCheck(zone.name || "unnamed", "forward", zone.forward));
      }
    }
  }

  checks.push({
    id: "rule-evaluation",
    title: "Firewall rule and redirect evaluation",
    scope: "Rules / NAT redirects",
    status: "unknown",
    detail: "Configuration summaries are available, but rule order, complete address/port scope, NAT behaviour, IPv6 policy and actual packet paths have not been evaluated. Redirect risk checks are manual-review signals only.",
  });

  return report(checks);
}
