import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { updateRouterOfficeZonePolicy } from "../ui/quantumgrid/src/routerApi.ts";

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

test("zone policy update sends output, forward and masquerade while requiring input preservation", async () => {
  let requestUrl = "";
  let requestInit;
  globalThis.fetch = async (url, init) => {
    requestUrl = String(url);
    requestInit = init;
    return jsonResponse({
      ok: true,
      section: "cfg_corp",
      name: "corp",
      input: "REJECT",
      output: "REJECT",
      forward: "DROP",
      masquerade: false,
      input_unchanged: true,
      reloaded: true,
      rolled_back: false,
    });
  };

  const result = await updateRouterOfficeZonePolicy({
    section: "cfg_corp",
    output: "REJECT",
    forward: "DROP",
    masquerade: false,
  });
  assert.equal(requestUrl, "/cgi-bin/luci/admin/services/quantumgrid/office-zone-update");
  assert.equal(requestInit.method, "POST");
  assert.equal(requestInit.credentials, "same-origin");
  assert.equal(requestInit.cache, "no-store");
  const form = new URLSearchParams(requestInit.body);
  assert.equal(form.get("section"), "cfg_corp");
  assert.equal(form.get("output"), "REJECT");
  assert.equal(form.get("forward"), "DROP");
  assert.equal(form.get("masquerade"), "0");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.input_unchanged, true);
});

test("zone policy API preserves explicit inherited and unchanged states", async () => {
  let posted = "";
  globalThis.fetch = async (_url, init) => {
    posted = init.body;
    return jsonResponse({
      ok: true,
      section: "cfg_guest",
      name: "guest",
      input: "REJECT",
      output: "",
      forward: "REJECT",
      masquerade: true,
      input_unchanged: true,
      reloaded: true,
      rolled_back: false,
    });
  };
  await updateRouterOfficeZonePolicy({
    section: "cfg_guest",
    output: "INHERIT",
    forward: "UNCHANGED",
    masquerade: true,
  });
  const form = new URLSearchParams(posted);
  assert.equal(form.get("output"), "INHERIT");
  assert.equal(form.get("forward"), "UNCHANGED");
});

test("zone policy API rejects invalid section and policy inputs before fetch", async () => {
  globalThis.fetch = async () => {
    throw new Error("fetch must not be called for invalid input");
  };
  await assert.rejects(
    updateRouterOfficeZonePolicy({
      section: "../firewall",
      output: "REJECT",
      forward: "REJECT",
      masquerade: false,
    }),
    /Invalid firewall zone section/,
  );
  await assert.rejects(
    updateRouterOfficeZonePolicy({
      section: "cfg_corp",
      output: "ACCEPT;uci",
      forward: "REJECT",
      masquerade: false,
    }),
    /must be unchanged, inherited, ACCEPT, REJECT or DROP/,
  );
});

test("zone policy API rejects a response that claims router INPUT was changed", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true,
    section: "cfg_corp",
    name: "corp",
    input: "ACCEPT",
    output: "REJECT",
    forward: "REJECT",
    masquerade: false,
    input_unchanged: false,
    reloaded: true,
    rolled_back: false,
  });
  await assert.rejects(
    updateRouterOfficeZonePolicy({
      section: "cfg_corp",
      output: "REJECT",
      forward: "REJECT",
      masquerade: false,
    }),
    /input preservation and firewall reload/,
  );
});

test("zone policy API rejects responses without successful firewall reload", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true,
    section: "cfg_corp",
    name: "corp",
    input: "REJECT",
    output: "REJECT",
    forward: "REJECT",
    masquerade: false,
    input_unchanged: true,
    reloaded: false,
    rolled_back: false,
  });
  await assert.rejects(
    updateRouterOfficeZonePolicy({
      section: "cfg_corp",
      output: "REJECT",
      forward: "REJECT",
      masquerade: false,
    }),
    /input preservation and firewall reload/,
  );
});
