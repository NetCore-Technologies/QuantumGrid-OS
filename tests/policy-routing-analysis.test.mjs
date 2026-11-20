import test from "node:test";
import assert from "node:assert/strict";
import { analyzePolicyRouting } from "../ui/quantumgrid/src/policyRouting.ts";

const rule = (overrides = {}) => ({
  family: "IPv4",
  priority: 1000,
  source: "all",
  destination: "all",
  fwmark: "",
  input_interface: "",
  output_interface: "",
  protocol: "",
  uid_range: "",
  table: "201",
  action: "lookup",
  selectors: "from all lookup 201",
  ...overrides,
});

const route = (overrides = {}) => ({
  family: "IPv4",
  route_type: "unicast",
  table: "201",
  device: "wan",
  gateway: "192.0.2.1",
  protocol: "static",
  ...overrides,
});

test("matches policy lookup rules to routes by both address family and table", () => {
  const result = analyzePolicyRouting(
    [rule(), rule({ priority: 1100, fwmark: "0x2/0xff" })],
    [route()],
  );
  assert.equal(result.matchedLookupRules, 2);
  assert.equal(result.missingDefaultRouteRules.length, 0);
  assert.equal(result.unreferencedDefaultTables.length, 0);
});

test("reports lookup tables without a reported default route without calling them invalid", () => {
  const missing = rule({ table: "202", priority: 2000, selectors: "from all lookup 202" });
  const result = analyzePolicyRouting([rule(), missing], [route()]);
  assert.equal(result.matchedLookupRules, 1);
  assert.deepEqual(result.missingDefaultRouteRules, [missing]);
});

test("does not match an IPv4 route to an IPv6 policy rule with the same table name", () => {
  const ipv6Rule = rule({ family: "IPv6", table: "201", priority: 100 });
  const result = analyzePolicyRouting([ipv6Rule], [route()]);
  assert.equal(result.matchedLookupRules, 0);
  assert.deepEqual(result.missingDefaultRouteRules, [ipv6Rule]);
});

test("keeps terminal actions separate and lists default-route tables with no lookup rule", () => {
  const terminal = rule({ priority: 50, action: "unreachable", table: "", selectors: "from all unreachable" });
  const result = analyzePolicyRouting([terminal], [route(), route({ table: "main" })]);
  assert.deepEqual(result.nonLookupRules, [terminal]);
  assert.deepEqual(result.unreferencedDefaultTables, [
    { family: "IPv4", table: "201", routeCount: 1 },
    { family: "IPv4", table: "main", routeCount: 1 },
  ]);
});

test("empty or unavailable inventories produce an empty analysis", () => {
  assert.deepEqual(analyzePolicyRouting(), {
    matchedLookupRules: 0,
    missingDefaultRouteRules: [],
    nonLookupRules: [],
    unreferencedDefaultTables: [],
  });
});
