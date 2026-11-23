import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { getRouterNetworkTuning, updateRouterNetworkTuning } from "../ui/quantumgrid/src/routerApi.ts";

const originalFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = originalFetch; });
function jsonResponse(payload, status = 200) {
  return new Response(JSON.stringify(payload), { status, headers: { "Content-Type": "application/json; charset=UTF-8" } });
}
const inventory = {
  available: true, congestion_controls: ["bbr", "cubic", "reno"], current_congestion_control: "bbr",
  default_qdiscs: ["cake", "fq", "fq_codel"], current_default_qdisc: "fq_codel", runtime_only: true,
};

test("loads kernel-reported network tuning choices using authenticated no-store GET", async () => {
  let url = ""; let init;
  globalThis.fetch = async (target, options) => {
    url = String(target); init = options;
    return jsonResponse({ ok: true, available: true, inventory });
  };
  const result = await getRouterNetworkTuning();
  assert.equal(url, "/cgi-bin/luci/admin/services/quantumgrid/network-tuning");
  assert.equal(init.method, "GET"); assert.equal(init.credentials, "same-origin"); assert.equal(init.cache, "no-store");
  assert.deepEqual(result, inventory);
});

test("updates allowlisted kernel settings with explicit same-origin confirmation", async () => {
  let url = ""; let init;
  globalThis.fetch = async (target, options) => {
    url = String(target); init = options;
    return jsonResponse({ ok: true, changed: true, congestion_control: "cubic",
      default_qdisc: "cake", runtime_only: true, reloaded: false, rolled_back: false });
  };
  const result = await updateRouterNetworkTuning({ congestionControl: "cubic", defaultQdisc: "cake" });
  assert.equal(url, "/cgi-bin/luci/admin/services/quantumgrid/network-tuning");
  assert.equal(init.method, "POST"); assert.equal(init.credentials, "same-origin"); assert.equal(init.cache, "no-store");
  const form = new URLSearchParams(init.body);
  assert.equal(form.get("congestion_control"), "cubic");
  assert.equal(form.get("default_qdisc"), "cake");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.changed, true); assert.equal(result.runtime_only, true); assert.equal(result.reloaded, false);
});

test("rejects command-like values and malformed kernel response allow-lists", async () => {
  globalThis.fetch = async () => { throw new Error("fetch must not run for unsafe choices"); };
  await assert.rejects(updateRouterNetworkTuning({ congestionControl: "bbr;reboot", defaultQdisc: "cake" }), /kernel allow-lists/);
  await assert.rejects(updateRouterNetworkTuning({ congestionControl: "bbr", defaultQdisc: "../cake" }), /kernel allow-lists/);
  globalThis.fetch = async () => jsonResponse({ ok: true, available: true, inventory: { ...inventory, default_qdiscs: ["cake; reboot"] } });
  await assert.rejects(getRouterNetworkTuning(), /qdisc allow-list/);
});
