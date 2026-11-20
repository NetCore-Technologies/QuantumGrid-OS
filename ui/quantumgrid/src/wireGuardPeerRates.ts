import { calculateCounterRateMbps } from "./interfaceRates";

export interface WireGuardPeerCounterInput {
  interface: string;
  allowed_ips: string[];
  receive_bytes: number;
  transmit_bytes: number;
}

export interface WireGuardPeerCounterSnapshot {
  receiveBytes: number;
  transmitBytes: number;
  sampledAt: number;
}

export interface WireGuardPeerMeasuredRate {
  receiveMbps: number | null;
  transmitMbps: number | null;
  sampleSeconds: number | null;
}

export function wireGuardPeerCounterKey(peer: Pick<WireGuardPeerCounterInput, "interface" | "allowed_ips">): string {
  return peer.interface + "\u001f" + [...peer.allowed_ips].sort().join("\u001f");
}

export function sampleWireGuardPeerRates(
  peers: readonly WireGuardPeerCounterInput[],
  previous: ReadonlyMap<string, WireGuardPeerCounterSnapshot>,
  sampledAt: number,
): {
  nextCounters: Map<string, WireGuardPeerCounterSnapshot>;
  rates: Map<string, WireGuardPeerMeasuredRate>;
} {
  const nextCounters = new Map<string, WireGuardPeerCounterSnapshot>();
  const rates = new Map<string, WireGuardPeerMeasuredRate>();
  const keyCounts = new Map<string, number>();

  for (const peer of peers) {
    const key = wireGuardPeerCounterKey(peer);
    keyCounts.set(key, (keyCounts.get(key) ?? 0) + 1);
  }

  for (const peer of peers) {
    const key = wireGuardPeerCounterKey(peer);
    // Identical interface/AllowedIPs tuples are ambiguous without exposing a
    // public key. Leave their rates unavailable rather than attributing bytes
    // to the wrong peer.
    if (keyCounts.get(key) !== 1) continue;

    const rxValid = Number.isSafeInteger(peer.receive_bytes) && peer.receive_bytes >= 0;
    const txValid = Number.isSafeInteger(peer.transmit_bytes) && peer.transmit_bytes >= 0;
    if (!rxValid || !txValid || !Number.isFinite(sampledAt)) continue;

    const prior = previous.get(key);
    if (prior) {
      const sampleSeconds = (sampledAt - prior.sampledAt) / 1000;
      const validInterval = Number.isFinite(sampleSeconds) && sampleSeconds > 0 && sampleSeconds <= 60;
      rates.set(key, {
        receiveMbps: calculateCounterRateMbps(peer.receive_bytes, prior.receiveBytes, sampleSeconds),
        transmitMbps: calculateCounterRateMbps(peer.transmit_bytes, prior.transmitBytes, sampleSeconds),
        sampleSeconds: validInterval ? sampleSeconds : null,
      });
    }

    nextCounters.set(key, {
      receiveBytes: peer.receive_bytes,
      transmitBytes: peer.transmit_bytes,
      sampledAt,
    });
  }

  return { nextCounters, rates };
}
