import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { updateRouterMwan3Interface, updateRouterMwan3Member } from "../ui/quantumgrid/src/routerApi.ts";

const originalFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = originalFetch; });

function jsonResponse(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json; charset=UTF-8" },
  });
}

const input = {
  section: "wan",
  enabled: true,
  trackIps: ["1.1.1.1", "2606:4700:4700::1111"],
  reliability: 2,
  count: 2,
  timeout: 3,
  interval: 5,
  down: 3,
  up: 5,
  initialState: "online" as const,
  confirmed: true,
};

function responseFor(values = input) {
  return {
    ok: true,
    section: values.section,
    enabled: values.enabled,
    track_ips: values.trackIps,
    reliability: values.reliability,
    count: values.count,
    timeout: values.timeout,
    interval: values.interval,
    down: values.down,
    up: values.up,
    initial_state: values.initialState,
    restarted: true,
    rolled_back: false,
  };
}

test("Multi-WAN API submits confirmed existing-interface health settings and verifies restart", async () => {
  let requestUrl = "";
  let requestInit: RequestInit | undefined;
  globalThis.fetch = async (url, init) => {
    requestUrl = String(url);
    requestInit = init;
    return jsonResponse(responseFor());
  };
  const result = await updateRouterMwan3Interface(
    input.section, input.enabled, input.trackIps, input.reliability, input.count,
    input.timeout, input.interval, input.down, input.up, input.initialState, input.confirmed,
  );
  assert.equal(requestUrl, "/cgi-bin/luci/admin/services/quantumgrid/mwan3-interface-update");
  assert.equal(requestInit?.method, "POST");
  assert.equal(requestInit?.credentials, "same-origin");
  assert.equal(requestInit?.cache, "no-store");
  const form = new URLSearchParams(String(requestInit?.body));
  assert.equal(form.get("section"), "wan");
  assert.equal(form.get("enabled"), "1");
  assert.deepEqual(JSON.parse(form.get("track_ips") ?? "[]"), input.trackIps);
  assert.equal(form.get("reliability"), "2");
  assert.equal(form.get("count"), "2");
  assert.equal(form.get("timeout"), "3");
  assert.equal(form.get("interval"), "5");
  assert.equal(form.get("down"), "3");
  assert.equal(form.get("up"), "5");
  assert.equal(form.get("initial_state"), "online");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.restarted, true);
});

test("Multi-WAN API rejects unconfirmed changes before network access", async () => {
  globalThis.fetch = async () => { throw new Error("fetch must not run"); };
  await assert.rejects(
    updateRouterMwan3Interface(
      input.section, input.enabled, input.trackIps, input.reliability, input.count,
      input.timeout, input.interval, input.down, input.up, input.initialState, false,
    ),
    /Confirm the Multi-WAN health-check change/,
  );
});

test("Multi-WAN API rejects unsafe sections, targets, duplicates and invalid probe ranges", async () => {
  globalThis.fetch = async () => { throw new Error("fetch must not run for invalid input"); };
  const run = (patch: Partial<typeof input>) => {
    const value = { ...input, ...patch };
    return updateRouterMwan3Interface(
      value.section, value.enabled, value.trackIps, value.reliability, value.count,
      value.timeout, value.interval, value.down, value.up, value.initialState, value.confirmed,
    );
  };
  await assert.rejects(run({ section: "../network" }), /section name/);
  await assert.rejects(run({ trackIps: ["1.1.1.1", "1.1.1.1"] }), /unique/);
  await assert.rejects(run({ trackIps: ["not-an-ip"] }), /tracking addresses/);
  await assert.rejects(run({ reliability: 3 }), /Reliability/);
  await assert.rejects(run({ timeout: 0 }), /Probe timeout/);
  await assert.rejects(run({ interval: 61 }), /Probe interval/);
  await assert.rejects(run({ down: 21 }), /Failure threshold/);
  await assert.rejects(run({ up: 0 }), /Recovery threshold/);
});

test("Multi-WAN API propagates router-side conflicts and service errors", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: false,
    error: "Only an existing mwan3 interface section can be edited.",
  }, 404);
  await assert.rejects(
    updateRouterMwan3Interface(
      input.section, input.enabled, input.trackIps, input.reliability, input.count,
      input.timeout, input.interval, input.down, input.up, input.initialState, true,
    ),
    /Only an existing mwan3 interface/,
  );
});

test("Multi-WAN API rejects incomplete or mismatched router confirmations", async () => {
  globalThis.fetch = async () => jsonResponse({ ...responseFor(), interval: 30 });
  await assert.rejects(
    updateRouterMwan3Interface(
      input.section, input.enabled, input.trackIps, input.reliability, input.count,
      input.timeout, input.interval, input.down, input.up, input.initialState, true,
    ),
    /did not confirm the Multi-WAN health-check update/,
  );
});


test("Multi-WAN member API updates an existing member's interface, metric and weight with confirmed restart", async () => {
  let requestUrl = "";
  let requestInit: RequestInit | undefined;
  globalThis.fetch = async (url, init) => {
    requestUrl = String(url);
    requestInit = init;
    return jsonResponse({
      ok: true, section: "wan_m1_w3", interface: "wan", metric: 1, weight: 3,
      restarted: true, rolled_back: false,
    });
  };
  const result = await updateRouterMwan3Member("wan_m1_w3", "wan", 1, 3, true);
  assert.equal(requestUrl, "/cgi-bin/luci/admin/services/quantumgrid/mwan3-member-update");
  assert.equal(requestInit?.method, "POST");
  assert.equal(requestInit?.credentials, "same-origin");
  assert.equal(requestInit?.cache, "no-store");
  const form = new URLSearchParams(String(requestInit?.body));
  assert.equal(form.get("section"), "wan_m1_w3");
  assert.equal(form.get("interface"), "wan");
  assert.equal(form.get("metric"), "1");
  assert.equal(form.get("weight"), "3");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.restarted, true);
  assert.equal(result.rolled_back, false);
});

test("Multi-WAN member API rejects unsafe sections, interfaces and out-of-range metrics/weights before fetch", async () => {
  globalThis.fetch = async () => { throw new Error("fetch must not run for invalid member values"); };
  await assert.rejects(updateRouterMwan3Member("../member", "wan", 1, 1, true), /section name/);
  await assert.rejects(updateRouterMwan3Member("wan_m1_w3", "../wan", 1, 1, true), /existing mwan3 interface/);
  await assert.rejects(updateRouterMwan3Member("wan_m1_w3", "wan", 0, 1, true), /metric/);
  await assert.rejects(updateRouterMwan3Member("wan_m1_w3", "wan", 256, 1, true), /metric/);
  await assert.rejects(updateRouterMwan3Member("wan_m1_w3", "wan", 1, 0, true), /weight/);
  await assert.rejects(updateRouterMwan3Member("wan_m1_w3", "wan", 1, 101, true), /weight/);
  await assert.rejects(updateRouterMwan3Member("wan_m1_w3", "wan", 1, 1, false), /Confirm the Multi-WAN member/);
});

test("Multi-WAN member API rejects unconfirmed or mismatched router restart responses", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true, section: "wan_m1_w3", interface: "wan", metric: 2, weight: 3,
    restarted: true, rolled_back: false,
  });
  await assert.rejects(updateRouterMwan3Member("wan_m1_w3", "wan", 1, 3, true), /did not confirm/);
  globalThis.fetch = async () => jsonResponse({ ok: false, error: "mwan3 restart failed." }, 502);
  await assert.rejects(updateRouterMwan3Member("wan_m1_w3", "wan", 1, 3, true), /mwan3 restart failed/);
});
