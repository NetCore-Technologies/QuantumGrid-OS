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
  agent_listener_configured: true,
  legacy_community_configured: false,
  legacy_network_firewall: false,
  firewall_inventory_available: true,
  firewall_conflict: false,
  managed_user_section: true,
  managed_firewall_rule: true,
  network_membership_verified: true,
  security_level: "authPriv",
  allow_write: "0",
  restricted_oid: ".1.3.6.1.2.1.1",
  firewall_available: true,
  firewall_rule_present: true,
  firewall_rule_configured: true,
  firewall_perimeter_safe: true,
  process_running: true,
  private_config_permissions: true,
  runtime_credentials_present: true,
  runtime_credentials_private: true,
  persistent_inventory_available: true,
  persistent_user_present: true,
  persistent_user_matches: 1,
  persistent_usm_user_count: 1,
  restarted: true,
  lock_released: true,
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
  assert.equal(result.agent_listener_configured, true);
  assert.equal(result.allow_write, "0");
  assert.equal(result.restricted_oid, ".1.3.6.1.2.1.1");
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
    { ...ready, agent_listener_configured: false },
    { ...ready, legacy_community_configured: true },
    { ...ready, legacy_network_firewall: true },
    { ...ready, firewall_inventory_available: false },
    { ...ready, firewall_conflict: true },
    { ...ready, managed_user_section: false },
    { ...ready, managed_firewall_rule: false },
    { ...ready, network_membership_verified: false },
    { ...ready, firewall_rule_present: false },
    { ...ready, allow_write: "1" },
    { ...ready, restricted_oid: ".1" },
    { ...ready, firewall_rule_configured: false },
    { ...ready, firewall_perimeter_safe: false },
    { ...ready, process_running: false },
    { ...ready, persistent_inventory_available: false },
    { ...ready, persistent_user_present: false },
    { ...ready, persistent_user_matches: 0 },
    { ...ready, persistent_usm_user_count: 2 },
    { ...ready, private_config_permissions: false },
    { ...ready, source_zone: "wan" },
    { ...ready, lock_released: false },
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

test("allows emergency SNMP disable when the firewall service is unavailable", async () => {
  globalThis.fetch = async () => jsonResponse({
    ...ready,
    enabled: false,
    status: "review",
    username: "",
    source_zone: "",
    auth_type: "",
    privacy_type: "",
    allow_write: "",
    restricted_oid: "",
    firewall_available: false,
    firewall_reloaded: false,
    firewall_rule_present: false,
    firewall_rule_configured: false,
    firewall_perimeter_safe: false,
    firewall_conflict: true,
    process_running: false,
    private_config_permissions: true,
    runtime_credentials_present: false,
    runtime_credentials_private: true,
    persistent_inventory_available: true,
    persistent_user_present: false,
    persistent_user_matches: 0,
    persistent_usm_user_count: 0,
  });
  const result = await updateRouterSnmpv3({
    enabled: false,
    username: "",
    authPassphrase: "",
    privacyPassphrase: "",
    sourceZone: "",
  });
  assert.equal(result.enabled, false);
  assert.equal(result.status, "review");
  assert.equal(result.firewall_available, false);
  assert.equal(result.firewall_reloaded, false);
  assert.equal(result.process_running, false);
  assert.equal(result.runtime_credentials_present, false);
  assert.equal(result.runtime_credentials_private, true);
});

test("disables SNMPv3 without resending or retaining passphrases", async () => {
  let requestInit;
  globalThis.fetch = async (_url, init) => {
    requestInit = init;
    return jsonResponse({
      ...ready,
      enabled: false,
      status: "review",
      username: "",
      source_zone: "",
      auth_type: "",
      privacy_type: "",
      allow_write: "",
      restricted_oid: "",
      firewall_available: true,
      firewall_reloaded: true,
      firewall_rule_present: false,
      firewall_rule_configured: false,
      process_running: false,
      private_config_permissions: true,
      runtime_credentials_present: false,
      runtime_credentials_private: true,
      persistent_inventory_available: true,
      persistent_user_present: false,
      persistent_user_matches: 0,
      persistent_usm_user_count: 1,
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
  assert.equal(result.status, "review");
  assert.equal(result.persistent_user_present, false);
  assert.equal(result.persistent_user_matches, 0);
  assert.equal(result.persistent_usm_user_count, 1,
    "unrelated persistent Net-SNMP users are preserved while the managed user's key is removed");
});
