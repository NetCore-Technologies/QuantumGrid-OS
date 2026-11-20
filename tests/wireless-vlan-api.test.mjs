import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { updateRouterWirelessConfig } from "../ui/quantumgrid/src/routerApi.ts";

const originalFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = originalFetch; });

function jsonResponse(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json; charset=UTF-8" },
  });
}

const input = {
  radio: "radio0",
  section: "staff_ap",
  ssid: "Staff-Secure",
  network: "corp20",
  encryption: "wpa2",
  key: "",
  radiusServer: "radius.example.com",
  radiusPort: "1812",
  radiusSecret: "",
  accountingServer: "",
  accountingPort: "1813",
  accountingSecret: "",
  hidden: false,
  channel: "auto",
  htmode: "auto",
  txpower: "auto",
  allowOpen: false,
};

const success = {
  ok: true,
  radio: "radio0",
  section: "staff_ap",
  ssid: "Staff-Secure",
  network: "corp20",
  encryption: "wpa2",
  hidden: false,
  channel: "auto",
  htmode: "auto",
  txpower: "auto",
  key_set: false,
  radius_secret_set: true,
  accounting_secret_set: false,
  reloaded: true,
  rolled_back: false,
};

test("wireless AP update sends one explicit routed VLAN interface and verifies the result", async () => {
  let requestUrl = "";
  let requestInit;
  globalThis.fetch = async (url, init) => {
    requestUrl = String(url);
    requestInit = init;
    return jsonResponse(success);
  };
  const result = await updateRouterWirelessConfig(input);
  assert.equal(requestUrl, "/cgi-bin/luci/admin/services/quantumgrid/wireless-update");
  assert.equal(requestInit.method, "POST");
  assert.equal(requestInit.credentials, "same-origin");
  assert.equal(requestInit.cache, "no-store");
  const form = new URLSearchParams(requestInit.body);
  assert.equal(form.get("network"), "corp20");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.network, "corp20");
});

test("wireless AP update rejects unsafe or ambiguous network identifiers before fetch", async () => {
  globalThis.fetch = async () => { throw new Error("fetch must not be called for invalid input"); };
  await assert.rejects(updateRouterWirelessConfig({ ...input, network: "../wan" }), /routed network/);
  await assert.rejects(updateRouterWirelessConfig({ ...input, network: "corp;uci" }), /routed network/);
  await assert.rejects(updateRouterWirelessConfig({ ...input, network: "" }), /routed network/);
});

test("wireless AP update rejects a response bound to a different L3 network", async () => {
  globalThis.fetch = async () => jsonResponse({ ...success, network: "lan" });
  await assert.rejects(
    updateRouterWirelessConfig(input),
    /did not confirm the wireless configuration/,
  );
});

test("wireless AP update retains existing WPA3 PMF and RADIUS response verification", async () => {
  const wpa3Input = {
    ...input,
    encryption: "wpa3",
    accountingServer: "",
    radiusServer: "192.0.2.10",
    radiusSecret: "a-strong-radius-shared-secret",
  };
  globalThis.fetch = async () => jsonResponse({
    ...success,
    encryption: "wpa3",
    ieee80211w: "2",
    radius_secret_set: true,
  });
  const result = await updateRouterWirelessConfig(wpa3Input);
  assert.equal(result.network, "corp20");
});
