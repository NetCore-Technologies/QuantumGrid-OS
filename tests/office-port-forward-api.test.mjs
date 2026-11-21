import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import {
  createRouterOfficePortForward,
  removeRouterOfficePortForward,
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

const baseInput = {
  name: "office-https",
  source: "wan",
  destination: "corp",
  protocol: "tcp",
  sourcePort: "443",
  destinationIp: "192.168.20.30",
  destinationPort: "8443",
};

test("creates a WAN-to-LAN DNAT rule and verifies firewall reload", async () => {
  let requestUrl = "";
  let requestInit;
  globalThis.fetch = async (url, init) => {
    requestUrl = String(url);
    requestInit = init;
    return jsonResponse({
      ok: true,
      section: "cfg443",
      name: "office-https",
      source: "wan",
      destination: "corp",
      protocol: "tcp",
      source_port: 443,
      destination_ip: "192.168.20.30",
      destination_port: 8443,
      reloaded: true,
      rolled_back: false,
    });
  };
  const result = await createRouterOfficePortForward(baseInput);
  assert.equal(requestUrl, "/cgi-bin/luci/admin/services/quantumgrid/office-port-forward-add");
  assert.equal(requestInit.method, "POST");
  assert.equal(requestInit.credentials, "same-origin");
  assert.equal(requestInit.cache, "no-store");
  const form = new URLSearchParams(requestInit.body);
  assert.equal(form.get("name"), "office-https");
  assert.equal(form.get("source"), "wan");
  assert.equal(form.get("destination"), "corp");
  assert.equal(form.get("protocol"), "tcp");
  assert.equal(form.get("source_port"), "443");
  assert.equal(form.get("destination_ip"), "192.168.20.30");
  assert.equal(form.get("destination_port"), "8443");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.section, "cfg443");
});

test("port-forward API rejects malformed names, zones, ports and protocols before fetch", async () => {
  globalThis.fetch = async () => {
    throw new Error("fetch must not be called for invalid input");
  };
  await assert.rejects(createRouterOfficePortForward({ ...baseInput, name: "../rule" }), /valid rule name/);
  await assert.rejects(createRouterOfficePortForward({ ...baseInput, source: "wan;uci" }), /valid rule name/);
  await assert.rejects(createRouterOfficePortForward({ ...baseInput, protocol: "icmp" }), /Protocol must be TCP/);
  await assert.rejects(createRouterOfficePortForward({ ...baseInput, sourcePort: "0" }), /ports must be whole numbers/);
  await assert.rejects(createRouterOfficePortForward({ ...baseInput, destinationPort: "65536" }), /ports must be whole numbers/);
  await assert.rejects(createRouterOfficePortForward({ ...baseInput, destinationIp: "192.168.020.30" }), /valid dotted-decimal IPv4/);
});

test("port-forward API rejects a response for a different destination", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true,
    section: "cfg443",
    name: "office-https",
    source: "wan",
    destination: "guest",
    protocol: "tcp",
    source_port: 443,
    destination_ip: "192.168.20.30",
    destination_port: 8443,
    reloaded: true,
    rolled_back: false,
  });
  await assert.rejects(createRouterOfficePortForward(baseInput), /did not confirm the WAN port-forward/);
});

test("removes a port-forward and verifies firewall reload", async () => {
  let requestUrl = "";
  let requestInit;
  globalThis.fetch = async (url, init) => {
    requestUrl = String(url);
    requestInit = init;
    return jsonResponse({
      ok: true,
      section: "cfg443",
      removed: true,
      reloaded: true,
      rolled_back: false,
    });
  };
  const result = await removeRouterOfficePortForward("cfg443");
  assert.equal(requestUrl, "/cgi-bin/luci/admin/services/quantumgrid/office-port-forward-remove");
  assert.equal(requestInit.method, "POST");
  assert.equal(new URLSearchParams(requestInit.body).get("section"), "cfg443");
  assert.equal(new URLSearchParams(requestInit.body).get("confirmed"), "1");
  assert.equal(result.removed, true);
  await assert.rejects(removeRouterOfficePortForward("../firewall"), /Invalid firewall redirect section/);
});

test("port-forward removal rejects an unconfirmed service reload", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true,
    section: "cfg443",
    removed: true,
    reloaded: false,
    rolled_back: false,
  });
  await assert.rejects(removeRouterOfficePortForward("cfg443"), /did not confirm port-forward removal/);
});
