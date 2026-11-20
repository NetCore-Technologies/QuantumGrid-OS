export interface RouterInterface {
  name: string;
  device: string;
  up: boolean;
  is_wan: boolean;
  rx_bytes: number;
  tx_bytes: number;
  ipv4: string[];
}

export interface RouterWirelessInterface {
  ifname: string;
  ssid: string;
  mode: string;
  up: boolean;
  channel?: number;
  frequency_mhz?: number;
  country?: string;
  hwmode?: string;
  htmode?: string;
  center_channel_1?: number;
  center_channel_2?: number;
  txpower_dbm?: number;
  signal_dbm?: number;
  noise_dbm?: number;
  bitrate_kbps?: number;
  quality?: number;
  quality_max?: number;
  survey_supported?: boolean;
  channel_busy_percent?: number;
  survey_interval_seconds?: number;
}

export interface RouterWirelessChannel {
  channel: number;
  frequency_mhz: number;
  band: string;
  restricted: boolean;
  active?: boolean;
  flags: string[];
}

export interface RouterWirelessTxPower {
  dbm: number;
  mw: number;
  active: boolean;
}

export interface RouterWirelessRadio {
  name: string;
  up: boolean;
  interfaces: RouterWirelessInterface[];
  channels?: RouterWirelessChannel[];
  txpower_levels?: RouterWirelessTxPower[];
}

export interface RouterClient {
  hostname: string;
  ip: string;
  mac: string;
  lease_remaining_seconds: number | null;
}

export interface RouterWirelessClient {
  ifname: string;
  radio: string;
  ssid: string;
  mac: string;
  associated: boolean;
  authorized: boolean;
  signal_dbm?: number;
  rx_rate_mbps?: number;
  tx_rate_mbps?: number;
  frequency_mhz?: number;
  band: string;
  noise_dbm?: number;
  connected_seconds?: number;
  inactive_ms?: number;
  rx_bytes?: number;
  tx_bytes?: number;
  rx_packets?: number;
  tx_packets?: number;
  tx_retries?: number;
  tx_failed?: number;
}

export interface RouterSqmQueue {
  name: string;
  enabled: boolean;
  interface: string;
  download_kbps?: number;
  upload_kbps?: number;
  qdisc: string;
  script: string;
  linklayer: string;
}

export interface RouterQdiscState {
  kind: string;
  handle: string;
  device?: string;
  parent?: string;
  root: boolean;
  bytes?: number;
  packets?: number;
  dropped?: number;
  overlimits?: number;
  requeues?: number;
  backlog_bytes?: number;
  backlog_packets?: number;
}

export interface RouterSqmStatus {
  installed: boolean;
  config_available: boolean;
  config_readable: boolean;
  queues: RouterSqmQueue[];
  runtime_available: boolean;
  qdiscs: RouterQdiscState[];
}

export interface RouterFirewallZone {
  name: string;
  networks: string[];
  input: string;
  output: string;
  forward: string;
  masquerade: boolean;
}

export interface RouterVpnInterface {
  name: string;
  up: boolean;
  device: string;
}

export interface RouterSecurityStatus {
  firewall_installed: boolean;
  firewall_config_available: boolean;
  firewall_config_readable: boolean;
  zones: RouterFirewallZone[];
  rules_count: number;
  redirects_count: number;
  nft_available: boolean;
  nft_tables: string[];
  adblock_fast: {
    installed: boolean;
    config_available: boolean;
    configured_enabled: boolean;
  };
  vpn: {
    wireguard_tool_installed: boolean;
    openvpn_service_installed: boolean;
    wireguard_interfaces: RouterVpnInterface[];
    openvpn_enabled_instances: number;
  };
}

export interface RouterWifiOperation {
  channel_width?: number;
  primary_channel?: number;
  secondary_channel_offset?: string;
  center_freq_1?: number;
  center_freq_2?: number;
}

export interface RouterWifiScanResult {
  radio: string; ifname: string; ssid: string; bssid: string; mode: string;
  channel?: number; frequency_mhz?: number; band: string;
  signal_dbm?: number; quality?: number; quality_max?: number;
  security: string; authentication?: string[]; ciphers?: string[];
  ht_operation?: RouterWifiOperation;
  vht_operation?: RouterWifiOperation;
  he_operation?: RouterWifiOperation;
  eht_operation?: RouterWifiOperation;
}
export interface RouterWifiScan {
  ok: true; scanned_at: number; cached: boolean;
  interfaces_scanned: number; interfaces_failed: number; truncated: boolean;
  results: RouterWifiScanResult[];
}

export interface RouterCellularStatus {
  modem_present: boolean;
  qmi_available: boolean;
  device: string;
  sampled_at: number;
  registration?: string;
  registered?: boolean;
  operator?: string;
  mcc?: number;
  mnc?: number;
  roaming?: boolean;
  radio_interfaces?: string[];
  signal_type?: string;
  rssi_dbm?: number;
  rsrp_dbm?: number;
  rsrq_db?: number;
  snr_db?: number;
  data_status?: string;
}

export interface RouterOverview {
  ok: true;
  timestamp: number;
  system: {
    uptime_seconds: number;
    load_avg: number[];
    cpu_percent: number | null;
    memory: {
      total_kib: number;
      available_kib: number;
      used_percent: number | null;
    };
    temperature_c: number | null;
    ping_ok: boolean;
    ping_ms: number | null;
  };
  interfaces: RouterInterface[];
  clients?: RouterClient[];
  wireless: RouterWirelessRadio[];
  wireless_clients?: RouterWirelessClient[];
  sqm?: RouterSqmStatus;
  security?: RouterSecurityStatus;
  cellular: RouterCellularStatus;
  phone: {
    service_installed: boolean;
    enabled: boolean;
    patch_installed: boolean;
  };
}

const API_URL = "/cgi-bin/luci/admin/services/quantumgrid/api";
const PASSWORD_URL = "/cgi-bin/luci/admin/services/quantumgrid/password";
const WIFI_SCAN_URL = "/cgi-bin/luci/admin/services/quantumgrid/wifi-scan";

async function decodeOverview(response: Response): Promise<RouterOverview> {
  const contentType = response.headers.get("content-type") ?? "";
  if (!response.ok || !contentType.includes("application/json")) {
    if (response.status === 403) {
      throw new Error("Router sign-in failed. Check the OpenWrt root password.");
    }
    throw new Error("QuantumGrid could not reach the authenticated router API.");
  }

  const payload: unknown = await response.json();
  if (
    typeof payload !== "object" ||
    payload === null ||
    !("ok" in payload) ||
    payload.ok !== true
  ) {
    throw new Error("The router returned an invalid telemetry response.");
  }

  return payload as RouterOverview;
}

async function authenticate(username: string, password: string): Promise<RouterOverview> {
  const form = new URLSearchParams();
  form.set("luci_username", username);
  form.set("luci_password", password);

  const response = await fetch(API_URL, {
    method: "POST",
    credentials: "same-origin",
    cache: "no-store",
    redirect: "follow",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
    },
    body: form.toString(),
  });

  return decodeOverview(response);
}

async function setInitialRootPassword(password: string): Promise<void> {
  const form = new URLSearchParams();
  form.set("password", password);

  const response = await fetch(PASSWORD_URL, {
    method: "POST",
    credentials: "same-origin",
    cache: "no-store",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
    },
    body: form.toString(),
  });

  const contentType = response.headers.get("content-type") ?? "";
  if (!response.ok || !contentType.includes("application/json")) {
    throw new Error("The router could not set its initial administrator password.");
  }

  const result: unknown = await response.json();
  if (
    typeof result !== "object" ||
    result === null ||
    !("ok" in result) ||
    result.ok !== true
  ) {
    throw new Error("The router rejected the initial administrator password.");
  }
}

export async function loginToRouter(
  username: string,
  password: string,
): Promise<RouterOverview> {
  try {
    return await authenticate(username, password);
  } catch (originalError) {
    // A blank password is accepted only on a router that has not been secured yet.
    // If an existing password is wrong, the blank-password attempt also fails and
    // the original authentication error is preserved.
    if (!password) throw originalError;

    try {
      await authenticate(username, "");
    } catch {
      throw originalError;
    }

    await setInitialRootPassword(password);
    return fetchRouterOverview();
  }
}

export async function fetchRouterOverview(): Promise<RouterOverview> {
  const response = await fetch(API_URL, {
    method: "GET",
    credentials: "same-origin",
    cache: "no-store",
    headers: { Accept: "application/json" },
  });

  return decodeOverview(response);
}


export async function scanRouterWifi(): Promise<RouterWifiScan> {
  const response = await fetch(WIFI_SCAN_URL, {
    method: "POST",
    credentials: "same-origin",
    cache: "no-store",
    headers: { Accept: "application/json" },
  });
  const contentType = response.headers.get("content-type") ?? "";
  if (!response.ok || !contentType.includes("application/json")) {
    if (response.status === 403) {
      throw new Error("Wi-Fi scanning requires an active router administrator session.");
    }
    throw new Error("The router could not complete the wireless scan.");
  }
  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null || !("ok" in payload) ||
      payload.ok !== true || !("results" in payload) || !Array.isArray(payload.results)) {
    throw new Error("The router returned an invalid Wi-Fi scan response.");
  }
  return payload as RouterWifiScan;
}
