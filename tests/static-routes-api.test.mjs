import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import {
  createRouterStaticRoute,
  removeRouterStaticRoute,
} from "../ui/quantumgrid/src/routerApi.ts";

const originalFetch = globalThis.fetch;

afterEach(() => {
  globalThis.fetch = originalFetch;
});

function jsonResponse(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json; charset=UTF-8" },
  });
}

const ipv4Input = {
  family: "IPv4",
  interface: "wan",
  target: "10.40.0.0/16",
  gateway: "192.0.2.1",
  metric: "20",
  table: "100",
};

const ipv4Success = {
  ok: true,
  section: "cfg_route_remote",
  family: "IPv4",
  interface: "wan",
  requested_target: "10.40.0.0/16",
  target: "10.40.0.0/16",
  gateway: "192.0.2.1",
  metric: "20",
  table: "100",
  reloaded: true,
  rolled_back: false,
};

test("creates an IPv4 static route with validated interface, gateway, metric and table", async () => {
  let requestUrl = "";
  let requestInit;
  globalThis.fetch = async (url, init) => {
    requestUrl = String(url);
    requestInit = init;
    return jsonResponse(ipv4Success);
  };

  const result = await createRouterStaticRoute(ipv4Input);
  assert.equal(requestUrl, "/cgi-bin/luci/admin/services/quantumgrid/static-route-add");
  assert.equal(requestInit.method, "POST");
  assert.equal(requestInit.credentials, "same-origin");
  assert.equal(requestInit.cache, "no-store");
  const form = new URLSearchParams(requestInit.body);
  assert.equal(form.get("family"), "IPv4");
  assert.equal(form.get("interface"), "wan");
  assert.equal(form.get("target"), "10.40.0.0/16");
  assert.equal(form.get("gateway"), "192.0.2.1");
  assert.equal(form.get("metric"), "20");
  assert.equal(form.get("table"), "100");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.section, "cfg_route_remote");
  assert.equal(result.metric, "20");
  assert.equal(result.reloaded, true);
});

test("creates an IPv6 static route and accepts the router's canonical expanded prefix", async () => {
  let requestInit;
  globalThis.fetch = async (_url, init) => {
    requestInit = init;
    return jsonResponse({
      ok: true,
      section: "cfg_route6_remote",
      family: "IPv6",
      interface: "wg0",
      requested_target: "2001:db8:40::/48",
      target: "2001:db8:40:0:0:0:0:0/48",
      gateway: "fe80:0:0:0:0:0:0:1",
      metric: "",
      table: "",
      reloaded: true,
      rolled_back: false,
    });
  };

  const result = await createRouterStaticRoute({
    family: "IPv6",
    interface: "wg0",
    target: "2001:db8:40::/48",
    gateway: "fe80::1",
    metric: "",
    table: "",
  });
  const form = new URLSearchParams(requestInit.body);
  assert.equal(form.get("family"), "IPv6");
  assert.equal(form.get("target"), "2001:db8:40::/48");
  assert.equal(form.get("gateway"), "fe80::1");
  assert.equal(result.target, "2001:db8:40:0:0:0:0:0/48");
  assert.equal(result.gateway, "fe80:0:0:0:0:0:0:1");
  assert.equal(result.metric, "");
  assert.equal(result.table, "");
});

test("static route client rejects unsafe and malformed values before fetch", async () => {
  globalThis.fetch = async () => {
    throw new Error("fetch must not be called for invalid input");
  };
  await assert.rejects(
    createRouterStaticRoute({ ...ipv4Input, interface: "../wan" }),
    /valid existing network interface/,
  );
  await assert.rejects(
    createRouterStaticRoute({ ...ipv4Input, target: "10.40.1.0/16" }),
    /canonical network CIDR/,
  );
  await assert.rejects(
    createRouterStaticRoute({ ...ipv4Input, target: "0.0.0.0/0" }),
    /IPv4 network CIDR/,
  );
  await assert.rejects(
    createRouterStaticRoute({ ...ipv4Input, target: "10.40.0.0/33" }),
    /IPv4 network CIDR/,
  );
  await assert.rejects(
    createRouterStaticRoute({ ...ipv4Input, metric: "65536" }),
    /Route metric/,
  );
  await assert.rejects(
    createRouterStaticRoute({ ...ipv4Input, table: "253" }),
    /Custom route table/,
  );
  await assert.rejects(
    createRouterStaticRoute({ ...ipv4Input, family: "IPv6", target: "2001:db8:40::/129" }),
    /IPv6 network CIDR/,
  );
});

test("static route API rejects a response for a different network interface or target", async () => {
  globalThis.fetch = async () => jsonResponse({
    ...ipv4Success,
    interface: "lan",
  });
  await assert.rejects(
    createRouterStaticRoute(ipv4Input),
    /did not confirm the static route configuration/,
  );

  globalThis.fetch = async () => jsonResponse({
    ...ipv4Success,
    requested_target: "10.41.0.0/16",
  });
  await assert.rejects(
    createRouterStaticRoute(ipv4Input),
    /did not confirm the static route configuration/,
  );
});

test("static route API rejects a response without an explicit metric result", async () => {
  const { metric: _metric, ...incomplete } = ipv4Success;
  globalThis.fetch = async () => jsonResponse(incomplete);
  await assert.rejects(
    createRouterStaticRoute(ipv4Input),
    /did not confirm the static route configuration/,
  );
});

test("removes a static route and verifies the network reload result", async () => {
  let requestUrl = "";
  let requestInit;
  globalThis.fetch = async (url, init) => {
    requestUrl = String(url);
    requestInit = init;
    return jsonResponse({
      ok: true,
      section: "cfg_route6_remote",
      family: "IPv6",
      removed: true,
      reloaded: true,
      rolled_back: false,
    });
  };
  const result = await removeRouterStaticRoute("cfg_route6_remote");
  assert.equal(requestUrl, "/cgi-bin/luci/admin/services/quantumgrid/static-route-remove");
  assert.equal(requestInit.method, "POST");
  assert.equal(requestInit.credentials, "same-origin");
  assert.equal(requestInit.cache, "no-store");
  const form = new URLSearchParams(requestInit.body);
  assert.equal(form.get("section"), "cfg_route6_remote");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.removed, true);
  await assert.rejects(removeRouterStaticRoute("../network"), /Invalid static route section/);
});

test("static route removal rejects an unverified network reload", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true,
    section: "cfg_route_remote",
    family: "IPv4",
    removed: true,
    reloaded: false,
    rolled_back: false,
  });
  await assert.rejects(
    removeRouterStaticRoute("cfg_route_remote"),
    /did not confirm static route removal/,
  );
});
