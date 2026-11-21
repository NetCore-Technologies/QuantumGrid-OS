import test from "node:test";
import assert from "node:assert/strict";
import { planWifiChannels, recommendWifiChannel } from "../ui/quantumgrid/src/wifiChannelPlanner.ts";

const channel = (number, band, restricted = false) => ({
  channel: number,
  frequency_mhz: band === "2.4 GHz"
    ? (number === 14 ? 2484 : 2407 + number * 5)
    : band === "5 GHz"
      ? 5000 + number * 5
      : 5950 + number * 5,
  band,
  restricted,
  flags: [],
});

const radio = ({ name = "radio0", interfaces, channels }) => ({
  name,
  up: true,
  interfaces: interfaces ?? [{
    ifname: "wlan0",
    ssid: "QuantumGrid",
    bssid: "02:00:00:00:00:01",
    mode: "ap",
    up: true,
    channel: 1,
    frequency_mhz: 2412,
    htmode: "HT20",
  }],
  channels,
});

const ap = ({ bssid, band = "2.4 GHz", channel: ch, signal = -60, width, center, center2 }) => ({
  radio: "scan",
  ifname: "scan0",
  ssid: "Neighbour",
  bssid,
  mode: "Master",
  channel: ch,
  frequency_mhz: band === "2.4 GHz"
    ? (ch === 14 ? 2484 : 2407 + ch * 5)
    : band === "5 GHz"
      ? 5000 + ch * 5
      : 5950 + ch * 5,
  band,
  signal_dbm: signal,
  security: "WPA2",
  ...(width === undefined ? {} : {
    vht_operation: {
      channel_width: width,
      ...(center === undefined ? {} : { center_freq_1: center }),
      ...(center2 === undefined ? {} : { center_freq_2: center2 }),
    },
  }),
});

test("restricted channels are excluded and observed overlap ranks within one band", () => {
  const plans = planWifiChannels([
    ap({ bssid: "aa:00:00:00:00:01", channel: 1, signal: -50 }),
    ap({ bssid: "aa:00:00:00:00:02", channel: 2, signal: -60 }),
  ], [radio({
    channels: [
      channel(1, "2.4 GHz"),
      channel(2, "2.4 GHz"),
      channel(6, "2.4 GHz", true),
      channel(11, "2.4 GHz"),
    ],
  })]);

  assert.equal(plans.length, 1);
  const options = plans[0].options;
  assert.deepEqual(options.map((item) => item.channel), [11, 2, 1]);
  assert.equal(options.some((item) => item.channel === 6), false);
  assert.ok(options[0].relativeScore === 0);
  assert.ok(options[2].relativeScore === 100);
  assert.ok(options[2].observedAccessPoints > options[0].observedAccessPoints);
});

test("the router's own BSSID is excluded from neighbour scoring", () => {
  const plans = planWifiChannels([
    ap({ bssid: "02:00:00:00:00:01", channel: 1, signal: -25 }),
  ], [radio({ channels: [channel(1, "2.4 GHz"), channel(6, "2.4 GHz")] })]);

  assert.equal(plans[0].localBssidsExcluded, 1);
  assert.equal(plans[0].options.every((item) => item.observedAccessPoints === 0), true);
  assert.equal(plans[0].options.every((item) => item.relativeScore === null), true);
});

test("observations are separated by radio band", () => {
  const plans = planWifiChannels([
    ap({ bssid: "aa:00:00:00:01:01", band: "5 GHz", channel: 36, signal: -45 }),
  ], [radio({
    channels: [
      channel(1, "2.4 GHz"),
      channel(11, "2.4 GHz"),
      channel(36, "5 GHz"),
      channel(44, "5 GHz"),
    ],
  })]);

  const plan24 = plans.find((item) => item.band === "2.4 GHz");
  const plan5 = plans.find((item) => item.band === "5 GHz");
  assert.ok(plan24);
  assert.ok(plan5);
  assert.equal(plan24.options.every((item) => item.observedAccessPoints === 0), true);
  assert.ok(plan5.options.some((item) => item.observedAccessPoints > 0));
});

test("advertised 80 MHz centre width is used for overlap geometry", () => {
  const plans = planWifiChannels([
    ap({
      bssid: "aa:00:00:00:02:01",
      band: "5 GHz",
      channel: 36,
      signal: -50,
      width: 80,
      center: 42,
    }),
  ], [radio({
    interfaces: [{
      ifname: "wlan1",
      ssid: "QuantumGrid-5G",
      bssid: "02:00:00:00:00:02",
      mode: "ap",
      up: true,
      channel: 36,
      frequency_mhz: 5180,
      htmode: "VHT80",
    }],
    channels: [
      channel(36, "5 GHz"),
      channel(40, "5 GHz"),
      channel(100, "5 GHz"),
    ],
  })]);

  const options = plans[0].options;
  assert.equal(options[0].channel, 100);
  const channel40 = options.find((item) => item.channel === 40);
  const channel36 = options.find((item) => item.channel === 36);
  assert.ok(channel40 && channel36);
  assert.ok(channel40.score > channel36.score);
  assert.ok(channel36.unknownWidthAccessPoints === 0);
});

test("unknown neighbour width is explicitly counted and uses a 20 MHz fallback", () => {
  const plans = planWifiChannels([
    ap({ bssid: "aa:00:00:00:03:01", channel: 1, signal: -70 }),
  ], [radio({ channels: [channel(1, "2.4 GHz"), channel(6, "2.4 GHz")] })]);

  const first = plans[0].options.find((item) => item.channel === 1);
  assert.ok(first);
  assert.equal(first.unknownWidthAccessPoints, 1);
  assert.equal(first.observedAccessPoints, 1);
});

test("missing signal is reported instead of silently counted as a measurement", () => {
  const unknown = ap({ bssid: "aa:00:00:00:04:01", channel: 1 });
  delete unknown.signal_dbm;
  const plans = planWifiChannels([unknown], [radio({ channels: [channel(1, "2.4 GHz")] })]);

  assert.equal(plans[0].options[0].knownSignalAccessPoints, 0);
  assert.equal(plans[0].options[0].unknownSignalAccessPoints, 1);
});

test("recommends a materially cleaner channel only with measured interference and safe flags", () => {
  const plans = planWifiChannels([
    ap({ bssid: "aa:00:00:00:09:01", channel: 1, signal: -35 }),
    ap({ bssid: "aa:00:00:00:09:02", channel: 2, signal: -45 }),
  ], [radio({
    channels: [channel(1, "2.4 GHz"), channel(2, "2.4 GHz"), channel(11, "2.4 GHz")],
  })]);
  const recommendation = recommendWifiChannel(plans[0]);
  assert.ok(recommendation);
  assert.equal(recommendation.channel, 11);
  assert.equal(recommendation.current, false);
});

test("does not recommend a change when the current channel is already clear", () => {
  const plans = planWifiChannels([], [radio({
    channels: [channel(1, "2.4 GHz"), channel(6, "2.4 GHz"), channel(11, "2.4 GHz")],
  })]);
  assert.equal(recommendWifiChannel(plans[0]), null);
});

test("does not auto-recommend when radio width or observed signal confidence is unknown", () => {
  const unknownWidth = planWifiChannels([
    ap({ bssid: "aa:00:00:00:09:03", channel: 1, signal: -45 }),
  ], [radio({
    interfaces: [{
      ifname: "wlan0", ssid: "QG", bssid: "02:00:00:00:00:01", mode: "ap",
      up: true, channel: 1, frequency_mhz: 2412,
    }],
    channels: [channel(1, "2.4 GHz"), channel(11, "2.4 GHz")],
  })]);
  assert.equal(recommendWifiChannel(unknownWidth[0]), null);
  const missingSignal = ap({ bssid: "aa:00:00:00:09:04", channel: 1 });
  delete missingSignal.signal_dbm;
  const uncertainSignal = planWifiChannels([missingSignal], [radio({
    channels: [channel(1, "2.4 GHz"), channel(11, "2.4 GHz")],
  })]);
  assert.equal(recommendWifiChannel(uncertainSignal[0]), null);
});

test("does not recommend DFS, radar, passive or no-IR candidate channels", () => {
  const plans = planWifiChannels([
    ap({ bssid: "aa:00:00:00:09:05", channel: 36, band: "5 GHz", signal: -35 }),
  ], [radio({
    interfaces: [{
      ifname: "wlan0", ssid: "QG", bssid: "02:00:00:00:00:01", mode: "ap",
      up: true, channel: 36, frequency_mhz: 5180, htmode: "VHT20",
    }],
    channels: [
      { ...channel(36, "5 GHz"), frequency_mhz: 5180 },
      { ...channel(149, "5 GHz"), frequency_mhz: 5745, flags: ["radar"] },
      { ...channel(157, "5 GHz"), frequency_mhz: 5785, flags: ["no-IR"] },
    ],
  })]);
  assert.equal(recommendWifiChannel(plans[0]), null);
});
