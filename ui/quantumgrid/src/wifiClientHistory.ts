import type { RouterOverview } from "./routerApi.js";

export type WifiClientHistoryRetentionDays = 1 | 7 | 30;

export type WifiClientHistorySample = {
  sampledAt: number;
  mac: string;
  hostname: string;
  ip: string;
  ssid: string;
  radio: string;
  band: string;
  authorized: boolean;
  signalDbm: number | null;
  rxMbps: number | null;
  txMbps: number | null;
};

export const WIFI_CLIENT_HISTORY_KEY = "quantumgrid-wifi-client-history-v1";
export const WIFI_CLIENT_HISTORY_SETTINGS_KEY = "quantumgrid-wifi-client-history-settings-v1";
export const WIFI_CLIENT_HISTORY_SAMPLE_INTERVAL_SECONDS = 900;
export const WIFI_CLIENT_HISTORY_MAX_SAMPLES = 10000;

const MAC_PATTERN = /^[0-9a-f]{2}(?::[0-9a-f]{2}){5}$/i;

function cleanText(value: unknown, limit: number): string {
  if (typeof value !== "string") return "";
  return value.replace(/[\u0000-\u001f\u007f]/g, " ").slice(0, limit);
}

function cleanMeasurement(value: unknown, minimum: number, maximum: number): number | null {
  return typeof value === "number" && Number.isFinite(value) && value >= minimum && value <= maximum
    ? value
    : null;
}

function normalizeSample(value: unknown): WifiClientHistorySample | null {
  if (typeof value !== "object" || value === null) return null;
  const sample = value as Record<string, unknown>;
  const mac = cleanText(sample.mac, 17).toLowerCase();
  if (!MAC_PATTERN.test(mac)) return null;
  if (typeof sample.sampledAt !== "number" || !Number.isFinite(sample.sampledAt) || sample.sampledAt <= 0) return null;
  if (typeof sample.authorized !== "boolean") return null;
  return {
    sampledAt: Math.floor(sample.sampledAt),
    mac,
    hostname: cleanText(sample.hostname, 128),
    ip: cleanText(sample.ip, 64),
    ssid: cleanText(sample.ssid, 128),
    radio: cleanText(sample.radio, 64),
    band: cleanText(sample.band, 32),
    authorized: sample.authorized,
    signalDbm: cleanMeasurement(sample.signalDbm, -130, 0),
    rxMbps: cleanMeasurement(sample.rxMbps, 0, 100000),
    txMbps: cleanMeasurement(sample.txMbps, 0, 100000),
  };
}

export function readWifiClientHistory(raw: string | null): WifiClientHistorySample[] {
  if (!raw) return [];
  try {
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed
      .map(normalizeSample)
      .filter((item): item is WifiClientHistorySample => item !== null)
      .slice(-WIFI_CLIENT_HISTORY_MAX_SAMPLES);
  } catch {
    return [];
  }
}

export function collectWifiClientHistory(
  overview: RouterOverview,
  sampledAt: number,
): WifiClientHistorySample[] {
  if (!Number.isFinite(sampledAt) || sampledAt <= 0) return [];
  const leases = new Map(
    (overview.clients ?? []).map((lease) => [lease.mac.toLowerCase(), lease]),
  );
  return (overview.wireless_clients ?? [])
    .filter((client) => client.associated === true && MAC_PATTERN.test(client.mac))
    .map((client) => {
      const lease = leases.get(client.mac.toLowerCase());
      return normalizeSample({
        sampledAt,
        mac: client.mac,
        hostname: lease?.hostname ?? "",
        ip: lease?.ip ?? "",
        ssid: client.ssid,
        radio: client.radio,
        band: client.band,
        authorized: client.authorized,
        signalDbm: client.signal_current_dbm ?? client.signal_dbm,
        rxMbps: client.measured_rx_mbps,
        txMbps: client.measured_tx_mbps,
      });
    })
    .filter((item): item is WifiClientHistorySample => item !== null);
}

export function pruneWifiClientHistory(
  samples: WifiClientHistorySample[],
  nowSeconds: number,
  retentionDays: WifiClientHistoryRetentionDays,
): WifiClientHistorySample[] {
  const cutoff = nowSeconds - retentionDays * 86400;
  return samples
    .map(normalizeSample)
    .filter((item): item is WifiClientHistorySample =>
      item !== null && item.sampledAt >= cutoff && item.sampledAt <= nowSeconds + 300)
    .sort((left, right) => left.sampledAt - right.sampledAt)
    .slice(-WIFI_CLIENT_HISTORY_MAX_SAMPLES);
}

export function mergeWifiClientHistory(
  existing: WifiClientHistorySample[],
  incoming: WifiClientHistorySample[],
  nowSeconds: number,
  retentionDays: WifiClientHistoryRetentionDays,
): WifiClientHistorySample[] {
  const retained = pruneWifiClientHistory(existing, nowSeconds, retentionDays);
  const keys = new Set(retained.map((item) => item.sampledAt + ":" + item.mac));
  for (const value of incoming) {
    const sample = normalizeSample(value);
    if (!sample || sample.sampledAt < nowSeconds - retentionDays * 86400 || sample.sampledAt > nowSeconds + 300) continue;
    const key = sample.sampledAt + ":" + sample.mac;
    if (keys.has(key)) continue;
    retained.push(sample);
    keys.add(key);
  }
  return retained
    .sort((left, right) => left.sampledAt - right.sampledAt)
    .slice(-WIFI_CLIENT_HISTORY_MAX_SAMPLES);
}
