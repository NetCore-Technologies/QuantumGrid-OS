import test from "node:test";
import assert from "node:assert/strict";
import {
  appendConntrackSample,
  CONNTRACK_HISTORY_MAX_SAMPLES,
  summarizeConntrackHistory,
} from "../ui/quantumgrid/src/conntrackHistory.ts";

const snapshot = (count, maximum = 1000) => ({
  available: true, count, maximum, free: Math.max(0, maximum - count),
});

test("records only valid available kernel counter samples", () => {
  const history = appendConntrackSample([], snapshot(250), 100);
  assert.deepEqual(history, [{
    sampledAt: 100, count: 250, maximum: 1000, free: 750, usedPercent: 25,
  }]);
});

test("does not invent samples when telemetry is unavailable or malformed", () => {
  assert.deepEqual(appendConntrackSample([], null, 100), []);
  assert.deepEqual(appendConntrackSample([], { available: false }, 100), []);
  assert.deepEqual(appendConntrackSample([], snapshot(-1), 100), []);
  assert.deepEqual(appendConntrackSample([], snapshot(10, 0), 100), []);
  assert.deepEqual(appendConntrackSample([], snapshot(1.5), 100), []);
  assert.deepEqual(appendConntrackSample([], snapshot(Number.NaN), 100), []);
  assert.deepEqual(appendConntrackSample([], snapshot(10), Number.NaN), []);
});

test("replaces a sample with the same timestamp instead of double-counting it", () => {
  const first = appendConntrackSample([], snapshot(100), 100);
  const updated = appendConntrackSample(first, snapshot(150), 100);
  assert.equal(updated.length, 1);
  assert.equal(updated[0].count, 150);
});

test("ignores out-of-order timestamps so history remains chronological", () => {
  const first = appendConntrackSample([], snapshot(100), 100);
  const second = appendConntrackSample(first, snapshot(200), 103);
  const older = appendConntrackSample(second, snapshot(50), 102);
  assert.deepEqual(older, second);
});

test("keeps a bounded rolling history", () => {
  let history = [];
  for (let second = 1; second <= 50; second += 1) {
    history = appendConntrackSample(history, snapshot(second), second);
  }
  assert.equal(history.length, CONNTRACK_HISTORY_MAX_SAMPLES);
  assert.equal(history[0].sampledAt, 21);
  assert.equal(history[history.length - 1].sampledAt, 50);
});

test("reports real capacity overflow without wrapping free entries", () => {
  const history = appendConntrackSample([], snapshot(1200, 1000), 100);
  assert.equal(history[0].free, 0);
  assert.equal(history[0].usedPercent, 120);
});

test("summarizes utilization range, sample duration and entry delta", () => {
  let history = appendConntrackSample([], snapshot(200, 1000), 10);
  history = appendConntrackSample(history, snapshot(750, 1000), 25);
  history = appendConntrackSample(history, snapshot(500, 1000), 40);
  assert.deepEqual(summarizeConntrackHistory(history), {
    samples: 3,
    firstSampleAt: 10,
    lastSampleAt: 40,
    durationSeconds: 30,
    firstCount: 200,
    lastCount: 500,
    entryDelta: 300,
    minimumUsedPercent: 20,
    maximumUsedPercent: 75,
  });
});

test("returns no summary for an empty history", () => {
  assert.equal(summarizeConntrackHistory([]), null);
});
