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

export interface RouterWirelessRadiusVlan {
  section: string;
  name: string;
  vid: number;
  network: string;
  managed: boolean;
}

export interface RouterWirelessRadiusVlanUpdate {
  vid: string;
  network: string;
  name?: string;
  device?: string;
  bridge?: string;
  zone?: string;
}

export interface RouterWirelessConfig {
  section: string;
  radio: string;
  mode: "ap";
  ssid: string;
  networks: string[];
  dynamic_vlan: number;
  radius_vlan_unmanaged: boolean;
  radius_vlan_mappings: RouterWirelessRadiusVlan[];
  encryption: string;
  ieee80211w: string;
  hidden: boolean;
  key_set: boolean;
  radius_auth_server: string;
  radius_auth_port: number;
  radius_secret_set: boolean;
  accounting_server: string;
  accounting_port: number;
  accounting_secret_set: boolean;
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
  network: string;
  encryption: string;
  ieee80211w?: string;
  hidden: boolean;
  channel: string;
  htmode: string;
  txpower: string;
  key_set: boolean;
  radius_auth_server?: string;
  radius_auth_port?: number;
  radius_secret_set: boolean;
  dynamic_vlan: number;
  radius_vlan_count: number;
  radius_vlan_mappings: RouterWirelessRadiusVlanUpdate[];
  accounting_server?: string;
  accounting_port?: number;
  accounting_secret_set: boolean;
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

export type RouterSqmCakeProfile = "default" | "besteffort" | "diffserv4" | "diffserv8" | "custom";
export type RouterSqmCakeProfileChoice = Exclude<RouterSqmCakeProfile, "custom">;

export interface RouterSqmQueue {
  name: string;
  enabled: boolean;
  interface: string;
  download_kbps?: number;
  upload_kbps?: number;
  qdisc: string;
  script: string;
  linklayer: string;
  overhead?: number;
  tc_mpu?: number;
  cake_profile?: RouterSqmCakeProfile;
  runtime_state: "observed" | "not_observed" | "unavailable" | "unconfigured" | "inventory_truncated" | "disabled";
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

export type RouterSqmClientDscpClass = "BE" | "AF41" | "EF" | "CS1";

export interface RouterSqmClientPolicy {
  section: string;
  name: string;
  mac: string;
  source_zone: string;
  destination_zone: string;
  dscp_class: RouterSqmClientDscpClass;
  enabled: boolean;
}

export interface RouterSqmClientPolicyResult {
  ok: true;
  section: string;
  mac: string;
  source_zone: string;
  destination_zone: string;
  dscp_class: RouterSqmClientDscpClass;
  reloaded: true;
  rolled_back: false;
}

export interface RouterSqmClientPolicyRemoveResult extends RouterSqmClientPolicyResult {
  removed: true;
}

export interface RouterSqmStatus {
  installed: boolean;
  config_available: boolean;
  config_readable: boolean;
  queues: RouterSqmQueue[];
  runtime_available: boolean;
  qdiscs_truncated: boolean;
  qdiscs: RouterQdiscState[];
  client_policy_available: boolean;
  client_policies: RouterSqmClientPolicy[];
  client_policies_truncated: boolean;
}

export interface RouterMwan3TrackTarget {
  ip: string;
  status: string;
  latency_ms?: number;
  packet_loss_percent?: number;
}

export interface RouterMwan3InterfaceConfig {
  section: string;
  enabled: boolean;
  track_ips: string[];
  track_targets_valid: boolean;
  reliability: number;
  count: number;
  timeout: number;
  interval: number;
  down: number;
  up: number;
  initial_state: "online" | "offline" | "unknown";
  valid: boolean;
}

export interface RouterMwan3InterfaceUpdateResult {
  ok: true;
  section: string;
  enabled: boolean;
  track_ips: string[];
  reliability: number;
  count: number;
  timeout: number;
  interval: number;
  down: number;
  up: number;
  initial_state: "online" | "offline";
  restarted: true;
  rolled_back: false;
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
  config_available: boolean;
  config_count: number;
  config_truncated: boolean;
  config_interfaces: RouterMwan3InterfaceConfig[];
}

export interface RouterSqmQueueUpdateResult {
  ok: true;
  section: string;
  enabled: boolean;
  download_kbps: number;
  upload_kbps: number;
  linklayer: string;
  overhead_bytes: number;
  tc_mpu_bytes: number;
  restarted: true;
  rolled_back: false;
}

export interface RouterSqmCakeProfileUpdateResult {
  ok: true;
  section: string;
  profile: RouterSqmCakeProfileChoice;
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

export interface RouterFirewallRedirect {
  section: string;
  name: string;
  source_zone: string;
  destination_zone: string;
  protocol: string;
  target: string;
  family: string;
  external_port: string;
  internal_port: string;
  enabled: boolean;
  source_ip_match: boolean;
  source_mac_match: boolean;
  destination_ip_match: boolean;
  source_destination_ip_match: boolean;
}

export interface RouterFirewallRuntimeChain {
  name: string;
  hook: string;
  policy: string;
  type: string;
  priority?: number;
  device: string;
  rule_count: number;
}

export interface RouterFirewallRuntimeStatus {
  available: boolean;
  table_present: boolean;
  chains: RouterFirewallRuntimeChain[];
  chain_count: number;
  rule_count: number;
  truncated: boolean;
  sampled_at: number;
}

export interface RouterDropbearInstance {
  name: string;
  enabled?: boolean | null;
  interface: string;
  interface_bound: boolean;
  port?: number | null;
  port_valid: boolean;
  password_auth_enabled?: boolean | null;
  root_password_auth_enabled?: boolean | null;
  gateway_ports_enabled?: boolean | null;
}

export interface RouterAuthorizedKeysStatus {
  available: boolean;
  path: string;
  size_bytes?: number | null;
  root_owned?: boolean | null;
  regular_file?: boolean | null;
  owner_readable?: boolean | null;
  group_writable?: boolean | null;
  other_writable?: boolean | null;
  directory_root_owned?: boolean | null;
  directory_valid?: boolean | null;
  directory_group_writable?: boolean | null;
  directory_other_writable?: boolean | null;
  directory: string;
  status: "present" | "missing" | "review" | "unknown" | "unavailable";
}

export interface RouterHttpsPrivateKeyStatus {
  available: boolean;
  path: string;
  size_bytes?: number;
  root_owned?: boolean;
  regular_file?: boolean;
  owner_readable?: boolean;
  group_access?: boolean;
  other_access?: boolean;
  status: "present" | "missing" | "review" | "unknown";
}

export interface RouterCertificateFingerprint {
  available: boolean;
  algorithm: "SHA-256";
  value?: string;
}

export interface RouterManagementTransport {
  service_installed: boolean;
  http_listener_count: number;
  https_listener_count: number;
  tls_library_available: boolean;
  certificate_available: boolean;
  key_generator_available: boolean;
  private_key?: RouterHttpsPrivateKeyStatus;
  certificate_fingerprint?: RouterCertificateFingerprint;
  http_redirect_enabled: boolean;
  https_configured: boolean;
  plaintext_http_unredirected: boolean;
  ssh_service_installed?: boolean;
  ssh_config_available?: boolean;
  ssh_instance_count?: number;
  ssh_enabled_instance_count?: number;
  ssh_truncated?: boolean;
  ssh_instances?: RouterDropbearInstance[];
  ssh_status?: "ready" | "review" | "unavailable" | "disabled";
  ssh_authorized_keys?: RouterAuthorizedKeysStatus;
  status: "ready" | "review" | "unavailable";
}

export interface RouterSecurityStatus {
  firewall_installed: boolean;
  firewall_config_available: boolean;
  firewall_config_readable: boolean;
  zones: RouterFirewallZone[];
  rules: RouterFirewallRule[];
  rules_count: number;
  redirects: RouterFirewallRedirect[];
  redirects_count: number;
  redirects_truncated: boolean;
  nft_available: boolean;
  nft_tables: string[];
  nft_runtime: RouterFirewallRuntimeStatus;
  management_transport?: RouterManagementTransport;
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

export interface RouterDeviceIdentity {
  available: boolean;
  status: "available" | "unavailable";
  id?: string;
}

export type RouterDeviceProfileCapabilityDeclaration =
  | "declared-supported"
  | "not-declared"
  | "unknown";

export interface RouterDeviceProfileCapabilities {
  available: boolean;
  nss: RouterDeviceProfileCapabilityDeclaration;
  fxs: RouterDeviceProfileCapabilityDeclaration;
}

export interface RouterRuntimeDeviceProfile {
  available: boolean;
  capabilities?: RouterDeviceProfileCapabilities;
  status: "matched" | "mismatch" | "unknown" | "unavailable";
  profile_id?: string;
  vendor?: string;
  model?: string;
  openwrt_device?: string;
  openwrt_target?: string;
  openwrt_subtarget?: string;
  board_compatible?: string[];
  observed_board_name?: string;
}

export interface RouterPlatformStatus {
  available: boolean;
  device_profile?: RouterRuntimeDeviceProfile;
  device_identity?: RouterDeviceIdentity;
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

export interface RouterGpioSysfsChip {
  name: string;
  label: string;
  base: number;
  ngpio: number;
}

export interface RouterGpioInventory {
  available: boolean;
  chips: RouterGpioChip[];
  chip_count: number;
  lines: RouterGpioLine[];
  line_count: number;
  truncated: boolean;
  sysfs: {
    available: boolean;
    chips: RouterGpioSysfsChip[];
    count: number;
    truncated: boolean;
  };
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

export interface RouterBoardGpioLineReference {
  name: string;
  purpose: string;
  tlmm_offset: number;
  direction: string;
  active_level: string;
  owner: string;
  linux_key?: string;
  initial_level?: string;
  note?: string;
}

export interface RouterBoardLedOutputReference {
  name: string;
  label: string;
  output_index: number;
  active_level: string;
}

export interface RouterBoardGpioReference {
  available: boolean;
  model?: string;
  compatible?: string;
  source_url?: string;
  source_blob_sha?: string;
  offset_namespace?: string;
  warning?: string;
  buttons: RouterBoardGpioLineReference[];
  auxiliary: RouterBoardGpioLineReference[];
  bus_signals: RouterBoardGpioLineReference[];
  phy_resets: RouterBoardGpioLineReference[];
  led_expander?: {
    part: string;
    register_count: number;
    clock_tlmm_offset: number;
    data_tlmm_offset: number;
    enable_tlmm_offset: number;
    outputs: RouterBoardLedOutputReference[];
  };
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
	board_reference: RouterBoardGpioReference;
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

export interface RouterOfficeVlanUpdateResult {
  ok: true;
  section: string;
  device: string;
  vlan_id: number;
  ports: string[];
  reloaded: true;
  rolled_back: false;
}

export interface RouterOfficeVlanRemoveResult {
  ok: true;
  section: string;
  device: string;
  vlan_id: number;
  removed: true;
  reloaded: true;
  rolled_back: false;
}

export interface RouterOfficeWifiAp {
  ssid: string;
  section: string;
  device: string;
  networks: string[];
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
  section: string;
  name: string;
  networks: string[];
  input: string;
  output: string;
  forward: string;
  masquerade: boolean;
}

export interface RouterOfficeFirewallZoneUpdateResult {
  ok: true;
  section: string;
  name: string;
  input: string;
  output: string;
  forward: string;
  masquerade: boolean;
  input_unchanged: true;
  reloaded: true;
  rolled_back: false;
}

export interface RouterOfficeSegmentCreateResult {
  ok: true;
  name: string;
  device: string;
  address: string;
  netmask: string;
  zone: string;
  pool_start_ip: string;
  pool_end_ip: string;
  firewall_rules: 3 | 7;
  ipv6_enabled: boolean;
  ipv6_assign: "" | "64";
  dhcpv6: "disabled" | "server";
  ra: "disabled" | "server";
  ra_flags: string[];
  ra_slaac: "0" | "1";
  ra_dns: "0" | "1";
  ra_preference: "medium" | "high" | "low";
  ra_lifetime: number;
  dhcpv6_na: "0" | "1";
  dhcpv6_pd: "0" | "1";
  dhcpv6_assignall: "0" | "1";
  ndp: "disabled";
  network_reloaded: true;
  firewall_reloaded: true;
  dhcp_restarted: true;
  odhcpd_restarted: boolean;
  rolled_back: false;
}

export interface RouterOfficeForwarding {
  section: string;
  name: string;
  source: string;
  destination: string;
}

export interface RouterOfficePortForward {
  section: string;
  name: string;
  source: string;
  destination: string;
  protocol: RouterOfficePortForwardProtocol;
  source_port: number;
  destination_ip: string;
  destination_port: number;
}

export interface RouterOfficeForwardingCreateResult {
  ok: true;
  section: string;
  source: string;
  destination: string;
  reloaded: true;
  rolled_back: false;
}

export interface RouterOfficeForwardingRemoveResult {
  ok: true;
  section: string;
  source: string;
  destination: string;
  removed: true;
  reloaded: true;
  rolled_back: false;
}

export type RouterOfficePortForwardProtocol = "tcp" | "udp" | "tcp udp";

export interface RouterOfficePortForwardCreateResult {
  ok: true;
  section: string;
  name: string;
  source: string;
  destination: string;
  protocol: RouterOfficePortForwardProtocol;
  source_port: number;
  destination_ip: string;
  destination_port: number;
  reloaded: true;
  rolled_back: false;
}

export interface RouterOfficePortForwardRemoveResult {
  ok: true;
  section: string;
  removed: true;
  reloaded: true;
  rolled_back: false;
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
  ndp: string;
  ra_flags: string[];
  ra_slaac: boolean;
  ra_dns: boolean;
  ra_preference: string;
  ra_lifetime: number;
  dhcpv6_na: boolean;
  dhcpv6_pd: boolean;
  dhcpv6_assignall: boolean;
  dhcpv6_pd_min_len: number;
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
  wifi_aps: RouterOfficeWifiAp[];
  forwardings: RouterOfficeForwarding[];
  forwarding_count: number;
  redirects: RouterOfficePortForward[];
  redirect_count: number;
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
  dhcpv6: string;
  ra: string;
  ndp: string;
  ra_flags: string[];
  ra_slaac: boolean;
  ra_dns: boolean;
  ra_preference: string;
  ra_lifetime: number;
  dhcpv6_na: boolean;
  dhcpv6_pd: boolean;
  dhcpv6_assignall: boolean;
  dhcpv6_pd_min_len: number;
  restarted: true;
  dnsmasq_restarted: true;
  odhcpd_restarted: boolean;
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
  root_password_set: boolean;
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
const MWAN3_INTERFACE_UPDATE_URL = "/cgi-bin/luci/admin/services/quantumgrid/mwan3-interface-update";
const SQM_CAKE_PROFILE_URL = "/cgi-bin/luci/admin/services/quantumgrid/sqm-cake-profile";
const SQM_CLIENT_QOS_ADD_URL = "/cgi-bin/luci/admin/services/quantumgrid/sqm-client-qos-add";
const SQM_CLIENT_QOS_REMOVE_URL = "/cgi-bin/luci/admin/services/quantumgrid/sqm-client-qos-remove";
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
const BRIDGE_VLAN_UPDATE_URL = "/cgi-bin/luci/admin/services/quantumgrid/bridge-vlan-update";
const BRIDGE_VLAN_REMOVE_URL = "/cgi-bin/luci/admin/services/quantumgrid/bridge-vlan-remove";
const OFFICE_FORWARDING_ADD_URL = "/cgi-bin/luci/admin/services/quantumgrid/office-forwarding-add";
const OFFICE_FORWARDING_REMOVE_URL = "/cgi-bin/luci/admin/services/quantumgrid/office-forwarding-remove";
const OFFICE_PORT_FORWARD_ADD_URL = "/cgi-bin/luci/admin/services/quantumgrid/office-port-forward-add";
const OFFICE_PORT_FORWARD_REMOVE_URL = "/cgi-bin/luci/admin/services/quantumgrid/office-port-forward-remove";
const OFFICE_ZONE_UPDATE_URL = "/cgi-bin/luci/admin/services/quantumgrid/office-zone-update";
const OFFICE_WIFI_NETWORK_UPDATE_URL = "/cgi-bin/luci/admin/services/quantumgrid/office-wifi-network-update";
const OFFICE_SEGMENT_ADD_URL = "/cgi-bin/luci/admin/services/quantumgrid/office-segment-add";
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
  if (
    !("root_password_set" in payload) ||
    typeof payload.root_password_set !== "boolean"
  ) {
    throw new Error(
      "This firmware cannot verify whether the root password is set. Update QuantumGrid firmware before signing in.",
    );
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
  let overview: RouterOverview;
  try {
    overview = await authenticate(username, password);
  } catch (originalError) {
    // rpcd accepts a session on an unconfigured root account because its password
    // hash is empty. Only retry with an empty password when the supplied login fails;
    // the API's root_password_set flag below decides whether setup is still required.
    if (!password) throw originalError;

    try {
      overview = await authenticate(username, "");
    } catch {
      throw originalError;
    }
  }

  // Never mistake rpcd's empty-hash bootstrap session for a secured administrator.
  if (!overview.root_password_set) {
    await setInitialRootPassword(password);
    return fetchRouterOverview();
  }

  return overview;
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
  network: string;
  encryption: "psk2" | "sae" | "sae-mixed" | "wpa2" | "wpa3" | "none";
  key: string;
  radiusServer: string;
  radiusPort: string;
  radiusSecret: string;
  manageRadiusVlans: boolean;
  dynamicVlanEnabled: boolean;
  radiusVlans: Array<{ vid: string; network: string }>;
  accountingServer: string;
  accountingPort: string;
  accountingSecret: string;
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
  if (!/^[A-Za-z0-9_.-]{1,64}$/.test(input.network) ||
      input.network === "." || input.network === "..") {
    throw new Error("Select one existing routed network interface.");
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
  const enterpriseMode = input.encryption === "wpa2" || input.encryption === "wpa3";
  if (enterpriseMode && input.accountingServer !== "") {
    const host = input.accountingServer;
    const labels = host.split(".");
    const hostnameValid = host.length >= 1 && host.length <= 253 &&
      /^[A-Za-z0-9.-]+$/.test(host) && !host.startsWith(".") && !host.endsWith(".") &&
      !host.includes("..") && labels.every((label) =>
        label.length >= 1 && label.length <= 63 &&
        /^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$/.test(label));
    const ipv4 = labels.length === 4 && labels.every((label) => /^\d+$/.test(label));
    const ipv4Valid = !ipv4 || labels.every((label) => Number(label) >= 0 && Number(label) <= 255);
    if (!hostnameValid || !ipv4Valid) {
      throw new Error("RADIUS accounting server must be an IPv4 address or valid DNS hostname.");
    }
    if (!/^[0-9]{1,5}$/.test(input.accountingPort) ||
        Number(input.accountingPort) < 1 || Number(input.accountingPort) > 65535) {
      throw new Error("RADIUS accounting port must be a whole number from 1 to 65535.");
    }
    const secretBytes = new TextEncoder().encode(input.accountingSecret).length;
    if (input.accountingSecret.length > 0 &&
        (secretBytes < 16 || secretBytes > 128 || hasControlCharacters(input.accountingSecret))) {
      throw new Error("RADIUS accounting shared secret must be 16–128 bytes and contain no control characters.");
    }
  }
  if (enterpriseMode) {
    const host = input.radiusServer;
    const labels = host.split(".");
    const hostnameValid = host.length >= 1 && host.length <= 253 &&
      /^[A-Za-z0-9.-]+$/.test(host) && !host.startsWith(".") && !host.endsWith(".") &&
      !host.includes("..") && labels.every((label) =>
        label.length >= 1 && label.length <= 63 &&
        /^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$/.test(label));
    const ipv4 = labels.length === 4 && labels.every((label) => /^\d+$/.test(label));
    const ipv4Valid = !ipv4 || labels.every((label) => Number(label) >= 0 && Number(label) <= 255);
    if (!hostnameValid || !ipv4Valid) {
      throw new Error("RADIUS server must be an IPv4 address or valid DNS hostname.");
    }
    if (!/^[0-9]{1,5}$/.test(input.radiusPort) ||
        Number(input.radiusPort) < 1 || Number(input.radiusPort) > 65535) {
      throw new Error("RADIUS authentication port must be a whole number from 1 to 65535.");
    }
    const secretBytes = new TextEncoder().encode(input.radiusSecret).length;
    if (input.radiusSecret.length > 0 &&
        (secretBytes < 16 || secretBytes > 128 || hasControlCharacters(input.radiusSecret))) {
      throw new Error("RADIUS shared secret must be 16–128 bytes and contain no control characters.");
    }
    if (input.key !== "") {
      throw new Error("Enterprise security uses the RADIUS shared secret, not a personal Wi-Fi passphrase.");
    }
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
  if (typeof input.manageRadiusVlans !== "boolean" ||
      typeof input.dynamicVlanEnabled !== "boolean" || !Array.isArray(input.radiusVlans)) {
    throw new Error("RADIUS VLAN control settings are invalid.");
  }
  if (!input.manageRadiusVlans && (input.dynamicVlanEnabled || input.radiusVlans.length !== 0)) {
    throw new Error("Externally managed RADIUS VLAN settings cannot be changed through QuantumGrid.");
  }
  if (input.manageRadiusVlans && input.dynamicVlanEnabled) {
    if (!enterpriseMode) {
      throw new Error("RADIUS dynamic VLAN requires WPA2-Enterprise or WPA3-Enterprise.");
    }
    if (input.radiusVlans.length < 1 || input.radiusVlans.length > 16) {
      throw new Error("Choose between 1 and 16 pre-provisioned RADIUS VLAN mappings.");
    }
    const seenVids = new Set<string>();
    const seenNetworks = new Set<string>();
    for (const mapping of input.radiusVlans) {
      if (!mapping || typeof mapping.vid !== "string" ||
          !/^[1-9][0-9]{0,3}$/.test(mapping.vid) ||
          Number(mapping.vid) < 1 || Number(mapping.vid) > 4094 ||
          !/^[A-Za-z0-9_.-]{1,64}$/.test(mapping.network) ||
          mapping.network === "." || mapping.network === "..") {
        throw new Error("Each RADIUS VLAN mapping requires a VLAN ID from 1 to 4094 and a valid routed network.");
      }
      if (seenVids.has(mapping.vid) || seenNetworks.has(mapping.network)) {
        throw new Error("RADIUS VLAN IDs and routed network interfaces must be unique.");
      }
      seenVids.add(mapping.vid);
      seenNetworks.add(mapping.network);
    }
  } else if (input.radiusVlans.length !== 0) {
    throw new Error("Disable RADIUS dynamic VLAN by removing all mappings.");
  }

  const form = new URLSearchParams();
  form.set("radio", input.radio);
  form.set("section", input.section);
  form.set("ssid", input.ssid);
  form.set("network", input.network);
  form.set("encryption", input.encryption);
  form.set("key", input.key);
  form.set("radius_server", input.radiusServer);
  form.set("radius_port", input.radiusPort);
  form.set("radius_secret", input.radiusSecret);
  form.set("manage_radius_vlans", input.manageRadiusVlans ? "1" : "0");
  form.set("dynamic_vlan_enabled", input.dynamicVlanEnabled ? "1" : "0");
  form.set("radius_vlan_mappings", JSON.stringify(input.radiusVlans));
  form.set("accounting_server", input.accountingServer);
  form.set("accounting_port", input.accountingPort);
  form.set("accounting_secret", input.accountingSecret);
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
  const expectedRadiusVlans = [...input.radiusVlans].sort((left, right) =>
    Number(left.vid) - Number(right.vid));
  if (
    !response.ok || !("ok" in payload) || payload.ok !== true ||
    !("radio" in payload) || payload.radio !== input.radio ||
    !("section" in payload) || payload.section !== input.section ||
    !("ssid" in payload) || payload.ssid !== input.ssid ||
    !("network" in payload) || payload.network !== input.network ||
    !("encryption" in payload) || payload.encryption !== input.encryption ||
    !("hidden" in payload) || payload.hidden !== input.hidden ||
    !("channel" in payload) || payload.channel !== input.channel ||
    !("htmode" in payload) || payload.htmode !== input.htmode ||
    !("txpower" in payload) || payload.txpower !== input.txpower ||
    !("reloaded" in payload) || payload.reloaded !== true ||
    !("rolled_back" in payload) || payload.rolled_back !== false ||
    (input.encryption === "wpa3" && (!("ieee80211w" in payload) || payload.ieee80211w !== "2")) ||
    !("radius_secret_set" in payload) || payload.radius_secret_set !== enterpriseMode ||
    !("accounting_secret_set" in payload) ||
      payload.accounting_secret_set !== (enterpriseMode && input.accountingServer !== "") ||
    (input.manageRadiusVlans && (
      !("dynamic_vlan" in payload) ||
      payload.dynamic_vlan !== (input.dynamicVlanEnabled ? 2 : 0) ||
      !("radius_vlan_count" in payload) ||
      payload.radius_vlan_count !== input.radiusVlans.length ||
      !("radius_vlan_mappings" in payload) || !Array.isArray(payload.radius_vlan_mappings) ||
      payload.radius_vlan_mappings.length !== expectedRadiusVlans.length ||
      payload.radius_vlan_mappings.some((mapping, index) =>
        typeof mapping !== "object" || mapping === null ||
        !("vid" in mapping) || mapping.vid !== expectedRadiusVlans[index].vid ||
        !("network" in mapping) || mapping.network !== expectedRadiusVlans[index].network
      )
    ))
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
  linklayer: string,
  overheadBytes: number,
  tcMpuBytes: number,
): Promise<RouterSqmQueueUpdateResult> {
  if (!/^[A-Za-z0-9_-]{1,32}$/.test(section)) {
    throw new Error("Invalid SQM queue section name.");
  }
  const validRate = (value: number) => Number.isInteger(value) && value >= 64 && value <= 1_000_000;
  if (!validRate(downloadKbps) || !validRate(uploadKbps)) {
    throw new Error("Download and upload rates must be whole numbers from 64 to 1,000,000 kbit/s.");
  }
  if (!["none", "ethernet", "atm", "ptm"].includes(linklayer)) throw new Error("Choose a supported link-layer type.");
  if (!Number.isInteger(overheadBytes) || overheadBytes < -64 || overheadBytes > 256) throw new Error("Packet overhead must be a whole number from -64 to 256 bytes.");
  if (!Number.isInteger(tcMpuBytes) || tcMpuBytes < 0 || tcMpuBytes > 256) throw new Error("Minimum packet unit must be a whole number from 0 to 256 bytes.");

  const form = new URLSearchParams();
  form.set("section", section);
  form.set("enabled", enabled ? "1" : "0");
  form.set("download", String(downloadKbps));
  form.set("upload", String(uploadKbps));
  form.set("linklayer", linklayer);
  form.set("overhead", String(overheadBytes));
  form.set("tc_mpu", String(tcMpuBytes));

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
    !("linklayer" in payload) || payload.linklayer !== linklayer ||
    !("overhead_bytes" in payload) || payload.overhead_bytes !== overheadBytes ||
    !("tc_mpu_bytes" in payload) || payload.tc_mpu_bytes !== tcMpuBytes ||
    !("restarted" in payload) || payload.restarted !== true ||
    !("rolled_back" in payload) || payload.rolled_back !== false
  ) {
    throw new Error("The router did not confirm the SQM queue update and service restart.");
  }
  return payload as RouterSqmQueueUpdateResult;
}


export async function updateRouterMwan3Interface(
  section: string,
  enabled: boolean,
  trackIps: string[],
  reliability: number,
  count: number,
  timeout: number,
  interval: number,
  down: number,
  up: number,
  initialState: "online" | "offline",
  confirmed: boolean,
): Promise<RouterMwan3InterfaceUpdateResult> {
  if (!/^[A-Za-z0-9_-]{1,32}$/.test(section)) {
    throw new Error("Invalid mwan3 interface section name.");
  }
  if (!confirmed) throw new Error("Confirm the Multi-WAN health-check change before continuing.");
  if (!Array.isArray(trackIps) || trackIps.length < 1 || trackIps.length > 8 ||
      trackIps.some((value) => typeof value !== "string" || value.length > 39 ||
        !/^[0-9A-Fa-f:.]+$/.test(value)) ||
      new Set(trackIps).size !== trackIps.length) {
    throw new Error("Enter 1 to 8 unique IPv4 or IPv6 tracking addresses.");
  }
  const wholeNumber = (value: number, minimum: number, maximum: number) =>
    Number.isInteger(value) && value >= minimum && value <= maximum;
  if (!wholeNumber(reliability, 1, trackIps.length)) {
    throw new Error("Reliability must be 1 to the number of tracking targets.");
  }
  if (!wholeNumber(count, 1, 10)) throw new Error("Probe count must be 1 to 10.");
  if (!wholeNumber(timeout, 1, 10)) throw new Error("Probe timeout must be 1 to 10 seconds.");
  if (!wholeNumber(interval, 1, 60)) throw new Error("Probe interval must be 1 to 60 seconds.");
  if (!wholeNumber(down, 1, 20)) throw new Error("Failure threshold must be 1 to 20.");
  if (!wholeNumber(up, 1, 20)) throw new Error("Recovery threshold must be 1 to 20.");
  if (initialState !== "online" && initialState !== "offline") {
    throw new Error("Choose an initial online or offline state.");
  }

  const form = new URLSearchParams();
  form.set("section", section);
  form.set("enabled", enabled ? "1" : "0");
  form.set("track_ips", JSON.stringify(trackIps));
  form.set("reliability", String(reliability));
  form.set("count", String(count));
  form.set("timeout", String(timeout));
  form.set("interval", String(interval));
  form.set("down", String(down));
  form.set("up", String(up));
  form.set("initial_state", initialState);
  form.set("confirmed", "1");

  const response = await fetch(MWAN3_INTERFACE_UPDATE_URL, {
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
      ? "Multi-WAN changes require an active router administrator session."
      : "The router returned an invalid Multi-WAN update response.");
  }

  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) {
    throw new Error("The router returned an invalid Multi-WAN update response.");
  }
  if ("error" in payload && typeof payload.error === "string") {
    throw new Error(payload.error);
  }
  if (!response.ok || !("ok" in payload) || payload.ok !== true ||
      !("section" in payload) || payload.section !== section ||
      !("enabled" in payload) || payload.enabled !== enabled ||
      !("track_ips" in payload) || !Array.isArray(payload.track_ips) ||
      payload.track_ips.length !== trackIps.length ||
      !payload.track_ips.every((value, index) => value === trackIps[index]) ||
      !("reliability" in payload) || payload.reliability !== reliability ||
      !("count" in payload) || payload.count !== count ||
      !("timeout" in payload) || payload.timeout !== timeout ||
      !("interval" in payload) || payload.interval !== interval ||
      !("down" in payload) || payload.down !== down ||
      !("up" in payload) || payload.up !== up ||
      !("initial_state" in payload) || payload.initial_state !== initialState ||
      !("restarted" in payload) || payload.restarted !== true ||
      !("rolled_back" in payload) || payload.rolled_back !== false) {
    throw new Error("The router did not confirm the Multi-WAN health-check update and service restart.");
  }
  return payload as RouterMwan3InterfaceUpdateResult;
}


export async function updateRouterCakeProfile(
  section: string,
  profile: RouterSqmCakeProfileChoice,
): Promise<RouterSqmCakeProfileUpdateResult> {
  if (!/^[A-Za-z0-9_-]{1,32}$/.test(section)) throw new Error("Invalid SQM queue section name.");
  if (!["default", "besteffort", "diffserv4", "diffserv8"].includes(profile)) throw new Error("Choose a supported CAKE profile.");
  const form = new URLSearchParams();
  form.set("section", section);
  form.set("profile", profile);
  const response = await fetch(SQM_CAKE_PROFILE_URL, {
    method: "POST", credentials: "same-origin", cache: "no-store",
    headers: { Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" },
    body: form.toString(),
  });
  const contentType = response.headers.get("content-type") ?? "";
  if (!contentType.includes("application/json")) {
    throw new Error(response.status === 403 ? "CAKE profile changes require an active router administrator session." : "The router returned an invalid CAKE profile response.");
  }
  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) throw new Error("The router returned an invalid CAKE profile response.");
  if ("error" in payload && typeof payload.error === "string") throw new Error(payload.error);
  if (!response.ok || !("ok" in payload) || payload.ok !== true ||
      !("section" in payload) || payload.section !== section ||
      !("profile" in payload) || payload.profile !== profile ||
      !("restarted" in payload) || payload.restarted !== true ||
      !("rolled_back" in payload) || payload.rolled_back !== false) {
    throw new Error("The router did not confirm the CAKE profile update and service restart.");
  }
  return payload as RouterSqmCakeProfileUpdateResult;
}


export async function addRouterSqmClientPolicy(input: {
  mac: string;
  sourceZone: string;
  destinationZone: string;
  dscpClass: RouterSqmClientDscpClass;
}): Promise<RouterSqmClientPolicyResult> {
  if (!/^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$/.test(input.mac)) {
    throw new Error("Choose one unicast client MAC address in six-octet notation.");
  }
  const firstOctet = Number.parseInt(input.mac.slice(0, 2), 16);
  if ((firstOctet & 1) !== 0 || input.mac.toLowerCase() === "00:00:00:00:00:00" ||
      input.mac.toLowerCase() === "ff:ff:ff:ff:ff:ff") {
    throw new Error("Choose one unicast client MAC address in six-octet notation.");
  }
  const validZone = (value: string) =>
    /^[A-Za-z0-9_.-]{1,64}$/.test(value) && value !== "." && value !== "..";
  if (!validZone(input.sourceZone) || !validZone(input.destinationZone) || input.sourceZone === input.destinationZone) {
    throw new Error("Choose different existing internal and external firewall zones.");
  }
  if (!["BE", "AF41", "EF", "CS1"].includes(input.dscpClass)) {
    throw new Error("Choose a supported DSCP class: BE, AF41, EF or CS1.");
  }
  const form = new URLSearchParams();
  form.set("mac", input.mac.toLowerCase());
  form.set("source_zone", input.sourceZone);
  form.set("destination_zone", input.destinationZone);
  form.set("dscp_class", input.dscpClass);
  form.set("confirmed", "1");
  const response = await fetch(SQM_CLIENT_QOS_ADD_URL, {
    method: "POST", credentials: "same-origin", cache: "no-store",
    headers: { Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" },
    body: form.toString(),
  });
  const contentType = response.headers.get("content-type") ?? "";
  if (!contentType.includes("application/json")) {
    throw new Error(response.status === 403
      ? "Client QoS changes require an active router administrator session."
      : "The router returned an invalid client QoS response.");
  }
  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) throw new Error("The router returned an invalid client QoS response.");
  if ("error" in payload && typeof payload.error === "string") throw new Error(payload.error);
  if (!response.ok || !("ok" in payload) || payload.ok !== true ||
      !("section" in payload) || typeof payload.section !== "string" || payload.section.length === 0 ||
      !("mac" in payload) || payload.mac !== input.mac.toLowerCase() ||
      !("source_zone" in payload) || payload.source_zone !== input.sourceZone ||
      !("destination_zone" in payload) || payload.destination_zone !== input.destinationZone ||
      !("dscp_class" in payload) || payload.dscp_class !== input.dscpClass ||
      !("reloaded" in payload) || payload.reloaded !== true ||
      !("rolled_back" in payload) || payload.rolled_back !== false) {
    throw new Error("The router did not confirm the client DSCP rule and firewall reload.");
  }
  return payload as RouterSqmClientPolicyResult;
}

export async function removeRouterSqmClientPolicy(section: string): Promise<RouterSqmClientPolicyRemoveResult> {
  if (!/^[A-Za-z0-9_.-]{1,64}$/.test(section) || section === "." || section === "..") {
    throw new Error("Invalid client QoS firewall rule section identifier.");
  }
  const form = new URLSearchParams();
  form.set("section", section);
  form.set("confirmed", "1");
  const response = await fetch(SQM_CLIENT_QOS_REMOVE_URL, {
    method: "POST", credentials: "same-origin", cache: "no-store",
    headers: { Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" },
    body: form.toString(),
  });
  const contentType = response.headers.get("content-type") ?? "";
  if (!contentType.includes("application/json")) {
    throw new Error(response.status === 403
      ? "Client QoS removal requires an active router administrator session."
      : "The router returned an invalid client QoS removal response.");
  }
  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) throw new Error("The router returned an invalid client QoS removal response.");
  if ("error" in payload && typeof payload.error === "string") throw new Error(payload.error);
  if (!response.ok || !("ok" in payload) || payload.ok !== true ||
      !("section" in payload) || payload.section !== section ||
      !("mac" in payload) || typeof payload.mac !== "string" ||
      !("source_zone" in payload) || typeof payload.source_zone !== "string" ||
      !("destination_zone" in payload) || typeof payload.destination_zone !== "string" ||
      !("dscp_class" in payload) || !["BE", "AF41", "EF", "CS1"].includes(String(payload.dscp_class)) ||
      !("removed" in payload) || payload.removed !== true ||
      !("reloaded" in payload) || payload.reloaded !== true ||
      !("rolled_back" in payload) || payload.rolled_back !== false) {
    throw new Error("The router did not confirm the client DSCP rule removal and firewall reload.");
  }
  return payload as RouterSqmClientPolicyRemoveResult;
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
  dhcpv6: "UNCHANGED" | "disabled" | "server";
  ra: "UNCHANGED" | "disabled" | "server";
  ndp: "UNCHANGED" | "disabled";
  ra_flags: "UNCHANGED" | "none" | "other-config" | "managed-config" | "managed-config+other-config";
  ra_slaac: "UNCHANGED" | "0" | "1";
  ra_dns: "UNCHANGED" | "0" | "1";
  ra_preference: "UNCHANGED" | "low" | "medium" | "high";
  ra_lifetime: string;
  dhcpv6_na: "UNCHANGED" | "0" | "1";
  dhcpv6_pd: "UNCHANGED" | "0" | "1";
  dhcpv6_assignall: "UNCHANGED" | "0" | "1";
  dhcpv6_pd_min_len: string;
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
  const validDhcpv6 = new Set(["UNCHANGED", "disabled", "server"]);
  const validRa = new Set(["UNCHANGED", "disabled", "server"]);
  const validNdp = new Set(["UNCHANGED", "disabled"]);
  if (!validDhcpv6.has(input.dhcpv6) || !validRa.has(input.ra) || !validNdp.has(input.ndp)) {
    throw new Error("DHCPv6 and RA must be unchanged, disabled or server; NDP must be unchanged or disabled. Relay/hybrid requires native odhcpd master configuration.");
  }
  const validFlags = new Set([
    "UNCHANGED",
    "none",
    "other-config",
    "managed-config",
    "managed-config+other-config",
  ]);
  const validToggle = (value: string) => value === "UNCHANGED" || value === "0" || value === "1";
  if (!validFlags.has(input.ra_flags) ||
      !validToggle(input.ra_slaac) || !validToggle(input.ra_dns) ||
      !validToggle(input.dhcpv6_na) || !validToggle(input.dhcpv6_pd) ||
      !validToggle(input.dhcpv6_assignall)) {
    throw new Error("Invalid RA flags or DHCPv6/SLAAC boolean option.");
  }
  if (!["UNCHANGED", "low", "medium", "high"].includes(input.ra_preference)) {
    throw new Error("RA route preference must be unchanged, low, medium or high.");
  }
  if (input.ra_lifetime !== "UNCHANGED" &&
      (!/^[0-9]{1,4}$/.test(input.ra_lifetime) ||
       Number(input.ra_lifetime) < 0 || Number(input.ra_lifetime) > 2700)) {
    throw new Error("RA lifetime must be unchanged or a whole number from 0 to 2700 seconds.");
  }
  if (input.dhcpv6_pd_min_len !== "UNCHANGED" &&
      (!/^[1-9][0-9]?$/.test(input.dhcpv6_pd_min_len) ||
       Number(input.dhcpv6_pd_min_len) < 1 || Number(input.dhcpv6_pd_min_len) > 64)) {
    throw new Error("Minimum delegated IPv6 prefix length must be unchanged or a whole number from 1 to 64.");
  }

  const form = new URLSearchParams();
  form.set("section", input.section);
  form.set("start", input.start);
  form.set("limit", input.limit);
  form.set("leasetime", input.lease_time);
  form.set("dhcpv6", input.dhcpv6);
  form.set("ra", input.ra);
  form.set("ndp", input.ndp);
  form.set("ra_flags", input.ra_flags);
  form.set("ra_slaac", input.ra_slaac);
  form.set("ra_dns", input.ra_dns);
  form.set("ra_preference", input.ra_preference);
  form.set("ra_lifetime", input.ra_lifetime);
  form.set("dhcpv6_na", input.dhcpv6_na);
  form.set("dhcpv6_pd", input.dhcpv6_pd);
  form.set("dhcpv6_assignall", input.dhcpv6_assignall);
  form.set("dhcpv6_pd_min_len", input.dhcpv6_pd_min_len);
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
  const expectedFlags: Record<string, string[]> = {
    none: ["none"],
    "other-config": ["other-config"],
    "managed-config": ["managed-config"],
    "managed-config+other-config": ["managed-config", "other-config"],
  };
  const ipv6RestartRequested = input.dhcpv6 !== "UNCHANGED" || input.ra !== "UNCHANGED" ||
    input.ndp !== "UNCHANGED" || input.ra_flags !== "UNCHANGED" ||
    input.ra_slaac !== "UNCHANGED" || input.ra_dns !== "UNCHANGED" ||
    input.ra_preference !== "UNCHANGED" || input.ra_lifetime !== "UNCHANGED" ||
    input.dhcpv6_na !== "UNCHANGED" || input.dhcpv6_pd !== "UNCHANGED" ||
    input.dhcpv6_assignall !== "UNCHANGED" || input.dhcpv6_pd_min_len !== "UNCHANGED";
  if (
    !response.ok || !("ok" in payload) || payload.ok !== true ||
    !("section" in payload) || payload.section !== input.section ||
    !("start" in payload) || payload.start !== String(Number(input.start)) ||
    !("limit" in payload) || payload.limit !== String(Number(input.limit)) ||
    !("lease_time" in payload) || payload.lease_time !== input.lease_time ||
    !("pool_start_ip" in payload) || typeof payload.pool_start_ip !== "string" ||
    !("pool_end_ip" in payload) || typeof payload.pool_end_ip !== "string" ||
    !("dhcpv6" in payload) || typeof payload.dhcpv6 !== "string" ||
      (input.dhcpv6 !== "UNCHANGED" && payload.dhcpv6 !== input.dhcpv6) ||
    !("ra" in payload) || typeof payload.ra !== "string" ||
      (input.ra !== "UNCHANGED" && payload.ra !== input.ra) ||
    !("ndp" in payload) || typeof payload.ndp !== "string" ||
      (input.ndp !== "UNCHANGED" && payload.ndp !== input.ndp) ||
    !("ra_flags" in payload) || !Array.isArray(payload.ra_flags) ||
      (input.ra_flags !== "UNCHANGED" &&
        JSON.stringify(payload.ra_flags) !== JSON.stringify(expectedFlags[input.ra_flags])) ||
    !("ra_slaac" in payload) || typeof payload.ra_slaac !== "boolean" ||
      (input.ra_slaac !== "UNCHANGED" && payload.ra_slaac !== (input.ra_slaac === "1")) ||
    !("ra_dns" in payload) || typeof payload.ra_dns !== "boolean" ||
      (input.ra_dns !== "UNCHANGED" && payload.ra_dns !== (input.ra_dns === "1")) ||
    !("ra_preference" in payload) || typeof payload.ra_preference !== "string" ||
      (input.ra_preference !== "UNCHANGED" && payload.ra_preference !== input.ra_preference) ||
    !("ra_lifetime" in payload) || typeof payload.ra_lifetime !== "number" ||
      (input.ra_lifetime !== "UNCHANGED" && payload.ra_lifetime !== Number(input.ra_lifetime)) ||
    !("dhcpv6_na" in payload) || typeof payload.dhcpv6_na !== "boolean" ||
      (input.dhcpv6_na !== "UNCHANGED" && payload.dhcpv6_na !== (input.dhcpv6_na === "1")) ||
    !("dhcpv6_pd" in payload) || typeof payload.dhcpv6_pd !== "boolean" ||
      (input.dhcpv6_pd !== "UNCHANGED" && payload.dhcpv6_pd !== (input.dhcpv6_pd === "1")) ||
    !("dhcpv6_assignall" in payload) || typeof payload.dhcpv6_assignall !== "boolean" ||
      (input.dhcpv6_assignall !== "UNCHANGED" && payload.dhcpv6_assignall !== (input.dhcpv6_assignall === "1")) ||
    !("dhcpv6_pd_min_len" in payload) || typeof payload.dhcpv6_pd_min_len !== "number" ||
      (input.dhcpv6_pd_min_len !== "UNCHANGED" && payload.dhcpv6_pd_min_len !== Number(input.dhcpv6_pd_min_len)) ||
    !("restarted" in payload) || payload.restarted !== true ||
    !("dnsmasq_restarted" in payload) || payload.dnsmasq_restarted !== true ||
    !("odhcpd_restarted" in payload) || typeof payload.odhcpd_restarted !== "boolean" ||
      payload.odhcpd_restarted !== ipv6RestartRequested ||
    !("rolled_back" in payload) || payload.rolled_back !== false
  ) {
    throw new Error("The router did not confirm the DHCP, RA, DHCPv6 and delegated-prefix settings with required service restarts.");
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
export async function updateRouterOfficeVlan(input: {
  section?: string;
  device: string;
  vlanId: string;
  ports: RouterOfficeVlanPort[];
}): Promise<RouterOfficeVlanUpdateResult> {
  if (!/^[A-Za-z0-9_.-]{1,64}$/.test(input.device) || input.device === "." || input.device === "..") {
    throw new Error("Select an existing bridge device.");
  }
  if (!/^[1-9][0-9]{0,3}$/.test(input.vlanId) ||
      Number(input.vlanId) < 1 || Number(input.vlanId) > 4094) {
    throw new Error("VLAN ID must be a whole number from 1 to 4094.");
  }
  if (input.section && (!/^[A-Za-z0-9_.-]{1,64}$/.test(input.section) ||
      input.section === "." || input.section === "..")) {
    throw new Error("Invalid bridge VLAN section identifier.");
  }
  if (!Array.isArray(input.ports) || input.ports.length < 1 || input.ports.length > 32) {
    throw new Error("Choose between 1 and 32 explicit bridge port memberships.");
  }
  const seen = new Set<string>();
  const portValues = input.ports.map((port) => {
    if (!/^[A-Za-z0-9_.-]{1,64}$/.test(port.name) || seen.has(port.name)) {
      throw new Error("Bridge port names must be valid and unique.");
    }
    seen.add(port.name);
    if (port.mode !== "tagged" && port.mode !== "untagged") {
      throw new Error("Every selected bridge port must be tagged or untagged.");
    }
    if (port.pvid && port.mode !== "untagged") {
      throw new Error("A PVID can only be assigned to an untagged bridge port.");
    }
    return port.name + (port.mode === "tagged" ? ":t" : port.pvid ? ":u*" : ":u");
  });
  const form = new URLSearchParams();
  form.set("section", input.section || "");
  form.set("device", input.device);
  form.set("vlan", String(Number(input.vlanId)));
  form.set("ports", portValues.join(" "));
  form.set("confirmed", "1");
  const response = await fetch(BRIDGE_VLAN_UPDATE_URL, {
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
      ? "Bridge VLAN changes require an active router administrator session."
      : "The router returned an invalid bridge VLAN update response.");
  }
  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) {
    throw new Error("The router returned an invalid bridge VLAN update response.");
  }
  if ("error" in payload && typeof payload.error === "string") throw new Error(payload.error);
  if (
    !response.ok || !("ok" in payload) || payload.ok !== true ||
    !("section" in payload) || typeof payload.section !== "string" || payload.section.length === 0 ||
    !("device" in payload) || payload.device !== input.device ||
    !("vlan_id" in payload) || payload.vlan_id !== Number(input.vlanId) ||
    !("ports" in payload) || !Array.isArray(payload.ports) ||
    payload.ports.length !== portValues.length ||
    payload.ports.some((port, index) => port !== portValues[index]) ||
    !("reloaded" in payload) || payload.reloaded !== true ||
    !("rolled_back" in payload) || payload.rolled_back !== false
  ) {
    throw new Error("The router did not confirm the bridge VLAN configuration and network reload.");
  }
  return payload as RouterOfficeVlanUpdateResult;
}

export async function createRouterOfficeSegment(input: {
  name: string;
  bridge: string;
  vlanId: string;
  address: string;
  netmask: string;
  zone: string;
  dhcpStart: string;
  dhcpLimit: string;
  leaseTime: string;
  ipv6Enabled?: boolean;
}): Promise<RouterOfficeSegmentCreateResult> {
  if (input.ipv6Enabled !== undefined && typeof input.ipv6Enabled !== "boolean") {
    throw new Error("IPv6 enablement must be a boolean choice.");
  }
  const ipv6Enabled = input.ipv6Enabled === true;
  const validName = /^[A-Za-z][A-Za-z0-9_-]{0,31}$/.test(input.name) &&
    !["lan", "wan", "wan6", "loopback", "wwan", "cellular"].includes(input.name);
  if (!validName) {
    throw new Error("Network name must be 1–32 safe characters and cannot use a reserved interface name.");
  }
  if (!/^[A-Za-z0-9_.-]{1,64}$/.test(input.bridge) ||
      input.bridge === "." || input.bridge === "..") {
    throw new Error("Select a valid existing VLAN-filtered bridge.");
  }
  if (!/^[1-9][0-9]{0,3}$/.test(input.vlanId) ||
      Number(input.vlanId) < 1 || Number(input.vlanId) > 4094) {
    throw new Error("Select a VLAN ID from 1 to 4094.");
  }
  const octets = input.address.split(".");
  if (octets.length !== 4 || octets.some((part) =>
    !/^(0|[1-9][0-9]{0,2})$/.test(part) || Number(part) > 255)) {
    throw new Error("Enter a canonical dotted-decimal IPv4 gateway address.");
  }
  const [first, second] = octets.map(Number);
  const privateAddress = first === 10 ||
    (first === 172 && second >= 16 && second <= 31) ||
    (first === 192 && second === 168);
  if (!privateAddress) {
    throw new Error("Use an RFC1918 private IPv4 gateway address for an office segment.");
  }
  const maskOctets = input.netmask.split(".");
  if (maskOctets.length !== 4 || maskOctets.some((part) =>
    !/^(0|[1-9][0-9]{0,2})$/.test(part) || Number(part) > 255)) {
    throw new Error("Enter a dotted-decimal contiguous IPv4 subnet mask.");
  }
  const maskBits = maskOctets.map(Number).map((value) => value.toString(2).padStart(8, "0")).join("");
  if (!/^1{1,30}0*$/.test(maskBits) || maskBits.length !== 32) {
    throw new Error("Subnet mask must be contiguous and between /1 and /30.");
  }
  if (!/^[A-Za-z0-9_.-]{1,64}$/.test(input.zone) || input.zone === "." || input.zone === "..") {
    throw new Error("Choose an existing internal firewall zone.");
  }
  if (!/^[1-9][0-9]{0,9}$/.test(input.dhcpStart) ||
      !/^[1-9][0-9]{0,9}$/.test(input.dhcpLimit)) {
    throw new Error("DHCP start and pool size must be positive whole numbers.");
  }
  if (!/^[1-9][0-9]{0,8}[smhdw]?$/.test(input.leaseTime)) {
    throw new Error("DHCP lease time must be a positive duration such as 12h.");
  }

  const form = new URLSearchParams();
  form.set("name", input.name);
  form.set("bridge", input.bridge);
  form.set("vlan", String(Number(input.vlanId)));
  form.set("address", input.address);
  form.set("netmask", input.netmask);
  form.set("zone", input.zone);
  form.set("start", input.dhcpStart);
  form.set("limit", input.dhcpLimit);
  form.set("leasetime", input.leaseTime);
  form.set("ipv6_enabled", ipv6Enabled ? "1" : "0");
  form.set("confirmed", "1");
  const response = await fetch(OFFICE_SEGMENT_ADD_URL, {
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
      ? "Office network provisioning requires an active router administrator session."
      : "The router returned an invalid office network provisioning response.");
  }
  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) {
    throw new Error("The router returned an invalid office network provisioning response.");
  }
  if ("error" in payload && typeof payload.error === "string") throw new Error(payload.error);
  if (
    !response.ok || !("ok" in payload) || payload.ok !== true ||
    !("name" in payload) || payload.name !== input.name ||
    !("device" in payload) || payload.device !== input.bridge + "." + String(Number(input.vlanId)) ||
    !("address" in payload) || payload.address !== input.address ||
    !("netmask" in payload) || payload.netmask !== input.netmask ||
    !("zone" in payload) || typeof payload.zone !== "string" || payload.zone.length === 0 ||
    !("pool_start_ip" in payload) || typeof payload.pool_start_ip !== "string" ||
    !("pool_end_ip" in payload) || typeof payload.pool_end_ip !== "string" ||
    !("firewall_rules" in payload) || payload.firewall_rules !== (ipv6Enabled ? 7 : 3) ||
    !("ipv6_enabled" in payload) || payload.ipv6_enabled !== ipv6Enabled ||
    !("ipv6_assign" in payload) || payload.ipv6_assign !== (ipv6Enabled ? "64" : "") ||
    !("dhcpv6" in payload) || payload.dhcpv6 !== (ipv6Enabled ? "server" : "disabled") ||
    !("ra" in payload) || payload.ra !== (ipv6Enabled ? "server" : "disabled") ||
    !("ra_flags" in payload) || !Array.isArray(payload.ra_flags) ||
      payload.ra_flags.length !== (ipv6Enabled ? 2 : 0) ||
      (ipv6Enabled && (
        payload.ra_flags[0] !== "managed-config" ||
        payload.ra_flags[1] !== "other-config"
      )) ||
    !("ra_slaac" in payload) || payload.ra_slaac !== (ipv6Enabled ? "1" : "0") ||
    !("ra_dns" in payload) || payload.ra_dns !== (ipv6Enabled ? "1" : "0") ||
    !("ra_preference" in payload) || payload.ra_preference !== (ipv6Enabled ? "medium" : "medium") ||
    !("ra_lifetime" in payload) || payload.ra_lifetime !== (ipv6Enabled ? 2700 : 0) ||
    !("dhcpv6_na" in payload) || payload.dhcpv6_na !== (ipv6Enabled ? "1" : "0") ||
    !("dhcpv6_pd" in payload) || payload.dhcpv6_pd !== "0" ||
    !("dhcpv6_assignall" in payload) || payload.dhcpv6_assignall !== "0" ||
    !("ndp" in payload) || payload.ndp !== "disabled" ||
    !("network_reloaded" in payload) || payload.network_reloaded !== true ||
    !("firewall_reloaded" in payload) || payload.firewall_reloaded !== true ||
    !("dhcp_restarted" in payload) || payload.dhcp_restarted !== true ||
    !("odhcpd_restarted" in payload) || payload.odhcpd_restarted !== ipv6Enabled ||
    !("rolled_back" in payload) || payload.rolled_back !== false
  ) {
    throw new Error("The router did not confirm the complete office network, firewall and DHCP transaction.");
  }
  return payload as RouterOfficeSegmentCreateResult;
}


export async function createRouterOfficePortForward(input: {
  name: string;
  source: string;
  destination: string;
  protocol: RouterOfficePortForwardProtocol;
  sourcePort: string;
  destinationIp: string;
  destinationPort: string;
}): Promise<RouterOfficePortForwardCreateResult> {
  if (!/^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$/.test(input.name)) {
    throw new Error("Enter a valid rule name using 1–64 letters, digits, dots, underscores or hyphens.");
  }
  const validZone = (value: string) =>
    /^[A-Za-z0-9_.-]{1,64}$/.test(value) && value !== "." && value !== "..";
  if (!validZone(input.source) || !validZone(input.destination)) {
    throw new Error("Select a valid existing firewall zone for the port-forward.");
  }
  if (input.source === input.destination) {
    throw new Error("Source and destination firewall zones must be different.");
  }
  if (input.protocol !== "tcp" && input.protocol !== "udp" && input.protocol !== "tcp udp") {
    throw new Error("Protocol must be TCP, UDP or TCP + UDP.");
  }
  const validPort = (value: string) =>
    /^[0-9]{1,5}$/.test(value) && Number(value) >= 1 && Number(value) <= 65535;
  if (!validPort(input.sourcePort) || !validPort(input.destinationPort)) {
    throw new Error("Ports must be whole numbers from 1 to 65535.");
  }
  const octets = input.destinationIp.split(".");
  if (
    octets.length !== 4 ||
    octets.some((part) => !/^(0|[1-9][0-9]{0,2})$/.test(part) || Number(part) > 255)
  ) {
    throw new Error("Destination must be a valid dotted-decimal IPv4 address.");
  }

  const form = new URLSearchParams();
  form.set("name", input.name);
  form.set("source", input.source);
  form.set("destination", input.destination);
  form.set("protocol", input.protocol);
  form.set("source_port", String(Number(input.sourcePort)));
  form.set("destination_ip", input.destinationIp);
  form.set("destination_port", String(Number(input.destinationPort)));
  form.set("confirmed", "1");

  const response = await fetch(OFFICE_PORT_FORWARD_ADD_URL, {
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
      ? "WAN port-forward changes require an active router administrator session."
      : "The router returned an invalid WAN port-forward response.");
  }
  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) {
    throw new Error("The router returned an invalid WAN port-forward response.");
  }
  if ("error" in payload && typeof payload.error === "string") throw new Error(payload.error);
  if (
    !response.ok || !("ok" in payload) || payload.ok !== true ||
    !("section" in payload) || typeof payload.section !== "string" || payload.section.length === 0 ||
    !("name" in payload) || payload.name !== input.name ||
    !("source" in payload) || payload.source !== input.source ||
    !("destination" in payload) || payload.destination !== input.destination ||
    !("protocol" in payload) || payload.protocol !== input.protocol ||
    !("source_port" in payload) || payload.source_port !== Number(input.sourcePort) ||
    !("destination_ip" in payload) || payload.destination_ip !== input.destinationIp ||
    !("destination_port" in payload) || payload.destination_port !== Number(input.destinationPort) ||
    !("reloaded" in payload) || payload.reloaded !== true ||
    !("rolled_back" in payload) || payload.rolled_back !== false
  ) {
    throw new Error("The router did not confirm the WAN port-forward configuration and firewall reload.");
  }
  return payload as RouterOfficePortForwardCreateResult;
}

export async function removeRouterOfficePortForward(section: string): Promise<RouterOfficePortForwardRemoveResult> {
  if (!/^[A-Za-z0-9_.-]{1,64}$/.test(section) || section === "." || section === "..") {
    throw new Error("Invalid firewall redirect section identifier.");
  }
  const form = new URLSearchParams();
  form.set("section", section);
  form.set("confirmed", "1");
  const response = await fetch(OFFICE_PORT_FORWARD_REMOVE_URL, {
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
      ? "WAN port-forward removal requires an active router administrator session."
      : "The router returned an invalid WAN port-forward removal response.");
  }
  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) {
    throw new Error("The router returned an invalid WAN port-forward removal response.");
  }
  if ("error" in payload && typeof payload.error === "string") throw new Error(payload.error);
  if (
    !response.ok || !("ok" in payload) || payload.ok !== true ||
    !("section" in payload) || payload.section !== section ||
    !("removed" in payload) || payload.removed !== true ||
    !("reloaded" in payload) || payload.reloaded !== true ||
    !("rolled_back" in payload) || payload.rolled_back !== false
  ) {
    throw new Error("The router did not confirm port-forward removal and firewall reload.");
  }
  return payload as RouterOfficePortForwardRemoveResult;
}

export async function createRouterOfficeForwarding(input: {
  source: string;
  destination: string;
}): Promise<RouterOfficeForwardingCreateResult> {
  const validName = (value: string) => /^[A-Za-z0-9_.-]{1,64}$/.test(value) &&
    value !== "." && value !== "..";
  if (!validName(input.source) || !validName(input.destination)) {
    throw new Error("Select valid existing firewall zones.");
  }
  if (input.source === input.destination) {
    throw new Error("Source and destination firewall zones must be different.");
  }
  const form = new URLSearchParams();
  form.set("source", input.source);
  form.set("destination", input.destination);
  form.set("confirmed", "1");
  const response = await fetch(OFFICE_FORWARDING_ADD_URL, {
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
      ? "Firewall forwarding changes require an active router administrator session."
      : "The router returned an invalid firewall forwarding response.");
  }
  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) {
    throw new Error("The router returned an invalid firewall forwarding response.");
  }
  if ("error" in payload && typeof payload.error === "string") throw new Error(payload.error);
  if (
    !response.ok || !("ok" in payload) || payload.ok !== true ||
    !("section" in payload) || typeof payload.section !== "string" || payload.section.length === 0 ||
    !("source" in payload) || payload.source !== input.source ||
    !("destination" in payload) || payload.destination !== input.destination ||
    !("reloaded" in payload) || payload.reloaded !== true ||
    !("rolled_back" in payload) || payload.rolled_back !== false
  ) {
    throw new Error("The router did not confirm the firewall forwarding and reload.");
  }
  return payload as RouterOfficeForwardingCreateResult;
}


export interface RouterOfficeWifiNetworkUpdateResult {
  ok: true;
  section: string;
  ssid: string;
  network: string;
  networks: string[];
  reloaded: boolean;
  rolled_back: false;
}

export async function updateRouterOfficeWifiNetwork(input: {
  section: string;
  network: string;
}): Promise<RouterOfficeWifiNetworkUpdateResult> {
  if (!/^[A-Za-z0-9_.-]{1,64}$/.test(input.section) || input.section === "." || input.section === "..") {
    throw new Error("Invalid wireless AP section identifier.");
  }
  if (!/^[A-Za-z0-9_.-]{1,64}$/.test(input.network) || input.network === "." || input.network === "..") {
    throw new Error("Select an existing office LAN/VLAN network interface.");
  }
  const form = new URLSearchParams();
  form.set("section", input.section);
  form.set("network", input.network);
  form.set("confirmed", "1");
  const response = await fetch(OFFICE_WIFI_NETWORK_UPDATE_URL, {
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
      ? "SSID network changes require an active router administrator session."
      : "The router returned an invalid SSID network update response.");
  }
  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) {
    throw new Error("The router returned an invalid SSID network update response.");
  }
  if ("error" in payload && typeof payload.error === "string") throw new Error(payload.error);
  if (
    !response.ok || !("ok" in payload) || payload.ok !== true ||
    !("section" in payload) || payload.section !== input.section ||
    !("ssid" in payload) || typeof payload.ssid !== "string" ||
    !("network" in payload) || payload.network !== input.network ||
    !("networks" in payload) || !Array.isArray(payload.networks) ||
    payload.networks.length !== 1 || payload.networks[0] !== input.network ||
    !("reloaded" in payload) || typeof payload.reloaded !== "boolean" ||
    !("rolled_back" in payload) || payload.rolled_back !== false
  ) {
    throw new Error("The router did not confirm the SSID network binding and Wi-Fi reload.");
  }
  return payload as RouterOfficeWifiNetworkUpdateResult;
}

export async function updateRouterOfficeZonePolicy(input: {
  section: string;
  output: "UNCHANGED" | "INHERIT" | "ACCEPT" | "REJECT" | "DROP";
  forward: "UNCHANGED" | "INHERIT" | "ACCEPT" | "REJECT" | "DROP";
  masquerade: boolean;
}): Promise<RouterOfficeFirewallZoneUpdateResult> {
  if (!/^[A-Za-z0-9_.-]{1,64}$/.test(input.section) ||
      input.section === "." || input.section === "..") {
    throw new Error("Invalid firewall zone section identifier.");
  }
  const allowed = new Set(["UNCHANGED", "INHERIT", "ACCEPT", "REJECT", "DROP"]);
  if (!allowed.has(input.output) || !allowed.has(input.forward)) {
    throw new Error("Zone output and forward policies must be unchanged, inherited, ACCEPT, REJECT or DROP.");
  }
  if (typeof input.masquerade !== "boolean") {
    throw new Error("Masquerading must be explicitly enabled or disabled.");
  }
  const form = new URLSearchParams();
  form.set("section", input.section);
  form.set("output", input.output);
  form.set("forward", input.forward);
  form.set("masquerade", input.masquerade ? "1" : "0");
  form.set("confirmed", "1");
  const response = await fetch(OFFICE_ZONE_UPDATE_URL, {
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
      ? "Firewall zone policy changes require an active router administrator session."
      : "The router returned an invalid firewall zone policy response.");
  }
  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) {
    throw new Error("The router returned an invalid firewall zone policy response.");
  }
  if ("error" in payload && typeof payload.error === "string") throw new Error(payload.error);
  if (
    !response.ok || !("ok" in payload) || payload.ok !== true ||
    !("section" in payload) || payload.section !== input.section ||
    !("name" in payload) || typeof payload.name !== "string" ||
    !("input" in payload) || typeof payload.input !== "string" ||
    !("output" in payload) || typeof payload.output !== "string" ||
      (input.output !== "UNCHANGED" && payload.output !== (input.output === "INHERIT" ? "" : input.output)) ||
      !["", "ACCEPT", "REJECT", "DROP"].includes(payload.output) ||
    !("forward" in payload) || typeof payload.forward !== "string" ||
      (input.forward !== "UNCHANGED" && payload.forward !== (input.forward === "INHERIT" ? "" : input.forward)) ||
      !["", "ACCEPT", "REJECT", "DROP"].includes(payload.forward) ||
    !("masquerade" in payload) || payload.masquerade !== input.masquerade ||
    !("input_unchanged" in payload) || payload.input_unchanged !== true ||
    !("reloaded" in payload) || payload.reloaded !== true ||
    !("rolled_back" in payload) || payload.rolled_back !== false
  ) {
    throw new Error("The router did not confirm zone policy changes, input preservation and firewall reload.");
  }
  return payload as RouterOfficeFirewallZoneUpdateResult;
}

export async function removeRouterOfficeForwarding(section: string): Promise<RouterOfficeForwardingRemoveResult> {
  if (!/^[A-Za-z0-9_.-]{1,64}$/.test(section) || section === "." || section === "..") {
    throw new Error("Invalid firewall forwarding section identifier.");
  }
  const form = new URLSearchParams();
  form.set("section", section);
  form.set("confirmed", "1");
  const response = await fetch(OFFICE_FORWARDING_REMOVE_URL, {
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
      ? "Firewall forwarding removal requires an active router administrator session."
      : "The router returned an invalid firewall forwarding removal response.");
  }
  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) {
    throw new Error("The router returned an invalid firewall forwarding removal response.");
  }
  if ("error" in payload && typeof payload.error === "string") throw new Error(payload.error);
  if (
    !response.ok || !("ok" in payload) || payload.ok !== true ||
    !("section" in payload) || payload.section !== section ||
    !("source" in payload) || typeof payload.source !== "string" ||
    !("destination" in payload) || typeof payload.destination !== "string" ||
    !("removed" in payload) || payload.removed !== true ||
    !("reloaded" in payload) || payload.reloaded !== true ||
    !("rolled_back" in payload) || payload.rolled_back !== false
  ) {
    throw new Error("The router did not confirm firewall forwarding removal and reload.");
  }
  return payload as RouterOfficeForwardingRemoveResult;
}

export async function removeRouterOfficeVlan(section: string): Promise<RouterOfficeVlanRemoveResult> {
  if (!/^[A-Za-z0-9_.-]{1,64}$/.test(section) || section === "." || section === "..") {
    throw new Error("Invalid bridge VLAN section identifier.");
  }
  const form = new URLSearchParams();
  form.set("section", section);
  form.set("confirmed", "1");
  const response = await fetch(BRIDGE_VLAN_REMOVE_URL, {
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
      ? "Bridge VLAN removal requires an active router administrator session."
      : "The router returned an invalid bridge VLAN removal response.");
  }
  const payload: unknown = await response.json();
  if (typeof payload !== "object" || payload === null) {
    throw new Error("The router returned an invalid bridge VLAN removal response.");
  }
  if ("error" in payload && typeof payload.error === "string") throw new Error(payload.error);
  if (
    !response.ok || !("ok" in payload) || payload.ok !== true ||
    !("section" in payload) || payload.section !== section ||
    !("device" in payload) || typeof payload.device !== "string" ||
    !("vlan_id" in payload) || typeof payload.vlan_id !== "number" ||
    !("removed" in payload) || payload.removed !== true ||
    !("reloaded" in payload) || payload.reloaded !== true ||
    !("rolled_back" in payload) || payload.rolled_back !== false
  ) {
    throw new Error("The router did not confirm bridge VLAN removal and network reload.");
  }
  return payload as RouterOfficeVlanRemoveResult;
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
