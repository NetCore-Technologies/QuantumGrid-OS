import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import {
  createRouterOfficeIpv6Pinhole,
  removeRouterOfficeIpv6Pinhole,
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
  name: "office-https-v6",
  source: "wan",
  destination: "corp",
  protocol: "tcp",
  destinationIp: "2001:4860:4860::8888",
  destinationPort: "443",
};

const success = {
  ok: true,
  section: "cfg_ipv6_https",
  name: "office-https-v6",
  source: "wan",
  destination: "corp",
  protocol: "tcp",
  destination_ip: "2001:4860:4860:0000:0000:0000:0000:8888",
  destination_port: 443,
  family: "ipv6",
  reloaded: true,
  rolled_back: false,
};

test("creates a zone-scoped IPv6 allow rule and verifies the exact service and reload", async () => {
  let requestUrl = "";
  let requestInit;
  globalThis.fetch = async (url, init) => {
    requestUrl = String(url);
    requestInit = init;
    return jsonResponse(success);
  };

  const result = await createRouterOfficeIpv6Pinhole(baseInput);
  assert.equal(requestUrl, "/cgi-bin/luci/admin/services/quantumgrid/office-ipv6-pinhole-add");
  assert.equal(requestInit.method, "POST");
  assert.equal(requestInit.credentials, "same-origin");
  assert.equal(requestInit.cache, "no-store");
  const form = new URLSearchParams(requestInit.body);
  assert.equal(form.get("name"), "office-https-v6");
  assert.equal(form.get("source"), "wan");
  assert.equal(form.get("destination"), "corp");
  assert.equal(form.get("protocol"), "tcp");
  assert.equal(form.get("destination_ip"), success.destination_ip);
  assert.equal(form.get("destination_port"), "443");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.family, "ipv6");
  assert.equal(result.destination_port, 443);
});

test("pinhole API rejects private, link-local, multicast, documentation and malformed addresses before fetch", async () => {
  globalThis.fetch = async () => {
    throw new Error("fetch must not be called for invalid input");
  };
  const invalidAddresses = [
    "fd00::10",
    "fe80::1",
    "ff02::1",
    "::",
    "2001:db8::1",
    "2001:4860:4860:::8888",
    "2001:4860:4860::8888/64",
    "192.0.2.1",
    "not-ipv6",
  ];
  for (const destinationIp of invalidAddresses) {
    await assert.rejects(
      createRouterOfficeIpv6Pinhole({ ...baseInput, destinationIp }),
      /global-unicast IPv6 host address/,
      destinationIp,
    );
  }
});

test("pinhole API rejects unsafe identifiers, identical zones, unsupported protocols and invalid ports", async () => {
  globalThis.fetch = async () => {
    throw new Error("fetch must not be called for invalid input");
  };
  await assert.rejects(createRouterOfficeIpv6Pinhole({ ...baseInput, name: "../rule" }), /valid IPv6 pinhole name/);
  await assert.rejects(createRouterOfficeIpv6Pinhole({ ...baseInput, source: "wan;uci" }), /different existing firewall zones/);
  await assert.rejects(createRouterOfficeIpv6Pinhole({ ...baseInput, destination: "wan" }), /different existing firewall zones/);
  await assert.rejects(createRouterOfficeIpv6Pinhole({ ...baseInput, protocol: "icmp" }), /Protocol must be TCP/);
  await assert.rejects(createRouterOfficeIpv6Pinhole({ ...baseInput, destinationPort: "0" }), /Destination port/);
  await assert.rejects(createRouterOfficeIpv6Pinhole({ ...baseInput, destinationPort: "65536" }), /Destination port/);
});

test("pinhole API rejects mismatched address, zones or firewall family responses", async () => {
  for (const payload of [
    { ...success, destination: "guest" },
    { ...success, destination_ip: "2001:4860:4860::8844" },
    { ...success, family: "ipv4" },
    { ...success, reloaded: false },
    { ...success, rolled_back: true },
  ]) {
    globalThis.fetch = async () => jsonResponse(payload);
    await assert.rejects(
      createRouterOfficeIpv6Pinhole(baseInput),
      /did not confirm the exact IPv6 pinhole/,
    );
  }
});

test("removes a managed IPv6 pinhole and verifies firewall reload", async () => {
  let requestUrl = "";
  let requestInit;
  globalThis.fetch = async (url, init) => {
    requestUrl = String(url);
    requestInit = init;
    return jsonResponse({
      ok: true,
      section: "cfg_ipv6_https",
      removed: true,
      reloaded: true,
      rolled_back: false,
    });
  };

  const result = await removeRouterOfficeIpv6Pinhole("cfg_ipv6_https");
  assert.equal(requestUrl, "/cgi-bin/luci/admin/services/quantumgrid/office-ipv6-pinhole-remove");
  assert.equal(requestInit.method, "POST");
  assert.equal(requestInit.credentials, "same-origin");
  assert.equal(new URLSearchParams(requestInit.body).get("section"), "cfg_ipv6_https");
  assert.equal(new URLSearchParams(requestInit.body).get("confirmed"), "1");
  assert.equal(result.removed, true);
  await assert.rejects(removeRouterOfficeIpv6Pinhole("../firewall"), /Invalid firewall IPv6 pinhole section/);
});

test("pinhole removal rejects incomplete or misdirected service confirmation", async () => {
  for (const payload of [
    { ok: true, section: "cfg_ipv6_https", removed: true, reloaded: false, rolled_back: false },
    { ok: true, section: "cfg_other", removed: true, reloaded: true, rolled_back: false },
    { ok: true, section: "cfg_ipv6_https", removed: false, reloaded: true, rolled_back: false },
  ]) {
    globalThis.fetch = async () => jsonResponse(payload);
    await assert.rejects(
      removeRouterOfficeIpv6Pinhole("cfg_ipv6_https"),
      /did not confirm IPv6 pinhole removal/,
    );
  }
});
