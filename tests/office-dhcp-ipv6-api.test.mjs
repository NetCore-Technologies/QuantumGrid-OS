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
  dhcpv6: "UNCHANGED",
  ra: "UNCHANGED",
  ndp: "UNCHANGED",
  ra_flags: "UNCHANGED",
  ra_slaac: "UNCHANGED",
  ra_dns: "UNCHANGED",
  ra_preference: "UNCHANGED",
  ra_lifetime: "UNCHANGED",
  dhcpv6_na: "UNCHANGED",
  dhcpv6_pd: "UNCHANGED",
  dhcpv6_assignall: "UNCHANGED",
  dhcpv6_pd_min_len: "UNCHANGED",
};

const defaultIpv6Response = {
  dhcpv6: "",
  ra: "",
  ndp: "",
  ra_flags: [],
  ra_slaac: true,
  ra_dns: true,
  ra_preference: "medium",
  ra_lifetime: 2700,
  dhcpv6_na: true,
  dhcpv6_pd: true,
  dhcpv6_assignall: true,
  dhcpv6_pd_min_len: 62,
};

test("DHCP scope API sends IPv6 server, RA flags, SLAAC and prefix delegation options", async () => {
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
      ra_flags: ["managed-config", "other-config"],
      ra_slaac: false,
      ra_dns: true,
      ra_preference: "high",
      ra_lifetime: 1800,
      dhcpv6_na: true,
      dhcpv6_pd: true,
      dhcpv6_assignall: false,
      dhcpv6_pd_min_len: 60,
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
    ra_flags: "managed-config+other-config",
    ra_slaac: "0",
    ra_dns: "1",
    ra_preference: "high",
    ra_lifetime: "1800",
    dhcpv6_na: "1",
    dhcpv6_pd: "1",
    dhcpv6_assignall: "0",
    dhcpv6_pd_min_len: "60",
  });
  assert.equal(requestUrl, "/cgi-bin/luci/admin/services/quantumgrid/dhcp-scope-update");
  assert.equal(requestInit.method, "POST");
  assert.equal(requestInit.credentials, "same-origin");
  assert.equal(requestInit.cache, "no-store");
  const form = new URLSearchParams(requestInit.body);
  assert.equal(form.get("dhcpv6"), "server");
  assert.equal(form.get("ra"), "server");
  assert.equal(form.get("ndp"), "disabled");
  assert.equal(form.get("ra_flags"), "managed-config+other-config");
  assert.equal(form.get("ra_slaac"), "0");
  assert.equal(form.get("ra_dns"), "1");
  assert.equal(form.get("dhcpv6_pd"), "1");
  assert.equal(form.get("dhcpv6_pd_min_len"), "60");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.odhcpd_restarted, true);
});

test("IPv4-only scope edits preserve existing relay/hybrid and advanced IPv6 settings", async () => {
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
      ra_flags: ["managed-config"],
      ra_slaac: true,
      ra_dns: true,
      ra_preference: "medium",
      ra_lifetime: 2700,
      dhcpv6_na: true,
      dhcpv6_pd: true,
      dhcpv6_assignall: true,
      dhcpv6_pd_min_len: 62,
      restarted: true,
      dnsmasq_restarted: true,
      odhcpd_restarted: false,
      rolled_back: false,
    });
  };
  const result = await updateRouterDhcpScope(baseInput);
  const form = new URLSearchParams(requestBody);
  for (const field of [
    "dhcpv6", "ra", "ndp", "ra_flags", "ra_slaac", "ra_dns", "ra_preference", "ra_lifetime",
    "dhcpv6_na", "dhcpv6_pd", "dhcpv6_assignall", "dhcpv6_pd_min_len",
  ]) assert.equal(form.get(field), "UNCHANGED", field + " must explicitly retain the existing value");
  assert.equal(result.dhcpv6, "relay");
  assert.equal(result.ra, "hybrid");
  assert.equal(result.ndp, "relay");
  assert.equal(result.odhcpd_restarted, false);
});

test("DHCP scope API rejects relay/hybrid changes without native odhcpd master topology", async () => {
  globalThis.fetch = async () => {
    throw new Error("fetch must not be called for unsupported relay modes");
  };
  await assert.rejects(
    updateRouterDhcpScope({ ...baseInput, dhcpv6: "relay" }),
    /Relay\/hybrid requires native odhcpd master configuration/,
  );
  await assert.rejects(
    updateRouterDhcpScope({ ...baseInput, ra: "hybrid" }),
    /Relay\/hybrid requires native odhcpd master configuration/,
  );
  await assert.rejects(
    updateRouterDhcpScope({ ...baseInput, ndp: "relay" }),
    /Relay\/hybrid requires native odhcpd master configuration/,
  );
});

test("DHCP scope API rejects unsafe RA flags, lifetimes and delegated prefix lengths", async () => {
  globalThis.fetch = async () => {
    throw new Error("fetch must not be called for invalid IPv6 settings");
  };
  await assert.rejects(
    updateRouterDhcpScope({ ...baseInput, ra_flags: "managed-config;uci" }),
    /Invalid RA flags or DHCPv6\/SLAAC boolean option/,
  );
  await assert.rejects(
    updateRouterDhcpScope({ ...baseInput, ra_lifetime: "2701" }),
    /RA lifetime must be unchanged or a whole number/,
  );
  await assert.rejects(
    updateRouterDhcpScope({ ...baseInput, dhcpv6_pd_min_len: "65" }),
    /Minimum delegated IPv6 prefix length/,
  );
});

test("DHCP scope API requires odhcpd restart after IPv6 settings change", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true,
    section: "lan",
    start: "100",
    limit: "120",
    lease_time: "12h",
    pool_start_ip: "192.168.10.100",
    pool_end_ip: "192.168.10.219",
    ...defaultIpv6Response,
    dhcpv6: "server",
    ra: "server",
    restarted: true,
    dnsmasq_restarted: true,
    odhcpd_restarted: false,
    rolled_back: false,
  });
  await assert.rejects(
    updateRouterDhcpScope({ ...baseInput, dhcpv6: "server", ra: "server" }),
    /required service restarts/,
  );
});

test("DHCP scope API rejects malformed section identifiers before fetch", async () => {
  globalThis.fetch = async () => {
    throw new Error("fetch must not be called for invalid input");
  };
  await assert.rejects(
    updateRouterDhcpScope({ ...baseInput, section: "../dhcp" }),
    /Invalid DHCP scope section/,
  );
});
