import test from "node:test";
import assert from "node:assert/strict";
import {
  collectWifiClientHistory,
  mergeWifiClientHistory,
  pruneWifiClientHistory,
  readWifiClientHistory,
  WIFI_CLIENT_HISTORY_MAX_SAMPLES,
} from "../ui/quantumgrid/src/wifiClientHistory.ts";

const sample = (overrides = {}) => ({
  sampledAt: 1_800_000_000,
  mac: "aa:bb:cc:dd:ee:ff",
  hostname: "laptop",
  ip: "192.0.2.10",
  ssid: "QuantumGrid",
  radio: "radio0",
  band: "5 GHz",
  authorized: true,
  signalDbm: -55,
  rxMbps: 12.5,
  txMbps: 6.25,
  ...overrides,
});

test("browser history parser rejects corrupt JSON and malformed records", () => {
  assert.deepEqual(readWifiClientHistory("{bad"), []);
  assert.deepEqual(readWifiClientHistory(JSON.stringify({ samples: [] })), []);
  const parsed = readWifiClientHistory(JSON.stringify([
    sample(),
    sample({ mac: "not-a-mac" }),
    sample({ sampledAt: Number.NaN }),
    null,
  ]));
  assert.equal(parsed.length, 1);
  assert.equal(parsed[0].mac, "aa:bb:cc:dd:ee:ff");
});

test("history parser strips control characters and bounds stored fields", () => {
  const parsed = readWifiClientHistory(JSON.stringify([
    sample({ hostname: "desk\n\u0000host", ssid: "x".repeat(200) }),
  ]));
  assert.equal(parsed[0].hostname, "desk  host");
  assert.equal(parsed[0].ssid.length, 128);
});

test("collection records associated Wi-Fi clients and matches optional DHCP leases", () => {
  const overview = {
    clients: [{
      hostname: "living-room-tv",
      ip: "192.0.2.44",
      mac: "aa:bb:cc:dd:ee:01",
      lease_remaining_seconds: 600,
    }],
    wireless_clients: [
      {
        ifname: "wlan0", radio: "radio0", ssid: "Home", mac: "aa:bb:cc:dd:ee:01",
        associated: true, authorized: true, band: "2.4 GHz", signal_dbm: -61,
        measured_rx_mbps: 8, measured_tx_mbps: 3,
      },
      {
        ifname: "wlan0", radio: "radio0", ssid: "Home", mac: "aa:bb:cc:dd:ee:02",
        associated: false, authorized: false, band: "2.4 GHz",
      },
    ],
  };
  const collected = collectWifiClientHistory(overview, 1_800_000_000);
  assert.equal(collected.length, 1);
  assert.equal(collected[0].hostname, "living-room-tv");
  assert.equal(collected[0].ip, "192.0.2.44");
  assert.equal(collected[0].signalDbm, -61);
  assert.equal(collected[0].rxMbps, 8);
});

test("collection keeps associated clients even when a DHCP lease is unavailable", () => {
  const overview = {
    wireless_clients: [{
      ifname: "wlan1", radio: "radio1", ssid: "Guest", mac: "aa:bb:cc:dd:ee:03",
      associated: true, authorized: false, band: "5 GHz",
    }],
  };
  const collected = collectWifiClientHistory(overview, 1_800_000_000);
  assert.equal(collected.length, 1);
  assert.equal(collected[0].hostname, "");
  assert.equal(collected[0].ip, "");
  assert.equal(collected[0].authorized, false);
});

test("retention removes expired and future-dated samples", () => {
  const now = 1_800_000_000;
  const pruned = pruneWifiClientHistory([
    sample({ sampledAt: now - 2 * 86400 }),
    sample({ mac: "aa:bb:cc:dd:ee:01", sampledAt: now - 3600 }),
    sample({ mac: "aa:bb:cc:dd:ee:02", sampledAt: now + 10000 }),
  ], now, 1);
  assert.equal(pruned.length, 1);
  assert.equal(pruned[0].mac, "aa:bb:cc:dd:ee:01");
});

test("merge deduplicates device timestamps, applies retention and caps storage", () => {
  const now = 1_800_000_000;
  const existing = [sample({ sampledAt: now - 60 })];
  const incoming = [
    sample({ sampledAt: now - 60 }),
    sample({ mac: "aa:bb:cc:dd:ee:01", sampledAt: now }),
    sample({ mac: "aa:bb:cc:dd:ee:02", sampledAt: now - 8 * 86400 }),
  ];
  const merged = mergeWifiClientHistory(existing, incoming, now, 7);
  assert.equal(merged.length, 2);
  assert.equal(merged[0].sampledAt, now - 60);
  assert.equal(merged[1].mac, "aa:bb:cc:dd:ee:01");

  const oversized = Array.from({ length: WIFI_CLIENT_HISTORY_MAX_SAMPLES + 10 }, (_, index) =>
    sample({ sampledAt: now - index, mac: "aa:bb:cc:dd:ee:ff" }),
  );
  const capped = pruneWifiClientHistory(oversized, now, 30);
  assert.equal(capped.length, WIFI_CLIENT_HISTORY_MAX_SAMPLES);
});
