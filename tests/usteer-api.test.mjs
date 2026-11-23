import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { updateRouterUsteer } from "../ui/quantumgrid/src/routerApi.ts";

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

const baseInput = {
  enabled: true,
  network: "corp20",
  ssids: ["Corp"],
  aggressiveness: 1,
  bandSteeringInterval: 30000,
  bandSteeringMinSnr: -65,
  bandSteeringThreshold: 5,
  loadBalancingThreshold: 0,
};

const running = {
  ok: true,
  enabled: true,
  network: "corp20",
  ssid_list: ["Corp"],
  aggressiveness: 1,
  assoc_steering: false,
  probe_steering: false,
  band_steering_interval: 30000,
  band_steering_min_snr: -65,
  band_steering_threshold: 5,
  load_balancing_threshold: 0,
  status: "cluster",
  running: true,
  policy_verified: true,
  local_ess_verified: true,
  local_node_count: 2,
  remote_host_count: 2,
  associated_clients: 7,
  service_action_completed: true,
  rolled_back: false,
};

test("enables usteer using an authenticated same-origin request and verifies live cluster status", async () => {
  let requestUrl = "";
  let requestInit;
  globalThis.fetch = async (url, init) => {
    requestUrl = String(url);
    requestInit = init;
    return jsonResponse(running);
  };

  const result = await updateRouterUsteer(baseInput);
  assert.equal(requestUrl, "/cgi-bin/luci/admin/services/quantumgrid/usteer-update");
  assert.equal(requestInit.method, "POST");
  assert.equal(requestInit.credentials, "same-origin");
  assert.equal(requestInit.cache, "no-store");
  const form = new URLSearchParams(requestInit.body);
  assert.equal(form.get("enabled"), "1");
  assert.equal(form.get("network"), "corp20");
  assert.deepEqual(JSON.parse(form.get("ssids")), ["Corp"]);
  assert.equal(form.get("aggressiveness"), "1");
  assert.equal(form.get("assoc_steering"), "0");
  assert.equal(form.get("probe_steering"), "0");
  assert.equal(form.get("band_steering_interval"), "30000");
  assert.equal(form.get("band_steering_min_snr"), "-65");
  assert.equal(form.get("band_steering_threshold"), "5");
  assert.equal(form.get("load_balancing_threshold"), "0");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.status, "cluster");
  assert.equal(result.remote_host_count, 2);
  assert.equal(result.running, true);
});

test("roaming API rejects unsafe, duplicate and invalid policy before fetch", async () => {
  globalThis.fetch = async () => {
    throw new Error("fetch must not be called for invalid input");
  };
  await assert.rejects(updateRouterUsteer({ ...baseInput, network: "../wan" }), /trusted internal network/);
  await assert.rejects(updateRouterUsteer({ ...baseInput, ssids: [] }), /one and eight existing SSIDs/);
  await assert.rejects(updateRouterUsteer({ ...baseInput, ssids: ["Corp", "Corp"] }), /Duplicate roaming SSIDs/);
  await assert.rejects(updateRouterUsteer({ ...baseInput, ssids: ["Bad\nSSID"] }), /no control characters/);
  await assert.rejects(updateRouterUsteer({ ...baseInput, ssids: ["x".repeat(33)] }), /1–32 bytes/);
  await assert.rejects(updateRouterUsteer({ ...baseInput, aggressiveness: 4 }), /safe ranges/);
  await assert.rejects(updateRouterUsteer({ ...baseInput, bandSteeringInterval: 300001 }), /safe ranges/);
  await assert.rejects(updateRouterUsteer({ ...baseInput, bandSteeringMinSnr: -91 }), /safe ranges/);
  await assert.rejects(updateRouterUsteer({ ...baseInput, bandSteeringThreshold: 21 }), /safe ranges/);
  await assert.rejects(updateRouterUsteer({ ...baseInput, loadBalancingThreshold: 33 }), /safe ranges/);
});

test("roaming API rejects altered destination, SSID set, service state and rollback response", async () => {
  const invalid = [
    { ...running, network: "guest20" },
    { ...running, ssid_list: ["Guest"] },
    { ...running, running: false },
    { ...running, status: "review" },
    { ...running, policy_verified: false },
    { ...running, service_action_completed: false },
    { ...running, rolled_back: true },
  ];
  for (const response of invalid) {
    globalThis.fetch = async () => jsonResponse(response);
    await assert.rejects(
      updateRouterUsteer(baseInput),
      /did not confirm the exact roaming policy and requested usteer service state/,
    );
  }
});

test("local-only runtime is accepted but never reported as a remote cluster", async () => {
  globalThis.fetch = async () => jsonResponse({
    ...running,
    status: "local_only",
    remote_host_count: 0,
  });
  const result = await updateRouterUsteer(baseInput);
  assert.equal(result.status, "local_only");
  assert.equal(result.remote_host_count, 0);
});

test("disabling usteer accepts its persisted SSID list and confirms stopped state", async () => {
  let requestInit;
  globalThis.fetch = async (_url, init) => {
    requestInit = init;
    return jsonResponse({
      ...running,
      enabled: false,
      network: "corp20",
      ssid_list: ["Corp"],
      status: "disabled",
      running: false,
      policy_verified: false,
      local_ess_verified: false,
      local_node_count: 0,
      remote_host_count: 0,
      associated_clients: 0,
    });
  };
  const result = await updateRouterUsteer({
    ...baseInput,
    enabled: false,
    ssids: [],
  });
  assert.equal(new URLSearchParams(requestInit.body).get("enabled"), "0");
  assert.equal(result.status, "disabled");
  assert.equal(result.running, false);
  assert.deepEqual(result.ssid_list, ["Corp"]);
});
