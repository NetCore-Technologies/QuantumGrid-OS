import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import {
  createRouterOfficeInterZoneRule,
  removeRouterOfficeInterZoneRule,
  createRouterOfficePortForward,
  removeRouterOfficePortForward,
  setRouterOfficePortForwardEnabled,
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
  await assert.rejects(createRouterOfficePortForward({ ...baseInput, source: "wan;uci" }), /valid existing firewall zone/);
  await assert.rejects(createRouterOfficePortForward({ ...baseInput, protocol: "icmp" }), /Protocol must be TCP/);
  await assert.rejects(createRouterOfficePortForward({ ...baseInput, sourcePort: "0" }), /ports must be whole numbers/i);
  await assert.rejects(createRouterOfficePortForward({ ...baseInput, destinationPort: "65536" }), /ports must be whole numbers/i);
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

test("enables or disables a validated port-forward with explicit state verification", async () => {
  let requestUrl = "";
  let requestInit;
  globalThis.fetch = async (url, init) => {
    requestUrl = String(url);
    requestInit = init;
    return jsonResponse({
      ok: true,
      section: "cfg443",
      enabled: false,
      changed: true,
      reloaded: true,
      rolled_back: false,
    });
  };
  const result = await setRouterOfficePortForwardEnabled("cfg443", false);
  assert.equal(requestUrl, "/cgi-bin/luci/admin/services/quantumgrid/office-port-forward-toggle");
  assert.equal(requestInit.method, "POST");
  assert.equal(requestInit.credentials, "same-origin");
  assert.equal(requestInit.cache, "no-store");
  const form = new URLSearchParams(requestInit.body);
  assert.equal(form.get("section"), "cfg443");
  assert.equal(form.get("enabled"), "0");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.enabled, false);
  assert.equal(result.changed, true);
  assert.equal(result.reloaded, true);
});

test("port-forward state API accepts an idempotent no-op without firewall reload", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true,
    section: "cfg443",
    enabled: true,
    changed: false,
    reloaded: false,
    rolled_back: false,
  });
  const result = await setRouterOfficePortForwardEnabled("cfg443", true);
  assert.equal(result.enabled, true);
  assert.equal(result.changed, false);
  assert.equal(result.reloaded, false);
});

test("port-forward state API rejects invalid sections before network access", async () => {
  globalThis.fetch = async () => {
    throw new Error("fetch must not be called for invalid input");
  };
  await assert.rejects(setRouterOfficePortForwardEnabled("../firewall", false), /Invalid firewall redirect section/);
});

test("port-forward state API rejects a server response for a different requested state", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true,
    section: "cfg443",
    enabled: true,
    changed: true,
    reloaded: true,
    rolled_back: false,
  });
  await assert.rejects(setRouterOfficePortForwardEnabled("cfg443", false), /did not confirm the requested port-forward state/);
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


test("creates a scoped internal IPv4 service rule with same-origin confirmation", async () => {
  let url = "";
  let init;
  globalThis.fetch = async (target, options) => {
    url = String(target);
    init = options;
    return jsonResponse({
      ok: true, section: "qg_office_rule_1", name: "guest-to-corp-https",
      source: "guest", destination: "corp", protocol: "tcp",
      source_ip: "192.168.30.50", destination_ip: "192.168.20.30",
      destination_port: 443, target: "ACCEPT", enabled: true,
      reloaded: true, rolled_back: false,
    });
  };
  const result = await createRouterOfficeInterZoneRule({
    name: "guest-to-corp-https", source: "guest", destination: "corp",
    protocol: "tcp", sourceIp: "192.168.30.50", destinationIp: "192.168.20.30",
    destinationPort: "443", target: "ACCEPT",
  });
  assert.equal(url, "/cgi-bin/luci/admin/services/quantumgrid/office-interzone-rule-add");
  assert.equal(init.method, "POST");
  assert.equal(init.credentials, "same-origin");
  assert.equal(init.cache, "no-store");
  const form = new URLSearchParams(init.body);
  assert.equal(form.get("name"), "guest-to-corp-https");
  assert.equal(form.get("source"), "guest");
  assert.equal(form.get("destination"), "corp");
  assert.equal(form.get("protocol"), "tcp");
  assert.equal(form.get("source_ip"), "192.168.30.50");
  assert.equal(form.get("destination_ip"), "192.168.20.30");
  assert.equal(form.get("destination_port"), "443");
  assert.equal(form.get("target"), "ACCEPT");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.section, "qg_office_rule_1");
});

test("creates IPv4 ICMP rules without a transport port", async () => {
  let init;
  globalThis.fetch = async (_target, options) => {
    init = options;
    return jsonResponse({
      ok: true, section: "qg_office_rule_2", name: "guest-ping",
      source: "guest", destination: "corp", protocol: "icmp",
      source_ip: "", destination_ip: "192.168.20.30",
      target: "REJECT", enabled: true, reloaded: true, rolled_back: false,
    });
  };
  const result = await createRouterOfficeInterZoneRule({
    name: "guest-ping", source: "guest", destination: "corp", protocol: "icmp",
    destinationIp: "192.168.20.30", target: "REJECT",
  });
  assert.equal(new URLSearchParams(init.body).get("destination_port"), "");
  assert.equal(result.protocol, "icmp");
  assert.equal(result.target, "REJECT");
  assert.equal(result.destination_port, undefined);
});

test("inter-zone API rejects WAN zones, invalid hosts, protocols, targets and ports before fetch", async () => {
  globalThis.fetch = async () => { throw new Error("fetch must not run for invalid input"); };
  const base = {
    name: "guest-to-corp", source: "guest", destination: "corp",
    protocol: "tcp", destinationIp: "192.168.20.30", destinationPort: "443", target: "ACCEPT",
  };
  await assert.rejects(createRouterOfficeInterZoneRule({ ...base, name: "../unsafe" }), /valid rule name/);
  await assert.rejects(createRouterOfficeInterZoneRule({ ...base, source: "wan" }), /internal firewall zones/);
  await assert.rejects(createRouterOfficeInterZoneRule({ ...base, destination: "corp;uci" }), /internal firewall zones/);
  await assert.rejects(createRouterOfficeInterZoneRule({ ...base, destinationIp: "192.168.020.30" }), /valid dotted-decimal/);
  await assert.rejects(createRouterOfficeInterZoneRule({ ...base, protocol: "all" }), /Protocol must be/);
  await assert.rejects(createRouterOfficeInterZoneRule({ ...base, target: "DROP" }), /ACCEPT or REJECT/);
  await assert.rejects(createRouterOfficeInterZoneRule({ ...base, destinationPort: "65536" }), /destination port/ii);
  await assert.rejects(createRouterOfficeInterZoneRule({ ...base, protocol: "icmp", destinationPort: "443" }), /do not use a destination port/);
});

test("removes only a managed inter-zone rule section and checks firewall reload", async () => {
  let url = "";
  let init;
  globalThis.fetch = async (target, options) => {
    url = String(target);
    init = options;
    return jsonResponse({ ok: true, section: "qg_office_rule_7", removed: true, reloaded: true, rolled_back: false });
  };
  const result = await removeRouterOfficeInterZoneRule("qg_office_rule_7");
  assert.equal(url, "/cgi-bin/luci/admin/services/quantumgrid/office-interzone-rule-remove");
  assert.equal(init.method, "POST");
  assert.equal(init.credentials, "same-origin");
  assert.equal(init.cache, "no-store");
  assert.equal(new URLSearchParams(init.body).get("confirmed"), "1");
  assert.equal(result.removed, true);
});

test("inter-zone removal rejects non-managed section identifiers before fetch", async () => {
  globalThis.fetch = async () => { throw new Error("fetch must not run for invalid section"); };
  await assert.rejects(removeRouterOfficeInterZoneRule("cfg_custom"), /managed inter-zone/);
  await assert.rejects(removeRouterOfficeInterZoneRule("../qg_office_rule_1"), /managed inter-zone/);
});
