import type { RouterDefaultRoute, RouterPolicyRule } from "./routerApi";

export interface PolicyRoutingCoverage {
  matchedLookupRules: number;
  missingDefaultRouteRules: RouterPolicyRule[];
  nonLookupRules: RouterPolicyRule[];
  unreferencedDefaultTables: Array<{
    family: RouterDefaultRoute["family"];
    table: string;
    routeCount: number;
  }>;
}

function tableKey(family: string, table: string): string {
  return family + "\\u0000" + table;
}

/**
 * Relates policy-rule lookup targets to default routes reported by the kernel.
 * This is an inventory cross-reference, not a packet-routing simulation.
 */
export function analyzePolicyRouting(
  rules: readonly RouterPolicyRule[] = [],
  routes: readonly RouterDefaultRoute[] = [],
): PolicyRoutingCoverage {
  const routesByTable = new Map<string, RouterDefaultRoute[]>();
  for (const route of routes) {
    const key = tableKey(route.family, route.table);
    const entries = routesByTable.get(key) ?? [];
    entries.push(route);
    routesByTable.set(key, entries);
  }

  const lookupRules = rules.filter((rule) => rule.action === "lookup" && rule.table.length > 0);
  const referencedTables = new Set<string>();
  const missingDefaultRouteRules: RouterPolicyRule[] = [];
  let matchedLookupRules = 0;

  for (const rule of lookupRules) {
    const key = tableKey(rule.family, rule.table);
    referencedTables.add(key);
    if ((routesByTable.get(key)?.length ?? 0) > 0) {
      matchedLookupRules += 1;
    } else {
      missingDefaultRouteRules.push(rule);
    }
  }

  const unreferencedDefaultTables = Array.from(routesByTable.entries())
    .filter(([key]) => !referencedTables.has(key))
    .map(([, tableRoutes]) => ({
      family: tableRoutes[0].family,
      table: tableRoutes[0].table,
      routeCount: tableRoutes.length,
    }))
    .sort((left, right) => left.family.localeCompare(right.family) || left.table.localeCompare(right.table));

  return {
    matchedLookupRules,
    missingDefaultRouteRules,
    nonLookupRules: rules.filter((rule) => rule.action !== "lookup"),
    unreferencedDefaultTables,
  };
}
