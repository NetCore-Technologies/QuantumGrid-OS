import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { addRouterSqmClientDownloadPolicy } from "../ui/quantumgrid/src/routerApi.ts";

const originalFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = originalFetch; });

function jsonResponse(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status, headers: { "Content-Type": "application/json; charset=UTF-8" },
  });
}

const baseInput = {
  mac: "02:11:22:33:44:55",
  destinationIp: "192.168.20.40",
  sourceZone: "wan",
  destinationZone: "corp",
  dscpClass: "AF41",
};

const success = {
  ok: true,
  section: "cfg_client_download_1",
  direction: "download",
  protocol: "all",
  mac: "02:11:22:33:44:55",
  destination_ip: "192.168.20.40",
  source_zone: "wan",
  destination_zone: "corp",
  dscp_class: "AF41",
  reloaded: true,
  rolled_back: false,
};

test("creates a static-IP download DSCP policy and verifies the exact firewall reload result", async () => {
  let url = "";
  let init;
  globalThis.fetch = async (requestUrl, requestInit) => {
    url = String(requestUrl);
    init = requestInit;
    return jsonResponse(success);
  };

  const result = await addRouterSqmClientDownloadPolicy(baseInput);
  assert.equal(url, "/cgi-bin/luci/admin/services/quantumgrid/sqm-client-qos-download-add");
  assert.equal(init.method, "POST");
  assert.equal(init.credentials, "same-origin");
  assert.equal(init.cache, "no-store");
  const form = new URLSearchParams(init.body);
  assert.equal(form.get("mac"), baseInput.mac);
  assert.equal(form.get("destination_ip"), baseInput.destinationIp);
  assert.equal(form.get("source_zone"), "wan");
  assert.equal(form.get("destination_zone"), "corp");
  assert.equal(form.get("dscp_class"), "AF41");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.direction, "download");
  assert.equal(result.protocol, "all");
  assert.equal(result.destination_ip, baseInput.destinationIp);
  assert.equal(result.reloaded, true);
});

test("download API rejects invalid, special-use or non-canonical IPv4 and invalid MACs before fetch", async () => {
  globalThis.fetch = async () => { throw new Error("fetch must not be called for invalid input"); };
  for (const destinationIp of [
    "192.168.20.040", "192.168.20.256", "192.168.20.1/24", "192.168.20",
    "0.1.2.3", "127.0.0.1", "169.254.1.20", "224.0.0.1", "192.168.20.255x",
  ]) {
    await assert.rejects(
      addRouterSqmClientDownloadPolicy({ ...baseInput, destinationIp }),
      /usable static IPv4 host address/,
      destinationIp,
    );
  }
  await assert.rejects(
    addRouterSqmClientDownloadPolicy({ ...baseInput, mac: "01:11:22:33:44:55" }),
    /unicast client MAC/,
  );
});

test("download API rejects invalid zones and DSCP classes before fetch", async () => {
  globalThis.fetch = async () => { throw new Error("fetch must not be called for invalid input"); };
  await assert.rejects(
    addRouterSqmClientDownloadPolicy({ ...baseInput, sourceZone: "../wan" }),
    /firewall zones/,
  );
  await assert.rejects(
    addRouterSqmClientDownloadPolicy({ ...baseInput, dscpClass: "EF; flush" }),
    /supported DSCP class/,
  );
});

test("download API refuses responses with the wrong client, IP, direction, zones or reload outcome", async () => {
  const invalid = [
    { ...success, direction: "upload" },
    { ...success, mac: "02:aa:bb:cc:dd:ee" },
    { ...success, destination_ip: "192.168.20.41" },
    { ...success, source_zone: "corp" },
    { ...success, destination_zone: "guest" },
    { ...success, dscp_class: "CS1" },
    { ...success, reloaded: false },
    { ...success, rolled_back: true },
  ];
  for (const response of invalid) {
    globalThis.fetch = async () => jsonResponse(response);
    await assert.rejects(
      addRouterSqmClientDownloadPolicy(baseInput),
      /did not confirm the exact client download DSCP rule/,
    );
  }
});

test("download API propagates missing-static-reservation and ambiguous-subnet conflicts", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: false,
    error: "The client must have exactly one matching static DHCP reservation for this MAC and IPv4 address.",
  }, 400);
  await assert.rejects(
    addRouterSqmClientDownloadPolicy(baseInput),
    /exactly one matching static DHCP reservation/,
  );
});
