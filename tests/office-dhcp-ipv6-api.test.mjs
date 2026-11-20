import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { updateRouterDhcpScope } from "../ui/quantumgrid/src/routerApi.ts";

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
  section: "lan",
  start: "100",
  limit: "120",
  lease_time: "12h",
};

test("DHCP scope API sends IPv6 server modes and verifies both service restarts", async () => {
  let requestUrl = "";
  let requestInit;
  globalThis.fetch = async (url, init) => {
    requestUrl = String(url);
    requestInit = init;
    return jsonResponse({
      ok: true,
      section: "lan",
      start: "100",
      limit: "120",
      lease_time: "12h",
      pool_start_ip: "192.168.10.100",
      pool_end_ip: "192.168.10.219",
      dhcpv6: "server",
      ra: "server",
      ndp: "disabled",
      restarted: true,
      dnsmasq_restarted: true,
      odhcpd_restarted: true,
      rolled_back: false,
    });
  };

  const result = await updateRouterDhcpScope({
    ...baseInput,
    dhcpv6: "server",
    ra: "server",
    ndp: "disabled",
  });
  assert.equal(requestUrl, "/cgi-bin/luci/admin/services/quantumgrid/dhcp-scope-update");
  assert.equal(requestInit.method, "POST");
  assert.equal(requestInit.credentials, "same-origin");
  assert.equal(requestInit.cache, "no-store");
  const form = new URLSearchParams(requestInit.body);
  assert.equal(form.get("dhcpv6"), "server");
  assert.equal(form.get("ra"), "server");
  assert.equal(form.get("ndp"), "disabled");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.odhcpd_restarted, true);
});

test("IPv4-only scope edits preserve existing relay/hybrid configuration without restarting odhcpd", async () => {
  let requestBody = "";
  globalThis.fetch = async (_url, init) => {
    requestBody = init.body;
    return jsonResponse({
      ok: true,
      section: "lan",
      start: "100",
      limit: "120",
      lease_time: "12h",
      pool_start_ip: "192.168.10.100",
      pool_end_ip: "192.168.10.219",
      dhcpv6: "relay",
      ra: "hybrid",
      ndp: "relay",
      restarted: true,
      dnsmasq_restarted: true,
      odhcpd_restarted: false,
      rolled_back: false,
    });
  };
  const result = await updateRouterDhcpScope({
    ...baseInput,
    dhcpv6: "UNCHANGED",
    ra: "UNCHANGED",
    ndp: "UNCHANGED",
  });
  const form = new URLSearchParams(requestBody);
  assert.equal(form.get("dhcpv6"), "UNCHANGED");
  assert.equal(form.get("ra"), "UNCHANGED");
  assert.equal(form.get("ndp"), "UNCHANGED");
  assert.equal(result.dhcpv6, "relay");
  assert.equal(result.ra, "hybrid");
  assert.equal(result.ndp, "relay");
  assert.equal(result.odhcpd_restarted, false);
});

test("DHCP scope API rejects relay and hybrid changes without native master-topology support", async () => {
  globalThis.fetch = async () => {
    throw new Error("fetch must not be called for unsupported relay modes");
  };
  await assert.rejects(
    updateRouterDhcpScope({
      ...baseInput,
      dhcpv6: "relay",
      ra: "server",
      ndp: "disabled",
    }),
    /Relay\/hybrid requires native odhcpd master configuration/,
  );
  await assert.rejects(
    updateRouterDhcpScope({
      ...baseInput,
      dhcpv6: "server",
      ra: "hybrid",
      ndp: "disabled",
    }),
    /Relay\/hybrid requires native odhcpd master configuration/,
  );
  await assert.rejects(
    updateRouterDhcpScope({
      ...baseInput,
      dhcpv6: "server",
      ra: "server",
      ndp: "relay",
    }),
    /Relay\/hybrid requires native odhcpd master configuration/,
  );
});

test("DHCP scope API rejects success responses that omit the required odhcpd restart", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true,
    section: "lan",
    start: "100",
    limit: "120",
    lease_time: "12h",
    pool_start_ip: "192.168.10.100",
    pool_end_ip: "192.168.10.219",
    dhcpv6: "server",
    ra: "server",
    ndp: "disabled",
    restarted: true,
    dnsmasq_restarted: true,
    odhcpd_restarted: false,
    rolled_back: false,
  });
  await assert.rejects(
    updateRouterDhcpScope({
      ...baseInput,
      dhcpv6: "server",
      ra: "server",
      ndp: "disabled",
    }),
    /required service restarts/,
  );
});

test("DHCP scope API rejects malformed section and policy values before fetch", async () => {
  globalThis.fetch = async () => {
    throw new Error("fetch must not be called for invalid input");
  };
  await assert.rejects(
    updateRouterDhcpScope({
      ...baseInput,
      section: "../dhcp",
      dhcpv6: "UNCHANGED",
      ra: "UNCHANGED",
      ndp: "UNCHANGED",
    }),
    /Invalid DHCP scope section/,
  );
  await assert.rejects(
    updateRouterDhcpScope({
      ...baseInput,
      dhcpv6: "server;uci",
      ra: "UNCHANGED",
      ndp: "UNCHANGED",
    }),
    /DHCPv6 and RA must be unchanged, disabled or server/,
  );
});
