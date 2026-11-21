import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { updateRouterCakeProfile } from "../ui/quantumgrid/src/routerApi.ts";

const originalFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = originalFetch; });

function jsonResponse(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status, headers: { "Content-Type": "application/json; charset=UTF-8" },
  });
}

test("CAKE profile API posts selected queue and confirms SQM restart", async () => {
  let requestUrl = "";
  let requestInit;
  globalThis.fetch = async (url, init) => {
    requestUrl = String(url); requestInit = init;
    return jsonResponse({ ok: true, section: "wan_main", profile: "diffserv4", restarted: true, rolled_back: false });
  };
  const result = await updateRouterCakeProfile("wan_main", "diffserv4");
  assert.equal(requestUrl, "/cgi-bin/luci/admin/services/quantumgrid/sqm-cake-profile");
  assert.equal(requestInit.method, "POST");
  assert.equal(requestInit.credentials, "same-origin");
  assert.equal(requestInit.cache, "no-store");
  const form = new URLSearchParams(requestInit.body);
  assert.equal(form.get("section"), "wan_main");
  assert.equal(form.get("profile"), "diffserv4");
  assert.equal(result.profile, "diffserv4");
});

test("CAKE profile API rejects invalid sections and unsupported profiles before fetch", async () => {
  globalThis.fetch = async () => { throw new Error("fetch must not run for invalid input"); };
  await assert.rejects(updateRouterCakeProfile("../sqm", "diffserv4"), /Invalid SQM queue section/);
  await assert.rejects(updateRouterCakeProfile("wan_main", "custom"), /supported CAKE profile/);
  await assert.rejects(updateRouterCakeProfile("wan_main", "diffserv3"), /supported CAKE profile/);
});

test("CAKE profile API propagates router-side validation errors", async () => {
  globalThis.fetch = async () => jsonResponse({ ok: false, error: "CAKE profiles can only be applied to an existing CAKE queue." }, 409);
  await assert.rejects(updateRouterCakeProfile("wan_main", "diffserv4"), /existing CAKE queue/);
});

test("CAKE profile API refuses responses without confirmed restart", async () => {
  globalThis.fetch = async () => jsonResponse({ ok: true, section: "wan_main", profile: "diffserv4", restarted: false, rolled_back: false });
  await assert.rejects(updateRouterCakeProfile("wan_main", "diffserv4"), /did not confirm the CAKE profile update/);
});
