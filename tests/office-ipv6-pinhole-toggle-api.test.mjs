import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { setRouterOfficeIpv6PinholeEnabled } from "../ui/quantumgrid/src/routerApi.ts";

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

test("disables a managed IPv6 pinhole with explicit confirmation and checked reload", async () => {
  let requestUrl = "";
  let requestInit;
  globalThis.fetch = async (url, init) => {
    requestUrl = String(url);
    requestInit = init;
    return jsonResponse({
      ok: true,
      section: "cfg_ipv6_https",
      enabled: false,
      changed: true,
      reloaded: true,
      rolled_back: false,
    });
  };
  const result = await setRouterOfficeIpv6PinholeEnabled("cfg_ipv6_https", false);
  assert.equal(requestUrl, "/cgi-bin/luci/admin/services/quantumgrid/office-ipv6-pinhole-toggle");
  assert.equal(requestInit.method, "POST");
  assert.equal(requestInit.credentials, "same-origin");
  assert.equal(requestInit.cache, "no-store");
  const form = new URLSearchParams(requestInit.body);
  assert.equal(form.get("section"), "cfg_ipv6_https");
  assert.equal(form.get("enabled"), "0");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.enabled, false);
  assert.equal(result.changed, true);
  assert.equal(result.reloaded, true);
});

test("enables a managed IPv6 pinhole and supports idempotent no-op confirmation", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true,
    section: "cfg_ipv6_https",
    enabled: true,
    changed: false,
    reloaded: false,
    rolled_back: false,
  });
  const result = await setRouterOfficeIpv6PinholeEnabled("cfg_ipv6_https", true);
  assert.equal(result.enabled, true);
  assert.equal(result.changed, false);
  assert.equal(result.reloaded, false);
});

test("pinhole toggle rejects unsafe section names before fetch", async () => {
  globalThis.fetch = async () => {
    throw new Error("fetch must not be called for invalid input");
  };
  await assert.rejects(
    setRouterOfficeIpv6PinholeEnabled("../firewall", true),
    /Invalid firewall IPv6 pinhole section/,
  );
});

test("pinhole toggle rejects incomplete, mismatched and unverified rollback responses", async () => {
  const responses = [
    { ok: true, section: "cfg_ipv6_https", enabled: false, changed: true, reloaded: false, rolled_back: false },
    { ok: true, section: "cfg_other", enabled: false, changed: true, reloaded: true, rolled_back: false },
    { ok: true, section: "cfg_ipv6_https", enabled: false, changed: true, reloaded: true, rolled_back: true },
    { ok: true, section: "cfg_ipv6_https", enabled: false, changed: false, reloaded: true, rolled_back: false },
  ];
  for (const payload of responses) {
    globalThis.fetch = async () => jsonResponse(payload);
    await assert.rejects(
      setRouterOfficeIpv6PinholeEnabled("cfg_ipv6_https", false),
      /did not confirm the requested IPv6 pinhole state/,
    );
  }
});

test("pinhole toggle never accepts an implicit desired state", async () => {
  globalThis.fetch = async () => {
    throw new Error("fetch must not be called for invalid input");
  };
  await assert.rejects(
    setRouterOfficeIpv6PinholeEnabled("cfg_ipv6_https", "false"),
    /explicit enabled state/,
  );
});
