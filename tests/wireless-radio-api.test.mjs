import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { updateRouterWirelessRadio } from "../ui/quantumgrid/src/routerApi.ts";

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

test("enables a disabled radio using same-origin POST and verifies live runtime state", async () => {
  let requestUrl = "";
  let requestInit;
  globalThis.fetch = async (url, init) => {
    requestUrl = String(url);
    requestInit = init;
    return jsonResponse({
      ok: true,
      radio: "radio0",
      enabled: true,
      disabled: false,
      runtime_up: true,
      changed: true,
      reloaded: true,
      rolled_back: false,
    });
  };

  const result = await updateRouterWirelessRadio({
    radio: "radio0",
    enabled: true,
    expectedDisabled: true,
  });
  assert.equal(requestUrl, "/cgi-bin/luci/admin/services/quantumgrid/wireless-radio-update");
  assert.equal(requestInit.method, "POST");
  assert.equal(requestInit.credentials, "same-origin");
  assert.equal(requestInit.cache, "no-store");
  const form = new URLSearchParams(requestInit.body);
  assert.equal(form.get("radio"), "radio0");
  assert.equal(form.get("enabled"), "1");
  assert.equal(form.get("expected_disabled"), "1");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.enabled, true);
  assert.equal(result.disabled, false);
  assert.equal(result.runtime_up, true);
  assert.equal(result.changed, true);
  assert.equal(result.reloaded, true);
});

test("disables an enabled radio with an explicit current-state precondition", async () => {
  let requestInit;
  globalThis.fetch = async (_url, init) => {
    requestInit = init;
    return jsonResponse({
      ok: true,
      radio: "radio1",
      enabled: false,
      disabled: true,
      runtime_up: false,
      changed: true,
      reloaded: true,
      rolled_back: false,
    });
  };

  const result = await updateRouterWirelessRadio({
    radio: "radio1",
    enabled: false,
    expectedDisabled: false,
  });
  const form = new URLSearchParams(requestInit.body);
  assert.equal(form.get("radio"), "radio1");
  assert.equal(form.get("enabled"), "0");
  assert.equal(form.get("expected_disabled"), "0");
  assert.equal(result.enabled, false);
  assert.equal(result.disabled, true);
  assert.equal(result.runtime_up, false);
});

test("accepts a verified no-op without claiming a Wi-Fi reload occurred", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true,
    radio: "radio0",
    enabled: true,
    disabled: false,
    runtime_up: true,
    changed: false,
    reloaded: false,
    rolled_back: false,
  });
  const result = await updateRouterWirelessRadio({
    radio: "radio0",
    enabled: true,
    expectedDisabled: false,
  });
  assert.equal(result.changed, false);
  assert.equal(result.reloaded, false);
});

test("radio API rejects unsafe identities and non-boolean state preconditions before fetch", async () => {
  globalThis.fetch = async () => {
    throw new Error("fetch must not be called for invalid input");
  };
  await assert.rejects(
    updateRouterWirelessRadio({ radio: "../radio0", enabled: true, expectedDisabled: true }),
    /Invalid wireless radio section name/,
  );
  await assert.rejects(
    updateRouterWirelessRadio({ radio: "radio0", enabled: 1, expectedDisabled: true }),
    /explicit booleans/,
  );
  await assert.rejects(
    updateRouterWirelessRadio({ radio: "radio0", enabled: true, expectedDisabled: "1" }),
    /explicit booleans/,
  );
});

test("radio API rejects a mismatched radio, configuration state or runtime state", async () => {
  const expected = {
    ok: true,
    radio: "radio0",
    enabled: false,
    disabled: true,
    runtime_up: false,
    changed: true,
    reloaded: true,
    rolled_back: false,
  };
  for (const payload of [
    { ...expected, radio: "radio1" },
    { ...expected, enabled: true },
    { ...expected, disabled: false },
    { ...expected, runtime_up: true },
    { ...expected, changed: false },
    { ...expected, reloaded: false },
    { ...expected, rolled_back: true },
  ]) {
    globalThis.fetch = async () => jsonResponse(payload);
    await assert.rejects(
      updateRouterWirelessRadio({ radio: "radio0", enabled: false, expectedDisabled: false }),
      /did not confirm the requested radio configuration and live runtime state/,
    );
  }
});

test("radio API rejects server errors and non-JSON session failures", async () => {
  globalThis.fetch = async () => jsonResponse({ error: "administrator session expired" }, 403);
  await assert.rejects(
    updateRouterWirelessRadio({ radio: "radio0", enabled: true, expectedDisabled: true }),
    /administrator session expired/,
  );
  globalThis.fetch = async () => new Response("Forbidden", { status: 403 });
  await assert.rejects(
    updateRouterWirelessRadio({ radio: "radio0", enabled: true, expectedDisabled: true }),
    /active router administrator session/,
  );
});
