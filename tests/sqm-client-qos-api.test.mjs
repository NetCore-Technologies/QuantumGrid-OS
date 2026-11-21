import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import {
  addRouterSqmClientPolicy,
  removeRouterSqmClientPolicy,
} from "../ui/quantumgrid/src/routerApi.ts";

const originalFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = originalFetch; });

function jsonResponse(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status, headers: { "Content-Type": "application/json; charset=UTF-8" },
  });
}

const baseInput = {
  mac: "02:11:22:33:44:55",
  sourceZone: "corp",
  destinationZone: "wan",
  dscpClass: "AF41",
};

test("client QoS API creates a fixed DSCP marking and verifies firewall reload", async () => {
  let url = "";
  let init;
  globalThis.fetch = async (requestUrl, requestInit) => {
    url = String(requestUrl);
    init = requestInit;
    return jsonResponse({
      ok: true, section: "cfg_client_1", mac: "02:11:22:33:44:55",
      source_zone: "corp", destination_zone: "wan", dscp_class: "AF41",
      reloaded: true, rolled_back: false,
    });
  };
  const result = await addRouterSqmClientPolicy(baseInput);
  assert.equal(url, "/cgi-bin/luci/admin/services/quantumgrid/sqm-client-qos-add");
  assert.equal(init.method, "POST");
  assert.equal(init.credentials, "same-origin");
  assert.equal(init.cache, "no-store");
  const form = new URLSearchParams(init.body);
  assert.equal(form.get("mac"), baseInput.mac);
  assert.equal(form.get("source_zone"), "corp");
  assert.equal(form.get("destination_zone"), "wan");
  assert.equal(form.get("dscp_class"), "AF41");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.section, "cfg_client_1");
});

test("client QoS API rejects multicast MACs, malformed MACs, bad zones and arbitrary DSCP values before fetch", async () => {
  globalThis.fetch = async () => { throw new Error("fetch must not be called for invalid input"); };
  await assert.rejects(addRouterSqmClientPolicy({ ...baseInput, mac: "01:11:22:33:44:55" }), /unicast client MAC/);
  await assert.rejects(addRouterSqmClientPolicy({ ...baseInput, mac: "02:11:22:33:44:5g" }), /unicast client MAC/);
  await assert.rejects(addRouterSqmClientPolicy({ ...baseInput, sourceZone: "../firewall" }), /firewall zones/);
  await assert.rejects(addRouterSqmClientPolicy({ ...baseInput, dscpClass: "DSCP 46; flush" }), /supported DSCP class/);
});

test("client QoS API rejects mismatched router results", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true, section: "cfg_client_1", mac: "02:11:22:33:44:55",
    source_zone: "guest", destination_zone: "wan", dscp_class: "AF41",
    reloaded: true, rolled_back: false,
  });
  await assert.rejects(addRouterSqmClientPolicy(baseInput), /did not confirm the client DSCP rule/);
});

test("client QoS API propagates server-side conflicts", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: false, error: "A QuantumGrid policy already exists for this client and zone pair.",
  }, 409);
  await assert.rejects(addRouterSqmClientPolicy(baseInput), /already exists/);
});

test("client QoS API removes an owned policy and verifies firewall reload", async () => {
  let url = "";
  let init;
  globalThis.fetch = async (requestUrl, requestInit) => {
    url = String(requestUrl);
    init = requestInit;
    return jsonResponse({
      ok: true, section: "cfg_client_1", mac: "02:11:22:33:44:55",
      source_zone: "corp", destination_zone: "wan", dscp_class: "AF41",
      removed: true, reloaded: true, rolled_back: false,
    });
  };
  const result = await removeRouterSqmClientPolicy("cfg_client_1");
  assert.equal(url, "/cgi-bin/luci/admin/services/quantumgrid/sqm-client-qos-remove");
  assert.equal(init.method, "POST");
  assert.equal(init.credentials, "same-origin");
  assert.equal(new URLSearchParams(init.body).get("confirmed"), "1");
  assert.equal(result.removed, true);
  await assert.rejects(removeRouterSqmClientPolicy("../rule"), /Invalid client QoS firewall rule section/);
});

test("client QoS API refuses removal without confirmed firewall reload", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true, section: "cfg_client_1", mac: "02:11:22:33:44:55",
    source_zone: "corp", destination_zone: "wan", dscp_class: "AF41",
    removed: true, reloaded: false, rolled_back: false,
  });
  await assert.rejects(removeRouterSqmClientPolicy("cfg_client_1"), /did not confirm the client DSCP rule removal/);
});
