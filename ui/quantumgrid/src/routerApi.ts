export interface RouterDefaultRoute {
  family: "IPv4" | "IPv6";
  route_type: string;
  table: string;
  device: string;
  gateway: string;
  metric?: number;
  protocol: string;
}

export interface RouterPolicyRule {
  family: "IPv4" | "IPv6";
  priority: number;
  source: string;
  destination: string;
  fwmark: string;
  input_interface: string;
  output_interface: string;
  protocol: string;
  uid_range: string;
  table: string;
  action: string;
  selectors: string;
}

export interface RouterInterface {
  name: string;
  device: string;
  up: boolean;
  is_wan: boolean;
  rx_bytes: number;
  tx_bytes: number;
  rx_packets?: number;
  tx_packets?: number;
  rx_errors?: number;
  tx_errors?: number;
  rx_dropped?: number;
  tx_dropped?: number;
  ipv4: string[];
  ipv6?: string[];
  dns_servers?: string[];
}

export interface RouterWirelessInterface {
  ifname: string;
  ssid: string;
  bssid?: string;
  mode: string;
  up: boolean;
  channel?: number;
  frequency_mhz?: number;
  country?: string;
  hwmode?: string;
  htmode?: string;
  hardware_modes?: string[];
  ht_modes?: string[];
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

export interface RouterWirelessConfig {
  section: string;
  radio: string;
  mode: "ap";
  ssid: string;
  encryption: string;
  hidden: boolean;
  key_set: boolean;
  interface_disabled: boolean;
  radio_disabled: boolean;
  channel: string;
  htmode: string;
  txpower?: number;
}

export interface RouterWirelessConfigInventory {
  available: boolean;
  sections: RouterWirelessConfig[];
}

export interface RouterWirelessUpdateResult {
  ok: true;
  radio: string;
  section: string;
  ssid: string;
  encryption: string;
  hidden: boolean;
  channel: string;
  key_set: boolean;
  reloaded: true;
  rolled_back: false;
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

export interface RouterWifiRateDetails {
  phy: string;
  mcs?: number;
  nss?: number;
  width_mhz?: number;
  short_gi?: boolean;
  he_gi?: number;
  eht_gi?: number;
}

export interface RouterWirelessClient {
  ifname: string;
  radio: string;
  ssid: string;
  mac: string;
  associated: boolean;
  authorized: boolean;
  signal_dbm?: number;
  signal_avg_dbm?: number;
  signal_current_dbm?: number;
  rx_rate_mbps?: number;
  tx_rate_mbps?: number;
  measured_rx_mbps?: number;
  measured_tx_mbps?: number;
  rx_details?: RouterWifiRateDetails;
  tx_details?: RouterWifiRateDetails;
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

export interface RouterMwan3TrackTarget {
  ip: string;
  status: string;
  latency_ms?: number;
  packet_loss_percent?: number;
}

export interface RouterMwan3Interface {
  name: string;
  enabled: boolean;
  running: boolean;
  up: boolean;
  status: string;
  tracking: string;
  age_seconds?: number;
  online_seconds?: number;
  offline_seconds?: number;
  interface_uptime_seconds?: number;
  score?: number;
  lost?: number;
  turn?: number;
  track_targets: RouterMwan3TrackTarget[];
}

export interface RouterMwan3PolicyMember {
  interface: string;
  percent: number;
}

export interface RouterMwan3Policy {
  family: "IPv4" | "IPv6";
  name: string;
  members: RouterMwan3PolicyMember[];
}

export interface RouterMwan3Status {
  installed: boolean;
  available: boolean;
  count: number;
  truncated: boolean;
  interfaces: RouterMwan3Interface[];
  policies_available: boolean;
  policy_count: number;
  policies: RouterMwan3Policy[];
  connected_available: boolean;
  connected_ipv4: string[];
  connected_ipv6: string[];
}

export interface RouterSqmQueueUpdateResult {
  ok: true;
  section: string;
  enabled: boolean;
  download_kbps: number;
  upload_kbps: number;
  restarted: true;
  rolled_back: false;
}

export interface RouterFirewallZone {
  name: string;
  networks: string[];
  input: string;
  output: string;
  forward: string;
  masquerade: boolean;
}

export interface RouterFirewallRule {
  name: string;
  source_zone: string;
  destination_zone: string;
  protocol: string;
  target: string;
  family: string;
  source_port: string;
  destination_port: string;
  enabled: boolean;
  source_ip_match: boolean;
  destination_ip_match: boolean;
  source_mac_match: boolean;
}

export interface RouterVpnInterface {
  name: string;
  up: boolean;
  device: string;
}

export interface RouterWireGuardPeer {
  interface: string;
  handshake_age_seconds?: number;
  handshake_seen: boolean;
  receive_bytes: number;
  transmit_bytes: number;
  allowed_ips: string[];
}

export interface RouterSecurityStatus {
  firewall_installed: boolean;
  firewall_config_available: boolean;
  firewall_config_readable: boolean;
  zones: RouterFirewallZone[];
  rules: RouterFirewallRule[];
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
    wireguard_peers_available: boolean;
    wireguard_peer_count: number;
    wireguard_peers_truncated: boolean;
    wireguard_peers: RouterWireGuardPeer[];
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

export interface RouterLatencyTest {
  ok: true;
  target: string;
  packets_sent: number;
  packets_received: number;
  packet_loss_percent: number;
  min_ms?: number;
  average_ms?: number;
  max_ms?: number;
  jitter_ms?: number;
  jitter_method: string;
  sampled_at: number;
  cached: boolean;
  retry_after_seconds?: number;
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

export interface RouterConntrackStatus {
  available: boolean;
  count?: number;
  maximum?: number;
  free?: number;
  used_percent?: number;
  status?: "normal" | "warning" | "critical";
}

export interface RouterPlatformStatus {
  available: boolean;
  hostname?: string;
  model?: string;
  board_name?: string;
  system?: string;
  kernel?: string;
  distribution?: string;
  version?: string;
  revision?: string;
  target?: string;
  description?: string;
  package_manager: string;
  modules: Array<{ name: string; loaded: boolean }>;
  tools: Array<{ name: string; available: boolean }>;
  services: Array<{ name: string; installed: boolean }>;
  storage: Array<{ device: string; name: string; size_bytes: number; erase_size_bytes: number }>;
  block_devices: Array<{ name: string; major: number; minor: number; size_bytes: number }>;
  mounts: Array<{
    source: string;
    mountpoint: string;
    filesystem: string;
    read_only: boolean;
    total_bytes?: number;
    available_bytes?: number;
    used_percent?: number;
  }>;
}

export interface RouterOverview {
  ok: true;
  platform?: RouterPlatformStatus;
  conntrack?: RouterConntrackStatus;
  timestamp: number;
  routes_available?: boolean;
  routes?: RouterDefaultRoute[];
  policy_rules_available?: boolean;
  policy_rules_count?: number;
  policy_rules_truncated?: boolean;
  policy_rules?: RouterPolicyRule[];
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
  wireless_configs?: RouterWirelessConfigInventory;
  wireless_clients?: RouterWirelessClient[];
  sqm?: RouterSqmStatus;
  mwan3?: RouterMwan3Status;
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
const LATENCY_TEST_URL = "/cgi-bin/luci/admin/services/quantumgrid/latency-test";
const SQM_UPDATE_URL = "/cgi-bin/luci/admin/services/quantumgrid/sqm-update";
const WIRELESS_UPDATE_URL = "/cgi-bin/luci/admin/services/quantumgrid/wireless-update";

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

export async function runRouterLatencyTest(): Promise<RouterLatencyTest> {
  const response = await fetch(LATENCY_TEST_URL, {
    method: "POST",
    credentials: "same-origin",
    cache: "no-store",
    headers: { Accept: "application/json" },
  });
  const contentType = response.headers.get("content-type") ?? "";
  if (!response.ok || !contentType.includes("application/json")) {
    if (response.status === 403) {
      throw new Error("Latency testing requires an active router administrator session.");
    }
    throw new Error("The router could not complete the latency test.");
  }
  const payload: unknown = await response.json();
  if (
    typeof payload !== "object" || payload === null ||
    !("ok" in payload) || payload.ok !== true ||
    !("target" in payload) || payload.target !== "1.1.1.1" ||
    !("packets_sent" in payload) || payload.packets_sent !== 5 ||
    !("packets_received" in payload) || typeof payload.packets_received !== "number" ||
    !("packet_loss_percent" in payload) || typeof payload.packet_loss_percent !== "number" ||
    !("sampled_at" in payload) || typeof payload.sampled_at !== "number"
  ) {
    throw new Error("The router returned an invalid latency-test response.");
  }
  return payload as RouterLatencyTest;
}


export async function updateRouterWirelessConfig(input: {
  radio: string;
  section: string;
  ssid: string;
  encryption: "psk2" | "sae" | "sae-mixed" | "none";
  key: string;
  hidden: boolean;
  channel: string;
  allowOpen: boolean;
}): Promise<RouterWirelessUpdateResult> {
  const validSection = (value: string) => /^[A-Za-z0-9_-]{1,32}$/.test(value);
  if (!validSection(input.radio) || !validSection(input.section)) {
    throw new Error("Invalid wireless radio or interface section.");
  }
  if (input.ssid.length < 1 || new TextEncoder().encode(input.ssid).length > 32 ||
      /[\u0000-\u001f\u007f]/.test(input.ssid)) {
    throw new Error("SSID must be 1–32 bytes and cannot contain control characters.");
  }
  if (input.encryption !== "none" &&
      (input.key.length < 8 || new TextEncoder().encode(input.key).length > 63 ||
       /[\u0000-\u001f\u007f]/.test(input.key))) {
    throw new Error("The wireless passphrase must be 8–63 bytes and cannot contain control characters.");
  }
  if (input.encryption === "none" && (!input.allowOpen || input.key !== "")) {
    throw new Error("An open wireless network requires explicit confirmation and no passphrase.");
  }
  if (input.channel !== "auto" && !/^[0-9]{1,3}$/.test(input.channel)) {
    throw new Error("Choose Auto or a supported numeric channel.");
  }

  const form = new URLSearchParams();
  form.set("radio", input.radio);
  form.set("section", input.section);
  form.set("ssid", input.ssid);
  form.set("encryption", input.encryption);
  form.set("key", input.key);
  form.set("hidden", input.hidden ? "1" : "0");
  form.set("channel", input.channel);
  form.set("allow_open", input.allowOpen ? "1" : "0");
  form.set("confirmed", "1");

  const response = await fetch(WIRELESS_UPDATE_URL, {
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
  if (!contentType.includes("application/json")) {
    throw new Error(response.status === 403
      ? "Wi-Fi changes require an active router administrator session."
      : "The router returned an invalid wireless update response.");
  }

  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) {
    throw new Error("The router returned an invalid wireless update response.");
  }
  if ("error" in payload && typeof payload.error === "string") {
    throw new Error(payload.error);
  }
  if (
    !response.ok || !("ok" in payload) || payload.ok !== true ||
    !("radio" in payload) || payload.radio !== input.radio ||
    !("section" in payload) || payload.section !== input.section ||
    !("ssid" in payload) || payload.ssid !== input.ssid ||
    !("encryption" in payload) || payload.encryption !== input.encryption ||
    !("hidden" in payload) || payload.hidden !== input.hidden ||
    !("channel" in payload) || payload.channel !== input.channel ||
    !("reloaded" in payload) || payload.reloaded !== true ||
    !("rolled_back" in payload) || payload.rolled_back !== false
  ) {
    throw new Error("The router did not confirm the wireless configuration and Wi-Fi reload.");
  }
  return payload as RouterWirelessUpdateResult;
}

export async function updateRouterSqmQueue(
  section: string,
  enabled: boolean,
  downloadKbps: number,
  uploadKbps: number,
): Promise<RouterSqmQueueUpdateResult> {
  if (!/^[A-Za-z0-9_-]{1,32}$/.test(section)) {
    throw new Error("Invalid SQM queue section name.");
  }
  const validRate = (value: number) => Number.isInteger(value) && value >= 64 && value <= 1_000_000;
  if (!validRate(downloadKbps) || !validRate(uploadKbps)) {
    throw new Error("Download and upload rates must be whole numbers from 64 to 1,000,000 kbit/s.");
  }

  const form = new URLSearchParams();
  form.set("section", section);
  form.set("enabled", enabled ? "1" : "0");
  form.set("download", String(downloadKbps));
  form.set("upload", String(uploadKbps));

  const response = await fetch(SQM_UPDATE_URL, {
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
  if (!contentType.includes("application/json")) {
    throw new Error(response.status === 403
      ? "SQM queue changes require an active router administrator session."
      : "The router returned an invalid SQM update response.");
  }

  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) {
    throw new Error("The router returned an invalid SQM update response.");
  }
  if ("error" in payload && typeof payload.error === "string") {
    throw new Error(payload.error);
  }
  if (
    !response.ok || !("ok" in payload) || payload.ok !== true ||
    !("section" in payload) || payload.section !== section ||
    !("enabled" in payload) || payload.enabled !== enabled ||
    !("download_kbps" in payload) || payload.download_kbps !== downloadKbps ||
    !("upload_kbps" in payload) || payload.upload_kbps !== uploadKbps ||
    !("restarted" in payload) || payload.restarted !== true ||
    !("rolled_back" in payload) || payload.rolled_back !== false
  ) {
    throw new Error("The router did not confirm the SQM queue update and service restart.");
  }
  return payload as RouterSqmQueueUpdateResult;
}
