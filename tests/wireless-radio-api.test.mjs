import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { updateRouterWirelessRadio, getRouterWirelessRadioSchedules, updateRouterWirelessRadioSchedule, createRouterWirelessAp } from "../ui/quantumgrid/src/routerApi.ts";

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


test("loads weekly radio schedules with same-origin no-store semantics", async () => {
  let url = "";
  let init;
  globalThis.fetch = async (target, options) => {
    url = String(target);
    init = options;
    return jsonResponse({ok:true,schedules:[{
      radio:"radio0",configured:true,valid:true,enabled:true,
      days:[1,2,3,4,5],start_time:"08:00",end_time:"22:00",
      runtime_available:true,runtime_managed:true,runtime_enabled:true,
      runtime_config_disabled:false,desired_enabled:true,runtime_matches:true,router_local_time:"08:00:15",router_weekday:1,
    }]});
  };
  const schedules = await getRouterWirelessRadioSchedules();
  assert.equal(url,"/cgi-bin/luci/admin/services/quantumgrid/wireless-radio-schedule");
  assert.equal(init.method,"GET");
  assert.equal(init.credentials,"same-origin");
  assert.equal(init.cache,"no-store");
  assert.deepEqual(schedules[0],{
    radio:"radio0",configured:true,valid:true,enabled:true,
    days:[1,2,3,4,5],start_time:"08:00",end_time:"22:00",
    runtime_available:true,runtime_managed:true,runtime_enabled:true,
    runtime_config_disabled:false,desired_enabled:true,runtime_matches:true,router_local_time:"08:00:15",router_weekday:1,
  });
});

test("preserves unknown runtime status without inventing an enabled or disabled result", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true,
    schedules: [{
      radio: "radio1",
      configured: true,
      valid: true,
      enabled: true,
      days: [1, 2, 3, 4, 5],
      start_time: "08:00",
      end_time: "22:00",
      runtime_available: false,
      runtime_managed: true,
      desired_enabled: true,
      router_local_time: "07:59:45",
      router_weekday: 1,
    }],
  });
  const [schedule] = await getRouterWirelessRadioSchedules();
  assert.equal(schedule.runtime_available, false);
  assert.equal(schedule.runtime_managed, true);
  assert.equal(schedule.desired_enabled, true);
  assert.equal(schedule.runtime_enabled, undefined);
  assert.equal(schedule.runtime_matches, undefined);
  assert.equal(schedule.router_local_time, "07:59:45");
});

test("rejects claimed live telemetry when required runtime fields are missing", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true,
    schedules: [{
      radio: "radio0", configured: true, valid: true, enabled: true,
      days: [1], start_time: "08:00", end_time: "22:00",
      runtime_available: true, runtime_managed: true,
      runtime_enabled: false, runtime_config_disabled: false,
      desired_enabled: true, runtime_matches: true,
      router_local_time: "08:00:00", router_weekday: 1,
    }],
  });
  await assert.rejects(getRouterWirelessRadioSchedules(), /invalid radio schedule record/);
});

test("saves a weekly radio schedule through confirmed same-origin POST", async () => {
  let url = "";
  let init;
  globalThis.fetch = async (target, options) => {
    url = String(target);
    init = options;
    return jsonResponse({
      ok:true,radio:"radio1",configured:true,valid:true,enabled:false,
      days:[1,5,7],start_time:"22:00",end_time:"06:00",
      runtime_available:true,runtime_managed:true,runtime_enabled:false,
      runtime_config_disabled:true,desired_enabled:true,runtime_matches:false,
      router_local_time:"22:00:02",router_weekday:1,apply_after_seconds:30,
    });
  };
  const result = await updateRouterWirelessRadioSchedule({
    radio:"radio1",enabled:false,days:[7,1,5],startTime:"22:00",endTime:"06:00",
  });
  assert.equal(url,"/cgi-bin/luci/admin/services/quantumgrid/wireless-radio-schedule");
  assert.equal(init.method,"POST");
  assert.equal(init.credentials,"same-origin");
  assert.equal(init.cache,"no-store");
  const form = new URLSearchParams(init.body);
  assert.equal(form.get("radio"),"radio1");
  assert.equal(form.get("enabled"),"0");
  assert.equal(form.get("days"),"1,5,7");
  assert.equal(form.get("start_time"),"22:00");
  assert.equal(form.get("end_time"),"06:00");
  assert.equal(form.get("confirmed"),"1");
  assert.equal(result.apply_after_seconds,30);
  assert.equal(result.runtime_available,true);
  assert.equal(result.runtime_enabled,false);
  assert.equal(result.runtime_config_disabled,true);
  assert.equal(result.runtime_matches,false);
  assert.equal(result.router_weekday,1);
  assert.equal(result.router_local_time,"22:00:02");
});

test("schedule API rejects unsafe radio, weekday and time values before network access", async () => {
  globalThis.fetch = async () => { throw new Error("fetch must not run for invalid input"); };
  await assert.rejects(updateRouterWirelessRadioSchedule({
    radio:"../radio0",enabled:true,days:[1],startTime:"08:00",endTime:"22:00",
  }),/Invalid wireless radio/);
  await assert.rejects(updateRouterWirelessRadioSchedule({
    radio:"radio0",enabled:true,days:[1,1],startTime:"08:00",endTime:"22:00",
  }),/unique weekdays/);
  await assert.rejects(updateRouterWirelessRadioSchedule({
    radio:"radio0",enabled:true,days:[1],startTime:"24:00",endTime:"22:00",
  }),/valid 24-hour times/);
});


test("creates an additional AP on an existing radio with same-origin and live-runtime confirmation", async () => {
  let url = "";
  let init;
  globalThis.fetch = async (target, options) => {
    url = String(target);
    init = options;
    return jsonResponse({
      ok: true, radio: "radio0", section: "qg_ap_1", ssid: "QuantumGrid Guest",
      network: "guest", encryption: "sae-mixed", hidden: false, key_set: true,
      reloaded: true, runtime_verified: true, rolled_back: false,
    });
  };
  const result = await createRouterWirelessAp({
    radio: "radio0", ssid: "QuantumGrid Guest", network: "guest",
    encryption: "sae-mixed", key: "secure-guest-passphrase", hidden: false,
  });
  assert.equal(url, "/cgi-bin/luci/admin/services/quantumgrid/wireless-ap-create");
  assert.equal(init.method, "POST");
  assert.equal(init.credentials, "same-origin");
  assert.equal(init.cache, "no-store");
  const form = new URLSearchParams(init.body);
  assert.equal(form.get("radio"), "radio0");
  assert.equal(form.get("ssid"), "QuantumGrid Guest");
  assert.equal(form.get("network"), "guest");
  assert.equal(form.get("encryption"), "sae-mixed");
  assert.equal(form.get("key"), "secure-guest-passphrase");
  assert.equal(form.get("hidden"), "0");
  assert.equal(form.get("confirmed"), "1");
  assert.equal(result.runtime_verified, true);
  assert.equal(result.rolled_back, false);
});

test("AP creation rejects unsafe identities, insecure modes and malformed credentials before fetch", async () => {
  globalThis.fetch = async () => { throw new Error("fetch must not run for invalid AP input"); };
  const base = {
    radio: "radio0", ssid: "Guest", network: "guest",
    encryption: "psk2", key: "secure-guest-passphrase", hidden: false,
  };
  await assert.rejects(createRouterWirelessAp({ ...base, radio: "../radio0" }), /existing wireless radio/);
  await assert.rejects(createRouterWirelessAp({ ...base, network: "../wan" }), /existing internal routed network/);
  await assert.rejects(createRouterWirelessAp({ ...base, ssid: "x".repeat(33) }), /SSID/);
  await assert.rejects(createRouterWirelessAp({ ...base, encryption: "none" }), /must use WPA2-Personal/);
  await assert.rejects(createRouterWirelessAp({ ...base, encryption: "wpa2" }), /must use WPA2-Personal/);
  await assert.rejects(createRouterWirelessAp({ ...base, key: "short" }), /8–63 bytes/);
  await assert.rejects(createRouterWirelessAp({ ...base, key: "bad\\npassphrase" }), /control characters/);
});

test("AP creation refuses a response that does not prove live runtime verification", async () => {
  globalThis.fetch = async () => jsonResponse({
    ok: true, radio: "radio0", section: "qg_ap_1", ssid: "Guest", network: "guest",
    encryption: "psk2", hidden: false, key_set: true,
    reloaded: true, runtime_verified: false, rolled_back: false,
  });
  await assert.rejects(createRouterWirelessAp({
    radio: "radio0", ssid: "Guest", network: "guest",
    encryption: "psk2", key: "secure-guest-passphrase", hidden: false,
  }), /did not confirm the new AP/);
});
