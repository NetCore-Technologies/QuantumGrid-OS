import type { RouterOverview, RouterWifiScan } from "./routerApi.js";

type WifiChannelOptionScore = {
  channel: number;
  frequencyMhz: number;
  score: number;
  relativeScore: number | null;
  observedAccessPoints: number;
  knownSignalAccessPoints: number;
  unknownSignalAccessPoints: number;
  unknownWidthAccessPoints: number;
  strongestSignalDbm: number | null;
  current: boolean;
  flags: string[];
};

type WifiChannelPlanGroup = {
  radio: string;
  band: string;
  widthMhz: number;
  widthAssumed: boolean;
  localBssidsExcluded: number;
  options: WifiChannelOptionScore[];
};

function frequencyForChannel(channel: number, band: string): number | null {
  if (!Number.isFinite(channel) || channel <= 0) return null;
  if (band === "2.4 GHz") {
    if (channel === 14) return 2484;
    if (channel >= 1 && channel <= 13) return 2407 + channel * 5;
    return null;
  }
  if (band === "5 GHz") return 5000 + channel * 5;
  if (band === "6 GHz") return channel === 2 ? 5935 : 5950 + channel * 5;
  return null;
}

function bandForFrequency(frequency: number | undefined): string | null {
  if (typeof frequency !== "number" || !Number.isFinite(frequency)) return null;
  if (frequency >= 5925 && frequency < 7125) return "6 GHz";
  if (frequency >= 4900 && frequency < 5925) return "5 GHz";
  if (frequency >= 2400 && frequency < 2500) return "2.4 GHz";
  return null;
}

function operatingWidth(htmode: string | undefined): { widthMhz: number; assumed: boolean } {
  if (typeof htmode !== "string") return { widthMhz: 20, assumed: true };
  const upper = htmode.toUpperCase();
  const match = upper.match(/(320|160|80|40|20)/);
  if (!match) return { widthMhz: 20, assumed: true };
  // 80+80 is non-contiguous; the planner uses the primary 80 MHz segment as a conservative baseline.
  if (upper.includes("80+80")) return { widthMhz: 80, assumed: true };
  return { widthMhz: Number(match[1]), assumed: false };
}

type WifiSpectrum = {
  segments: Array<{ centerMhz: number; widthMhz: number }>;
  widthAssumed: boolean;
};

function scannedNetworkSpectrum(network: RouterWifiScan["results"][number]): WifiSpectrum | null {
  const band = network.band || "Unknown";
  const operations = [
    network.eht_operation,
    network.he_operation,
    network.vht_operation,
    network.ht_operation,
  ];
  const operation = operations.find((item) => item !== undefined);
  const width = operation?.channel_width;
  let widthMhz = 20;
  let widthAssumed = true;
  if (width === 2040) { widthMhz = 40; widthAssumed = false; }
  else if (width === 8080) { widthMhz = 80; widthAssumed = true; }
  else if ([20, 40, 80, 160, 320].includes(width ?? -1)) {
    widthMhz = width as number;
    widthAssumed = false;
  }

  const center1 = typeof operation?.center_freq_1 === "number"
    ? frequencyForChannel(operation.center_freq_1, band)
    : null;
  const center2 = typeof operation?.center_freq_2 === "number" && operation.center_freq_2 > 0
    ? frequencyForChannel(operation.center_freq_2, band)
    : null;
  const primary = typeof network.frequency_mhz === "number" && Number.isFinite(network.frequency_mhz)
    ? network.frequency_mhz
    : null;
  const center = center1 ?? primary;
  if (center === null) return null;

  if (width === 8080) {
    const segments = [{ centerMhz: center, widthMhz: 80 }];
    if (center2 !== null && center2 !== center) segments.push({ centerMhz: center2, widthMhz: 80 });
    else widthAssumed = true;
    return { segments, widthAssumed };
  }
  return { segments: [{ centerMhz: center, widthMhz }], widthAssumed: widthAssumed || (center1 === null && widthMhz > 20) };
}

function spectrumOverlapFraction(
  candidateFrequencyMhz: number,
  candidateWidthMhz: number,
  neighbour: WifiSpectrum,
): number {
  const candidateLow = candidateFrequencyMhz - candidateWidthMhz / 2;
  const candidateHigh = candidateFrequencyMhz + candidateWidthMhz / 2;
  let overlap = 0;
  for (const segment of neighbour.segments) {
    const neighbourLow = segment.centerMhz - segment.widthMhz / 2;
    const neighbourHigh = segment.centerMhz + segment.widthMhz / 2;
    overlap += Math.max(0, Math.min(candidateHigh, neighbourHigh) - Math.max(candidateLow, neighbourLow));
  }
  return Math.min(1, overlap / candidateWidthMhz);
}

export function planWifiChannels(
  results: RouterWifiScan["results"],
  radios: RouterOverview["wireless"],
): WifiChannelPlanGroup[] {
  const plans: WifiChannelPlanGroup[] = [];
  for (const radio of radios) {
    const activeInterface =
      radio.interfaces.find((item) => item.up && item.mode.toLowerCase().includes("ap")) ??
      radio.interfaces.find((item) => item.up) ??
      radio.interfaces[0];
    if (!activeInterface) continue;
    const width = operatingWidth(activeInterface.htmode);
    const localBssids = new Set(
      radio.interfaces
        .map((item) => item.bssid?.toLowerCase())
        .filter((value): value is string => typeof value === "string" && value.length > 0),
    );
    const byBand = new Map<string, typeof radio.channels>();
    for (const channel of radio.channels ?? []) {
      if (channel.restricted || !Number.isFinite(channel.frequency_mhz) || channel.frequency_mhz <= 0) continue;
      const band = channel.band || bandForFrequency(channel.frequency_mhz);
      if (!band || band === "Unknown") continue;
      const existing = byBand.get(band) ?? [];
      if (!existing.some((item) => item.channel === channel.channel)) existing.push(channel);
      byBand.set(band, existing);
    }

    for (const [band, channels] of byBand) {
      const seenBssids = new Set<string>();
      const neighbours = results.filter((network) => {
        if ((network.band || "Unknown") !== band) return false;
        const bssid = network.bssid.toLowerCase();
        if (localBssids.has(bssid) || seenBssids.has(bssid)) return false;
        seenBssids.add(bssid);
        return true;
      }).map((network) => ({ network, spectrum: scannedNetworkSpectrum(network) }))
        .filter((item) => item.spectrum !== null);

      const candidates = (channels ?? []).map((channel) => {
        let score = 0;
        let observedAccessPoints = 0;
        let knownSignalAccessPoints = 0;
        let unknownSignalAccessPoints = 0;
        let unknownWidthAccessPoints = 0;
        let strongestSignalDbm: number | null = null;
        for (const item of neighbours) {
          const overlap = spectrumOverlapFraction(
            channel.frequency_mhz,
            width.widthMhz,
            item.spectrum!,
          );
          if (overlap <= 0) continue;
          observedAccessPoints += 1;
          if (item.spectrum!.widthAssumed) unknownWidthAccessPoints += 1;
          const signal = item.network.signal_dbm;
          let weight = 1;
          if (typeof signal === "number" && Number.isFinite(signal)) {
            const boundedSignal = Math.max(-100, Math.min(-20, signal));
            weight = Math.pow(10, (boundedSignal + 100) / 10);
            knownSignalAccessPoints += 1;
            strongestSignalDbm = strongestSignalDbm === null
              ? signal
              : Math.max(strongestSignalDbm, signal);
          } else {
            unknownSignalAccessPoints += 1;
          }
          score += weight * overlap;
        }
        return {
          channel: channel.channel,
          frequencyMhz: channel.frequency_mhz,
          score,
          relativeScore: null as number | null,
          observedAccessPoints,
          knownSignalAccessPoints,
          unknownSignalAccessPoints,
          unknownWidthAccessPoints,
          strongestSignalDbm,
          current: activeInterface.channel === channel.channel &&
            bandForFrequency(activeInterface.frequency_mhz) === band,
          flags: channel.flags ?? [],
        };
      }).sort((left, right) => left.score - right.score || left.channel - right.channel);
      const maximum = Math.max(0, ...candidates.map((item) => item.score));
      for (const option of candidates) {
        option.relativeScore = maximum > 0 ? (option.score / maximum) * 100 : null;
      }
      plans.push({
        radio: radio.name,
        band,
        widthMhz: width.widthMhz,
        widthAssumed: width.assumed,
        localBssidsExcluded: localBssids.size,
        options: candidates,
      });
    }
  }
  return plans;
}




export function recommendWifiChannel(plan: WifiChannelPlanGroup): WifiChannelOptionScore | null {
  if (!Array.isArray(plan.options) || plan.options.length < 2 || plan.widthAssumed) return null;
  const current = plan.options.find((option) => option.current);
  if (!current || current.score <= 0 || current.knownSignalAccessPoints < 1 ||
      current.unknownSignalAccessPoints > 0 || current.unknownWidthAccessPoints > 0) return null;
  const minimumImprovement = Math.max(0.5, current.score * 0.15);
  return plan.options.find((option) => {
    if (option.current || option.score >= current.score - minimumImprovement) return false;
    if (option.unknownSignalAccessPoints > 0 || option.unknownWidthAccessPoints > 0) return false;
    return !option.flags.some((flag) => /no.?ir|passive|radar|dfs|disabled/i.test(flag));
  }) ?? null;
}
