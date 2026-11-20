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
  htmodes: string[];
  txpower?: number;
  txpower_levels: RouterWirelessTxPower[];
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
  htmode: string;
  txpower: string;
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

export interface RouterAccelerationComponent {
  name: string;
  kind: "device-tree" | "kernel-module" | "firmware";
  present: boolean;
  detail: string;
}

export interface RouterAccelerationStatus {
  status: "not-detected" | "partial" | "components-present-unverified";
  present_components: number;
  required_components: number;
  offload_verified: false;
  components: RouterAccelerationComponent[];
  note: string;
}

export interface RouterKernelModule {
  name: string;
  path: string;
  loaded: boolean;
}

export interface RouterKernelModuleInventory {
  available: boolean;
  count: number;
  loaded_count: number;
  truncated: boolean;
  modules: RouterKernelModule[];
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
  acceleration?: RouterAccelerationStatus;
  kernel_modules?: RouterKernelModuleInventory;
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

export interface RouterPackage {
  name: string;
  version: string;
  manager: "apk" | "opkg";
}

export interface RouterPackageOperationResult {
  ok: true;
  manager: "apk" | "opkg";
  operation: "update" | "install" | "remove";
  package?: string;
  exit_code: 0;
  output: string;
  sampled_at: number;
}

export interface RouterPackageInventory {
  ok: true;
  manager: "apk" | "opkg";
  count: number;
  truncated: boolean;
  packages: RouterPackage[];
  sampled_at: number;
}

export interface RouterGpioLine {
  number: number;
  label: string;
  consumer: string;
  direction: string;
  state: string;
  value?: number;
  is_button: boolean;
}

export interface RouterGpioChip {
  name: string;
  first_gpio?: number;
  last_gpio?: number;
}

export interface RouterGpioInventory {
  available: boolean;
  chips: RouterGpioChip[];
  chip_count: number;
  lines: RouterGpioLine[];
  line_count: number;
  truncated: boolean;
}

export interface RouterLedDevice {
  name: string;
  brightness?: number;
  max_brightness?: number;
  trigger?: string;
  trigger_available: boolean;
  controllable: boolean;
}

export interface RouterInputDevice {
  name: string;
  bus?: string;
  handlers: string[];
  event_nodes: string[];
  button_like: boolean;
}

export interface RouterInputDeviceInventory {
  available: boolean;
  devices: RouterInputDevice[];
  count: number;
  truncated: boolean;
}

export interface RouterButtonEvent {
  timestamp: number;
  sequence: string;
  button: string;
  action: "pressed" | "released";
  seen_seconds: number;
  type: "key" | "switch";
}

export interface RouterButtonEventInventory {
  available: boolean;
  monitor_available: boolean;
  events: RouterButtonEvent[];
  count: number;
  truncated: boolean;
  sampled_at: number;
}

export interface RouterHardwareIoStatus {
  available: boolean;
  gpio: RouterGpioInventory;
  input_devices: RouterInputDeviceInventory;
  leds_available: boolean;
  leds: RouterLedDevice[];
  button_driver_loaded: boolean;
  button_hooks_available: boolean;
  button_handlers: string[];
  button_events: RouterButtonEventInventory;
  sampled_at: number;
}

export interface RouterLedUpdateResult {
  ok: true;
  name: string;
  brightness: number;
  max_brightness: number;
  applied: true;
  persistent: false;
}

export interface RouterOfficeBridge {
  name: string;
  type: string;
  ports: string[];
  vlan_filtering: boolean;
}

export interface RouterOfficeVlanPort {
  name: string;
  mode: "tagged" | "untagged" | "unspecified";
  pvid: boolean;
}

export interface RouterOfficeVlan {
  name: string;
  device: string;
  vlan_id: number;
  ports: RouterOfficeVlanPort[];
}

export interface RouterOfficeWifiAp {
  ssid: string;
  section: string;
  device: string;
  disabled: boolean;
}

export interface RouterOfficeInterface {
  name: string;
  protocol: string;
  device: string;
  up: boolean;
  ipv4: string[];
  netmask: string;
  ip6assign: string;
  ipv6: string[];
  vlan_ids: number[];
  firewall_zones: string[];
  wifi_aps: RouterOfficeWifiAp[];
}

export interface RouterOfficeFirewallZone {
  name: string;
  networks: string[];
  input: string;
  output: string;
  forward: string;
  masquerade: boolean;
}

export interface RouterOfficeForwarding {
  name: string;
  source: string;
  destination: string;
}

export interface RouterOfficeDhcpScope {
  section: string;
  name: string;
  interface: string;
  start: string;
  limit?: number;
  lease_time: string;
  ignore: boolean;
  dhcpv6: string;
  ra: string;
  range_valid: boolean;
  pool_start_ip: string;
  pool_end_ip: string;
  range_error: string;
  overlap: boolean;
}

export interface RouterOfficeStaticLease {
  section: string;
  name: string;
  mac: string;
  ipv4: string;
}

export interface RouterOfficeNetworks {
  available: boolean;
  firewall_available: boolean;
  wireless_available: boolean;
  dhcp_available: boolean;
  dhcp_scopes: RouterOfficeDhcpScope[];
  static_leases: RouterOfficeStaticLease[];
  dhcp_scope_count: number;
  static_lease_count: number;
  truncated: boolean;
  interfaces: RouterOfficeInterface[];
  bridges: RouterOfficeBridge[];
  vlans: RouterOfficeVlan[];
  zones: RouterOfficeFirewallZone[];
  forwardings: RouterOfficeForwarding[];
  forwarding_count: number;
  interface_count: number;
  bridge_count: number;
  vlan_count: number;
  zone_count: number;
  wifi_ap_count: number;
  vlan_filtering_bridge_count: number;
  segmented_interface_count: number;
  sampled_at: number;
}

export interface RouterDhcpScopeCreateResult {
  ok: true;
  section: string;
  network: string;
  start: string;
  limit: string;
  lease_time: string;
  pool_start_ip: string;
  pool_end_ip: string;
  restarted: true;
  rolled_back: false;
}

export interface RouterDhcpScopeRemoveResult {
  ok: true;
  section: string;
  interface: string;
  removed: true;
  restarted: true;
  rolled_back: false;
}

export interface RouterDhcpScopeToggleResult {
  ok: true;
  section: string;
  enabled: boolean;
  changed: boolean;
  restarted: boolean;
  rolled_back: false;
}

export interface RouterDhcpScopeUpdateResult {
  ok: true;
  section: string;
  start: string;
  limit: string;
  lease_time: string;
  pool_start_ip: string;
  pool_end_ip: string;
  restarted: true;
  rolled_back: false;
}

export interface RouterDhcpReservationUpdateResult {
  ok: true;
  section: string;
  name: string;
  mac: string;
  ipv4: string;
  network: string;
  restarted: true;
  rolled_back: false;
}

export interface RouterDhcpReservationRemoveResult {
  ok: true;
  section: string;
  name: string;
  mac: string;
  ipv4: string;
  removed: true;
  restarted: true;
  rolled_back: false;
}

export interface RouterDhcpReservationResult {
  ok: true;
  section: string;
  name: string;
  mac: string;
  ipv4: string;
  network: string;
  restarted: true;
  rolled_back: false;
}
export interface RouterAuditEvent {
  timestamp: number;
  actor: string;
  remote_ip: string;
  action: string;
  target: string;
  outcome: "success" | "failed";
}

export interface RouterAuditLog {
  ok: true;
  available: boolean;
  events: RouterAuditEvent[];
  count: number;
  truncated: boolean;
  sampled_at: number;
}

export interface RouterRemoteSyslogStatus {
  available: boolean;
  service_installed: boolean;
  config_available: boolean;
  enabled: boolean;
  host: string;
  port: number;
  protocol: "tcp" | "udp";
  hostname: string;
  prefix: string;
  sampled_at: number;
}

export interface RouterRemoteSyslogUpdateResult {
  ok: true;
  enabled: boolean;
  host: string;
  port: number;
  protocol: "tcp" | "udp";
  hostname: string;
  prefix: string;
  restarted: true;
  rolled_back: false;
}

export interface RouterOverview {
  ok: true;
  platform?: RouterPlatformStatus;
  hardware_io?: RouterHardwareIoStatus;
  office_networks?: RouterOfficeNetworks;
  remote_syslog?: RouterRemoteSyslogStatus;
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
const PACKAGES_URL = "/cgi-bin/luci/admin/services/quantumgrid/packages";
const PACKAGES_UPDATE_URL = "/cgi-bin/luci/admin/services/quantumgrid/packages-update";
const LED_UPDATE_URL = "/cgi-bin/luci/admin/services/quantumgrid/led-update";
const CONFIG_BACKUP_URL = "/cgi-bin/luci/admin/services/quantumgrid/config-backup";
const AUDIT_URL = "/cgi-bin/luci/admin/services/quantumgrid/audit";
const DHCP_RESERVATION_URL = "/cgi-bin/luci/admin/services/quantumgrid/dhcp-reservation";
const DHCP_RESERVATION_REMOVE_URL = "/cgi-bin/luci/admin/services/quantumgrid/dhcp-reservation-remove";
const DHCP_RESERVATION_UPDATE_URL = "/cgi-bin/luci/admin/services/quantumgrid/dhcp-reservation-update";
const DHCP_SCOPE_UPDATE_URL = "/cgi-bin/luci/admin/services/quantumgrid/dhcp-scope-update";
const DHCP_SCOPE_TOGGLE_URL = "/cgi-bin/luci/admin/services/quantumgrid/dhcp-scope-toggle";
const DHCP_SCOPE_ADD_URL = "/cgi-bin/luci/admin/services/quantumgrid/dhcp-scope-add";
const DHCP_SCOPE_REMOVE_URL = "/cgi-bin/luci/admin/services/quantumgrid/dhcp-scope-remove";
const REMOTE_SYSLOG_URL = "/cgi-bin/luci/admin/services/quantumgrid/remote-syslog";

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


export async function runRouterPackageOperation(
  operation: "update" | "install" | "remove",
  packageName = "",
  confirmed = false,
): Promise<RouterPackageOperationResult> {
  if (operation !== "update" && !/^[A-Za-z0-9][A-Za-z0-9+_.-]{0,127}$/.test(packageName)) {
    throw new Error("Enter a valid OpenWrt package name.");
  }
  if (!confirmed) {
    throw new Error("Confirm the package operation before continuing.");
  }
  if (operation === "remove" &&
      (/^kmod-/.test(packageName) || /^wpad/.test(packageName) ||
       /^qca-nss/.test(packageName) || /^ath11k/.test(packageName) ||
       /^kernel-/.test(packageName) || /^luci-mod-/.test(packageName))) {
    throw new Error("Kernel, Wi-Fi and NSS packages must be changed through an offline firmware build.");
  }

  const form = new URLSearchParams();
  form.set("operation", operation);
  form.set("package", operation === "update" ? "" : packageName);
  form.set("confirmed", "1");
  const response = await fetch(PACKAGES_UPDATE_URL, {
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
      ? "Package management requires an active router administrator session."
      : "The router returned an invalid package-operation response.");
  }

  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) {
    throw new Error("The router returned an invalid package-operation response.");
  }
  if (!response.ok || !("ok" in payload) || payload.ok !== true) {
    const message = "error" in payload && typeof payload.error === "string"
      ? payload.error
      : "The package manager rejected the operation.";
    const output = "output" in payload && typeof payload.output === "string"
      ? payload.output
      : "";
    throw new Error(output ? message + "\n" + output : message);
  }
  if (
    !("manager" in payload) || (payload.manager !== "apk" && payload.manager !== "opkg") ||
    !("operation" in payload) || payload.operation !== operation ||
    !("exit_code" in payload) || payload.exit_code !== 0 ||
    !("output" in payload) || typeof payload.output !== "string" ||
    !("sampled_at" in payload) || typeof payload.sampled_at !== "number"
  ) {
    throw new Error("The router did not confirm successful completion of the package operation.");
  }
  return payload as RouterPackageOperationResult;
}

export async function fetchRouterPackages(): Promise<RouterPackageInventory> {
  const response = await fetch(PACKAGES_URL, {
    method: "GET",
    credentials: "same-origin",
    cache: "no-store",
    headers: { Accept: "application/json" },
  });
  const contentType = response.headers.get("content-type") ?? "";
  if (!response.ok || !contentType.includes("application/json")) {
    if (response.status === 403) {
      throw new Error("Package inventory requires an active router administrator session.");
    }
    throw new Error("The router could not read its installed-package inventory.");
  }
  const payload: unknown = await response.json();
  if (
    typeof payload !== "object" || payload === null ||
    !("ok" in payload) || payload.ok !== true ||
    !("manager" in payload) || (payload.manager !== "apk" && payload.manager !== "opkg") ||
    !("count" in payload) || typeof payload.count !== "number" ||
    !("packages" in payload) || !Array.isArray(payload.packages) ||
    !("sampled_at" in payload) || typeof payload.sampled_at !== "number"
  ) {
    throw new Error("The router returned an invalid package inventory response.");
  }
  return payload as RouterPackageInventory;
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


function hasControlCharacters(value: string): boolean {
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    if (code < 0x20 || code === 0x7f) return true;
  }
  return false;
}

export async function updateRouterWirelessConfig(input: {
  radio: string;
  section: string;
  ssid: string;
  encryption: "psk2" | "sae" | "sae-mixed" | "none";
  key: string;
  hidden: boolean;
  channel: string;
  htmode: string;
  txpower: string;
  allowOpen: boolean;
}): Promise<RouterWirelessUpdateResult> {
  const validSection = (value: string) => /^[A-Za-z0-9_-]{1,32}$/.test(value);
  if (!validSection(input.radio) || !validSection(input.section)) {
    throw new Error("Invalid wireless radio or interface section.");
  }
  if (input.ssid.length < 1 || new TextEncoder().encode(input.ssid).length > 32 ||
      hasControlCharacters(input.ssid)) {
    throw new Error("SSID must be 1–32 bytes and cannot contain control characters.");
  }
  if (input.key.length > 0 &&
      (input.key.length < 8 || new TextEncoder().encode(input.key).length > 63 ||
       hasControlCharacters(input.key))) {
    throw new Error("The wireless passphrase must be 8–63 bytes and cannot contain control characters.");
  }
  if (input.encryption === "none" && (!input.allowOpen || input.key !== "")) {
    throw new Error("An open wireless network requires explicit confirmation and no passphrase.");
  }
  if (input.channel !== "auto" && !/^[0-9]{1,3}$/.test(input.channel)) {
    throw new Error("Choose Auto or a supported numeric channel.");
  }

  if (input.htmode !== "auto" && !/^[A-Z0-9+]{1,16}$/.test(input.htmode)) {
    throw new Error("Choose Auto or a driver-reported wireless width/PHY mode.");
  }
  if (input.txpower !== "auto" && !/^(?:[0-9]|[1-9][0-9]|100)$/.test(input.txpower)) {
    throw new Error("Choose Auto or a driver-reported whole-number transmit power.");
  }

  const form = new URLSearchParams();
  form.set("radio", input.radio);
  form.set("section", input.section);
  form.set("ssid", input.ssid);
  form.set("encryption", input.encryption);
  form.set("key", input.key);
  form.set("hidden", input.hidden ? "1" : "0");
  form.set("channel", input.channel);
  form.set("htmode", input.htmode);
  form.set("txpower", input.txpower);
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
    !("htmode" in payload) || payload.htmode !== input.htmode ||
    !("txpower" in payload) || payload.txpower !== input.txpower ||
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


export async function updateRouterLedBrightness(
  name: string,
  brightness: number,
): Promise<RouterLedUpdateResult> {
  if (!/^[A-Za-z0-9_.:-]{1,64}$/.test(name) || name === "." || name === "..") {
    throw new Error("Invalid LED class device name.");
  }
  if (!Number.isSafeInteger(brightness) || brightness < 0 || brightness > 65535) {
    throw new Error("LED brightness must be a whole number from 0 to 65,535.");
  }

  const form = new URLSearchParams();
  form.set("name", name);
  form.set("brightness", String(brightness));
  const response = await fetch(LED_UPDATE_URL, {
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
      ? "LED controls require an active router administrator session."
      : "The router returned an invalid LED control response.");
  }

  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) {
    throw new Error("The router returned an invalid LED control response.");
  }
  if ("error" in payload && typeof payload.error === "string") {
    throw new Error(payload.error);
  }
  if (
    !response.ok || !("ok" in payload) || payload.ok !== true ||
    !("name" in payload) || payload.name !== name ||
    !("brightness" in payload) || payload.brightness !== brightness ||
    !("max_brightness" in payload) || typeof payload.max_brightness !== "number" ||
    brightness > payload.max_brightness ||
    !("applied" in payload) || payload.applied !== true ||
    !("persistent" in payload) || payload.persistent !== false
  ) {
    throw new Error("The router did not confirm the requested LED brightness.");
  }
  return payload as RouterLedUpdateResult;
}


export async function downloadRouterConfigBackup(): Promise<void> {
  const form = new URLSearchParams();
  form.set("confirmed", "1");
  const response = await fetch(CONFIG_BACKUP_URL, {
    method: "POST",
    credentials: "same-origin",
    cache: "no-store",
    headers: {
      Accept: "application/gzip, application/json",
      "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
    },
    body: form.toString(),
  });
  const contentType = response.headers.get("content-type") ?? "";
  if (!response.ok) {
    if (contentType.includes("application/json")) {
      const payload: unknown = await response.json();
      if (typeof payload === "object" && payload !== null &&
          "error" in payload && typeof payload.error === "string") {
        throw new Error(payload.error);
      }
    }
    throw new Error(response.status === 403
      ? "Configuration backups require an active router administrator session."
      : "The router could not create the configuration backup.");
  }
  if (!contentType.includes("application/gzip")) {
    throw new Error("The router returned an unexpected configuration backup format.");
  }

  const archive = await response.blob();
  if (archive.size < 1 || archive.size > 64 * 1024 * 1024) {
    throw new Error("The downloaded configuration archive is empty or larger than 64 MiB.");
  }

  const exportedAt = new Date().toISOString();
  const objectUrl = URL.createObjectURL(archive);
  const link = document.createElement("a");
  link.href = objectUrl;
  link.download = "quantumgrid-config-backup-" + exportedAt.replace(/[:.]/g, "-") + ".tar.gz";
  document.body.appendChild(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(objectUrl), 0);
}


export async function fetchRouterAuditLog(): Promise<RouterAuditLog> {
  const response = await fetch(AUDIT_URL, {
    method: "GET",
    credentials: "same-origin",
    cache: "no-store",
    headers: { Accept: "application/json" },
  });
  const contentType = response.headers.get("content-type") ?? "";
  if (!response.ok || !contentType.includes("application/json")) {
    throw new Error(response.status === 403
      ? "The audit log requires an active router administrator session."
      : "The router could not read its administrative audit log.");
  }
  const payload: unknown = await response.json();
  if (
    typeof payload !== "object" || payload === null ||
    !("ok" in payload) || payload.ok !== true ||
    !("available" in payload) || typeof payload.available !== "boolean" ||
    !("events" in payload) || !Array.isArray(payload.events) ||
    !("count" in payload) || typeof payload.count !== "number" ||
    !("sampled_at" in payload) || typeof payload.sampled_at !== "number"
  ) {
    throw new Error("The router returned an invalid audit-log response.");
  }
  return payload as RouterAuditLog;
}
export async function createRouterDhcpReservation(input: {
  name: string;
  mac: string;
  ipv4: string;
  network: string;
}): Promise<RouterDhcpReservationResult> {
  const form = new URLSearchParams();
  form.set("name", input.name);
  form.set("mac", input.mac);
  form.set("ipv4", input.ipv4);
  form.set("network", input.network);
  form.set("confirmed", "1");
  const response = await fetch(DHCP_RESERVATION_URL, {
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
      ? "Static DHCP reservations require an active router administrator session."
      : "The router returned an invalid DHCP reservation response.");
  }
  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) {
    throw new Error("The router returned an invalid DHCP reservation response.");
  }
  if ("error" in payload && typeof payload.error === "string") {
    throw new Error(payload.error);
  }
  if (
    !response.ok || !("ok" in payload) || payload.ok !== true ||
    !("name" in payload) || payload.name !== input.name ||
    !("mac" in payload) || payload.mac !== input.mac.toLowerCase() ||
    !("ipv4" in payload) || payload.ipv4 !== input.ipv4 ||
    !("network" in payload) || payload.network !== input.network ||
    !("restarted" in payload) || payload.restarted !== true ||
    !("rolled_back" in payload) || payload.rolled_back !== false
  ) {
    throw new Error("The router did not confirm the DHCP reservation and dnsmasq restart.");
  }
  return payload as RouterDhcpReservationResult;
}
export async function removeRouterDhcpReservation(section: string): Promise<RouterDhcpReservationRemoveResult> {
  if (!/^[A-Za-z0-9_.-]{1,64}$/.test(section) || section === "." || section === "..") {
    throw new Error("Invalid DHCP reservation section identifier.");
  }
  const form = new URLSearchParams();
  form.set("section", section);
  form.set("confirmed", "1");
  const response = await fetch(DHCP_RESERVATION_REMOVE_URL, {
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
      ? "Removing a DHCP reservation requires an active router administrator session."
      : "The router returned an invalid DHCP reservation removal response.");
  }
  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) {
    throw new Error("The router returned an invalid DHCP reservation removal response.");
  }
  if ("error" in payload && typeof payload.error === "string") {
    throw new Error(payload.error);
  }
  if (
    !response.ok || !("ok" in payload) || payload.ok !== true ||
    !("section" in payload) || payload.section !== section ||
    !("removed" in payload) || payload.removed !== true ||
    !("restarted" in payload) || payload.restarted !== true ||
    !("rolled_back" in payload) || payload.rolled_back !== false
  ) {
    throw new Error("The router did not confirm reservation removal and dnsmasq restart.");
  }
  return payload as RouterDhcpReservationRemoveResult;
}
export async function updateRouterDhcpScope(input: {
  section: string;
  start: string;
  limit: string;
  lease_time: string;
}): Promise<RouterDhcpScopeUpdateResult> {
  if (!/^[A-Za-z0-9_.-]{1,64}$/.test(input.section) || input.section === "." || input.section === "..") {
    throw new Error("Invalid DHCP scope section identifier.");
  }
  if (!/^[1-9][0-9]{0,9}$/.test(input.start) || !/^[1-9][0-9]{0,9}$/.test(input.limit)) {
    throw new Error("DHCP start and limit must be positive whole numbers.");
  }
  if (!/^[1-9][0-9]{0,8}[smhdw]?$/.test(input.lease_time)) {
    throw new Error("DHCP lease time must be a positive duration such as 12h, 30m or 86400s.");
  }
  const form = new URLSearchParams();
  form.set("section", input.section);
  form.set("start", input.start);
  form.set("limit", input.limit);
  form.set("leasetime", input.lease_time);
  form.set("confirmed", "1");
  const response = await fetch(DHCP_SCOPE_UPDATE_URL, {
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
      ? "DHCP scope changes require an active router administrator session."
      : "The router returned an invalid DHCP scope update response.");
  }
  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) {
    throw new Error("The router returned an invalid DHCP scope update response.");
  }
  if ("error" in payload && typeof payload.error === "string") {
    throw new Error(payload.error);
  }
  if (
    !response.ok || !("ok" in payload) || payload.ok !== true ||
    !("section" in payload) || payload.section !== input.section ||
    !("start" in payload) || payload.start !== String(Number(input.start)) ||
    !("limit" in payload) || payload.limit !== String(Number(input.limit)) ||
    !("lease_time" in payload) || payload.lease_time !== input.lease_time ||
    !("pool_start_ip" in payload) || typeof payload.pool_start_ip !== "string" ||
    !("pool_end_ip" in payload) || typeof payload.pool_end_ip !== "string" ||
    !("restarted" in payload) || payload.restarted !== true ||
    !("rolled_back" in payload) || payload.rolled_back !== false
  ) {
    throw new Error("The router did not confirm the DHCP scope update and dnsmasq restart.");
  }
  return payload as RouterDhcpScopeUpdateResult;
}
export async function updateRouterRemoteSyslog(input: {
  enabled: boolean;
  host: string;
  port: number;
  protocol: "tcp" | "udp";
  hostname: string;
  prefix: string;
}): Promise<RouterRemoteSyslogUpdateResult> {
  if (input.enabled) {
    if (!/^(?:[A-Za-z0-9-]+\.)*[A-Za-z0-9-]+$/.test(input.host) || input.host.length > 253 || input.host.includes("..")) {
      throw new Error("Enter a valid IPv4 address or DNS host name for the remote syslog server.");
    }
    if (!Number.isSafeInteger(input.port) || input.port < 1 || input.port > 65535) {
      throw new Error("Remote syslog port must be a whole number from 1 to 65,535.");
    }
    if (input.protocol !== "tcp" && input.protocol !== "udp") {
      throw new Error("Remote syslog transport must be TCP or UDP.");
    }
    if (input.hostname && (!/^(?:[A-Za-z0-9][A-Za-z0-9-]*\.)*[A-Za-z0-9][A-Za-z0-9-]*$/.test(input.hostname) || input.hostname.length > 253)) {
      throw new Error("The sender hostname must be a valid DNS host name.");
    }
    if (input.prefix.length > 32 || (input.prefix !== "" && !/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(input.prefix))) {
      throw new Error("The syslog prefix may contain letters, digits, dots, underscores and hyphens (maximum 32 characters).");
    }
  }
  const form = new URLSearchParams();
  form.set("enabled", input.enabled ? "1" : "0");
  form.set("host", input.host);
  form.set("port", String(input.port));
  form.set("protocol", input.protocol);
  form.set("hostname", input.hostname);
  form.set("prefix", input.prefix);
  const response = await fetch(REMOTE_SYSLOG_URL, {
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
      ? "Remote syslog changes require an active router administrator session."
      : "The router returned an invalid remote syslog response.");
  }
  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) {
    throw new Error("The router returned an invalid remote syslog response.");
  }
  if ("error" in payload && typeof payload.error === "string") {
    throw new Error(payload.error);
  }
  if (
    !response.ok || !("ok" in payload) || payload.ok !== true ||
    !("enabled" in payload) || payload.enabled !== input.enabled ||
    !("restarted" in payload) || payload.restarted !== true ||
    !("rolled_back" in payload) || payload.rolled_back !== false ||
    !("host" in payload) || typeof payload.host !== "string" ||
    !("port" in payload) || typeof payload.port !== "number" ||
    !("protocol" in payload) || (payload.protocol !== "tcp" && payload.protocol !== "udp")
  ) {
    throw new Error("The router did not confirm the remote syslog update and log-service restart.");
  }
  return payload as RouterRemoteSyslogUpdateResult;
}
export async function updateRouterDhcpReservation(input: {
  section: string;
  name: string;
  mac: string;
  ipv4: string;
  network: string;
}): Promise<RouterDhcpReservationUpdateResult> {
  if (!/^[A-Za-z0-9_.-]{1,64}$/.test(input.section) || input.section === "." || input.section === "..") {
    throw new Error("Invalid DHCP reservation section identifier.");
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9-]{0,62}$/.test(input.name)) {
    throw new Error("Host name must start with a letter or digit and contain only letters, digits or hyphens.");
  }
  if (!/^[A-Fa-f0-9]{2}(:[A-Fa-f0-9]{2}){5}$/.test(input.mac)) {
    throw new Error("A six-octet MAC address is required.");
  }
  if (!/^[0-9]{1,3}(\.[0-9]{1,3}){3}$/.test(input.ipv4)) {
    throw new Error("A dotted-decimal IPv4 address is required.");
  }
  if (!/^[A-Za-z0-9_.-]{1,64}$/.test(input.network) || input.network === "." || input.network === "..") {
    throw new Error("Invalid LAN interface name.");
  }
  const form = new URLSearchParams();
  form.set("section", input.section);
  form.set("name", input.name);
  form.set("mac", input.mac);
  form.set("ipv4", input.ipv4);
  form.set("network", input.network);
  form.set("confirmed", "1");
  const response = await fetch(DHCP_RESERVATION_UPDATE_URL, {
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
      ? "Editing DHCP reservations requires an active router administrator session."
      : "The router returned an invalid DHCP reservation update response.");
  }
  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) {
    throw new Error("The router returned an invalid DHCP reservation update response.");
  }
  if ("error" in payload && typeof payload.error === "string") {
    throw new Error(payload.error);
  }
  if (
    !response.ok || !("ok" in payload) || payload.ok !== true ||
    !("section" in payload) || payload.section !== input.section ||
    !("name" in payload) || payload.name !== input.name ||
    !("mac" in payload) || payload.mac !== input.mac.toLowerCase() ||
    !("ipv4" in payload) || payload.ipv4 !== input.ipv4 ||
    !("network" in payload) || payload.network !== input.network ||
    !("restarted" in payload) || payload.restarted !== true ||
    !("rolled_back" in payload) || payload.rolled_back !== false
  ) {
    throw new Error("The router did not confirm the reservation edit and dnsmasq restart.");
  }
  return payload as RouterDhcpReservationUpdateResult;
}
export async function updateRouterDhcpScopeEnabled(section: string, enabled: boolean): Promise<RouterDhcpScopeToggleResult> {
  if (!/^[A-Za-z0-9_.-]{1,64}$/.test(section) || section === "." || section === "..") {
    throw new Error("Invalid DHCP scope section identifier.");
  }
  const form = new URLSearchParams();
  form.set("section", section);
  form.set("enabled", enabled ? "1" : "0");
  form.set("confirmed", "1");
  const response = await fetch(DHCP_SCOPE_TOGGLE_URL, {
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
      ? "DHCP scope changes require an active router administrator session."
      : "The router returned an invalid DHCP scope state response.");
  }
  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) {
    throw new Error("The router returned an invalid DHCP scope state response.");
  }
  if ("error" in payload && typeof payload.error === "string") {
    throw new Error(payload.error);
  }
  if (
    !response.ok || !("ok" in payload) || payload.ok !== true ||
    !("section" in payload) || payload.section !== section ||
    !("enabled" in payload) || payload.enabled !== enabled ||
    !("changed" in payload) || typeof payload.changed !== "boolean" ||
    !("restarted" in payload) || typeof payload.restarted !== "boolean" ||
    !("rolled_back" in payload) || payload.rolled_back !== false ||
    payload.changed !== payload.restarted
  ) {
    throw new Error("The router did not confirm the DHCP scope state and dnsmasq result.");
  }
  return payload as RouterDhcpScopeToggleResult;
}
export async function createRouterDhcpScope(input: {
  network: string;
  start: string;
  limit: string;
  lease_time: string;
}): Promise<RouterDhcpScopeCreateResult> {
  if (!/^[A-Za-z0-9_.-]{1,64}$/.test(input.network) || input.network === "." || input.network === "..") {
    throw new Error("Invalid LAN interface name.");
  }
  if (!/^[1-9][0-9]{0,9}$/.test(input.start) || !/^[1-9][0-9]{0,9}$/.test(input.limit)) {
    throw new Error("DHCP start and limit must be positive whole numbers.");
  }
  if (!/^[1-9][0-9]{0,8}[smhdw]?$/.test(input.lease_time)) {
    throw new Error("DHCP lease time must be a positive duration such as 12h, 30m or 86400s.");
  }
  const form = new URLSearchParams();
  form.set("network", input.network);
  form.set("start", input.start);
  form.set("limit", input.limit);
  form.set("leasetime", input.lease_time);
  form.set("confirmed", "1");
  const response = await fetch(DHCP_SCOPE_ADD_URL, {
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
      ? "Creating a DHCP scope requires an active router administrator session."
      : "The router returned an invalid DHCP scope creation response.");
  }
  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) {
    throw new Error("The router returned an invalid DHCP scope creation response.");
  }
  if ("error" in payload && typeof payload.error === "string") {
    throw new Error(payload.error);
  }
  if (
    !response.ok || !("ok" in payload) || payload.ok !== true ||
    !("section" in payload) || typeof payload.section !== "string" || payload.section.length === 0 ||
    !("network" in payload) || payload.network !== input.network ||
    !("start" in payload) || payload.start !== String(Number(input.start)) ||
    !("limit" in payload) || payload.limit !== String(Number(input.limit)) ||
    !("lease_time" in payload) || payload.lease_time !== input.lease_time ||
    !("pool_start_ip" in payload) || typeof payload.pool_start_ip !== "string" ||
    !("pool_end_ip" in payload) || typeof payload.pool_end_ip !== "string" ||
    !("restarted" in payload) || payload.restarted !== true ||
    !("rolled_back" in payload) || payload.rolled_back !== false
  ) {
    throw new Error("The router did not confirm the new DHCP scope and dnsmasq restart.");
  }
  return payload as RouterDhcpScopeCreateResult;
}
export async function removeRouterDhcpScope(section: string): Promise<RouterDhcpScopeRemoveResult> {
  if (!/^[A-Za-z0-9_.-]{1,64}$/.test(section) || section === "." || section === "..") {
    throw new Error("Invalid DHCP scope section identifier.");
  }
  const form = new URLSearchParams();
  form.set("section", section);
  form.set("confirmed", "1");
  const response = await fetch(DHCP_SCOPE_REMOVE_URL, {
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
      ? "Removing a DHCP scope requires an active router administrator session."
      : "The router returned an invalid DHCP scope removal response.");
  }
  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) {
    throw new Error("The router returned an invalid DHCP scope removal response.");
  }
  if ("error" in payload && typeof payload.error === "string") {
    throw new Error(payload.error);
  }
  if (
    !response.ok || !("ok" in payload) || payload.ok !== true ||
    !("section" in payload) || payload.section !== section ||
    !("interface" in payload) || typeof payload.interface !== "string" ||
    !("removed" in payload) || payload.removed !== true ||
    !("restarted" in payload) || payload.restarted !== true ||
    !("rolled_back" in payload) || payload.rolled_back !== false
  ) {
    throw new Error("The router did not confirm DHCP scope removal and dnsmasq restart.");
  }
  return payload as RouterDhcpScopeRemoveResult;
}
