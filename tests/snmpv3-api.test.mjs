import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { updateRouterSnmpv3 } from "../ui/quantumgrid/src/routerApi.ts";

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

const validInput = {
  enabled: true,
  username: "qg-collector",
  authPassphrase: "StrongAuthPassphrase-2026!",
  privacyPassphrase: "StrongPrivacySecret-2026!",
  sourceZone: "mgmt",
};

const ready = {
  ok: true,
  enabled: true,
  status: "ready",
  username: "qg-collector",
  source_zone: "mgmt",
  auth_type: "SHA",
  privacy_type: "AES",
  security_level: "authPriv",
  allow_write: "0",
  restricted_oid: ".1.3.6.1.2.1",
  firewall_rule_configured: true,
  firewall_perimeter_safe: true,
  process_running: true,
  private_config_permissions: true,
  restarted: true,
  firewall_reloaded: true,
  rolled_back: false,
  sampled_at: 1790000000,
};

test("enables read-only SNMPv3 authPriv through an authenticated same-origin request", async () => {
  let requestUrl = "";
  let requestInit;
  globalThis.fetch = async (url, init) => {
    requestUrl = String(url);
    requestInit = init;
    return jsonResponse(ready);
  };
  const result = await updateRouterSnmpv3(validInput);
  assert.equal(requestUrl, "/cgi-bin/luci/admin/services/quantumgrid/snmpv3-update");
  assert.equal(requestInit.method, "POST");
  assert.equal(requestInit.credentials, "same-origin");
  assert.equal(requestInit.cache, "no-store");
  const form = new URLSearchParams(requestInit.body);
  assert.equal(form.get("confirmed"), "1");
  assert.equal(form.get("enabled"), "1");
  assert.equal(form.get("username"), validInput.username);
  assert.equal(form.get("auth_pass"), validInput.authPassphrase);
  assert.equal(form.get("privacy_pass"), validInput.privacyPassphrase);
  assert.equal(form.get("source_zone"), validInput.sourceZone);
  assert.equal(result.auth_type, "SHA");
  assert.equal(result.privacy_type, "AES");
  assert.equal(result.allow_write, "0");
  assert.equal(result.restricted_oid, ".1.3.6.1.2.1");
  assert.equal(result.firewall_rule_configured, true);
  assert.equal(result.private_config_permissions, true);
});

test("rejects weak credentials, unsafe user names, same secrets and unsafe zones before fetch", async () => {
  globalThis.fetch = async () => {
    throw new Error("fetch must not be called for invalid input");
  };
  await assert.rejects(updateRouterSnmpv3({ ...validInput, username: "root" }), /username/);
  await assert.rejects(updateRouterSnmpv3({ ...validInput, username: "../nms" }), /username/);
  await assert.rejects(updateRouterSnmpv3({ ...validInput, username: "1collector" }), /username/);
  await assert.rejects(updateRouterSnmpv3({ ...validInput, authPassphrase: "short" }), /authentication passphrase/);
  await assert.rejects(updateRouterSnmpv3({ ...validInput, privacyPassphrase: "short" }), /privacy passphrase/);
  await assert.rejects(updateRouterSnmpv3({ ...validInput, authPassphrase: validInput.privacyPassphrase }), /must be different/);
  await assert.rejects(updateRouterSnmpv3({ ...validInput, sourceZone: "wan" }), /trusted internal management firewall zone/);
  await assert.rejects(updateRouterSnmpv3({ ...validInput, authPassphrase: "StrongSecretWith Space-2026!" }), /supported ASCII/);
  await assert.rejects(updateRouterSnmpv3({ ...validInput, privacyPassphrase: "StrongSecretWith\"Quote-2026!" }), /supported ASCII/);
});

test("rejects API success responses unless they prove SHA/AES authPriv, read-only scope and live firewall posture", async () => {
  const failures = [
    { ...ready, status: "review" },
    { ...ready, auth_type: "MD5" },
    { ...ready, privacy_type: "DES" },
    { ...ready, allow_write: "1" },
    { ...ready, restricted_oid: ".1" },
    { ...ready, firewall_rule_configured: false },
    { ...ready, firewall_perimeter_safe: false },
    { ...ready, process_running: false },
    { ...ready, private_config_permissions: false },
    { ...ready, source_zone: "wan" },
    { ...ready, restarted: false },
    { ...ready, firewall_reloaded: false },
    { ...ready, rolled_back: true },
  ];
  for (const payload of failures) {
    globalThis.fetch = async () => jsonResponse(payload);
    await assert.rejects(
      updateRouterSnmpv3(validInput),
      /did not confirm the selected read-only SNMPv3 authPriv and firewall posture/,
    );
  }
});

test("disables SNMPv3 without resending or retaining passphrases", async () => {
  let requestInit;
  globalThis.fetch = async (_url, init) => {
    requestInit = init;
    return jsonResponse({
      ...ready,
      enabled: false,
      status: "disabled",
      username: "",
      source_zone: "",
      auth_type: "",
      privacy_type: "",
      allow_write: "",
      restricted_oid: "",
      firewall_rule_configured: false,
      process_running: false,
      private_config_permissions: true,
    });
  };
  const result = await updateRouterSnmpv3({
    enabled: false,
    username: "",
    authPassphrase: "",
    privacyPassphrase: "",
    sourceZone: "",
  });
  const form = new URLSearchParams(requestInit.body);
  assert.equal(form.get("confirmed"), "1");
  assert.equal(form.get("enabled"), "0");
  assert.equal(form.has("auth_pass"), false);
  assert.equal(form.has("privacy_pass"), false);
  assert.equal(result.status, "disabled");
});
