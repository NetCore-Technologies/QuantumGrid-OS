import test from "node:test";
import assert from "node:assert/strict";
import {
  sampleWireGuardPeerRates,
  wireGuardPeerCounterKey,
} from "../ui/quantumgrid/src/wireGuardPeerRates.ts";

const peer = (overrides = {}) => ({
  interface: "wg0",
  allowed_ips: ["10.0.0.0/24", "192.0.2.0/24"],
  receive_bytes: 0,
  transmit_bytes: 0,
  ...overrides,
});

test("peer keys are stable across AllowedIPs ordering and do not require key material", () => {
  assert.equal(
    wireGuardPeerCounterKey(peer()),
    wireGuardPeerCounterKey(peer({ allowed_ips: ["192.0.2.0/24", "10.0.0.0/24"] })),
  );
});

test("measures per-peer receive and transmit Mbps from successive samples", () => {
  const first = sampleWireGuardPeerRates([peer()], new Map(), 10_000);
  assert.equal(first.rates.size, 0);
  const second = sampleWireGuardPeerRates(
    [peer({ receive_bytes: 1_250_000, transmit_bytes: 2_500_000 })],
    first.nextCounters,
    11_000,
  );
  const rate = second.rates.get(wireGuardPeerCounterKey(peer()));
  assert.deepEqual(rate, { receiveMbps: 10, transmitMbps: 20, sampleSeconds: 1 });
});

test("idle peers report a measured zero rate", () => {
  const first = sampleWireGuardPeerRates([peer()], new Map(), 1_000);
  const second = sampleWireGuardPeerRates([peer()], first.nextCounters, 4_000);
  assert.deepEqual(second.rates.get(wireGuardPeerCounterKey(peer())), {
    receiveMbps: 0, transmitMbps: 0, sampleSeconds: 3,
  });
});

test("missing peers and the first sample never invent rates", () => {
  const first = sampleWireGuardPeerRates([peer()], new Map(), 1_000);
  assert.equal(first.rates.size, 0);
  const absent = sampleWireGuardPeerRates([], first.nextCounters, 2_000);
  assert.equal(absent.rates.size, 0);
  assert.equal(absent.nextCounters.size, 0);
});

test("counter resets and stale intervals remain unavailable", () => {
  const first = sampleWireGuardPeerRates([peer({ receive_bytes: 100, transmit_bytes: 200 })], new Map(), 1_000);
  const reset = sampleWireGuardPeerRates(
    [peer({ receive_bytes: 50, transmit_bytes: 250 })], first.nextCounters, 2_000,
  );
  const resetRate = reset.rates.get(wireGuardPeerCounterKey(peer()));
  assert.equal(resetRate?.receiveMbps, null);
  assert.equal(resetRate?.transmitMbps, 0.0004);
  const stale = sampleWireGuardPeerRates(
    [peer({ receive_bytes: 100, transmit_bytes: 300 })], reset.nextCounters, 63_000,
  );
  const staleRate = stale.rates.get(wireGuardPeerCounterKey(peer()));
  assert.equal(staleRate?.receiveMbps, null);
  assert.equal(staleRate?.transmitMbps, null);
  assert.equal(staleRate?.sampleSeconds, null);
});

test("duplicate interface and AllowedIPs tuples are ambiguous and never matched", () => {
  const previous = sampleWireGuardPeerRates([peer()], new Map(), 1_000);
  const duplicates = sampleWireGuardPeerRates(
    [peer({ receive_bytes: 1000 }), peer({ receive_bytes: 2000 })],
    previous.nextCounters,
    2_000,
  );
  assert.equal(duplicates.rates.size, 0);
  assert.equal(duplicates.nextCounters.size, 0);
});
