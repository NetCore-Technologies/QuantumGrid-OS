import type { RouterSecurityStatus } from "./routerApi.js";

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
  return names.length === 0 || names.some(looksLikeExternalName);
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
    title: "Individual firewall rules",
    scope: "Rules / redirects",
    status: "unknown",
    detail: "Only configuration counts are available here. Rule order, address/port scope, NAT behaviour, IPv6 policy and actual packet paths have not been evaluated.",
  });

  return report(checks);
}
