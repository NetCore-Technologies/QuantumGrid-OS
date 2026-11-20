import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { createRouterOfficeSegment } from "../ui/quantumgrid/src/routerApi.ts";

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

const input = {
  name: "corp20",
  bridge: "br-lan",
  vlanId: "20",
  address: "192.168.20.1",
  netmask: "255.255.255.0",
  zone: "cfg-corp",
  dhcpStart: "100",
  dhcpLimit: "100",
  leaseTime: "12h",
};

const success = {
  ok: true,
  name: "corp20",
  device: "br-lan.20",
  address: "192.168.20.1",
  netmask: "255.255.255.0",
  zone: "corp",
  pool_start_ip: "192.168.20.100",
  pool_end_ip: "192.168.20.199",
  firewall_rules: 3,
  network_reloaded: true,
  firewall_reloaded: true,
  dhcp_restarted: true,
  rolled_back: false,
};

test("office segment request provisions the selected VLAN, static gateway, firewall zone and DHCP pool", async () => {
  let requestUrl = "";
  let requestInit;
  globalThis.fetch = async (url, init) => {
    requestUrl = String(url);
    requestInit = init;
    return jsonResponse(success);
  };

  const result = await createRouterOfficeSegment(input);
  assert.equal(requestUrl, "/cgi-bin/luci/admin/services/quantumgrid/office-segment-add");
  assert.equal(requestInit.method, "POST");
  assert.equal(requestInit.credentials, "same-origin");
  assert.equal(requestInit.cache, "no-store");
  const form = new URLSearchParams(requestInit.body);
  assert.equal(form.get("name"), "corp20");
  assert.equal(form.get("bridge"), "br-lan");
  assert.equal(form.get("vlan"), "20");
  assert.equal(form.get("address"), "192.168.20.1");
  assert.equal(form.get("netmask"), "255.255.255.0");
  assert.equal(form.get("zone"), "cfg-corp");
  assert.equal(form.get("start"), "100");
  assert.equal(form.get("limit"), "100");
  assert.equal(form.get("leasetime"), "12h");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.device, "br-lan.20");
  assert.equal(result.firewall_rules, 3);
});

test("office segment client rejects reserved or unsafe network identifiers before fetch", async () => {
  globalThis.fetch = async () => {
    throw new Error("fetch must not be called for invalid input");
  };
  await assert.rejects(createRouterOfficeSegment({ ...input, name: "../corp" }), /Network name/);
  await assert.rejects(createRouterOfficeSegment({ ...input, name: "lan" }), /Network name/);
  await assert.rejects(createRouterOfficeSegment({ ...input, bridge: "br-lan;uci" }), /bridge/);
  await assert.rejects(createRouterOfficeSegment({ ...input, vlanId: "4095" }), /VLAN ID/);
});

test("office segment client only accepts canonical RFC1918 gateways and contiguous masks", async () => {
  globalThis.fetch = async () => {
    throw new Error("fetch must not be called for invalid input");
  };
  await assert.rejects(createRouterOfficeSegment({ ...input, address: "8.8.8.8" }), /RFC1918/);
  await assert.rejects(createRouterOfficeSegment({ ...input, address: "192.168.020.1" }), /canonical/);
  await assert.rejects(createRouterOfficeSegment({ ...input, netmask: "255.0.255.0" }), /contiguous/);
  await assert.rejects(createRouterOfficeSegment({ ...input, netmask: "255.255.255.254" }), /contiguous/);
});

test("office segment client validates DHCP inputs and firewall-zone section identifiers", async () => {
  globalThis.fetch = async () => {
    throw new Error("fetch must not be called for invalid input");
  };
  await assert.rejects(createRouterOfficeSegment({ ...input, zone: "../wan" }), /firewall zone/);
  await assert.rejects(createRouterOfficeSegment({ ...input, dhcpStart: "0" }), /DHCP start/);
  await assert.rejects(createRouterOfficeSegment({ ...input, dhcpLimit: "0" }), /DHCP start/);
  await assert.rejects(createRouterOfficeSegment({ ...input, leaseTime: "forever" }), /lease time/);
});

test("office segment client rejects a response describing a different routed device", async () => {
  globalThis.fetch = async () => jsonResponse({
    ...success,
    device: "br-other.20",
  });
  await assert.rejects(
    createRouterOfficeSegment(input),
    /did not confirm the complete office network/,
  );
});

test("office segment client rejects a partial service-reload result", async () => {
  globalThis.fetch = async () => jsonResponse({
    ...success,
    dhcp_restarted: false,
  });
  await assert.rejects(
    createRouterOfficeSegment(input),
    /did not confirm the complete office network/,
  );
});
