import assert from "node:assert/strict";
import { afterEach, beforeEach, test } from "node:test";
import { loginToRouter } from "../ui/quantumgrid/src/routerApi.ts";

const API_URL = "/cgi-bin/luci/admin/services/quantumgrid/api";
const PASSWORD_URL = "/cgi-bin/luci/admin/services/quantumgrid/password";
const originalFetch = globalThis.fetch;

function jsonResponse(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json; charset=UTF-8" },
  });
}

beforeEach(() => {
  globalThis.fetch = originalFetch;
});

afterEach(() => {
  globalThis.fetch = originalFetch;
});

test("first login sets the root password even when rpcd accepts the initial session", async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    const path = String(url);
    calls.push({ path, options });
    if (path === API_URL && options.method === "POST") {
      return jsonResponse({ ok: true, root_password_set: false });
    }
    if (path === PASSWORD_URL) {
      return jsonResponse({ ok: true });
    }
    if (path === API_URL && options.method === "GET") {
      return jsonResponse({ ok: true, root_password_set: true });
    }
    throw new Error(`Unexpected request: ${path} ${options.method ?? "GET"}`);
  };

  const overview = await loginToRouter("root", "A-strong-first-boot-password");
  assert.equal(overview.root_password_set, true);
  assert.equal(calls.length, 3);
  assert.equal(calls[0].path, API_URL);
  assert.equal(new URLSearchParams(calls[0].options.body).get("luci_password"), "A-strong-first-boot-password");
  assert.equal(calls[1].path, PASSWORD_URL);
  assert.equal(new URLSearchParams(calls[1].options.body).get("password"), "A-strong-first-boot-password");
  assert.equal(calls[2].path, API_URL);
  assert.equal(calls[2].options.method, "GET");
});

test("existing root password is not changed during normal login", async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    calls.push({ path: String(url), options });
    return jsonResponse({ ok: true, root_password_set: true });
  };
  const overview = await loginToRouter("root", "Existing-correct-password");
  assert.equal(overview.root_password_set, true);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].path, API_URL);
});

test("wrong password on an already-configured router never triggers password setup", async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    calls.push({ path: String(url), options });
    return jsonResponse({ error: "unauthorized" }, 403);
  };
  await assert.rejects(() => loginToRouter("root", "Wrong-password"), /Router sign-in failed/);
  assert.equal(calls.length, 2);
  assert.equal(calls[0].path, API_URL);
  assert.equal(calls[1].path, API_URL);
  assert.equal(new URLSearchParams(calls[1].options.body).get("luci_password"), "");
  assert.ok(calls.every(call => call.path !== PASSWORD_URL));
});

test("firmware without the root-password state signal fails closed", async () => {
  let calls = 0;
  globalThis.fetch = async () => {
    calls += 1;
    return jsonResponse({ ok: true });
  };
  await assert.rejects(() => loginToRouter("root", "Some-password"), /cannot verify whether the root password is set/);
  assert.equal(calls, 2);
});
