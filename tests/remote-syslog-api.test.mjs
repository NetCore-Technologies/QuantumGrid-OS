import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { updateRouterRemoteSyslog } from "../ui/quantumgrid/src/routerApi.ts";

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

const tlsInput = {
  enabled: true,
  host: "logs.corp.example",
  port: 6514,
  protocol: "tls",
  hostname: "qg-office-router",
  prefix: "office-site1",
};

const tlsSuccess = {
  ok: true,
  enabled: true,
  host: "logs.corp.example",
  port: 6514,
  protocol: "tls",
  hostname: "qg-office-router",
  prefix: "office-site1",
  tls_status: "ready",
  restarted: true,
  rolled_back: false,
};

test("configures TLS syslog with same-origin POST and confirms verified tunnel restart", async () => {
  let requestUrl = "";
  let requestInit;
  globalThis.fetch = async (url, init) => {
    requestUrl = String(url);
    requestInit = init;
    return jsonResponse(tlsSuccess);
  };

  const result = await updateRouterRemoteSyslog(tlsInput);
  assert.equal(requestUrl, "/cgi-bin/luci/admin/services/quantumgrid/remote-syslog");
  assert.equal(requestInit.method, "POST");
  assert.equal(requestInit.credentials, "same-origin");
  assert.equal(requestInit.cache, "no-store");
  const form = new URLSearchParams(requestInit.body);
  assert.equal(form.get("confirmed"), "1");
  assert.equal(form.get("enabled"), "1");
  assert.equal(form.get("host"), "logs.corp.example");
  assert.equal(form.get("port"), "6514");
  assert.equal(form.get("protocol"), "tls");
  assert.equal(form.get("hostname"), "qg-office-router");
  assert.equal(form.get("prefix"), "office-site1");
  assert.equal(result.protocol, "tls");
  assert.equal(result.tls_status, "ready");
  assert.equal(result.restarted, true);
  assert.equal(result.rolled_back, false);
});

test("TLS syslog canonicalizes a global-unicast IPv6 collector before sending the request", async () => {
  let requestInit;
  const canonical = "2001:4860:4860:0000:0000:0000:0000:8888";
  globalThis.fetch = async (_url, init) => {
    requestInit = init;
    return jsonResponse({ ...tlsSuccess, host: canonical });
  };
  const result = await updateRouterRemoteSyslog({ ...tlsInput, host: "2001:4860:4860::8888" });
  assert.equal(new URLSearchParams(requestInit.body).get("host"), canonical);
  assert.equal(result.host, canonical);
});

test("remote syslog accepts an internal ULA IPv6 collector and rejects unsafe IPv6 ranges before fetch", async () => {
  globalThis.fetch = async (_url, init) => {
    const form = new URLSearchParams(init.body);
    assert.equal(form.get("host"), "fd12:3456:0000:0000:0000:0000:0000:0010");
    return jsonResponse({ ...tlsSuccess, host: "fd12:3456:0000:0000:0000:0000:0000:0010", protocol: "udp", port: 514, tls_status: undefined });
  };
  const result = await updateRouterRemoteSyslog({ ...tlsInput, host: "fd12:3456::10", protocol: "udp", port: 514 });
  assert.equal(result.host, "fd12:3456:0000:0000:0000:0000:0000:0010");
  globalThis.fetch = async () => { throw new Error("fetch must not run for unsafe IPv6 addresses"); };
  for (const host of ["::", "::1", "fe80::1", "ff02::1", "2001:db8::10", "2002:c000:0201::1", "3fff::1", "2001:4860:::8888", "2001:4860::1%wan"]) {
    await assert.rejects(updateRouterRemoteSyslog({ ...tlsInput, host }), /valid IPv4 address, unicast IPv6 address or DNS host name/);
  }
});

test("TLS syslog client rejects malformed destinations and unknown transports before fetch", async () => {
  globalThis.fetch = async () => {
    throw new Error("fetch must not be called for invalid input");
  };
  await assert.rejects(
    updateRouterRemoteSyslog({ ...tlsInput, host: "logs..corp.example" }),
    /valid IPv4 address or DNS host name/,
  );
  await assert.rejects(
    updateRouterRemoteSyslog({ ...tlsInput, host: "192.0.2.999" }),
    /valid IPv4 address or DNS host name/,
  );
  await assert.rejects(
    updateRouterRemoteSyslog({ ...tlsInput, host: "192.0.2.015" }),
    /valid IPv4 address or DNS host name/,
  );
  await assert.rejects(
    updateRouterRemoteSyslog({ ...tlsInput, hostname: "bad-.corp.example" }),
    /sender hostname must be a valid DNS host name/,
  );
  await assert.rejects(
    updateRouterRemoteSyslog({ ...tlsInput, port: 65536 }),
    /port must be a whole number/,
  );
  await assert.rejects(
    updateRouterRemoteSyslog({ ...tlsInput, protocol: "sctp" }),
    /transport must be UDP, TCP or authenticated TLS/,
  );
});

test("TLS syslog API rejects responses that do not confirm the selected protocol and tunnel restart", async () => {
  const invalidResponses = [
    { ...tlsSuccess, protocol: "tcp" },
    { ...tlsSuccess, enabled: false },
    { ...tlsSuccess, restarted: false },
    { ...tlsSuccess, rolled_back: true },
    { ...tlsSuccess, host: "other.corp.example" },
    { ...tlsSuccess, port: 6515 },
    { ...tlsSuccess, tls_status: "review" },
    { ...tlsSuccess, tls_status: undefined },
  ];
  for (const response of invalidResponses) {
    globalThis.fetch = async () => jsonResponse(response);
    await assert.rejects(
      updateRouterRemoteSyslog(tlsInput),
      /did not confirm the remote syslog update and log-service restart/,
    );
  }
});

test("plain TCP and UDP remote syslog remain supported", async () => {
  for (const protocol of ["tcp", "udp"]) {
    globalThis.fetch = async () => jsonResponse({
      ...tlsSuccess,
      port: 514,
      protocol,
      tls_status: undefined,
    });
    const result = await updateRouterRemoteSyslog({ ...tlsInput, protocol, port: 514 });
    assert.equal(result.protocol, protocol);
  }
});
