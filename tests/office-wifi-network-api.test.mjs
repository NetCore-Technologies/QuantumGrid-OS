import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { updateRouterOfficeWifiNetwork } from "../ui/quantumgrid/src/routerApi.ts";

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

test("SSID network update posts one selected office network and confirms Wi-Fi reload", async () => {
  let requestUrl = "";
  let requestInit;
  globalThis.fetch = async (url, init) => {
    requestUrl = String(url);
    requestInit = init;
    return jsonResponse({
      ok: true,
      section: "corp_ap",
      ssid: "Office-Corp",
      network: "corp",
      networks: ["corp"],
      reloaded: true,
      rolled_back: false,
    });
  };
  const result = await updateRouterOfficeWifiNetwork({
    section: "corp_ap",
    network: "corp",
  });
  assert.equal(requestUrl, "/cgi-bin/luci/admin/services/quantumgrid/office-wifi-network-update");
  assert.equal(requestInit.method, "POST");
  assert.equal(requestInit.credentials, "same-origin");
  assert.equal(requestInit.cache, "no-store");
  const form = new URLSearchParams(requestInit.body);
  assert.equal(form.get("section"), "corp_ap");
  assert.equal(form.get("network"), "corp");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.network, "corp");
});

test("SSID network API rejects invalid UCI section and interface identifiers before fetch", async () => {
  globalThis.fetch = async () => {
    throw new Error("fetch must not be called for invalid input");
  };
  await assert.rejects(
    updateRouterOfficeWifiNetwork({ section: "../wireless", network: "corp" }),
    /Invalid wireless AP section/,
  );
  await assert.rejects(
    updateRouterOfficeWifiNetwork({ section: "corp_ap", network: "../network" }),
    /existing office LAN\/VLAN network/,
  );
});

test("SSID network API rejects a response that binds multiple networks", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true,
    section: "corp_ap",
    ssid: "Office-Corp",
    network: "corp",
    networks: ["corp", "guest"],
    reloaded: true,
    rolled_back: false,
  });
  await assert.rejects(
    updateRouterOfficeWifiNetwork({ section: "corp_ap", network: "corp" }),
    /did not confirm the SSID network binding/,
  );
});

test("SSID network API accepts an already-correct binding without requiring reload", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true,
    section: "guest_ap",
    ssid: "Office-Guest",
    network: "guest",
    networks: ["guest"],
    reloaded: false,
    rolled_back: false,
  });
  const result = await updateRouterOfficeWifiNetwork({ section: "guest_ap", network: "guest" });
  assert.equal(result.reloaded, false);
});

test("SSID network API refuses a result with unconfirmed rollback state", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true,
    section: "corp_ap",
    ssid: "Office-Corp",
    network: "corp",
    networks: ["corp"],
    reloaded: true,
    rolled_back: true,
  });
  await assert.rejects(
    updateRouterOfficeWifiNetwork({ section: "corp_ap", network: "corp" }),
    /did not confirm the SSID network binding/,
  );
});
