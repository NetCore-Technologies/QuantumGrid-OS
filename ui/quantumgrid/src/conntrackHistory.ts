export interface ConntrackSnapshotInput {
  available: boolean;
  count?: number;
  maximum?: number;
  free?: number;
  used_percent?: number;
}

export interface ConntrackHistorySample {
  sampledAt: number;
  count: number;
  maximum: number;
  free: number;
  usedPercent: number;
}

export interface ConntrackHistorySummary {
  samples: number;
  firstSampleAt: number;
  lastSampleAt: number;
  durationSeconds: number;
  firstCount: number;
  lastCount: number;
  entryDelta: number;
  minimumUsedPercent: number;
  maximumUsedPercent: number;
}

export const CONNTRACK_HISTORY_MAX_SAMPLES = 30;

function validCounter(value: number | undefined): value is number {
  return value !== undefined && Number.isSafeInteger(value) && value >= 0;
}

export function appendConntrackSample(
  history: readonly ConntrackHistorySample[],
  snapshot: ConntrackSnapshotInput | null | undefined,
  sampledAt: number,
  maximumSamples = CONNTRACK_HISTORY_MAX_SAMPLES,
): ConntrackHistorySample[] {
  if (
    !snapshot ||
    snapshot.available !== true ||
    !validCounter(snapshot.count) ||
    !validCounter(snapshot.maximum) ||
    snapshot.maximum < 1 ||
    !Number.isFinite(sampledAt) ||
    sampledAt <= 0 ||
    !Number.isInteger(maximumSamples) ||
    maximumSamples < 1
  ) {
    return history.slice(-CONNTRACK_HISTORY_MAX_SAMPLES);
  }

  const sample: ConntrackHistorySample = {
    sampledAt,
    count: snapshot.count,
    maximum: snapshot.maximum,
    free: Math.max(0, snapshot.maximum - snapshot.count),
    usedPercent: snapshot.count / snapshot.maximum * 100,
  };

  const last = history[history.length - 1];
  if (last && sampledAt < last.sampledAt) {
    return history.slice(-maximumSamples);
  }

  if (last && sampledAt === last.sampledAt) {
    return [...history.slice(0, -1), sample].slice(-maximumSamples);
  }

  return [...history, sample].slice(-maximumSamples);
}

export function summarizeConntrackHistory(
  history: readonly ConntrackHistorySample[],
): ConntrackHistorySummary | null {
  if (history.length === 0) return null;
  const first = history[0];
  const last = history[history.length - 1];
  let minimumUsedPercent = first.usedPercent;
  let maximumUsedPercent = first.usedPercent;

  for (const sample of history.slice(1)) {
    minimumUsedPercent = Math.min(minimumUsedPercent, sample.usedPercent);
    maximumUsedPercent = Math.max(maximumUsedPercent, sample.usedPercent);
  }

  return {
    samples: history.length,
    firstSampleAt: first.sampledAt,
    lastSampleAt: last.sampledAt,
    durationSeconds: Math.max(0, last.sampledAt - first.sampledAt),
    firstCount: first.count,
    lastCount: last.count,
    entryDelta: last.count - first.count,
    minimumUsedPercent,
    maximumUsedPercent,
  };
}
