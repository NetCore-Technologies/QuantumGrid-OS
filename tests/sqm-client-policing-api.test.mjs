import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import {
  getRouterSqmClientPolicingStatus,
  addRouterSqmClientPolicingPolicy,
  removeRouterSqmClientPolicingPolicy,
} from "../ui/quantumgrid/src/routerApi.ts";

const originalFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = originalFetch; });

function jsonResponse(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json; charset=UTF-8" },
  });
}

const policy = {
  section: "qg_rate_01",
  slot: 1,
  name: "desktop",
  mac: "02:11:22:33:44:55",
  client_ip: "192.168.20.40",
  source_zone: "fiber-edge",
  destination_zone: "corp",
  upload_kbps: 25000,
  download_kbps: 100000,
  devices: ["pppoe-wan"],
  enabled: true,
  policing: true,
};

test("loads saved client policers and runtime status without caching", async () => {
  let url = "";
  let init;
  globalThis.fetch = async (target, options) => {
    url = String(target);
    init = options;
    return jsonResponse({
      ok: true,
      available: true,
      inventory_available: true,
      policies: [policy],
      runtime: {
        available: true,
        ready: true,
        policing_mode: "drop_excess",
        policy_count: 1,
        applied_filter_count: 2,
        sampled_at: 1790000000,
        stale: false,
        notice: "TC police drops packets over the configured cap.",
      },
    });
  };
  const result = await getRouterSqmClientPolicingStatus();
  assert.equal(url, "/cgi-bin/luci/admin/services/quantumgrid/client-policing");
  assert.equal(init.method, "GET");
  assert.equal(init.credentials, "same-origin");
  assert.equal(init.cache, "no-store");
  assert.equal(result.inventory_available, true);
  assert.deepEqual(result.policies[0], policy);
  assert.equal(result.runtime?.ready, true);
  assert.equal(result.runtime?.policing_mode, "drop_excess");
});

test("adds a static-reservation client policer and verifies live TC application", async () => {
  let url = "";
  let init;
  globalThis.fetch = async (target, options) => {
    url = String(target);
    init = options;
    return jsonResponse({
      ok: true,
      section: "qg_rate_01",
      slot: 1,
      mac: "02:11:22:33:44:55",
      client_ip: "192.168.20.40",
      upload_kbps: 25000,
      download_kbps: 100000,
      devices: ["pppoe-wan", "wwan0"],
      mode: "drop_excess",
      runtime_verified: true,
    });
  };
  const result = await addRouterSqmClientPolicingPolicy({
    mac: "02:11:22:33:44:55",
    clientIp: "192.168.20.40",
    sourceZone: "fiber-edge",
    destinationZone: "corp",
    uploadKbps: "25000",
    downloadKbps: "100000",
    name: "desktop",
  });
  assert.equal(url, "/cgi-bin/luci/admin/services/quantumgrid/client-policing");
  assert.equal(init.method, "POST");
  assert.equal(init.credentials, "same-origin");
  assert.equal(init.cache, "no-store");
  const form = new URLSearchParams(init.body);
  assert.equal(form.get("operation"), "add");
  assert.equal(form.get("mac"), "02:11:22:33:44:55");
  assert.equal(form.get("client_ip"), "192.168.20.40");
  assert.equal(form.get("upload_kbps"), "25000");
  assert.equal(form.get("download_kbps"), "100000");
  assert.equal(form.get("confirmed"), "1");
  assert.deepEqual(result.devices, ["pppoe-wan", "wwan0"]);
  assert.equal(result.runtime_verified, true);
  assert.equal(result.mode, "drop_excess");
});

test("adds an upload-only or download-only cap but requires at least one rate", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true,
    section: "qg_rate_02",
    slot: 2,
    mac: "02:11:22:33:44:55",
    client_ip: "192.168.20.40",
    upload_kbps: 64,
    devices: ["pppoe-wan"],
    mode: "drop_excess",
    runtime_verified: true,
  });
  const result = await addRouterSqmClientPolicingPolicy({
    mac: "02:11:22:33:44:55",
    clientIp: "192.168.20.40",
    sourceZone: "fiber-edge",
    destinationZone: "corp",
    uploadKbps: "64",
    downloadKbps: "",
  });
  assert.equal(result.upload_kbps, 64);
  assert.equal(result.download_kbps, undefined);
  await assert.rejects(addRouterSqmClientPolicingPolicy({
    mac: "02:11:22:33:44:55",
    clientIp: "192.168.20.40",
    sourceZone: "fiber-edge",
    destinationZone: "corp",
    uploadKbps: "",
    downloadKbps: "",
  }), /Set an upload cap/);
});

test("rejects malformed identities, command-like rates, and invalid bounds before fetch", async () => {
  globalThis.fetch = async () => { throw new Error("fetch must not run for invalid input"); };
  const base = {
    mac: "02:11:22:33:44:55",
    clientIp: "192.168.20.40",
    sourceZone: "fiber-edge",
    destinationZone: "corp",
    uploadKbps: "1000",
    downloadKbps: "",
  };
  await assert.rejects(addRouterSqmClientPolicingPolicy({ ...base, mac: "01:11:22:33:44:55" }), /unicast client MAC/);
  await assert.rejects(addRouterSqmClientPolicingPolicy({ ...base, clientIp: "192.168.20.999" }), /valid reserved client IPv4/);
  await assert.rejects(addRouterSqmClientPolicingPolicy({ ...base, uploadKbps: "63" }), /between 64 and 1000000/);
  await assert.rejects(addRouterSqmClientPolicingPolicy({ ...base, uploadKbps: "1000;reboot" }), /whole numbers/);
  await assert.rejects(addRouterSqmClientPolicingPolicy({ ...base, sourceZone: "../wan" }), /firewall zones/);
});

test("removes an owned policer only after router runtime verification", async () => {
  let url = "";
  let init;
  globalThis.fetch = async (target, options) => {
    url = String(target);
    init = options;
    return jsonResponse({ ok: true, section: "qg_rate_01", removed: true, runtime_verified: true });
  };
  const result = await removeRouterSqmClientPolicingPolicy("qg_rate_01");
  assert.equal(url, "/cgi-bin/luci/admin/services/quantumgrid/client-policing");
  assert.equal(init.method, "POST");
  assert.equal(init.credentials, "same-origin");
  const form = new URLSearchParams(init.body);
  assert.equal(form.get("operation"), "remove");
  assert.equal(form.get("section"), "qg_rate_01");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.removed, true);
  await assert.rejects(removeRouterSqmClientPolicingPolicy("../rule"), /valid QuantumGrid/);
});

test("rejects runtime mismatches and propagates server conflicts", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true, section: "qg_rate_01", slot: 1,
    mac: "02:11:22:33:44:55", client_ip: "192.168.20.40",
    upload_kbps: 25000, download_kbps: 100000,
    devices: ["pppoe-wan"], mode: "drop_excess", runtime_verified: false,
  });
  await assert.rejects(addRouterSqmClientPolicingPolicy({
    mac: "02:11:22:33:44:55", clientIp: "192.168.20.40",
    sourceZone: "fiber-edge", destinationZone: "corp",
    uploadKbps: "25000", downloadKbps: "100000",
  }), /did not confirm/);

  globalThis.fetch = async () => jsonResponse({ ok: false, error: "A client bandwidth policy already exists." }, 409);
  await assert.rejects(addRouterSqmClientPolicingPolicy({
    mac: "02:11:22:33:44:55", clientIp: "192.168.20.40",
    sourceZone: "fiber-edge", destinationZone: "corp",
    uploadKbps: "25000", downloadKbps: "",
  }), /already exists/);
});
