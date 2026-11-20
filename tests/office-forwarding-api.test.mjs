import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import {
  createRouterOfficeForwarding,
  removeRouterOfficeForwarding,
} from "../ui/quantumgrid/src/routerApi.ts";

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

test("creating an inter-zone forwarding posts the selected direction and verifies firewall reload", async () => {
  let requestUrl = "";
  let requestInit;
  globalThis.fetch = async (url, init) => {
    requestUrl = String(url);
    requestInit = init;
    return jsonResponse({
      ok: true,
      section: "cfg-corp-wan",
      source: "corp",
      destination: "wan",
      reloaded: true,
      rolled_back: false,
    });
  };

  const result = await createRouterOfficeForwarding({ source: "corp", destination: "wan" });
  assert.equal(requestUrl, "/cgi-bin/luci/admin/services/quantumgrid/office-forwarding-add");
  assert.equal(requestInit.method, "POST");
  assert.equal(requestInit.credentials, "same-origin");
  assert.equal(requestInit.cache, "no-store");
  const form = new URLSearchParams(requestInit.body);
  assert.equal(form.get("source"), "corp");
  assert.equal(form.get("destination"), "wan");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.section, "cfg-corp-wan");
});

test("forwarding creation rejects invalid and identical zones before fetch", async () => {
  globalThis.fetch = async () => {
    throw new Error("fetch must not be called for invalid input");
  };
  await assert.rejects(
    createRouterOfficeForwarding({ source: "../wan", destination: "corp" }),
    /valid existing firewall zones/,
  );
  await assert.rejects(
    createRouterOfficeForwarding({ source: "corp", destination: "corp" }),
    /must be different/,
  );
});

test("forwarding creation rejects a response with a different policy direction", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true,
    section: "cfg-corp-wan",
    source: "guest",
    destination: "lan",
    reloaded: true,
    rolled_back: false,
  });
  await assert.rejects(
    createRouterOfficeForwarding({ source: "corp", destination: "wan" }),
    /did not confirm the firewall forwarding and reload/,
  );
});

test("removing an inter-zone forwarding verifies section identity and reload completion", async () => {
  let requestUrl = "";
  let requestInit;
  globalThis.fetch = async (url, init) => {
    requestUrl = String(url);
    requestInit = init;
    return jsonResponse({
      ok: true,
      section: "cfg-corp-wan",
      source: "corp",
      destination: "wan",
      removed: true,
      reloaded: true,
      rolled_back: false,
    });
  };
  const result = await removeRouterOfficeForwarding("cfg-corp-wan");
  assert.equal(requestUrl, "/cgi-bin/luci/admin/services/quantumgrid/office-forwarding-remove");
  assert.equal(requestInit.method, "POST");
  const form = new URLSearchParams(requestInit.body);
  assert.equal(form.get("section"), "cfg-corp-wan");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.removed, true);
  await assert.rejects(removeRouterOfficeForwarding("../firewall"), /Invalid firewall forwarding section/);
});

test("forwarding removal rejects a response without confirmed reload", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true,
    section: "cfg-corp-wan",
    source: "corp",
    destination: "wan",
    removed: true,
    reloaded: false,
    rolled_back: false,
  });
  await assert.rejects(
    removeRouterOfficeForwarding("cfg-corp-wan"),
    /did not confirm firewall forwarding removal/,
  );
});
