import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import {
  removeRouterOfficeVlan,
  updateRouterOfficeVlan,
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

const validUpdateInput = {
  device: "br-lan",
  vlanId: "20",
  ports: [
    { name: "lan1", mode: "tagged", pvid: false },
    { name: "lan2", mode: "untagged", pvid: true },
    { name: "lan3", mode: "untagged", pvid: false },
  ],
};

test("bridge VLAN update sends explicit UCI port modes and verifies the reload result", async () => {
  let requestUrl = "";
  let requestInit;
  globalThis.fetch = async (url, init) => {
    requestUrl = String(url);
    requestInit = init;
    return jsonResponse({
      ok: true,
      section: "cfg20",
      device: "br-lan",
      vlan_id: 20,
      ports: ["lan1:t", "lan2:u*", "lan3:u"],
      reloaded: true,
      rolled_back: false,
    });
  };

  const result = await updateRouterOfficeVlan(validUpdateInput);
  assert.equal(requestUrl, "/cgi-bin/luci/admin/services/quantumgrid/bridge-vlan-update");
  assert.equal(requestInit.method, "POST");
  assert.equal(requestInit.credentials, "same-origin");
  assert.equal(requestInit.cache, "no-store");
  const form = new URLSearchParams(requestInit.body);
  assert.equal(form.get("device"), "br-lan");
  assert.equal(form.get("vlan"), "20");
  assert.equal(form.get("ports"), "lan1:t lan2:u* lan3:u");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.section, "cfg20");
});

test("bridge VLAN update rejects duplicate, malformed and ambiguous port entries before fetch", async () => {
  globalThis.fetch = async () => {
    throw new Error("fetch must not be called for invalid input");
  };
  await assert.rejects(
    updateRouterOfficeVlan({
      ...validUpdateInput,
      ports: [
        { name: "lan1", mode: "tagged", pvid: false },
        { name: "lan1", mode: "untagged", pvid: true },
      ],
    }),
    /valid and unique/,
  );
  await assert.rejects(
    updateRouterOfficeVlan({
      ...validUpdateInput,
      ports: [{ name: "lan1", mode: "unspecified", pvid: false }],
    }),
    /must be tagged or untagged/,
  );
  await assert.rejects(
    updateRouterOfficeVlan({
      ...validUpdateInput,
      ports: [{ name: "lan1", mode: "tagged", pvid: true }],
    }),
    /PVID can only be assigned to an untagged/,
  );
  await assert.rejects(
    updateRouterOfficeVlan({ ...validUpdateInput, vlanId: "4095" }),
    /VLAN ID must be a whole number/,
  );
});

test("bridge VLAN update rejects mismatched membership in the router response", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true,
    section: "cfg20",
    device: "br-lan",
    vlan_id: 20,
    ports: ["lan1:u*", "lan2:t", "lan3:u"],
    reloaded: true,
    rolled_back: false,
  });

  await assert.rejects(
    updateRouterOfficeVlan(validUpdateInput),
    /did not confirm the bridge VLAN configuration/,
  );
});

test("bridge VLAN removal requires a valid section and confirms a successful network reload", async () => {
  let requestUrl = "";
  let requestInit;
  globalThis.fetch = async (url, init) => {
    requestUrl = String(url);
    requestInit = init;
    return jsonResponse({
      ok: true,
      section: "cfg20",
      device: "br-lan",
      vlan_id: 20,
      removed: true,
      reloaded: true,
      rolled_back: false,
    });
  };

  const result = await removeRouterOfficeVlan("cfg20");
  assert.equal(requestUrl, "/cgi-bin/luci/admin/services/quantumgrid/bridge-vlan-remove");
  assert.equal(requestInit.method, "POST");
  const form = new URLSearchParams(requestInit.body);
  assert.equal(form.get("section"), "cfg20");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.removed, true);
  await assert.rejects(removeRouterOfficeVlan("../wireless"), /Invalid bridge VLAN section/);
});

test("bridge VLAN API refuses a response that claims removal without a successful reload", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true,
    section: "cfg20",
    device: "br-lan",
    vlan_id: 20,
    removed: true,
    reloaded: false,
    rolled_back: false,
  });
  await assert.rejects(
    removeRouterOfficeVlan("cfg20"),
    /did not confirm bridge VLAN removal/,
  );
});
