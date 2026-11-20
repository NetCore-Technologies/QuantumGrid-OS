import test from "node:test";
import assert from "node:assert/strict";
import { calculateCounterRateMbps } from "../ui/quantumgrid/src/interfaceRates.ts";

test("converts cumulative byte deltas into decimal megabits per second", () => {
  assert.equal(calculateCounterRateMbps(1_250_000, 0, 1), 10);
  assert.equal(calculateCounterRateMbps(2_000_000, 1_000_000, 0.5), 16);
});

test("reports an idle interface as a measured zero rate", () => {
  assert.equal(calculateCounterRateMbps(10_000, 10_000, 3), 0);
});

test("does not invent rates before two valid samples", () => {
  assert.equal(calculateCounterRateMbps(undefined, 100, 1), null);
  assert.equal(calculateCounterRateMbps(100, undefined, 1), null);
  assert.equal(calculateCounterRateMbps(Number.NaN, 100, 1), null);
});

test("rejects counter resets and invalid intervals", () => {
  assert.equal(calculateCounterRateMbps(50, 100, 1), null);
  assert.equal(calculateCounterRateMbps(100, 0, 0), null);
  assert.equal(calculateCounterRateMbps(100, 0, -1), null);
  assert.equal(calculateCounterRateMbps(100, 0, 61), null);
  assert.equal(calculateCounterRateMbps(100, 0, Number.NaN), null);
});

test("keeps byte counters separate from decimal Mbps units", () => {
  assert.equal(calculateCounterRateMbps(125_000, 0, 1), 1);
  assert.equal(calculateCounterRateMbps(1_250_000, 0, 1), 10);
});
