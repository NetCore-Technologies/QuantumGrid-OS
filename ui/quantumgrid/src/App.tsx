import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import { createRouterDhcpReservation, downloadRouterConfigBackup, removeRouterDhcpReservation, createRouterOfficeSegment, createRouterOfficeForwarding, removeRouterOfficeForwarding, updateRouterOfficeZonePolicy, updateRouterOfficeVlan, updateRouterOfficeWifiNetwork, removeRouterOfficeVlan, updateRouterDhcpReservation, updateRouterDhcpScopeEnabled, createRouterDhcpScope, updateRouterDhcpScope, removeRouterDhcpScope, fetchRouterAuditLog, fetchRouterOverview, fetchRouterPackages, loginToRouter, runRouterPackageOperation, runRouterLatencyTest, scanRouterWifi, updateRouterLedBrightness, updateRouterRemoteSyslog, updateRouterSqmQueue, updateRouterWirelessConfig, type RouterAuditLog, type RouterClient, type RouterLatencyTest, type RouterOfficeDhcpScope, type RouterOfficeBridge, type RouterOfficeVlan, type RouterOfficeFirewallZone, type RouterOfficeForwarding, type RouterBoardGpioLineReference, type RouterOfficeInterface, type RouterOfficeStaticLease, type RouterOfficeNetworks, type RouterOverview, type RouterPackageInventory, type RouterRemoteSyslogStatus, type RouterWifiScan, type RouterWifiRateDetails, type RouterWirelessClient, type RouterWirelessConfig, type RouterWirelessRadio, type RouterSqmQueue } from "./routerApi";
import { planWifiChannels } from "./wifiChannelPlanner";
import { auditFirewallPosture } from "./firewallPosture";
import { analyzePolicyRouting } from "./policyRouting";
import { appendConntrackSample, summarizeConntrackHistory, type ConntrackHistorySample } from "./conntrackHistory";
import { calculateCounterRateMbps } from "./interfaceRates";
import { sampleWireGuardPeerRates, wireGuardPeerCounterKey, type WireGuardPeerCounterSnapshot, type WireGuardPeerMeasuredRate } from "./wireGuardPeerRates";
import {
  collectWifiClientHistory,
  mergeWifiClientHistory,
  pruneWifiClientHistory,
  readWifiClientHistory,
  WIFI_CLIENT_HISTORY_KEY,
  WIFI_CLIENT_HISTORY_SETTINGS_KEY,
  type WifiClientHistoryRetentionDays,
  type WifiClientHistorySample,
} from "./wifiClientHistory";
import {
  Activity,
  ArrowLeft,
  ArrowRight,
  Check,
  ChevronRight,
  CircleGauge,
  Cpu,
  Database,
  Download,
  Gamepad2,
  Globe2,
  HardDrive,
  KeyRound,
  Lock,
  Menu,
  Monitor,
  Network,
  RefreshCw,
  Router,
  RadioTower,
  Settings,
  Shield,
  SlidersHorizontal,
  Signal,
  Sparkles,
  Thermometer,
  Upload,
  User,
  Users,
  Wifi,
  X,
  Zap,
  PhoneCall,
} from "lucide-react";

type Page =
  | "dashboard"
  | "gaming"
  | "devices"
  | "wifi"
  | "5g"
  | "phone"
  | "network"
  | "security"
  | "diagnostics"
  | "analytics"
  | "system"
  | "advanced"
  | "hardware"
  | "office"
  | "audit"
  | "apps";

type SetupStep = "welcome" | "account" | "wifi" | "wan";

type Stats = {
  latency: number | null;
  probeDelta: number | null;
  download: number;
  upload: number;
  wanAvailable: boolean;
  reachable: boolean;
  cpu: number | null;
  ram: number | null;
  temp: number | null;
};

type CellularHistorySample = {
  sampledAt: number;
  rssi_dbm: number | null;
  rsrp_dbm: number | null;
  rsrq_db: number | null;
  snr_db: number | null;
};

const nav = [
  ["dashboard", "Dashboard", CircleGauge],
  ["gaming", "Gaming", Gamepad2],
  ["devices", "Devices", Users],
  ["wifi", "Wi-Fi", Wifi],
  ["5g", "5G", Signal],
  ["phone", "Phone", PhoneCall],
  ["network", "Network", Network],
  ["security", "Security", Shield],
  ["diagnostics", "Diagnostics", Activity],
  ["office", "Office Networks", Network],
  ["audit", "Admin Audit", Shield],
  ["analytics", "Analytics", Database],
  ["system", "System", Cpu],
  ["advanced", "Advanced", Settings],
  ["hardware", "Hardware I/O", Cpu],
  ["apps", "OpenWrt Apps", Monitor],
] as const;

function fmt(value: number, digits = 0) {
  return value.toLocaleString("en-US", {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  });
}

function formatDurationSeconds(value: number | undefined): string {
  if (value === undefined || !Number.isFinite(value) || value < 0) return "N/A";
  let remaining = Math.floor(value);
  const days = Math.floor(remaining / 86400);
  remaining %= 86400;
  const hours = Math.floor(remaining / 3600);
  remaining %= 3600;
  const minutes = Math.floor(remaining / 60);
  const seconds = remaining % 60;
  const parts: string[] = [];
  if (days > 0) parts.push(days + "d");
  if (hours > 0 || days > 0) parts.push(hours + "h");
  if (minutes > 0 || hours > 0 || days > 0) parts.push(minutes + "m");
  parts.push(seconds + "s");
  return parts.join(" ");
}

function Status({ children, active = true }: { children: React.ReactNode; active?: boolean }) {
  return (
    <span className="status">
      <span className={active ? "status-dot live" : "status-dot"} />
      {children}
    </span>
  );
}

function SetupFrame({
  children,
  progress,
  step,
}: {
  children: React.ReactNode;
  progress: number;
  step: number;
}) {
  return (
    <div className="setup-screen">
      <div className="atmosphere atmosphere-red" />
      <div className="atmosphere atmosphere-blue" />
      <div className="atmosphere atmosphere-purple" />
      <div className="grid-overlay" />

      <header className="setup-header">
        <div className="brand-inline">
          <div className="brand-q">Q</div>
          <div>
            <strong>QUANTUMGRID</strong>
            <span>NETWORK OS</span>
          </div>
        </div>

        <div className="setup-steps">
          <span className={step >= 1 ? "done" : ""}>01</span>
          <i />
          <span className={step >= 2 ? "done" : ""}>02</span>
          <i />
          <span className={step >= 3 ? "done active" : ""}>03</span>
        </div>
      </header>

      <main className="setup-main">
        <div className="setup-progress">
          <span style={{ width: `${progress}%` }} />
        </div>
        {children}
      </main>
    </div>
  );
}

function Welcome({
  next,
}: {
  next: () => void;
}) {
  return (
    <div className="welcome-screen">
      <div className="welcome-q">Q</div>

      <div className="welcome-wordmark">QUANTUMGRID</div>
      <div className="welcome-subtitle">NETWORK OPERATING SYSTEM</div>
<h1>
        Welcome to <span>QuantumGrid.</span>
      </h1>

      <p>
        A new network operating system built around intelligence,
        performance, gaming, security and control.
      </p>

      <div className="welcome-features">
        <Feature icon={Zap} text="Maximum performance" />
        <Feature icon={Gamepad2} text="Gaming intelligence" />
        <Feature icon={Shield} text="Protection built in" />
        <Feature icon={Signal} text="5G ready" />
      </div>

      <button className="hero-button" onClick={next}>
        Get Started
        <ArrowRight size={18} />
      </button>

      <div className="welcome-meta">
        AW1000 • IPQ807x • QUANTUMGRID OS
      </div>
    </div>
  );
}

function Feature({
  icon: Icon,
  text,
}: {
  icon: React.ElementType;
  text: string;
}) {
  return (
    <div className="welcome-feature">
      <Icon size={17} />
      <span>{text}</span>
    </div>
  );
}

function AccountSetup({
  username,
  setUsername,
  password,
  setPassword,
  confirm,
  setConfirm,
  next,
  back,
}: {
  username: string;
  setUsername: (v: string) => void;
  password: string;
  setPassword: (v: string) => void;
  confirm: string;
  setConfirm: (v: string) => void;
  next: () => void;
  back: () => void;
}) {
  const [error, setError] = useState("");

  const validUser = username.trim() === "root";
  const validPassword = password.length >= 8;
  const validMatch = password.length > 0 && password === confirm;

  function submit() {
    if (!validUser) {
      setError("Use the existing OpenWrt root administrator account.");
      return;
    }

    if (!validPassword) {
      setError("Your password must contain at least 8 characters.");
      return;
    }

    if (!validMatch) {
      setError("Your passwords do not match.");
      return;
    }

    setError("");
    next();
  }

  return (
    <SetupFrame progress={42} step={1}>
      <div className="account-layout">
        <section className="account-main">
          <div className="setup-kicker">STEP 1 OF 3 • ADMINISTRATOR</div>

          <h1>
            Connect your
            <span> router administrator.</span>
          </h1>

          <p>
            Use the existing OpenWrt root account. On a brand-new router, QuantumGrid will set its password once.
          </p>

          <div className="account-form">
            <Field
              label="ROUTER ADMINISTRATOR"
              icon={User}
              value={username}
              placeholder="root"
              onChange={setUsername}
              valid={validUser}
              readOnly
            />

            <Field
              label="ROOT PASSWORD"
              icon={Lock}
              value={password}
              placeholder="New on first boot · current otherwise"
              onChange={setPassword}
              type="password"
              valid={validPassword}
            />

            <Field
              label="CONFIRM ROOT PASSWORD"
              icon={Lock}
              value={confirm}
              placeholder="Confirm the new or current password"
              onChange={setConfirm}
              type="password"
              valid={validMatch}
            />
          </div>

          <div className="rules">
            <Rule text="Existing OpenWrt root account" valid={validUser} />
            <Rule text="8+ character password" valid={validPassword} />
            <Rule text="Passwords match" valid={validMatch} />
          </div>
        </section>

        <aside className="account-aside">
          <div className="aside-q">Q</div>
          <strong>Secure your network.</strong>
          <p>
            Your administrator account controls wireless, WAN, gaming,
            security and advanced QuantumGrid services.
          </p>

          <div className="aside-line">
            <Shield size={15} />
            Protected management access
          </div>

          <div className="aside-line">
            <Lock size={15} />
            Secure administrator authentication
          </div>
        </aside>
      </div>

      <div className="wizard-nav">
        <button className="ghost-button" onClick={back}>
          <ArrowLeft size={17} />
          Back
        </button>

        <button className="hero-button" onClick={submit}>
          Continue
          <ArrowRight size={17} />
        </button>
      </div>

      {error && (
        <div className="error-layer">
          <div className="error-modal">
            <button className="close-error" onClick={() => setError("")}>
              <X size={17} />
            </button>

            <div className="error-icon">
              <Shield size={20} />
            </div>

            <div className="setup-kicker">SETUP CHECK</div>

            <h2>Almost there.</h2>
            <p>{error}</p>

            <button className="error-button" onClick={() => setError("")}>
              Go back
            </button>
          </div>
        </div>
      )}
    </SetupFrame>
  );
}

function Field({
  label,
  icon: Icon,
  value,
  placeholder,
  onChange,
  valid,
  type = "text",
  readOnly = false,
}: {
  label: string;
  icon: React.ElementType;
  value: string;
  placeholder: string;
  onChange: (v: string) => void;
  valid: boolean;
  type?: string;
  readOnly?: boolean;
}) {
  return (
    <label className="setup-field">
      <span>{label}</span>

      <div className={valid ? "input-shell valid" : "input-shell"}>
        <div className="input-icon">
          <Icon size={17} />
        </div>

        <input
          type={type}
          value={value}
          placeholder={placeholder}
          onChange={(e) => onChange(e.target.value)}
          readOnly={readOnly}
        />

        {valid && <Check size={17} className="input-success" />}
      </div>
    </label>
  );
}

function Rule({
  text,
  valid,
}: {
  text: string;
  valid: boolean;
}) {
  return (
    <div className={valid ? "rule valid" : "rule"}>
      <Check size={13} />
      {text}
    </div>
  );
}


function WifiSetup({
  ssid,
  setSsid,
  password,
  setPassword,
  next,
  back,
}: {
  ssid: string;
  setSsid: (v: string) => void;
  password: string;
  setPassword: (v: string) => void;
  next: () => void;
  back: () => void;
}) {
  const [mode, setMode] = useState<"steering" | "standalone">("steering");

  const [ssid24, setSsid24] = useState("QuantumGrid-2.4G");
  const [ssid5, setSsid5] = useState("QuantumGrid-5G");

  const [pass24, setPass24] = useState("");
  const [pass5, setPass5] = useState("");

  const [security24, setSecurity24] = useState<"wpa2" | "wpa3">("wpa2");
  const [security5, setSecurity5] = useState<"wpa2" | "wpa3">("wpa2");

  const steeringValid =
    ssid.trim().length >= 2 &&
    password.length >= 8;

  const standaloneValid =
    ssid24.trim().length >= 2 &&
    ssid5.trim().length >= 2 &&
    pass24.length >= 8 &&
    pass5.length >= 8;

  const valid = mode === "steering" ? steeringValid : standaloneValid;

  return (
    <SetupFrame progress={70} step={2}>
      <div className="wifi-setup">
        <div className="wifi-heading">
          <div className="setup-kicker">
            STEP 2 OF 3 • WIRELESS CONFIGURATION
          </div>

          <div className="wifi-icon">
            <Wifi size={27} />
          </div>

          <h1>
            Configure your
            <span> wireless network.</span>
          </h1>

          <p>
            Choose one intelligent network across both radios, or configure
            each band independently.
          </p>
        </div>

        <div className="wifi-mode-switch">
          <button
            className={mode === "steering" ? "selected" : ""}
            onClick={() => setMode("steering")}
          >
            <Sparkles size={17} />
            <div>
              <strong>Band Steering</strong>
              <span>
                One SSID across 2.4 GHz and 5 GHz with automatic client steering.
              </span>
            </div>
            {mode === "steering" && <Check size={17} />}
          </button>

          <button
            className={mode === "standalone" ? "selected" : ""}
            onClick={() => setMode("standalone")}
          >
            <SlidersHorizontal size={17} />
            <div>
              <strong>Standalone Bands</strong>
              <span>
                Separate SSIDs, passwords and security settings for each radio.
              </span>
            </div>
            {mode === "standalone" && <Check size={17} />}
          </button>
        </div>

        {mode === "steering" ? (
          <div className="wifi-grid">
            <section className="wifi-card">
              <div className="card-heading">
                <span>SMART NETWORK</span>
                <Status>2 RADIOS</Status>
              </div>

              <label className="setup-field">
                <span>SHARED NETWORK NAME</span>

                <div className={ssid.trim().length >= 2 ? "input-shell valid" : "input-shell"}>
                  <Wifi size={17} />

                  <input
                    value={ssid}
                    onChange={(e) => setSsid(e.target.value)}
                    placeholder="QuantumGrid"
                  />

                  {ssid.trim().length >= 2 && (
                    <Check size={17} className="input-success" />
                  )}
                </div>
              </label>

              <label className="setup-field">
                <span>SHARED NETWORK PASSWORD</span>

                <div className={password.length >= 8 ? "input-shell valid" : "input-shell"}>
                  <Lock size={17} />

                  <input
                    type="password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder="Create a secure Wi-Fi password"
                  />

                  {password.length >= 8 && (
                    <Check size={17} className="input-success" />
                  )}
                </div>
              </label>

              <div className="security-select-row">
                <div>
                  <span>SECURITY</span>
                  <strong>WPA2 / WPA3</strong>
                </div>

                <div className="security-chip active">
                  <Shield size={13} />
                  Protected
                </div>
              </div>

              <div className="steering-features">
                <Rule text="2.4 GHz + 5 GHz" valid={true} />
                <Rule text="Automatic client steering" valid={true} />
                <Rule text="Priority and signal aware" valid={true} />
              </div>
            </section>

            <section className="wifi-card wifi-preview-card">
              <div className="wifi-halo" />

              <div className="router-visual">
                <Wifi size={31} />
              </div>

              <div className="preview-label">
                QUANTUMGRID SMART WI-FI
              </div>

              <strong>{ssid.trim() || "QuantumGrid"}</strong>

              <span className="secured">
                <Lock size={12} />
                WPA2 / WPA3 protected
              </span>

              <div className="radio-preview">
                <div>
                  <span>2.4 GHz</span>
                  <b>SMART</b>
                </div>

                <div>
                  <span>5 GHz</span>
                  <b>PRIORITY</b>
                </div>
              </div>

              <div className="preview-message">
                <Sparkles size={14} />
                QuantumGrid will automatically move clients between bands
                according to signal quality, device priority and performance.
              </div>
            </section>
          </div>
        ) : (
          <div className="wifi-grid standalone-grid">
            <section className="wifi-card">
              <div className="card-heading">
                <span>2.4 GHz RADIO</span>
                <Status>ACTIVE</Status>
              </div>

              <label className="setup-field">
                <span>SSID</span>

                <div className={ssid24.trim().length >= 2 ? "input-shell valid" : "input-shell"}>
                  <Wifi size={17} />
                  <input
                    value={ssid24}
                    onChange={(e) => setSsid24(e.target.value)}
                    placeholder="QuantumGrid-2.4G"
                  />
                  {ssid24.trim().length >= 2 && (
                    <Check size={17} className="input-success" />
                  )}
                </div>
              </label>

              <label className="setup-field">
                <span>PASSWORD</span>

                <div className={pass24.length >= 8 ? "input-shell valid" : "input-shell"}>
                  <Lock size={17} />
                  <input
                    type="password"
                    value={pass24}
                    onChange={(e) => setPass24(e.target.value)}
                    placeholder="8+ characters"
                  />
                  {pass24.length >= 8 && (
                    <Check size={17} className="input-success" />
                  )}
                </div>
              </label>

              <label className="security-select">
                <span>SECURITY</span>
                <select
                  value={security24}
                  onChange={(e) =>
                    setSecurity24(e.target.value as "wpa2" | "wpa3")
                  }
                >
                  <option value="wpa2">WPA2-PSK</option>
                  <option value="wpa3">WPA3-SAE</option>
                </select>
              </label>
            </section>

            <section className="wifi-card">
              <div className="card-heading">
                <span>5 GHz RADIO</span>
                <Status>ACTIVE</Status>
              </div>

              <label className="setup-field">
                <span>SSID</span>

                <div className={ssid5.trim().length >= 2 ? "input-shell valid" : "input-shell"}>
                  <Wifi size={17} />
                  <input
                    value={ssid5}
                    onChange={(e) => setSsid5(e.target.value)}
                    placeholder="QuantumGrid-5G"
                  />
                  {ssid5.trim().length >= 2 && (
                    <Check size={17} className="input-success" />
                  )}
                </div>
              </label>

              <label className="setup-field">
                <span>PASSWORD</span>

                <div className={pass5.length >= 8 ? "input-shell valid" : "input-shell"}>
                  <Lock size={17} />
                  <input
                    type="password"
                    value={pass5}
                    onChange={(e) => setPass5(e.target.value)}
                    placeholder="8+ characters"
                  />
                  {pass5.length >= 8 && (
                    <Check size={17} className="input-success" />
                  )}
                </div>
              </label>

              <label className="security-select">
                <span>SECURITY</span>
                <select
                  value={security5}
                  onChange={(e) =>
                    setSecurity5(e.target.value as "wpa2" | "wpa3")
                  }
                >
                  <option value="wpa2">WPA2-PSK</option>
                  <option value="wpa3">WPA3-SAE</option>
                </select>
              </label>
            </section>
          </div>
        )}

        <div className="wifi-footer-note">
          <Shield size={15} />
          <span>
            WPA2/WPA3 security will be enforced on the configured radios.
          </span>
        </div>
      </div>

      <div className="wizard-nav">
        <button className="ghost-button" onClick={back}>
          <ArrowLeft size={17} />
          Back
        </button>

        <button
          className="hero-button"
          disabled={!valid}
          onClick={next}
        >
          Continue
          <ArrowRight size={17} />
        </button>
      </div>
    </SetupFrame>
  );
}


function WanSetup({
  type,
  setType,
  next,
  back,
}: {
  type: "dhcp" | "pppoe" | "static";
  setType: (v: "dhcp" | "pppoe" | "static") => void;
  next: () => void;
  back: () => void;
}) {
  const [pppoeUser, setPppoeUser] = useState("");
  const [pppoePassword, setPppoePassword] = useState("");

  const [staticIp, setStaticIp] = useState("");
  const [staticMask, setStaticMask] = useState("");
  const [staticGateway, setStaticGateway] = useState("");
  const [staticDns, setStaticDns] = useState("");

  const pppoeValid =
    pppoeUser.trim().length >= 1 &&
    pppoePassword.length >= 1;

  const staticValid =
    staticIp.trim().length > 0 &&
    staticMask.trim().length > 0 &&
    staticGateway.trim().length > 0 &&
    staticDns.trim().length > 0;

  const valid =
    type === "dhcp"
      ? true
      : type === "pppoe"
        ? pppoeValid
        : staticValid;

  return (
    <SetupFrame progress={91} step={3}>
      <div className="wan-setup">
        <div className="wan-heading">
          <div className="setup-kicker">
            STEP 3 OF 3 • INTERNET CONFIGURATION
          </div>

          <div className="wan-icon">
            <Globe2 size={27} />
          </div>

          <h1>
            Connect QuantumGrid
            <span> to the Internet.</span>
          </h1>

          <p>
            Select your WAN connection type. QuantumGrid will only ask for
            the information required by that connection.
          </p>
        </div>

        <div className="wan-options">
          {[
            ["dhcp", "Automatic DHCP", "IP address supplied automatically", Globe2],
            ["pppoe", "PPPoE", "ISP username and password", Network],
            ["static", "Static IP", "Manually assigned network settings", Settings],
          ].map(([id, title, description, Icon]) => (
            <button
              key={id as string}
              className={
                type === id
                  ? "wan-option selected"
                  : "wan-option"
              }
              onClick={() =>
                setType(id as "dhcp" | "pppoe" | "static")
              }
            >
              <div className="wan-option-icon">
                <Icon size={19} />
              </div>

              <div className="wan-option-text">
                <strong>{title as string}</strong>
                <span>{description as string}</span>
              </div>

              <div className="wan-radio">
                {type === id && <span />}
              </div>

              <ChevronRight size={17} />
            </button>
          ))}
        </div>

        {type === "dhcp" && (
          <section className="wan-detail-card dhcp-detail">
            <div className="wan-detail-icon">
              <Check size={21} />
            </div>

            <div>
              <strong>Automatic DHCP selected.</strong>
              <span>
                No additional information is required. Your ISP will provide
                the WAN address automatically.
              </span>
            </div>

            <Status>READY</Status>
          </section>
        )}

        {type === "pppoe" && (
          <section className="wan-detail-card">
            <div className="wan-detail-title">
              <div className="wan-detail-icon">
                <KeyRound size={19} />
              </div>

              <div>
                <strong>ISP authentication</strong>
                <span>Enter the credentials supplied by your ISP.</span>
              </div>
            </div>

            <div className="wan-fields">
              <label className="setup-field">
                <span>ISP USERNAME</span>

                <div className="input-shell">
                  <User size={17} />

                  <input
                    value={pppoeUser}
                    onChange={(e) => setPppoeUser(e.target.value)}
                    placeholder="ISP username"
                  />
                </div>
              </label>

              <label className="setup-field">
                <span>ISP PASSWORD</span>

                <div className="input-shell">
                  <Lock size={17} />

                  <input
                    type="password"
                    value={pppoePassword}
                    onChange={(e) => setPppoePassword(e.target.value)}
                    placeholder="ISP password"
                  />
                </div>
              </label>
            </div>
          </section>
        )}

        {type === "static" && (
          <section className="wan-detail-card">
            <div className="wan-detail-title">
              <div className="wan-detail-icon">
                <Settings size={19} />
              </div>

              <div>
                <strong>Static WAN configuration</strong>
                <span>Enter the network settings provided by your ISP.</span>
              </div>
            </div>

            <div className="wan-static-grid">
              <label className="setup-field">
                <span>IP ADDRESS</span>
                <div className="input-shell">
                  <Network size={17} />
                  <input
                    value={staticIp}
                    onChange={(e) => setStaticIp(e.target.value)}
                    placeholder="203.0.113.10"
                  />
                </div>
              </label>

              <label className="setup-field">
                <span>SUBNET MASK</span>
                <div className="input-shell">
                  <Network size={17} />
                  <input
                    value={staticMask}
                    onChange={(e) => setStaticMask(e.target.value)}
                    placeholder="255.255.255.0"
                  />
                </div>
              </label>

              <label className="setup-field">
                <span>GATEWAY</span>
                <div className="input-shell">
                  <Globe2 size={17} />
                  <input
                    value={staticGateway}
                    onChange={(e) => setStaticGateway(e.target.value)}
                    placeholder="203.0.113.1"
                  />
                </div>
              </label>

              <label className="setup-field">
                <span>DNS SERVER</span>
                <div className="input-shell">
                  <Activity size={17} />
                  <input
                    value={staticDns}
                    onChange={(e) => setStaticDns(e.target.value)}
                    placeholder="1.1.1.1"
                  />
                </div>
              </label>
            </div>
          </section>
        )}

        <div className="wan-ready">
          <Sparkles size={16} />
          <span>
            QuantumGrid will automatically test the WAN after first login.
          </span>
        </div>
      </div>

      <div className="wizard-nav">
        <button className="ghost-button" onClick={back}>
          <ArrowLeft size={17} />
          Back
        </button>

        <button
          className="hero-button"
          disabled={!valid}
          onClick={next}
        >
          Jump In
          <ArrowRight size={17} />
        </button>
      </div>
    </SetupFrame>
  );
}


function Login({
  username,
  password,
  setPassword,
  login,
  error,
  clearError,
}: {
  username: string;
  password: string;
  setPassword: (v: string) => void;
  login: () => void;
  error: string;
  clearError: () => void;
}) {
  const showError = Boolean(error);

  return (
    <div className="login-landscape">
      <div className="login-landscape-red" />
      <div className="login-landscape-blue" />
      <div className="login-landscape-purple" />
      <div className="login-landscape-grid" />

      <div className="login-landscape-layout">
        <section className="login-brand-side">
          <div className="login-brand-q-wrap">
            <div className="login-brand-q">Q</div>
          </div>

          <div className="login-brand-name">QUANTUMGRID</div>
          <div className="login-brand-sub">NETWORK OPERATING SYSTEM</div>

          <div className="login-brand-line" />

          <div className="login-brand-kicker">SECURE NETWORK ACCESS</div>

          <h1>
            Welcome
            <span> back.</span>
          </h1>

          <p>
            Your network command center is ready.
            Access real-time performance, gaming,
            wireless, security and advanced controls.
          </p>

          <div className="login-brand-status">
            <span />
            <strong>QUANTUMGRID SYSTEMS ONLINE</strong>
          </div>
        </section>

        <section className="login-access-side">
          <div className="login-access-heading">
            <div>
              <span>ADMINISTRATOR ACCESS</span>
              <strong>Sign in to continue</strong>
            </div>

            <div className="login-lock-badge">
              <Lock size={17} />
            </div>
          </div>

          <div className="login-landscape-fields">
            <label className="login-landscape-field">
              <span>USERNAME</span>

              <div>
                <div className="login-field-icon">
                  <User size={17} />
                </div>

                <input value={username} readOnly />

                <Check size={17} className="input-success" />
              </div>
            </label>

            <label className="login-landscape-field">
              <span>PASSWORD</span>

              <div>
                <div className="login-field-icon">
                  <Lock size={17} />
                </div>

                <input
                  type="password"
                  value={password}
                  placeholder="Enter your password"
                  onChange={(e) => {
                    setPassword(e.target.value);
                    clearError();
                  }}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") login();
                  }}
                  autoFocus
                />
              </div>
            </label>
          </div>

          {error && showError && (
            <div className="login-landscape-error">
              <div className="login-error-symbol">
                !
              </div>

              <div>
                <strong>Access denied</strong>
                <span>{error}</span>
              </div>

              <button onClick={() => clearError()}>
                <X size={15} />
              </button>
            </div>
          )}

          <button className="login-landscape-button" onClick={login}>
            <span>Enter QuantumGrid</span>
            <ArrowRight size={18} />
          </button>

          <div className="login-landscape-footer">
            <div>
              <Shield size={13} />
              Protected management session
            </div>

            <div>
              <span className="footer-status-dot" />
              Router ready
            </div>
          </div>
        </section>
      </div>
    </div>
  );
}


function Dashboard({
  stats,
  refresh,
  secondsUntilRefresh,
  collapsed,
  setCollapsed,
  page,
  setPage,
  logout,
  telemetryError,
  routerOverview,
  trafficHistory,
  cellularHistory,
  interfaceCounterDeltas,
  wireGuardPeerRates,
}: {
  stats: Stats;
  refresh: () => void;
  secondsUntilRefresh: number;
  collapsed: boolean;
  setCollapsed: (v: boolean) => void;
  page: Page;
  setPage: (v: Page) => void;
  logout: () => void;
  telemetryError: string;
  routerOverview: RouterOverview | null;
  trafficHistory: number[];
  cellularHistory: CellularHistorySample[];
  interfaceCounterDeltas: Map<string, InterfaceCounterDelta>;
  wireGuardPeerRates: Map<string, WireGuardPeerMeasuredRate>;
}) {
  const [mobile, setMobile] = useState(false);

  return (
    <div className={`app-shell ${collapsed ? "app-shell-collapsed" : ""}`}>
      <aside className={mobile ? "sidebar mobile-open" : "sidebar"}>
        <div className="sidebar-brand">
          <button
            className="brand-q-button"
            onClick={() => setCollapsed(!collapsed)}
            title={collapsed ? "Expand sidebar" : "Collapse sidebar"}
            aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}
          >
            <span className="brand-q">Q</span>
          </button>

          {!collapsed && (
            <div className="sidebar-brand-text">
              <strong>QUANTUMGRID</strong>
              <span>NETWORK OS</span>
            </div>
          )}

          {mobile && (
            <button
              className="mobile-close"
              onClick={() => setMobile(false)}
              aria-label="Close navigation"
            >
              <X size={16} />
            </button>
          )}
        </div>

        <nav className="sidebar-nav">
          <NavSection title="Overview" collapsed={collapsed}>
            {nav.slice(0, 3).map(([id, label, Icon]) => (
              <NavButton
                key={id}
                label={label}
                Icon={Icon}
                active={page === id}
                collapsed={collapsed}
                onClick={() => {
                  setPage(id);
                  setMobile(false);
                }}
              />
            ))}
          </NavSection>

          <NavSection title="Network" collapsed={collapsed}>
            {nav.slice(3, 9).map(([id, label, Icon]) => (
              <NavButton
                key={id}
                label={label}
                Icon={Icon}
                active={page === id}
                collapsed={collapsed}
                onClick={() => {
                  setPage(id);
                  setMobile(false);
                }}
              />
            ))}
          </NavSection>

          <NavSection title="Office" collapsed={collapsed}>
            {nav.slice(9, 11).map(([id, label, Icon]) => (
              <NavButton
                key={id}
                label={label}
                Icon={Icon}
                active={page === id}
                collapsed={collapsed}
                onClick={() => {
                  setPage(id);
                  setMobile(false);
                }}
              />
            ))}
          </NavSection>

          <NavSection title="System" collapsed={collapsed}>
            {nav.slice(11).map(([id, label, Icon]) => (
              <NavButton
                key={id}
                label={label}
                Icon={Icon}
                active={page === id}
                collapsed={collapsed}
                onClick={() => {
                  setPage(id);
                  setMobile(false);
                }}
              />
            ))}
          </NavSection>
        </nav>

        {!collapsed && (
          <div className="sidebar-router">
            <Router size={18} />
            <div>
              <strong>AW1000</strong>
              <span>IPQ807x PLATFORM</span>
            </div>
            <span className="online-dot" />
          </div>
        )}
      </aside>

      <main className="app-main">
        <header className="app-header">
          <div className="header-left">
            <button className="mobile-menu" onClick={() => setMobile(true)}>
              <Menu size={19} />
            </button>

            <span>QUANTUMGRID</span>
            <ChevronRight size={14} />
            <strong>{page.toUpperCase()}</strong>
          </div>

          <div className="header-right">
            <Status active={Boolean(routerOverview) && !telemetryError}>
              {telemetryError ? "ROUTER API OFFLINE" : routerOverview ? "LIVE ROUTER DATA" : "CONNECTING TO ROUTER"}
            </Status>

            <div className="refresh-countdown">
              NEXT REFRESH
              <strong>{secondsUntilRefresh}s</strong>
            </div>

            <button
              className="refresh-button"
              onClick={refresh}
              title="Refresh now"
              aria-label="Refresh now"
            >
              <RefreshCw size={16} />
            </button>

            <button
              className="header-security"
              onClick={logout}
              title="Lock / sign out"
              aria-label="Lock / sign out"
            >
              <Lock size={15} />
            </button>
          </div>
        </header>

        <section className="dashboard-content">
          <DashboardPage
            stats={stats}
            refresh={refresh}
            page={page}
            telemetryError={telemetryError}
            routerOverview={routerOverview}
            trafficHistory={trafficHistory}
            cellularHistory={cellularHistory}
            interfaceCounterDeltas={interfaceCounterDeltas}
            wireGuardPeerRates={wireGuardPeerRates}
          />
        </section>
      </main>
    </div>
  );
}

function NavSection({
  title,
  collapsed,
  children,
}: {
  title: string;
  collapsed: boolean;
  children: React.ReactNode;
}) {
  return (
    <div className="nav-section">
      {!collapsed && <div className="nav-title">{title}</div>}
      {children}
    </div>
  );
}

function NavButton({
  label,
  Icon,
  active,
  collapsed,
  onClick,
}: {
  label: string;
  Icon: React.ElementType;
  active: boolean;
  collapsed: boolean;
  onClick: () => void;
}) {
  return (
    <button
      className={active ? "nav-button active" : "nav-button"}
      onClick={onClick}
      title={collapsed ? label : undefined}
    >
      <Icon size={18} />
      {!collapsed && <span>{label}</span>}
    </button>
  );
}


function PhonePage({ routerOverview }: { routerOverview: RouterOverview | null }) {
  const phone = routerOverview?.phone ?? null;
  const phoneStatus = !phone
    ? "WAITING FOR ROUTER"
    : !phone.service_installed
      ? "FXS SERVICE NOT INSTALLED"
      : !phone.patch_installed
        ? "SLIC PATCH REQUIRED"
        : phone.enabled
          ? "PHONE SERVICE ENABLED"
          : "DISABLED BY SAFE DEFAULT";

  return (
    <div className="phone-page">
      <section className="phone-hero">
        <div className="phone-hero-mark"><PhoneCall size={30} /></div>
        <div className="phone-hero-copy">
          <div className="setup-kicker">AW1000 ANALOG VOICE • FXS</div>
          <h1>Bring your <span>RJ11 phone line</span> back to life.</h1>
          <p>Use the AW1000's built-in analogue phone port with a VoLTE-enabled SIM. QuantumGrid integrates the hardware-matched FXS driver, voice daemon and native call-management service.</p>
          <div className="phone-hero-actions">
            <a className="hero-button phone-primary-action" href="/cgi-bin/luci/admin/services/fxs/status">Open Phone (RJ11) controls <ChevronRight size={17} /></a>
            <a className="secondary-button" href="https://github.com/Perz3us/openwrt-aw1000-phone" target="_blank" rel="noreferrer">Driver & service source <Globe2 size={15} /></a>
          </div>
        </div>
        <div className="phone-readiness">
          <Status active={Boolean(phone?.service_installed && phone.patch_installed && phone.enabled)}>{phoneStatus}</Status>
          <strong>AW1000 FXS</strong>
          <span>Single analogue handset port</span>
          <small>{phone ? "Status read from the router's FXS configuration." : "Connect to the router to read FXS status."}</small>
        </div>
      </section>
      <div className="phone-layout">
        <Panel title="Hardware profile" eyebrow="VOICE PLATFORM">
          <div className="phone-detail-grid">
            <div className="phone-detail"><span>PHONE INTERFACE</span><strong>RJ11 / FXS</strong><small>One analogue handset</small></div>
            <div className="phone-detail"><span>FXS SERVICE</span><strong>{phone?.service_installed ? "Installed" : phone ? "Not installed" : "Unknown"}</strong><small>Native fxsd service files</small></div>
            <div className="phone-detail"><span>SLIC PATCH</span><strong>{phone?.patch_installed ? "Present" : phone ? "Required" : "Unknown"}</strong><small>Proprietary patch is not bundled</small></div>
            <div className="phone-detail"><span>LINE SERVICE</span><strong>{phone ? (phone.enabled ? "Enabled" : "Disabled") : "Unknown"}</strong><small>Safe by default</small></div>
          </div>
        </Panel>
        <Panel title="Before enabling the line" eyebrow="SAFE FIRST BOOT">
          <div className="phone-setup-list">
            <div><span>01</span><div><strong>Install a matching firmware build</strong><small>The kernel module must match the exact running kernel.</small></div></div>
            <div><span>02</span><div><strong>Provide the SLIC DSP patch</strong><small>Supply your legally obtained Skyworks patch at /etc/fxs/si3226x_patch.bin.</small></div></div>
            <div><span>03</span><div><strong>Use a VoLTE-enabled SIM</strong><small>Confirm voice service and carrier support before placing calls.</small></div></div>
            <div><span>04</span><div><strong>Enable the service intentionally</strong><small>The service is disabled by default to avoid an unexpected modem restart.</small></div></div>
          </div>
          <a className="phone-doc-link" href="https://github.com/NetCore-Technologies/QuantumGrid-OS/blob/main/Docs/PHONE-PORT.md" target="_blank" rel="noreferrer">Read the QuantumGrid setup guide <ArrowRight size={15} /></a>
        </Panel>
      </div>
      <Panel title="Voice features" eyebrow="SUPPORTED BY THE AW1000 FXS STACK">
        <div className="phone-feature-grid">
          {[
            ["VoLTE handset calls", "Make and receive calls through the modem SIM"],
            ["Caller ID & call waiting", "Caller identity, hold and flash-button call waiting"],
            ["Phonebook & speed dial", "Contacts, redial, callback and configured shortcuts"],
            ["Call policies", "Blocked numbers, outgoing rules and do-not-disturb schedules"],
            ["Call history & recording", "Review call history and optionally record to local or USB storage"],
            ["SIP extensions", "Optional SIP service integration for LAN phones and apps"],
          ].map(([title, detail]) => (
            <div className="phone-feature" key={title}><Check size={16} /><div><strong>{title}</strong><span>{detail}</span></div></div>
          ))}
        </div>
        <p className="phone-footnote">Feature availability depends on the selected modem/SIP backend, carrier, SIM plan and configuration. Emergency calling has not been validated; keep an independent, certified emergency calling option.</p>
      </Panel>
    </div>
  );
}

function formatUptime(seconds: number | undefined): string {
  if (seconds === undefined || !Number.isFinite(seconds) || seconds < 0) return "N/A";
  const whole = Math.floor(seconds);
  const days = Math.floor(whole / 86400);
  const hours = Math.floor((whole % 86400) / 3600);
  const minutes = Math.floor((whole % 3600) / 60);
  return days > 0 ? `${days}d ${hours}h` : hours > 0 ? `${hours}h ${minutes}m` : `${minutes}m`;
}

function formatLeaseRemaining(seconds: number | null): string {
  if (seconds === null) return "No expiry";
  if (!Number.isFinite(seconds) || seconds < 0) return "Expired";
  if (seconds === 0) return "Expiring";
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${minutes}m`;
  if (minutes > 0) return `${minutes}m`;
  return `${Math.floor(seconds)}s`;
}

function ClientLeaseList({ clients, available, maxRows }: { clients: RouterClient[]; available: boolean; maxRows?: number }) {
  const [filter, setFilter] = useState("");
  const [sort, setSort] = useState<"hostname" | "ip" | "remaining">("hostname");
  const visibleClients = clients.filter((client) =>
    [client.hostname, client.ip, client.mac].some((value) => value.toLocaleLowerCase().includes(filter.trim().toLocaleLowerCase()))
  ).slice().sort((left, right) => {
    if (sort === "ip") return left.ip.localeCompare(right.ip, undefined, { numeric: true });
    if (sort === "remaining") {
      const leftRemaining = left.lease_remaining_seconds ?? Number.POSITIVE_INFINITY;
      const rightRemaining = right.lease_remaining_seconds ?? Number.POSITIVE_INFINITY;
      return leftRemaining - rightRemaining;
    }
    return (left.hostname || "").localeCompare(right.hostname || "");
  });
  const exportLeases = () => {
    if (visibleClients.length === 0) return;
    const exportedAt = new Date().toISOString();
    const rows: Array<Array<string | number | null | undefined>> = [
      ["Exported at (UTC)", "Search filter", "Sort order", "Hostname", "IPv4 address", "MAC address", "Lease remaining seconds", "Lease remaining"],
      ...visibleClients.map((client) => [
        exportedAt, filter, sort, client.hostname, client.ip, client.mac,
        client.lease_remaining_seconds, formatLeaseRemaining(client.lease_remaining_seconds),
      ]),
    ];
    const csv = rows.map((row) => row.map(csvCell).join(",")).join("\r\n");
    const objectUrl = URL.createObjectURL(new Blob(["\uFEFF", csv], { type: "text/csv;charset=utf-8" }));
    const link = document.createElement("a");
    link.href = objectUrl;
    link.download = "quantumgrid-dhcp-leases-" + exportedAt.replace(/[:.]/g, "-") + ".csv";
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(objectUrl), 0);
  };
  if (!available) return <div className="module-message">DHCP client inventory is not available from this router API.</div>;
  if (clients.length === 0) return <div className="module-message">No unexpired DHCPv4 leases were reported. Static-IP devices may not appear here.</div>;
  const displayedClients = visibleClients.slice(0, maxRows ?? visibleClients.length);
  return (
    <>
      <div className="dhcp-client-tools">
        <input type="search" aria-label="Search DHCP leases" placeholder="Search hostname, IP or MAC" value={filter} onChange={(event) => setFilter(event.target.value)} />
        <select aria-label="Sort DHCP leases" value={sort} onChange={(event) => setSort(event.target.value as "hostname" | "ip" | "remaining")}>
          <option value="hostname">Hostname A–Z</option>
          <option value="ip">IP address</option>
          <option value="remaining">Lease expiring soon</option>
        </select>
        <span>{visibleClients.length} of {clients.length} leases</span>
        <button className="hero-button wifi-export-button" onClick={exportLeases} disabled={visibleClients.length === 0}>Export lease CSV</button>
      </div>
      {displayedClients.length === 0 ? (
        <div className="module-message">No DHCP leases match the current search.</div>
      ) : (
        <div className="device-list">
          {displayedClients.map((client) => (
            <div className="device-row" key={client.mac}>
              <div className="device-title">
                <div className="device-icon"><Monitor size={17} /></div>
                <div><strong>{client.hostname || "Unknown device"}</strong><span>DHCPv4 lease</span></div>
              </div>
              <div><small>IP ADDRESS</small><b>{client.ip}</b></div>
              <div><small>MAC ADDRESS</small><b>{client.mac.toUpperCase()}</b></div>
              <div><small>LEASE REMAINING</small><b>{formatLeaseRemaining(client.lease_remaining_seconds)}</b></div>
              <div><small>SOURCE</small><b>DHCPv4</b></div>
            </div>
          ))}
        </div>
      )}
    </>
  );
}

function formatWifiRateDetails(details: RouterWifiRateDetails | undefined): string {
  if (!details) return "PHY details N/A";
  const parts = [details.phy];
  if (details.mcs !== undefined) parts.push("MCS " + details.mcs);
  if (details.nss !== undefined && details.nss > 0) parts.push(details.nss + "SS");
  if (details.width_mhz !== undefined && details.width_mhz > 0) parts.push(details.width_mhz + " MHz");
  if (details.short_gi) parts.push("Short GI");
  if (details.he_gi !== undefined) parts.push("HE GI " + details.he_gi);
  if (details.eht_gi !== undefined) parts.push("EHT GI " + details.eht_gi);
  return parts.join(" · ");
}

function WirelessClientList({
  clients,
  available,
  leases,
}: {
  clients: RouterWirelessClient[];
  available: boolean;
  leases: RouterClient[];
}) {
  const [filter, setFilter] = useState("");
  const [authorizationFilter, setAuthorizationFilter] = useState<"all" | "authorized" | "associated">("all");
  const [bandFilter, setBandFilter] = useState("all");
  const [transmissionFilter, setTransmissionFilter] = useState<"all" | "issues" | "failures" | "unavailable">("all");
  const [sort, setSort] = useState<"signal" | "rx" | "tx" | "measured-rx" | "measured-tx" | "retries" | "failures" | "mac">("signal");
  const hostnames = new Map(leases.map((lease) => [lease.mac.toLowerCase(), lease.hostname]));
  const stationsWithRetries = clients.filter((client) => typeof client.tx_retries === "number" && Number.isFinite(client.tx_retries) && client.tx_retries > 0).length;
  const stationsWithFailures = clients.filter((client) => typeof client.tx_failed === "number" && Number.isFinite(client.tx_failed) && client.tx_failed > 0).length;
  const stationsWithCompleteTxCounters = clients.filter((client) => typeof client.tx_retries === "number" && typeof client.tx_failed === "number").length;
  const availableBands = [...new Set(clients.map((client) => client.band || "Unknown"))].sort();
  const authorizedCount = clients.filter((client) => client.authorized).length;
  const associatedOnlyCount = clients.length - authorizedCount;
  const measuredStations = clients.filter((client) =>
    typeof client.measured_rx_mbps === "number" &&
    typeof client.measured_tx_mbps === "number" &&
    Number.isFinite(client.measured_rx_mbps) &&
    Number.isFinite(client.measured_tx_mbps)
  );
  const totalMeasuredRx = measuredStations.reduce((total, client) => total + (client.measured_rx_mbps ?? 0), 0);
  const totalMeasuredTx = measuredStations.reduce((total, client) => total + (client.measured_tx_mbps ?? 0), 0);
  const measuredCoverage = measuredStations.length > 0
    ? `${measuredStations.length}/${clients.length} stations sampled`
    : "Awaiting two valid counter samples";
  const visibleClients = clients
    .filter((client) => {
      const query = filter.trim().toLocaleLowerCase();
      const matchesText = !query || [
        client.mac, client.ssid, client.ifname, client.radio, client.band,
        hostnames.get(client.mac.toLowerCase()) ?? "",
      ].some((value) => value.toLocaleLowerCase().includes(query));
      const matchesAuthorization = authorizationFilter === "all" ||
        (authorizationFilter === "authorized" && client.authorized) ||
        (authorizationFilter === "associated" && !client.authorized);
      const matchesBand = bandFilter === "all" || (client.band || "Unknown") === bandFilter;
      const hasTxRetries = typeof client.tx_retries === "number" && Number.isFinite(client.tx_retries);
      const hasTxFailures = typeof client.tx_failed === "number" && Number.isFinite(client.tx_failed);
      const hasTxIssue = (hasTxRetries && client.tx_retries! > 0) || (hasTxFailures && client.tx_failed! > 0);
      const matchesTransmission = transmissionFilter === "all" ||
        (transmissionFilter === "issues" && hasTxIssue) ||
        (transmissionFilter === "failures" && hasTxFailures && client.tx_failed! > 0) ||
        (transmissionFilter === "unavailable" && (!hasTxRetries || !hasTxFailures));
      return matchesText && matchesAuthorization && matchesBand && matchesTransmission;
    })
    .slice()
    .sort((left, right) => {
      if (sort === "mac") return left.mac.localeCompare(right.mac);
      if (sort === "rx") return (right.rx_rate_mbps ?? -Infinity) - (left.rx_rate_mbps ?? -Infinity);
      if (sort === "tx") return (right.tx_rate_mbps ?? -Infinity) - (left.tx_rate_mbps ?? -Infinity);
      if (sort === "measured-rx") return (right.measured_rx_mbps ?? -Infinity) - (left.measured_rx_mbps ?? -Infinity);
      if (sort === "measured-tx") return (right.measured_tx_mbps ?? -Infinity) - (left.measured_tx_mbps ?? -Infinity);
      if (sort === "retries") return (right.tx_retries ?? -1) - (left.tx_retries ?? -1);
      if (sort === "failures") return (right.tx_failed ?? -1) - (left.tx_failed ?? -1);
      return (right.signal_dbm ?? -Infinity) - (left.signal_dbm ?? -Infinity);
    });
  const exportStations = () => {
    if (visibleClients.length === 0) return;
    const exportedAt = new Date().toISOString();
    const rows: Array<Array<string | number | boolean | null | undefined>> = [
      ["Exported at (UTC)", "Search filter", "Band filter", "Authorization filter", "TX diagnostics filter", "Sort order", "Hostname", "SSID", "MAC", "Radio", "Interface", "Band", "Authorized", "Signal average dBm", "Signal current dBm", "Noise dBm", "RX Mbps", "TX Mbps", "RX PHY", "TX PHY", "Measured RX Mbps", "Measured TX Mbps", "RX bytes", "RX packets", "TX bytes", "TX packets", "Connected seconds", "Inactive ms", "TX retries", "TX failed"],
      ...visibleClients.map((client) => [
        exportedAt, filter, bandFilter, authorizationFilter, transmissionFilter, sort,
        hostnames.get(client.mac.toLowerCase()) ?? "", client.ssid, client.mac, client.radio, client.ifname,
        client.band, client.authorized, client.signal_avg_dbm, client.signal_current_dbm, client.noise_dbm,
        client.rx_rate_mbps, client.tx_rate_mbps, formatWifiRateDetails(client.rx_details),
        formatWifiRateDetails(client.tx_details), client.measured_rx_mbps, client.measured_tx_mbps,
        client.rx_bytes, client.rx_packets, client.tx_bytes, client.tx_packets,
        client.connected_seconds, client.inactive_ms,
        client.tx_retries, client.tx_failed,
      ]),
    ];
    const csv = rows.map((row) => row.map(csvCell).join(",")).join("\r\n");
    const objectUrl = URL.createObjectURL(new Blob(["\uFEFF", csv], { type: "text/csv;charset=utf-8" }));
    const link = document.createElement("a");
    link.href = objectUrl;
    link.download = `quantumgrid-wifi-stations-${new Date().toISOString().replace(/[:.]/g, "-")}.csv`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(objectUrl), 0);
  };

  if (!available) return <div className="module-message">Wireless association telemetry is not available from this router API.</div>;
  if (clients.length === 0) return <div className="module-message">No associated Wi-Fi stations were reported by iwinfo.</div>;

  return (
    <div className="wifi-client-table">
      <div className="metrics wifi-station-summary">
        <Metric title="Associated stations" value={fmt(clients.length)} unit="" detail="Current iwinfo associations" icon={Users} />
        <Metric title="Authorized" value={fmt(authorizedCount)} unit="" detail="Stations reported authorized by the driver" icon={Shield} />
        <Metric title="Associated only" value={fmt(associatedOnlyCount)} unit="" detail="Associated but not authorized" icon={Wifi} />
        <Metric title="Measured RX" value={measuredStations.length ? `${fmt(totalMeasuredRx, 2)} Mbps` : "N/A"} unit="" detail={measuredCoverage} icon={Download} />
        <Metric title="Measured TX" value={measuredStations.length ? `${fmt(totalMeasuredTx, 2)} Mbps` : "N/A"} unit="" detail={measuredCoverage} icon={Upload} />
      </div>
      <div className="wifi-station-diagnostics" role="status">
        <span><strong>{fmt(stationsWithRetries)}</strong> stations report TX retries</span>
        <span><strong>{fmt(stationsWithFailures)}</strong> report failed TX packets</span>
        <span><strong>{fmt(stationsWithCompleteTxCounters)}/{fmt(clients.length)}</strong> have both counters</span>
      </div>
      <div className="wifi-station-tools">
        <input
          type="search"
          aria-label="Filter associated Wi-Fi clients"
          placeholder="Filter hostname, MAC, SSID or radio"
          value={filter}
          onChange={(event) => setFilter(event.target.value)}
        />
        <select aria-label="Filter station band" value={bandFilter} onChange={(event) => setBandFilter(event.target.value)}>
          <option value="all">All Wi-Fi bands</option>
          {availableBands.map((band) => <option value={band} key={band}>{band}</option>)}
        </select>
        <select aria-label="Filter station authorization" value={authorizationFilter} onChange={(event) => setAuthorizationFilter(event.target.value as "all" | "authorized" | "associated")}>
          <option value="all">All station states</option>
          <option value="authorized">Authorized only</option>
          <option value="associated">Associated, not authorized</option>
        </select>
        <select aria-label="Filter station transmission diagnostics" value={transmissionFilter} onChange={(event) => setTransmissionFilter(event.target.value as "all" | "issues" | "failures" | "unavailable")}>
          <option value="all">All TX diagnostics</option>
          <option value="issues">Any TX retries or failures</option>
          <option value="failures">Failed TX packets only</option>
          <option value="unavailable">Missing TX counters</option>
        </select>
        <select aria-label="Sort associated Wi-Fi clients" value={sort} onChange={(event) => setSort(event.target.value as "signal" | "rx" | "tx" | "measured-rx" | "measured-tx" | "retries" | "failures" | "mac")}>
          <option value="signal">Strongest signal</option>
          <option value="rx">Highest RX PHY rate</option>
          <option value="tx">Highest TX PHY rate</option>
          <option value="measured-rx">Highest measured RX throughput</option>
          <option value="measured-tx">Highest measured TX throughput</option>
          <option value="retries">Most TX retries</option>
          <option value="failures">Most failed TX packets</option>
          <option value="mac">MAC address A–Z</option>
        </select>
        <span>{visibleClients.length} of {clients.length} clients</span>
        <button className="hero-button wifi-export-button" onClick={exportStations} disabled={visibleClients.length === 0}>Export station CSV</button>
      </div>
      <div className="wifi-client-table-head">
        <span>DEVICE / MAC</span>
        <span>RADIO</span>
        <span>SIGNAL</span>
        <span>RX / TX RATE</span>
        <span>STATE</span>
      </div>
      {visibleClients.length === 0 ? (
        <div className="module-message">No associated stations match the current text, band and authorization filters.</div>
      ) : visibleClients.map((client) => (
        <div className="wifi-client-table-row" key={`${client.ifname}-${client.mac}`}>
          <div className="wifi-client-name">
            <div className="device-icon"><Wifi size={15} /></div>
            <div>
              <strong>{hostnames.get(client.mac.toLowerCase()) || client.mac.toUpperCase()}</strong>
              <span>
                {client.ssid || client.ifname} · {client.mac.toUpperCase()}
                {client.connected_seconds === undefined ? "" : ` · connected ${formatUptime(client.connected_seconds)}`}
                {client.inactive_ms === undefined ? "" : ` · inactive ${fmt(client.inactive_ms / 1000, 1)}s`}
                {client.tx_retries === undefined ? "" : ` · TX retries ${fmt(client.tx_retries)}`}
                {client.tx_failed === undefined ? "" : ` · TX failed ${fmt(client.tx_failed)}`}
              </span>
            </div>
          </div>
          <b>{client.band}</b>
          <div className="wifi-client-signal-cell">
            <b>{client.signal_dbm === undefined ? "N/A" : `${fmt(client.signal_dbm)} dBm`}</b>
            <small>{client.signal_avg_dbm === undefined ? "Average N/A" : "Average " + fmt(client.signal_avg_dbm) + " dBm"}</small>
            {client.signal_current_dbm === undefined ? null : <small>Current {fmt(client.signal_current_dbm)} dBm</small>}
          </div>
          <div className="wifi-client-rate-cell">
            <b>{client.rx_rate_mbps === undefined || client.tx_rate_mbps === undefined
              ? "N/A"
              : `${fmt(client.rx_rate_mbps, 1)} / ${fmt(client.tx_rate_mbps, 1)} Mbps`}</b>
            <small>RX {formatWifiRateDetails(client.rx_details)}</small>
            <small>TX {formatWifiRateDetails(client.tx_details)}</small>
            <small>Measured RX/TX {client.measured_rx_mbps !== undefined && client.measured_tx_mbps !== undefined
              ? `${fmt(client.measured_rx_mbps, 2)} / ${fmt(client.measured_tx_mbps, 2)} Mbps`
              : "Collecting two counter samples"}</small>
            <small>RX total {formatTrafficBytes(client.rx_bytes)} · {client.rx_packets === undefined ? "N/A" : fmt(client.rx_packets)} packets</small>
            <small>TX total {formatTrafficBytes(client.tx_bytes)} · {client.tx_packets === undefined ? "N/A" : fmt(client.tx_packets)} packets</small>
          </div>
          <span className={client.authorized ? "priority-pill high" : "priority-pill normal"}>
            {client.authorized ? "AUTHORIZED" : "ASSOCIATED"}
          </span>
        </div>
      ))}
    </div>
  );
}

function DevicesControlPage({ routerOverview }: { routerOverview: RouterOverview | null }) {
  const clients = routerOverview?.clients ?? [];
  const inventoryAvailable = Array.isArray(routerOverview?.clients);
  const wirelessClients = routerOverview?.wireless_clients ?? [];
  const wirelessInventoryAvailable = Array.isArray(routerOverview?.wireless_clients);
  return (
    <div className="module-page">
      <section className="module-hero">
        <div className="module-icon"><Users size={25} /></div>
        <div>
          <div className="setup-kicker">CLIENT INTELLIGENCE · READ ONLY</div>
          <h1>Known Network Clients</h1>
          <p>Inventory of validated, unexpired IPv4 DHCP leases reported by dnsmasq on this router. Entries update with router telemetry.</p>
        </div>
      </section>
      <div className="module-grid">
        <Panel title="DHCPv4 client inventory" eyebrow="ROUTER LEASE TABLE" action={<Status active={inventoryAvailable}>{inventoryAvailable ? "LIVE" : "WAITING"}</Status>}>
          <ClientLeaseList clients={clients} available={inventoryAvailable} />
        </Panel>
        <Panel title="Associated Wi-Fi clients" eyebrow="LIVE HOSTAPD ASSOCIATIONS" action={<Status active={wirelessInventoryAvailable}>{wirelessInventoryAvailable ? "LIVE" : "WAITING"}</Status>}>
          <WirelessClientList clients={wirelessClients} available={wirelessInventoryAvailable} leases={clients} />
        </Panel>
      </div>
      <Panel title="Data provenance" eyebrow="HOW TO READ THIS LIST">
        <div className="module-message">DHCP leases show address allocation. Wi-Fi entries come from iwinfo association data. Signal and rates are shown only when the router driver reports them; neither source implies every LAN device is wireless or reachable through ICMP.</div>
      </Panel>
    </div>
  );
}

function formatTrafficBytes(bytes: number | undefined): string {
  if (bytes === undefined || !Number.isFinite(bytes) || bytes < 0) return "N/A";
  if (bytes < 1024) return `${fmt(bytes)} B`;
  const units = ["KB", "MB", "GB", "TB"];
  let value = bytes / 1024;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return `${fmt(value, 1)} ${units[unit]}`;
}

function NetworkControlPage({
  routerOverview,
  stats,
  interfaceCounterDeltas,
}: {
  routerOverview: RouterOverview | null;
  stats: Stats;
  interfaceCounterDeltas: Map<string, InterfaceCounterDelta>;
}) {
  const interfaces = routerOverview?.interfaces ?? [];
  const routes = routerOverview?.routes ?? [];
  const policyRules = routerOverview?.policy_rules ?? [];
  const mwan3 = routerOverview?.mwan3;
  const mwan3Interfaces = mwan3?.interfaces ?? [];
  const [mwanSearch, setMwanSearch] = useState("");
  const [mwanStateFilter, setMwanStateFilter] = useState<"all" | "online" | "offline" | "disabled" | "tracker-down">("all");
  const [mwanSort, setMwanSort] = useState<"name" | "status" | "tracking">("name");
  const [ruleFamily, setRuleFamily] = useState<"all" | "IPv4" | "IPv6">("all");
  const [ruleSearch, setRuleSearch] = useState("");
  const [routeFamily, setRouteFamily] = useState<"all" | "IPv4" | "IPv6">("all");
  const [interfaceScope, setInterfaceScope] = useState<"all" | "wan" | "lan">("all");
  const [interfaceSort, setInterfaceSort] = useState<"name" | "rx" | "tx" | "errors">("name");
  const visibleInterfaces = interfaces.filter((item) =>
    interfaceScope === "all" ||
    (interfaceScope === "wan" && item.is_wan) ||
    (interfaceScope === "lan" && !item.is_wan)
  ).slice().sort((left, right) => {
    if (interfaceSort === "rx") return right.rx_bytes - left.rx_bytes;
    if (interfaceSort === "tx") return right.tx_bytes - left.tx_bytes;
    if (interfaceSort === "errors") {
      const leftCount = left.rx_errors === undefined && left.tx_errors === undefined && left.rx_dropped === undefined && left.tx_dropped === undefined
        ? -1 : (left.rx_errors ?? 0) + (left.tx_errors ?? 0) + (left.rx_dropped ?? 0) + (left.tx_dropped ?? 0);
      const rightCount = right.rx_errors === undefined && right.tx_errors === undefined && right.rx_dropped === undefined && right.tx_dropped === undefined
        ? -1 : (right.rx_errors ?? 0) + (right.tx_errors ?? 0) + (right.rx_dropped ?? 0) + (right.tx_dropped ?? 0);
      return rightCount - leftCount;
    }
    return left.name.localeCompare(right.name);
  });
  const visibleRoutes = routes
    .filter((route) => routeFamily === "all" || route.family === routeFamily)
    .slice()
    .sort((left, right) => left.family.localeCompare(right.family) ||
      left.table.localeCompare(right.table) ||
      (left.metric ?? Number.MAX_SAFE_INTEGER) - (right.metric ?? Number.MAX_SAFE_INTEGER));

  const ruleQuery = ruleSearch.trim().toLocaleLowerCase();
  const policyCoverage = analyzePolicyRouting(policyRules, routes);
  const visiblePolicyRules = policyRules
    .filter((rule) => (ruleFamily === "all" || rule.family === ruleFamily) && [
      rule.family, String(rule.priority), rule.source, rule.destination, rule.fwmark,
      rule.input_interface, rule.output_interface, rule.protocol, rule.uid_range,
      rule.table, rule.action, rule.selectors,
    ].join(" ").toLocaleLowerCase().includes(ruleQuery))
    .slice()
    .sort((left, right) => left.family.localeCompare(right.family) ||
      left.priority - right.priority || left.selectors.localeCompare(right.selectors));

  const mwanQuery = mwanSearch.trim().toLocaleLowerCase();
  const visibleMwanInterfaces = mwan3Interfaces
    .filter((iface) => {
      const online = iface.status === "online" && iface.up;
      const stateMatches = mwanStateFilter === "all" ||
        (mwanStateFilter === "online" && online) ||
        (mwanStateFilter === "offline" && iface.status === "offline") ||
        (mwanStateFilter === "disabled" && !iface.enabled) ||
        (mwanStateFilter === "tracker-down" && iface.enabled && iface.tracking !== "active");
      const searchable = [
        iface.name, iface.status, iface.tracking,
        ...iface.track_targets.map((target) => [target.ip, target.status].join(" ")),
      ].join(" ").toLocaleLowerCase();
      return stateMatches && searchable.includes(mwanQuery);
    })
    .slice()
    .sort((left, right) => {
      if (mwanSort === "status") return left.status.localeCompare(right.status) || left.name.localeCompare(right.name);
      if (mwanSort === "tracking") return left.tracking.localeCompare(right.tracking) || left.name.localeCompare(right.name);
      return left.name.localeCompare(right.name);
    });

  const exportMwan3 = () => {
    if (!mwan3?.available || visibleMwanInterfaces.length === 0) return;
    const exportedAt = new Date().toISOString();
    const rows: Array<Array<string | number | boolean | null | undefined>> = [
      ["Exported at (UTC)", "State filter", "Search filter", "Sort order", "Interface", "Enabled", "Netifd up", "mwan3 status", "Tracker state", "Tracker running", "Age seconds", "Online seconds", "Offline seconds", "Interface uptime seconds", "Score", "Lost", "Turn", "Measured RX Mbps", "Measured TX Mbps", "Sample interval seconds", "Tracking targets"],
      ...visibleMwanInterfaces.map((iface) => {
        const delta = interfaceCounterDeltas.get(iface.name);
        return [
        exportedAt, mwanStateFilter, mwanSearch, mwanSort, iface.name, iface.enabled, iface.up,
        iface.status, iface.tracking, iface.running, iface.age_seconds, iface.online_seconds,
        iface.offline_seconds, iface.interface_uptime_seconds, iface.score, iface.lost, iface.turn,
        delta?.rxMbps, delta?.txMbps, delta?.sampleSeconds,
        iface.track_targets.map((target) =>
          [target.ip, target.status, target.latency_ms, target.packet_loss_percent].join("/")
        ).join(" | "),
        ];
      }),
    ];
    const csv = rows.map((row) => row.map(csvCell).join(",")).join("\r\n");
    const objectUrl = URL.createObjectURL(new Blob(["\uFEFF", csv], { type: "text/csv;charset=utf-8" }));
    const link = document.createElement("a");
    link.href = objectUrl;
    link.download = "quantumgrid-mwan3-health-" + exportedAt.replace(/[:.]/g, "-") + ".csv";
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(objectUrl), 0);
  };

  const exportRoutes = () => {
    if (!routerOverview?.routes_available || visibleRoutes.length === 0) return;
    const exportedAt = new Date().toISOString();
    const rows: Array<Array<string | number | null | undefined>> = [
      ["Exported at (UTC)", "Family filter", "Family", "Route type", "Table", "Device", "Gateway", "Metric", "Protocol"],
      ...visibleRoutes.map((route) => [
        exportedAt, routeFamily, route.family, route.route_type, route.table,
        route.device, route.gateway, route.metric, route.protocol,
      ]),
    ];
    const csv = rows.map((row) => row.map(csvCell).join(",")).join("\r\n");
    const objectUrl = URL.createObjectURL(new Blob(["\uFEFF", csv], { type: "text/csv;charset=utf-8" }));
    const link = document.createElement("a");
    link.href = objectUrl;
    link.download = "quantumgrid-default-routes-" + exportedAt.replace(/[:.]/g, "-") + ".csv";
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(objectUrl), 0);
  };

  const exportPolicyRules = () => {
    if (!routerOverview?.policy_rules_available || visiblePolicyRules.length === 0) return;
    const exportedAt = new Date().toISOString();
    const rows: Array<Array<string | number | null | undefined>> = [
      ["Exported at (UTC)", "Family filter", "Search filter", "Family", "Priority", "Source", "Destination", "Firewall mark", "Input interface", "Output interface", "Protocol", "UID range", "Action", "Lookup table", "Selectors"],
      ...visiblePolicyRules.map((rule) => [
        exportedAt, ruleFamily, ruleSearch, rule.family, rule.priority, rule.source, rule.destination,
        rule.fwmark, rule.input_interface, rule.output_interface, rule.protocol, rule.uid_range,
        rule.action, rule.table, rule.selectors,
      ]),
    ];
    const csv = rows.map((row) => row.map(csvCell).join(",")).join("\r\n");
    const objectUrl = URL.createObjectURL(new Blob(["\uFEFF", csv], { type: "text/csv;charset=utf-8" }));
    const link = document.createElement("a");
    link.href = objectUrl;
    link.download = "quantumgrid-policy-routing-rules-" + exportedAt.replace(/[:.]/g, "-") + ".csv";
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(objectUrl), 0);
  };

  const exportInterfaces = () => {
    if (visibleInterfaces.length === 0) return;
    const exportedAt = new Date().toISOString();
    const rows: Array<Array<string | number | boolean | null | undefined>> = [
      ["Exported at (UTC)", "Scope filter", "Sort order", "Interface", "Device", "Class", "State", "IPv4 addresses", "IPv6 addresses", "Assigned DNS servers", "RX bytes", "RX packets", "RX errors", "RX dropped", "TX bytes", "TX packets", "TX errors", "TX dropped", "RX error delta", "RX drop delta", "TX error delta", "TX drop delta"],
      ...visibleInterfaces.map((item) => {
        const delta = interfaceCounterDeltas.get(item.name);
        return [
          exportedAt, interfaceScope, interfaceSort, item.name, item.device, item.is_wan ? "WAN" : "LAN / other",
          item.up ? "UP" : "DOWN", item.ipv4.join(" "), (item.ipv6 ?? []).join(" "), (item.dns_servers ?? []).join(" "), item.rx_bytes, item.rx_packets, item.rx_errors,
          item.rx_dropped, item.tx_bytes, item.tx_packets, item.tx_errors, item.tx_dropped,
          delta?.rxErrors, delta?.rxDropped, delta?.txErrors, delta?.txDropped,
        ];
      }),
    ];
    const csv = rows.map((row) => row.map(csvCell).join(",")).join("\r\n");
    const objectUrl = URL.createObjectURL(new Blob(["\uFEFF", csv], { type: "text/csv;charset=utf-8" }));
    const link = document.createElement("a");
    link.href = objectUrl;
    link.download = "quantumgrid-interface-inventory-" + exportedAt.replace(/[:.]/g, "-") + ".csv";
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(objectUrl), 0);
  };
  const radios = routerOverview?.wireless ?? [];
  const wirelessClients = routerOverview?.wireless_clients ?? [];
  const wanCount = interfaces.filter((item) => item.is_wan).length;
  const activeInterfaces = interfaces.filter((item) => item.up).length;
  const activeRadios = radios.filter((radio) => radio.up).length;
  const knownClientCount = Array.isArray(routerOverview?.clients)
    ? fmt(routerOverview.clients.length)
    : "N/A";

  return (
    <div className="module-page">
      <section className="module-hero">
        <div className="module-icon"><Network size={25} /></div>
        <div>
          <div className="setup-kicker">LIVE ROUTER INTERFACES</div>
          <h1>Network</h1>
          <p>WAN/LAN interface telemetry, IPv4/IPv6 addresses, assigned DNS servers, default routes across kernel policy tables, kernel counters and wireless radio status from the authenticated router API.</p>
        </div>
      </section>

      <div className="metrics">
        <Metric title="Active Interfaces" value={routerOverview ? `${activeInterfaces}/${interfaces.length}` : "N/A"} unit="" detail="Kernel interface state" icon={Network} />
        <Metric title="WAN Interfaces" value={routerOverview ? fmt(wanCount) : "N/A"} unit="" detail="Configured WAN links" icon={Globe2} />
        <Metric title="Active Radios" value={routerOverview ? `${activeRadios}/${radios.length}` : "N/A"} unit="" detail="Wireless radio state" icon={Wifi} />
        <Metric title="Known DHCP Clients" value={knownClientCount} unit="" detail="Unexpired IPv4 leases" icon={Users} />
      </div>

      <Panel title="Network interfaces" eyebrow="KERNEL COUNTERS" action={<Status active={Boolean(routerOverview)}>{routerOverview ? "LIVE" : "WAITING"}</Status>}>
        {!routerOverview ? (
          <div className="module-message">Waiting for authenticated router telemetry.</div>
        ) : interfaces.length === 0 ? (
          <div className="module-message">The router did not report any network interfaces.</div>
        ) : (
          <>
          <div className="network-interface-tools">
            <select aria-label="Filter network interface scope" value={interfaceScope} onChange={(event) => setInterfaceScope(event.target.value as "all" | "wan" | "lan")}>
              <option value="all">All interfaces</option>
              <option value="wan">WAN only</option>
              <option value="lan">LAN / other only</option>
            </select>
            <select aria-label="Sort network interfaces" value={interfaceSort} onChange={(event) => setInterfaceSort(event.target.value as "name" | "rx" | "tx" | "errors")}>
              <option value="name">Name A–Z</option>
              <option value="rx">Highest RX bytes</option>
              <option value="tx">Highest TX bytes</option>
              <option value="errors">Most errors / drops</option>
            </select>
            <span>{visibleInterfaces.length} of {interfaces.length} interfaces</span>
            <button className="hero-button wifi-export-button" onClick={exportInterfaces} disabled={visibleInterfaces.length === 0}>Export interface CSV</button>
          </div>
          {visibleInterfaces.length === 0 ? (
            <div className="module-message">No interfaces match the selected scope.</div>
          ) : (
          <div className="device-list">
            {visibleInterfaces.map((item) => (
              <div className="device-row" key={item.name}>
                <div className="device-title">
                  <div className="device-icon"><Network size={17} /></div>
                  <div><strong>{item.name}</strong><span>{item.device}{item.is_wan ? " · WAN" : " · LAN / other"}</span></div>
                </div>
                <div><small>STATE</small><b>{item.up ? "UP" : "DOWN"}</b></div>
                <div><small>IPV4</small><b>{item.ipv4.length > 0 ? item.ipv4.join(", ") : "—"}</b></div>
                <div><small>IPV6</small><b>{(item.ipv6 ?? []).length > 0 ? item.ipv6?.join(", ") : "—"}</b></div>
                <div><small>ASSIGNED DNS</small><b>{(item.dns_servers ?? []).length > 0 ? item.dns_servers?.join(", ") : "—"}</b></div>
                <div>
                  <small>RX TOTAL</small>
                  <b>{formatTrafficBytes(item.rx_bytes)}</b>
                  <small>Packets {item.rx_packets === undefined ? "N/A" : fmt(item.rx_packets)} · errors {item.rx_errors === undefined ? "N/A" : fmt(item.rx_errors)} · dropped {item.rx_dropped === undefined ? "N/A" : fmt(item.rx_dropped)}</small>
                  <small>Since previous sample · errors {interfaceCounterDeltas.get(item.name)?.rxErrors == null ? "N/A" : "+" + fmt(interfaceCounterDeltas.get(item.name)!.rxErrors!)} · drops {interfaceCounterDeltas.get(item.name)?.rxDropped == null ? "N/A" : "+" + fmt(interfaceCounterDeltas.get(item.name)!.rxDropped!)}</small>
                </div>
                <div>
                  <small>TX TOTAL</small>
                  <b>{formatTrafficBytes(item.tx_bytes)}</b>
                  <small>Packets {item.tx_packets === undefined ? "N/A" : fmt(item.tx_packets)} · errors {item.tx_errors === undefined ? "N/A" : fmt(item.tx_errors)} · dropped {item.tx_dropped === undefined ? "N/A" : fmt(item.tx_dropped)}</small>
                  <small>Since previous sample · errors {interfaceCounterDeltas.get(item.name)?.txErrors == null ? "N/A" : "+" + fmt(interfaceCounterDeltas.get(item.name)!.txErrors!)} · drops {interfaceCounterDeltas.get(item.name)?.txDropped == null ? "N/A" : "+" + fmt(interfaceCounterDeltas.get(item.name)!.txDropped!)}</small>
                </div>
              </div>
            ))}
          </div>
          )}
          </>
        )}
        <div className="module-message">Byte, packet, error and drop values are cumulative kernel interface counters since the driver or interface counters were reset; they are not instantaneous link speeds. Short-interval error/drop deltas compare successive API samples, remain N/A on the first sample or after a counter reset, and do not estimate packet loss. Counters the driver does not expose remain N/A. CSV export includes the active scope and sort filters.</div>
      </Panel>

      <Panel
        title="Default routes"
        eyebrow="KERNEL ROUTING TABLES · READ-ONLY"
        action={
          <div className="network-interface-tools">
            <select aria-label="Filter default route family" value={routeFamily} onChange={(event) => setRouteFamily(event.target.value as "all" | "IPv4" | "IPv6")}>
              <option value="all">IPv4 + IPv6</option>
              <option value="IPv4">IPv4 only</option>
              <option value="IPv6">IPv6 only</option>
            </select>
            <button className="hero-button wifi-export-button" onClick={exportRoutes} disabled={!routerOverview?.routes_available || visibleRoutes.length === 0}>Export route CSV</button>
          </div>
        }
      >
        {!routerOverview ? (
          <div className="module-message">Waiting for authenticated router telemetry.</div>
        ) : !routerOverview.routes_available ? (
          <div className="module-message">This router API does not report the kernel route inventory. Update the router firmware to enable this read-only view.</div>
        ) : visibleRoutes.length === 0 ? (
          <div className="module-message">No default routes were returned for the selected address family.</div>
        ) : (
          <>
            <div className="module-message">{visibleRoutes.length} default routes shown across all kernel routing tables. Table names such as 201 or 202 may be used by policy-routing and Multi-WAN configurations.</div>
            <div className="device-list">
              {visibleRoutes.map((route, index) => (
                <div className="device-row default-route-row" key={route.family + "-" + route.table + "-" + route.device + "-" + index}>
                  <div className="device-title">
                    <div className="device-icon"><Globe2 size={17} /></div>
                    <div><strong>{route.family} · {route.table}</strong><span>{route.route_type} · {route.protocol || "protocol N/A"}</span></div>
                  </div>
                  <div><small>DEVICE</small><b>{route.device || "N/A"}</b></div>
                  <div><small>GATEWAY</small><b>{route.gateway || "On-link / unspecified"}</b></div>
                  <div><small>METRIC</small><b>{route.metric === undefined ? "N/A" : fmt(route.metric)}</b></div>
                </div>
              ))}
            </div>
          </>
        )}
        <div className="module-message">This is a read-only snapshot of kernel policy rules. Rules are evaluated by ascending priority; lookup rules direct matching packets to a routing table. QuantumGrid does not change rule order, marks, routes or Multi-WAN policy.</div>
      </Panel>

      <Panel
        title="Policy routing rules"
        eyebrow="IP RULES · READ-ONLY"
        action={
          <div className="network-interface-tools">
            <select aria-label="Filter policy rule family" value={ruleFamily} onChange={(event) => setRuleFamily(event.target.value as "all" | "IPv4" | "IPv6")}>
              <option value="all">IPv4 + IPv6</option>
              <option value="IPv4">IPv4 only</option>
              <option value="IPv6">IPv6 only</option>
            </select>
            <input type="search" aria-label="Search policy routing rules" placeholder="Search mark, source, interface or table" value={ruleSearch} onChange={(event) => setRuleSearch(event.target.value)} />
            <span>{visiblePolicyRules.length} of {routerOverview?.policy_rules_count ?? policyRules.length} rules</span>
            <button className="hero-button wifi-export-button" onClick={exportPolicyRules} disabled={!routerOverview?.policy_rules_available || visiblePolicyRules.length === 0}>Export policy rules CSV</button>
          </div>
        }
      >
        {!routerOverview ? (
          <div className="module-message">Waiting for authenticated router telemetry.</div>
        ) : !routerOverview.policy_rules_available ? (
          <div className="module-message">The router could not read IPv4/IPv6 policy rules. Check that the ip utility is installed.</div>
        ) : visiblePolicyRules.length === 0 ? (
          <div className="module-message">{policyRules.length === 0 ? "No policy rules were returned by the router." : "No policy rules match the selected family and search filter."}</div>
        ) : (
          <>
            <div className="module-message">{visiblePolicyRules.length} matching rules shown. {routerOverview.policy_rules_truncated ? "The router inventory is capped at 64 rules; the export contains the visible subset only." : "The complete reported inventory is available."}</div>
            <div className="device-list">
              {visiblePolicyRules.map((rule) => (
                <div className="device-row policy-rule-row" key={rule.family + "-" + rule.priority + "-" + rule.selectors}>
                  <div className="device-title">
                    <div className="device-icon"><Globe2 size={17} /></div>
                    <div><strong>{rule.family} · Priority {fmt(rule.priority)}</strong><span>{rule.action === "lookup" ? "Lookup rule" : rule.action}</span></div>
                  </div>
                  <div><small>LOOKUP TARGET</small><b>{rule.table || "N/A"}</b></div>
                  <div><small>SOURCE / DESTINATION</small><b>From {rule.source} · To {rule.destination}</b></div>
                  <div><small>MARK / INTERFACES</small><b>{rule.fwmark || "No mark"}</b><small>{[rule.input_interface ? "iif " + rule.input_interface : "", rule.output_interface ? "oif " + rule.output_interface : "", rule.protocol ? rule.protocol : "", rule.uid_range ? "uid " + rule.uid_range : ""].filter(Boolean).join(" · ") || "No additional selectors"}</small></div>
                  <div><small>ALL SELECTORS</small><b>{rule.selectors || "—"}</b></div>
                </div>
              ))}
            </div>
          </>
        )}
        <div className="module-message">Priority order is reported by the kernel, but a rule listing is not a packet-by-packet route simulation. This view does not verify connection tracking marks, mwan3 health checks, reachability or which interface a live flow ultimately uses.</div>
      </Panel>

      <Panel title="Policy routing table coverage" eyebrow="RULES ↔ DEFAULT ROUTES · READ-ONLY">
        {!routerOverview ? (
          <div className="module-message">Waiting for authenticated router telemetry.</div>
        ) : !routerOverview.policy_rules_available || !routerOverview.routes_available ? (
          <div className="module-message">Coverage is unknown because the kernel rule or default-route inventory is unavailable.</div>
        ) : (
          <>
            <div className="policy-coverage-grid">
              <div><small>LOOKUPS WITH DEFAULT ROUTE</small><strong>{fmt(policyCoverage.matchedLookupRules)}</strong></div>
              <div><small>LOOKUPS WITHOUT DEFAULT</small><strong>{fmt(policyCoverage.missingDefaultRouteRules.length)}</strong></div>
              <div><small>NON-LOOKUP ACTIONS</small><strong>{fmt(policyCoverage.nonLookupRules.length)}</strong></div>
              <div><small>UNREFERENCED DEFAULT TABLES</small><strong>{fmt(policyCoverage.unreferencedDefaultTables.length)}</strong></div>
            </div>
            {policyCoverage.missingDefaultRouteRules.length > 0 ? (
              <div className="policy-coverage-findings">
                <strong>Lookup rules without a reported default route</strong>
                {policyCoverage.missingDefaultRouteRules.map((rule) => (
                  <div key={rule.family + "-" + rule.priority + "-" + rule.selectors}>
                    <span>{rule.family} · priority {fmt(rule.priority)}</span>
                    <b>Table {rule.table}</b>
                    <small>{rule.selectors}</small>
                  </div>
                ))}
              </div>
            ) : (
              <div className="module-message">Every reported lookup rule points to a table with at least one reported default route.</div>
            )}
            {policyCoverage.unreferencedDefaultTables.length > 0 ? (
              <div className="policy-coverage-findings">
                <strong>Default-route tables not named by a lookup rule</strong>
                {policyCoverage.unreferencedDefaultTables.map((item) => (
                  <div key={item.family + "-" + item.table}>
                    <span>{item.family}</span>
                    <b>Table {item.table}</b>
                    <small>{fmt(item.routeCount)} default route(s)</small>
                  </div>
                ))}
              </div>
            ) : null}
          </>
        )}
        <div className="module-message">This cross-reference compares address family and table name only. A lookup table with no default route may still contain specific routes or serve non-default traffic; an unreferenced default route is not automatically unused. No rule priority, fwmark, connection-tracking or packet path is simulated.</div>
      </Panel>

      <Panel
        title="Multi-WAN health"
        eyebrow="MWAN3 TRACKING · READ-ONLY"
        action={<Status active={Boolean(mwan3?.available)}>{!routerOverview ? "WAITING" : !mwan3 ? "API UPDATE REQUIRED" : !mwan3.installed ? "NOT INSTALLED" : mwan3.available ? "LIVE" : "UNAVAILABLE"}</Status>}
      >
        {!routerOverview ? (
          <div className="module-message">Waiting for authenticated router telemetry.</div>
        ) : !mwan3 ? (
          <div className="module-message">This router API does not report Multi-WAN telemetry. Update QuantumGrid firmware to enable the view.</div>
        ) : !mwan3.installed ? (
          <div className="module-message">The mwan3 service is not installed in this firmware.</div>
        ) : !mwan3.available ? (
          <div className="module-message">The mwan3 tracking API is unavailable. This is unknown state, not proof that a WAN link is down.</div>
        ) : mwan3Interfaces.length === 0 ? (
          <div className="module-message">mwan3 is available but has no configured interface sections.</div>
        ) : (
          <>
            <div className="network-interface-tools mwan3-tools">
              <select aria-label="Filter Multi-WAN state" value={mwanStateFilter} onChange={(event) => setMwanStateFilter(event.target.value as "all" | "online" | "offline" | "disabled" | "tracker-down")}>
                <option value="all">All links</option>
                <option value="online">Online and netifd up</option>
                <option value="offline">mwan3 offline</option>
                <option value="disabled">Disabled in config</option>
                <option value="tracker-down">Tracker not active</option>
              </select>
              <input type="search" aria-label="Search Multi-WAN interfaces and targets" placeholder="Search interface or tracking target" value={mwanSearch} onChange={(event) => setMwanSearch(event.target.value)} />
              <select aria-label="Sort Multi-WAN interfaces" value={mwanSort} onChange={(event) => setMwanSort(event.target.value as "name" | "status" | "tracking")}>
                <option value="name">Name A–Z</option>
                <option value="status">Status</option>
                <option value="tracking">Tracker state</option>
              </select>
              <span>{visibleMwanInterfaces.length} of {mwan3.count} links</span>
              <button className="hero-button wifi-export-button" onClick={exportMwan3} disabled={visibleMwanInterfaces.length === 0}>Export Multi-WAN CSV</button>
            </div>
            {mwan3.truncated ? <div className="module-message">The interface inventory is capped at 16 entries. The CSV contains the visible subset only.</div> : null}
            {visibleMwanInterfaces.length === 0 ? (
              <div className="module-message">No Multi-WAN interfaces match the current filter.</div>
            ) : (
              <div className="device-list">
                {visibleMwanInterfaces.map((iface) => {
                  const online = iface.status === "online" && iface.up;
                  const label = !iface.enabled ? "DISABLED" : iface.status.toUpperCase();
                  const delta = interfaceCounterDeltas.get(iface.name);
                  return (
                    <div className="device-row mwan3-interface-row" key={iface.name}>
                      <div className="device-title">
                        <div className="device-icon"><Globe2 size={17} /></div>
                        <div><strong>{iface.name}</strong><span>{iface.enabled ? "Enabled in mwan3" : "Disabled in mwan3"} · netifd {iface.up ? "up" : "down"}</span></div>
                      </div>
                      <div>
                        <small>LINK HEALTH</small>
                        <Status active={online}>{label}</Status>
                        <small>mwan3 status is separate from the netifd interface-up flag.</small>
                      </div>
                      <div>
                        <small>TRACKER</small>
                        <b>{iface.tracking.toUpperCase()}</b>
                        <small>{iface.running ? "Tracker process running" : "Tracker process not running"}</small>
                      </div>
                      <div>
                        <small>LAST TRANSITION</small>
                        <b>{iface.age_seconds === undefined ? "N/A" : formatUptime(iface.age_seconds)}</b>
                        <small>Online {iface.online_seconds === undefined ? "N/A" : formatUptime(iface.online_seconds)} · offline {iface.offline_seconds === undefined ? "N/A" : formatUptime(iface.offline_seconds)}</small>
                      </div>
                      <div>
                        <small>TRACK COUNTERS</small>
                        <b>Score {iface.score === undefined ? "N/A" : fmt(iface.score)}</b>
                        <small>Lost {iface.lost === undefined ? "N/A" : fmt(iface.lost)} · turn {iface.turn === undefined ? "N/A" : fmt(iface.turn)}</small>
                        <small>MEASURED RX / TX</small>
                        <b>{delta?.rxMbps == null || delta?.txMbps == null ? "N/A · waiting for valid counters" : `${fmt(delta!.rxMbps!, 2)} / ${fmt(delta!.txMbps!, 2)} Mbps`}</b>
                        <small>{delta?.sampleSeconds == null ? "Sample interval N/A" : `Sample ${fmt(delta!.sampleSeconds!, 1)} s`}</small>
                      </div>
                      <div className="mwan3-targets">
                        <small>TRACKING TARGETS ({iface.track_targets.length})</small>
                        {iface.track_targets.length === 0 ? (
                          <b>No tracking targets reported</b>
                        ) : iface.track_targets.map((target) => (
                          <div key={target.ip}>
                            <b>{target.ip} · {target.status}</b>
                            <small>Latency {target.latency_ms === undefined ? "N/A" : fmt(target.latency_ms) + " ms"} · loss {target.packet_loss_percent === undefined ? "N/A" : fmt(target.packet_loss_percent) + "%"}</small>
                          </div>
                        ))}
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </>
        )}
        <div className="module-message">This inventory is read-only. “Online” requires both mwan3's online state and netifd's up flag; tracker-process state and per-target latency/loss are displayed separately. It does not change failover policy, route metrics, marks or interface configuration.</div>
      </Panel>

      <div className="module-grid mwan3-secondary-grid">
        <Panel title="Active load-balancing policies" eyebrow="MWAN3 · IPV4 / IPV6 · READ-ONLY">
          {!routerOverview ? (
            <div className="module-message">Waiting for authenticated router telemetry.</div>
          ) : !mwan3 ? (
            <div className="module-message">This router API does not report Multi-WAN policy data.</div>
          ) : !mwan3.policies_available ? (
            <div className="module-message">The active policy inventory is unavailable.</div>
          ) : mwan3.policies.length === 0 ? (
            <div className="module-message">mwan3 is available but no active policy weights were reported.</div>
          ) : (
            <div className="mwan3-policy-list">
              {mwan3.policies.map((policy) => (
                <div className="mwan3-policy-row" key={policy.family + "-" + policy.name}>
                  <div><small>{policy.family}</small><strong>{policy.name}</strong></div>
                  <div className="mwan3-policy-members">
                    {policy.members.length === 0 ? (
                      <span>No interface weights reported</span>
                    ) : policy.members.map((member) => (
                      <div key={member.interface}>
                        <span>{member.interface}</span>
                        <b>{fmt(member.percent, 1)}%</b>
                        <i><span style={{ width: Math.max(0, Math.min(100, member.percent)) + "%" }} /></i>
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          )}
          {mwan3?.truncated ? <div className="module-message">Some Multi-WAN telemetry was capped for response size.</div> : null}
          <div className="module-message">Percentages are the active mwan3 policy weights reported from firewall policy rules. They are not measured traffic shares or per-flow throughput.</div>
        </Panel>
        <Panel title="Connected WAN networks" eyebrow="MWAN3 · IPV4 / IPV6 · READ-ONLY">
          {!routerOverview ? (
            <div className="module-message">Waiting for authenticated router telemetry.</div>
          ) : !mwan3?.connected_available ? (
            <div className="module-message">The connected-network inventory is unavailable.</div>
          ) : (
            <div className="mwan3-connected-grid">
              <div>
                <strong>IPv4 networks</strong>
                {mwan3.connected_ipv4.length === 0 ? <span>None reported</span> : mwan3.connected_ipv4.map((network) => <code key={network}>{network}</code>)}
              </div>
              <div>
                <strong>IPv6 networks</strong>
                {mwan3.connected_ipv6.length === 0 ? <span>None reported</span> : mwan3.connected_ipv6.map((network) => <code key={network}>{network}</code>)}
              </div>
            </div>
          )}
          <div className="module-message">These are the networks mwan3 reports as directly connected. Their presence does not prove internet reachability or that a policy currently selects them.</div>
        </Panel>
      </div>

      <div className="module-grid">
        <Panel title="Wireless radio measurements" eyebrow="IWINFO · LIVE">
          <WirelessRadioInventory radios={radios} available={Boolean(routerOverview)} />
        </Panel>
        <Panel title="Live WAN throughput" eyebrow="SUCCESSIVE COUNTER SAMPLES">
          <div className="health-grid">
            <Health icon={Download} label="DOWNLOAD" value={stats.wanAvailable ? `${fmt(stats.download, 2)} Mbps` : "N/A"} />
            <Health icon={Upload} label="UPLOAD" value={stats.wanAvailable ? `${fmt(stats.upload, 2)} Mbps` : "N/A"} />
          </div>
          <div className="module-message">Throughput is calculated between successive WAN counter samples and requires two valid samples.</div>
        </Panel>
      </div>

      <Panel title="Associated Wi-Fi stations" eyebrow="IWINFO ASSOCIATION DATA">
        <WirelessClientList
          clients={wirelessClients}
          available={Array.isArray(routerOverview?.wireless_clients)}
          leases={routerOverview?.clients ?? []}
        />
      </Panel>
    </div>
  );
}

function DiagnosticsControlPage({
  stats,
  telemetryError,
  routerOverview,
  refresh,
}: {
  stats: Stats;
  telemetryError: string;
  routerOverview: RouterOverview | null;
  refresh: () => void;
}) {
  const wanInterfaces = routerOverview?.interfaces.filter((item) => item.is_wan) ?? [];
  const lastSample = routerOverview
    ? new Date(routerOverview.timestamp * 1000).toLocaleString()
    : "N/A";
  const [latencyTest, setLatencyTest] = useState<RouterLatencyTest | null>(null);
  const [testingLatency, setTestingLatency] = useState(false);
  const [latencyTestError, setLatencyTestError] = useState("");

  const runLatencyTest = async () => {
    setTestingLatency(true);
    setLatencyTestError("");
    try {
      setLatencyTest(await runRouterLatencyTest());
    } catch (error) {
      setLatencyTestError(error instanceof Error ? error.message : "The latency test failed.");
    } finally {
      setTestingLatency(false);
    }
  };

  return (
    <div className="module-page">
      <section className="module-hero">
        <div className="module-icon"><Activity size={25} /></div>
        <div>
          <div className="setup-kicker">READ-ONLY CONNECTIVITY CHECKS</div>
          <h1>Diagnostics</h1>
          <p>Inspect authenticated router telemetry and run an on-demand, five-packet ICMP latency test to a fixed public target.</p>
          <button className="hero-button" onClick={refresh}><RefreshCw size={16} /> Refresh diagnostics</button>
        </div>
      </section>

      <div className="metrics">
        <Metric title="Internet Probe" value={routerOverview ? (stats.reachable ? "ONLINE" : "NO REPLY") : "N/A"} unit="" detail="Single ICMP target · 1.1.1.1" icon={Signal} />
        <Metric title="Latest latency" value={stats.latency === null ? "N/A" : fmt(stats.latency, 1)} unit={stats.latency === null ? "" : "ms"} detail="One-packet telemetry sample" icon={Activity} />
        <Metric title="Measured packet loss" value={latencyTest ? fmt(latencyTest.packet_loss_percent, 1) : "N/A"} unit={latencyTest ? "%" : ""} detail="Five-packet diagnostic window" icon={CircleGauge} />
        <Metric title="Measured jitter" value={latencyTest?.jitter_ms === undefined ? "N/A" : fmt(latencyTest.jitter_ms, 1)} unit={latencyTest?.jitter_ms === undefined ? "" : "ms"} detail="Mean consecutive RTT difference" icon={Activity} />
        <Metric title="WAN Links Up" value={routerOverview ? fmt(wanInterfaces.filter((item) => item.up).length) : "N/A"} unit={routerOverview ? `/${wanInterfaces.length}` : ""} detail="Reported WAN interfaces" icon={Globe2} />
      </div>

      <div className="module-grid">
        <Panel title="Probe details" eyebrow="CONNECTIVITY">
          <InfoRows rows={[
            ["ROUTER API", telemetryError ? "ERROR" : routerOverview ? "AUTHENTICATED" : "WAITING"],
            ["TARGET", "1.1.1.1 · ICMP"],
            ["RESULT", routerOverview ? (stats.reachable ? "REPLY RECEIVED" : "NO REPLY") : "NOT SAMPLED"],
            ["LAST SAMPLE", lastSample],
          ]} />
          {telemetryError && <div className="module-message">{telemetryError}</div>}
        </Panel>
        <Panel title="WAN interface checks" eyebrow="ROUTER REPORTED STATE">
          {wanInterfaces.length === 0 ? (
            <div className="module-message">{routerOverview ? "No WAN interface was identified by the router API." : "Waiting for router interface telemetry."}</div>
          ) : (
            <InfoRows rows={wanInterfaces.map((item) => [
              item.name,
              item.up ? "LINK UP" : "LINK DOWN",
            ])} />
          )}
        </Panel>
      </div>

      <Panel title="Multi-packet latency test" eyebrow="ON-DEMAND · FIVE ICMP PACKETS">
        <div className="module-message">Sends five ICMP echo requests from the router to the fixed target 1.1.1.1. The router caches results for 30 seconds to protect low-resource devices.</div>
        <button className="hero-button" onClick={runLatencyTest} disabled={testingLatency}>
          <Activity size={16} /> {testingLatency ? "Running five-packet test…" : "Run latency test"}
        </button>
        {latencyTestError && <div className="module-message" role="alert">{latencyTestError}</div>}
        {latencyTest && (
          <InfoRows rows={[
            ["TARGET", latencyTest.target],
            ["PACKETS", `${latencyTest.packets_received} / ${latencyTest.packets_sent} received`],
            ["PACKET LOSS", `${fmt(latencyTest.packet_loss_percent, 1)}%`],
            ["RTT MIN / AVG / MAX", [latencyTest.min_ms, latencyTest.average_ms, latencyTest.max_ms].map((value) => value === undefined ? "N/A" : `${fmt(value, 2)} ms`).join(" / ")],
            ["JITTER", latencyTest.jitter_ms === undefined ? "N/A · fewer than two replies" : `${fmt(latencyTest.jitter_ms, 2)} ms`],
            ["JITTER METHOD", latencyTest.jitter_method],
            ["SAMPLED AT", new Date(latencyTest.sampled_at * 1000).toLocaleString()],
            ["CACHE", latencyTest.cached ? `CACHED · retry in ${latencyTest.retry_after_seconds ?? 0}s` : "FRESH"],
          ]} />
        )}
      </Panel>
      <Panel title="Measurement boundaries" eyebrow="INTERPRETING THE NUMBERS">
        <div className="module-message">Packet loss is the missing-reply fraction within these five requests to this one target. Jitter is the mean absolute difference between consecutive successful RTT samples, not an RFC 3550 RTP jitter value. This is an on-demand unloaded-route sample, not a controlled bufferbloat test, continuous monitor, DNS test or proof that every Internet destination is reachable.</div>
      </Panel>
    </div>
  );
}

function RemoteSyslogSettings({ status, refresh }: {
  status?: RouterRemoteSyslogStatus;
  refresh: () => void;
}) {
  const [enabled, setEnabled] = useState(status?.enabled ?? false);
  const [host, setHost] = useState(status?.host ?? "");
  const [port, setPort] = useState(String(status?.port ?? 514));
  const [protocol, setProtocol] = useState<"tcp" | "udp">(status?.protocol ?? "udp");
  const [hostname, setHostname] = useState(status?.hostname ?? "");
  const [prefix, setPrefix] = useState(status?.prefix ?? "");
  const [confirmed, setConfirmed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<{ success: boolean; message: string } | null>(null);

  const save = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!confirmed || busy || !status?.service_installed || !status.config_available) return;
    setBusy(true);
    setNotice(null);
    try {
      const result = await updateRouterRemoteSyslog({
        enabled,
        host: host.trim(),
        port: Number(port),
        protocol,
        hostname: hostname.trim(),
        prefix: prefix.trim(),
      });
      setEnabled(result.enabled);
      setHost(result.host);
      setPort(String(result.port));
      setProtocol(result.protocol);
      setHostname(result.hostname);
      setPrefix(result.prefix);
      setConfirmed(false);
      setNotice({
        success: true,
        message: result.enabled
          ? "Remote syslog forwarding is enabled to " + result.host + ":" + result.port + " over " + result.protocol.toUpperCase() + "."
          : "Remote syslog forwarding has been disabled.",
      });
      refresh();
    } catch (cause) {
      setNotice({
        success: false,
        message: cause instanceof Error ? cause.message : "Remote syslog settings could not be updated.",
      });
    } finally {
      setBusy(false);
    }
  };

  return (
    <Panel
      title="Remote system logging"
      eyebrow="NATIVE OPENWRT LOGREAD · CENTRAL OFFICE COLLECTION"
      action={<Status active={Boolean(status?.enabled)}>{status?.enabled ? "FORWARDING" : status?.available ? "DISABLED" : "UNAVAILABLE"}</Status>}
    >
      {!status?.service_installed || !status.config_available ? (
        <div className="module-message">The native OpenWrt log service or system configuration is unavailable on this firmware.</div>
      ) : (
        <form className="remote-syslog-form" onSubmit={save}>
          <div className="remote-syslog-warning" role="note">
            <strong>Transport is not encrypted.</strong>
            <span>OpenWrt's built-in forwarder supports TCP or UDP syslog, not TLS. Use a trusted management network or VPN between the router and log collector. Do not send operational logs across an untrusted public network.</span>
          </div>
          <label className="remote-syslog-enabled">
            <input type="checkbox" checked={enabled} disabled={busy} onChange={(event) => setEnabled(event.target.checked)} />
            <span>Enable remote syslog forwarding</span>
          </label>
          {enabled && (
            <div className="remote-syslog-fields">
              <label>
                <span>Server IPv4 / DNS name</span>
                <input type="text" value={host} onChange={(event) => setHost(event.target.value)} placeholder="syslog.office.example" maxLength={253} required />
              </label>
              <label>
                <span>Port</span>
                <input type="number" value={port} onChange={(event) => setPort(event.target.value)} min={1} max={65535} step={1} required />
              </label>
              <label>
                <span>Transport</span>
                <select value={protocol} onChange={(event) => setProtocol(event.target.value as "tcp" | "udp")}>
                  <option value="udp">UDP</option>
                  <option value="tcp">TCP</option>
                </select>
              </label>
              <label>
                <span>Sender hostname (optional)</span>
                <input type="text" value={hostname} onChange={(event) => setHostname(event.target.value)} placeholder="aw1000-office-router" maxLength={253} />
              </label>
              <label>
                <span>Message prefix (optional)</span>
                <input type="text" value={prefix} onChange={(event) => setPrefix(event.target.value)} placeholder="office-site1" maxLength={32} />
              </label>
            </div>
          )}
          <label className="remote-syslog-confirm">
            <input
              type="checkbox"
              checked={confirmed}
              disabled={busy}
              onChange={(event) => setConfirmed(event.target.checked)}
            />
            <span>I confirm this destination and authorize QuantumGrid to update the native system logging settings and restart the log service.</span>
          </label>
          <div className="remote-syslog-actions">
            <button className="hero-button" type="submit" disabled={!confirmed || busy || (enabled && (!host.trim() || !port))}>
              <Check size={14} /> {busy ? "Applying logging…" : "Apply remote logging"}
            </button>
            <span>Local log buffering stays enabled. Changes are limited to the native remote destination options and can be disabled here.</span>
          </div>
          {notice && (
            <div className={notice.success ? "module-message remote-syslog-success" : "module-message remote-syslog-error"} role={notice.success ? "status" : "alert"}>
              {notice.message}
            </div>
          )}
        </form>
      )}
    </Panel>
  );
}


function SystemControlPage({ routerOverview, stats, refresh }: { routerOverview: RouterOverview | null; stats: Stats; refresh: () => void }) {
  const memory = routerOverview?.system.memory;
  const load = routerOverview?.system.load_avg ?? [];
  const [backupConfirmed, setBackupConfirmed] = useState(false);
  const [backupBusy, setBackupBusy] = useState(false);
  const [backupNotice, setBackupNotice] = useState<{ success: boolean; message: string } | null>(null);

  const createBackup = async () => {
    if (!backupConfirmed || backupBusy) return;
    setBackupBusy(true);
    setBackupNotice(null);
    try {
      await downloadRouterConfigBackup();
      setBackupNotice({ success: true, message: "The configuration archive was generated and sent to this browser. Store it in encrypted private storage." });
      setBackupConfirmed(false);
    } catch (error) {
      setBackupNotice({
        success: false,
        message: error instanceof Error ? error.message : "The configuration backup failed.",
      });
    } finally {
      setBackupBusy(false);
    }
  };

  return (
    <div className="module-page">
      <section className="module-hero">
        <div className="module-icon"><Cpu size={25} /></div>
        <div>
          <div className="setup-kicker">LIVE HARDWARE TELEMETRY</div>
          <h1>System</h1>
          <p>CPU, memory, temperature, uptime and load averages reported by the AW1000 router.</p>
        </div>
      </section>
      <div className="metrics">
        <Metric title="CPU Utilisation" value={stats.cpu === null ? "N/A" : fmt(stats.cpu, 1)} unit={stats.cpu === null ? "" : "%"} detail="Kernel-derived sample" icon={Cpu} />
        <Metric title="Memory Used" value={stats.ram === null ? "N/A" : fmt(stats.ram, 1)} unit={stats.ram === null ? "" : "%"} detail={memory ? `${fmt(memory.available_kib / 1024, 0)} MiB available` : "Unavailable"} icon={Database} />
        <Metric title="Temperature" value={stats.temp === null ? "N/A" : fmt(stats.temp, 1)} unit={stats.temp === null ? "" : "°C"} detail="First available thermal zone" icon={Thermometer} />
        <Metric title="Uptime" value={formatUptime(routerOverview?.system.uptime_seconds)} unit="" detail="Since the last boot" icon={HardDrive} />
      </div>
      <div className="module-grid">
        <Panel title="System load" eyebrow="1 / 5 / 15 MINUTES">
          <InfoRows rows={[
            ["1 MIN", load[0] === undefined ? "N/A" : fmt(load[0], 2)],
            ["5 MIN", load[1] === undefined ? "N/A" : fmt(load[1], 2)],
            ["15 MIN", load[2] === undefined ? "N/A" : fmt(load[2], 2)],
          ]} />
        </Panel>
        <Panel title="Memory inventory" eyebrow="PROC / MEMINFO">
          <InfoRows rows={[
            ["TOTAL", memory ? `${fmt(memory.total_kib / 1024, 0)} MiB` : "N/A"],
            ["AVAILABLE", memory ? `${fmt(memory.available_kib / 1024, 0)} MiB` : "N/A"],
            ["USED", stats.ram === null ? "N/A" : `${fmt(stats.ram, 1)}%`],
          ]} />
        </Panel>
      </div>
      <div className="module-message">Values are reported by the router API; some hardware/firmware builds may not expose CPU, memory or thermal data for every sample.</div>
      <RemoteSyslogSettings
        key={JSON.stringify(routerOverview?.remote_syslog ?? null)}
        status={routerOverview?.remote_syslog}
        refresh={refresh}
      />
      <Panel title="Configuration backup" eyebrow="NATIVE SYSUPGRADE · PRIVATE RECOVERY ARCHIVE">
        <div className="config-backup-warning" role="note">
          <strong>This archive contains secrets.</strong>
          <span>It may include administrator credentials, Wi-Fi passphrases, VPN private keys, certificates and other private configuration. Download it only to a trusted device, store it encrypted, restrict access and never email it or publish it in support logs.</span>
        </div>
        <label className="config-backup-confirm">
          <input
            type="checkbox"
            checked={backupConfirmed}
            disabled={backupBusy}
            onChange={(event) => setBackupConfirmed(event.target.checked)}
          />
          <span>I understand the archive contains sensitive router configuration and have a secure place to store it.</span>
        </label>
        <div className="config-backup-actions">
          <button className="hero-button" onClick={() => { void createBackup(); }} disabled={!backupConfirmed || backupBusy}>
            <Download size={15} /> {backupBusy ? "Creating backup…" : "Create & download backup"}
          </button>
          <span>Generated by the router's native sysupgrade backup operation. Does not reboot or change router configuration.</span>
        </div>
        {backupNotice && (
          <div className={backupNotice.success ? "module-message config-backup-success" : "module-message config-backup-error"} role={backupNotice.success ? "status" : "alert"}>
            {backupNotice.message}
          </div>
        )}
        <div className="module-message">A backup is not a firmware image and should only be restored to a compatible device and firmware build. QuantumGrid does not currently provide a one-click restore operation; use the documented recovery process and retain a separate recovery route before any firmware change.</div>
      </Panel>
    </div>
  );
}

function AnalyticsControlPage({ stats, trafficHistory }: { stats: Stats; trafficHistory: number[] }) {
  const peak = trafficHistory.length > 0 ? Math.max(...trafficHistory) : 0;
  const average = trafficHistory.length > 0
    ? trafficHistory.reduce((sum, value) => sum + value, 0) / trafficHistory.length
    : 0;
  const maximum = Math.max(1, peak);
  const current = stats.wanAvailable ? stats.download + stats.upload : 0;

  return (
    <div className="module-page">
      <section className="module-hero">
        <div className="module-icon"><Database size={25} /></div>
        <div>
          <div className="setup-kicker">MEASURED WAN COUNTERS</div>
          <h1>Analytics</h1>
          <p>Short-window WAN throughput history derived from successive kernel byte-counter samples.</p>
        </div>
      </section>
      <div className="metrics">
        <Metric title="Current Combined" value={stats.wanAvailable ? fmt(current, 2) : "N/A"} unit={stats.wanAvailable ? "Mbps" : ""} detail="Download + upload" icon={Activity} />
        <Metric title="Window Peak" value={stats.wanAvailable ? fmt(peak, 2) : "N/A"} unit={stats.wanAvailable ? "Mbps" : ""} detail="Highest 30-sample total" icon={Signal} />
        <Metric title="Window Average" value={stats.wanAvailable ? fmt(average, 2) : "N/A"} unit={stats.wanAvailable ? "Mbps" : ""} detail="Average sample total" icon={CircleGauge} />
        <Metric title="Sample Count" value={stats.wanAvailable ? fmt(trafficHistory.length) : "N/A"} unit="" detail="Approximately 90 seconds" icon={Database} />
      </div>
      <Panel title="WAN throughput history" eyebrow="30 SAMPLES · 3 SECOND REFRESH" action={<Status active={stats.wanAvailable}>{stats.wanAvailable ? "LIVE" : "WAITING"}</Status>}>
        <div className="traffic-demo">
          {trafficHistory.map((value, index) => {
            const height = value > 0 ? Math.max(3, (value / maximum) * 90) : 3;
            return <div className="traffic-column" key={index}><span style={{ height: `${height}%` }} /></div>;
          })}
        </div>
        <div className="traffic-labels"><span>OLDEST</span><span>~45s</span><span>NOW</span></div>
        <div className="module-message">This is an in-memory rolling window. It resets when the QuantumGrid page reloads and is not a historical usage/accounting database.</div>
      </Panel>
    </div>
  );
}

const cellularSignalSeries = [
  { key: "rssi_dbm", label: "RSSI", unit: "dBm" },
  { key: "rsrp_dbm", label: "RSRP", unit: "dBm" },
  { key: "rsrq_db", label: "RSRQ", unit: "dB" },
  { key: "snr_db", label: "SNR", unit: "dB" },
] as const;

function CellularSignalHistory({ history }: { history: CellularHistorySample[] }) {
  const latest = history[history.length - 1];
  const exportHistory = () => {
    if (history.length === 0) return;
    const exportedAt = new Date().toISOString();
    const rows: Array<Array<string | number | null | undefined>> = [
      ["Exported at (UTC)", "Sampled at (UTC)", "RSSI dBm", "RSRP dBm", "RSRQ dB", "SNR dB"],
      ...history.map((sample) => [
        exportedAt, new Date(sample.sampledAt * 1000).toISOString(),
        sample.rssi_dbm, sample.rsrp_dbm, sample.rsrq_db, sample.snr_db,
      ]),
    ];
    const csv = rows.map((row) => row.map(csvCell).join(",")).join("\r\n");
    const objectUrl = URL.createObjectURL(new Blob(["\uFEFF", csv], { type: "text/csv;charset=utf-8" }));
    const link = document.createElement("a");
    link.href = objectUrl;
    link.download = "quantumgrid-cellular-rf-history-" + exportedAt.replace(/[:.]/g, "-") + ".csv";
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(objectUrl), 0);
  };

  return (
    <Panel
      title="5G RF signal history"
      eyebrow="UP TO 30 DISTINCT QMI READINGS"
      action={
        <div className="rf-history-actions">
          <Status active={history.length > 0}>{history.length > 0 ? `${history.length} SAMPLES` : "WAITING"}</Status>
          <button className="hero-button wifi-export-button" onClick={exportHistory} disabled={history.length === 0}>Export RF history CSV</button>
        </div>
      }
    >
      {history.length === 0 ? (
        <div className="module-message">Waiting for the modem to return numeric RF measurements. No sample is generated when the modem does not report a value.</div>
      ) : (
        <div className="rf-history">
          {cellularSignalSeries.map((metric) => {
            const readings = history.map((sample) => sample[metric.key]);
            const values = readings.filter((value): value is number => value !== null && Number.isFinite(value));
            const minimum = values.length > 0 ? Math.min(...values) : 0;
            const maximum = values.length > 0 ? Math.max(...values) : 0;
            const current = values[values.length - 1];

            return (
              <div className="rf-history-row" key={metric.key}>
                <div className="rf-history-heading">
                  <strong>{metric.label}</strong>
                  <span>{current === undefined ? "NOT REPORTED" : `${fmt(current, 1)} ${metric.unit}`}</span>
                </div>
                <div className="rf-history-track" role="img" aria-label={`${metric.label} history across ${history.length} distinct modem samples`}>
                  {readings.map((value, index) => {
                    const height = value === null
                      ? 4
                      : maximum === minimum
                        ? 52
                        : 10 + ((value - minimum) / (maximum - minimum)) * 90;
                    const title = value === null
                      ? `${metric.label}: not reported`
                      : `${metric.label}: ${fmt(value, 1)} ${metric.unit}`;

                    return (
                      <div className="rf-history-column" key={history[index].sampledAt}>
                        <span
                          className={value === null ? "rf-history-gap" : ""}
                          style={{ height: `${height}%` }}
                          title={title}
                          aria-hidden="true"
                        />
                      </div>
                    );
                  })}
                </div>
              </div>
            );
          })}
        </div>
      )}
      {latest && (
        <div className="module-message">
          {history.length} unique modem samples · Last sample {new Date(latest.sampledAt * 1000).toLocaleTimeString()}. Bar heights compare readings within this session only; they are not a coverage or signal-quality grade.
        </div>
      )}
    </Panel>
  );
}

function CellularControlPage({ routerOverview, cellularHistory }: { routerOverview: RouterOverview | null; cellularHistory: CellularHistorySample[] }) {
  const cellular = routerOverview?.cellular;
  const detected = cellular?.modem_present ?? false;
  const registered = cellular?.registered === true;
  const signalValue = (value: number | undefined, suffix: string) =>
    value === undefined ? "N/A" : `${fmt(value, 1)} ${suffix}`;
  const radio = cellular?.radio_interfaces?.length
    ? cellular.radio_interfaces.join(", ").toUpperCase()
    : cellular?.signal_type?.toUpperCase() || "N/A";
  const plmn = cellular?.mcc && cellular?.mnc
    ? `${cellular.mcc}-${cellular.mnc}`
    : "N/A";

  return (
    <div className="module-page">
      <section className="module-hero">
        <div className="module-icon"><Signal size={25} /></div>
        <div>
          <div className="setup-kicker">AW1000 CELLULAR HARDWARE · QMI</div>
          <h1>5G Modem</h1>
          <p>Read-only Quectel modem registration, serving-network, data-session and RF measurements from uqmi where the modem exposes them.</p>
        </div>
      </section>

      <div className="metrics">
        <Metric title="Modem" value={cellular ? (detected ? "DETECTED" : "NOT FOUND") : "N/A"} unit="" detail="AW1000 modem device presence" icon={Signal} />
        <Metric title="Network Registration" value={!cellular?.qmi_available ? "N/A" : registered ? "REGISTERED" : (cellular.registration || "UNKNOWN").toUpperCase()} unit="" detail="QMI serving-system status" icon={Globe2} />
        <Metric title="Radio Technology" value={radio} unit="" detail="Serving radio interface" icon={RadioTower} />
        <Metric title="Data Session" value={cellular?.data_status ? cellular.data_status.toUpperCase() : "N/A"} unit="" detail="QMI packet-data status" icon={Activity} />
      </div>

      <div className="module-grid">
        <Panel title="RF signal measurements" eyebrow="QMI NAS · READ ONLY" action={<Status active={Boolean(cellular?.qmi_available)}>{cellular?.qmi_available ? "QMI AVAILABLE" : detected ? "QMI NOT AVAILABLE" : "WAITING"}</Status>}>
          {cellular?.qmi_available ? (
            <div className="metrics">
              <Metric title="RSSI" value={signalValue(cellular.rssi_dbm, "dBm")} unit="" detail="Received signal strength" icon={Signal} />
              <Metric title="RSRP" value={signalValue(cellular.rsrp_dbm, "dBm")} unit="" detail="Reference signal power" icon={Activity} />
              <Metric title="RSRQ" value={signalValue(cellular.rsrq_db, "dB")} unit="" detail="Reference signal quality" icon={CircleGauge} />
              <Metric title="SNR" value={signalValue(cellular.snr_db, "dB")} unit="" detail="Signal-to-noise ratio" icon={RadioTower} />
            </div>
          ) : (
            <div className="module-message">{detected ? "A modem device node exists, but /dev/cdc-wdm0 or uqmi is unavailable for QMI measurements." : "Waiting for an accessible QMI modem control device."}</div>
          )}
        </Panel>

        <Panel title="Serving network" eyebrow="REGISTRATION / OPERATOR">
          <InfoRows rows={[
            ["REGISTRATION", cellular?.registration ? cellular.registration.toUpperCase() : "N/A"],
            ["OPERATOR", cellular?.operator || "N/A"],
            ["MCC / MNC", plmn],
            ["ROAMING", cellular?.roaming === undefined ? "N/A" : cellular.roaming ? "YES" : "NO"],
            ["RADIO", radio],
          ]} />
          <div className="module-message">Operator and radio fields appear only when returned by the modem. No band or cell identity is inferred from signal values.</div>
        </Panel>
      </div>

      <Panel title="Modem telemetry freshness" eyebrow="QMI SAMPLE CACHE">
        <InfoRows rows={[
          ["CONTROL DEVICE", cellular?.device || "N/A"],
          ["QMI CLIENT", cellular?.qmi_available ? "AVAILABLE" : "UNAVAILABLE"],
          ["LAST SAMPLE", cellular?.sampled_at ? new Date(cellular.sampled_at * 1000).toLocaleTimeString() : "N/A"],
          ["DATA SESSION", cellular?.data_status ? cellular.data_status.toUpperCase() : "N/A"],
        ]} />
        <div className="module-message">Read-only queries are cached for eight seconds. The page does not change network mode, APN, roaming, registration, SIM PIN or data-session state. IMEI, IMSI and SIM credentials are never requested.</div>
      </Panel>

      <CellularSignalHistory history={cellularHistory} />
    </div>
  );
}


function SecurityControlPage({ routerOverview, wireGuardPeerRates }: { routerOverview: RouterOverview | null; wireGuardPeerRates: Map<string, WireGuardPeerMeasuredRate> }) {
  const security = routerOverview?.security;
  const zones = security?.zones ?? [];
  const fw4Present = security?.nft_tables.includes("inet/fw4") ?? false;
  const nftRuntime = security?.nft_runtime;
  const activeWireGuard = security?.vpn.wireguard_interfaces.filter((item) => item.up) ?? [];
  const wireGuardPeers = security?.vpn.wireguard_peers ?? [];
  const wireGuardPeersAvailable = security?.vpn.wireguard_peers_available === true;
  const firewallPosture = auditFirewallPosture(security);
  const [firewallRuleSearch, setFirewallRuleSearch] = useState("");
  const [firewallRuleSort, setFirewallRuleSort] = useState<"name" | "source" | "destination" | "target">("source");
  const firewallRules = security?.rules ?? [];
  const firewallRedirects = security?.redirects ?? [];
  const [firewallRedirectSearch, setFirewallRedirectSearch] = useState("");
  const visibleFirewallRedirects = firewallRedirects.filter((redirect) => [
    redirect.name, redirect.source_zone, redirect.destination_zone, redirect.protocol,
    redirect.target, redirect.family, redirect.external_port, redirect.internal_port,
  ].some((value) => value.toLocaleLowerCase().includes(firewallRedirectSearch.trim().toLocaleLowerCase())));
  const reviewedRedirectNames = new Set(
    firewallPosture.checks
      .filter((check) => check.id.startsWith("external-redirect:"))
      .map((check) => check.id.slice("external-redirect:".length)),
  );
  const wideRedirectNames = new Set(
    firewallPosture.checks
      .filter((check) => check.id.startsWith("external-redirect-any-port:"))
      .map((check) => check.id.slice("external-redirect-any-port:".length)),
  );
  const adminRedirectNames = new Set(
    firewallPosture.checks
      .filter((check) => check.id.startsWith("external-redirect-admin-service:"))
      .map((check) => check.id.slice("external-redirect-admin-service:".length)),
  );
  const externalAllowRuleNames = new Set(
    firewallPosture.checks
      .filter((check) => check.id.startsWith("external-allow-rule:"))
      .map((check) => check.id.slice("external-allow-rule:".length)),
  );
  const visibleFirewallRules = firewallRules
    .filter((rule) => [
      rule.name, rule.source_zone, rule.destination_zone, rule.protocol,
      rule.target, rule.family, rule.source_port, rule.destination_port,
    ].some((value) => value.toLocaleLowerCase().includes(firewallRuleSearch.trim().toLocaleLowerCase())))
    .slice()
    .sort((left, right) => {
      if (firewallRuleSort === "name") return left.name.localeCompare(right.name);
      if (firewallRuleSort === "destination") return left.destination_zone.localeCompare(right.destination_zone);
      if (firewallRuleSort === "target") return left.target.localeCompare(right.target);
      return left.source_zone.localeCompare(right.source_zone) || left.name.localeCompare(right.name);
    });
  const exportSecurityInventory = () => {
    if (!security) return;
    const exportedAt = new Date().toISOString();
    const rows: Array<Array<string | number | boolean | null | undefined>> = [
      ["Exported at (UTC)", "Category", "Item", "Status", "Details"],
      [exportedAt, "Firewall", "Init service", security.firewall_installed ? "INSTALLED" : "MISSING", ""],
      [exportedAt, "Firewall", "Configuration", security.firewall_config_readable ? "READABLE" : "UNAVAILABLE", ""],
      [exportedAt, "Firewall", "Rules", "REPORTED", security.rules_count],
      [exportedAt, "Firewall", "Redirects", "REPORTED", security.redirects_count],
      [exportedAt, "Firewall", "Redirect sample coverage", security.redirects_truncated ? "TRUNCATED" : "COMPLETE", "Returned " + firewallRedirects.length + " of " + security.redirects_count + " configured redirects"],
      [exportedAt, "Firewall", "fw4 table", fw4Present ? "PRESENT" : "NOT FOUND", "inet/fw4"],
      [exportedAt, "Firewall runtime", "fw4 chain snapshot", nftRuntime?.available ? "PARSED" : nftRuntime?.table_present ? "UNAVAILABLE" : "NOT PRESENT", "chains=" + (nftRuntime?.chain_count ?? 0) + "; rules=" + (nftRuntime?.rule_count ?? 0) + "; truncated=" + (nftRuntime?.truncated ?? false)],
      ...(nftRuntime?.chains ?? []).map((chain) => [
        exportedAt, "Firewall runtime chain", chain.name, chain.policy.toUpperCase(),
        "hook=" + (chain.hook || "base chain") + "; type=" + chain.type + "; priority=" + (chain.priority ?? "unknown") + "; device=" + (chain.device || "any") + "; rules=" + chain.rule_count,
      ]),
      ...zones.map((zone) => [
        exportedAt, "Firewall zone", zone.name, "REPORTED",
        "networks=" + zone.networks.join(" ") + "; input=" + zone.input + "; output=" + zone.output +
          "; forward=" + zone.forward + "; masquerade=" + (zone.masquerade ? "on" : "off"),
      ]),
      ...firewallRules.map((rule) => [
        exportedAt, "Firewall rule", rule.name, rule.enabled ? "ENABLED" : "DISABLED",
        "source=" + (rule.source_zone || "any") + "; destination=" + (rule.destination_zone || "any") +
          "; protocol=" + (rule.protocol || "any") + "; target=" + rule.target +
          "; family=" + (rule.family || "any") + "; source_port=" + (rule.source_port || "any") +
          "; destination_port=" + (rule.destination_port || "any") +
          "; source_ip_match=" + rule.source_ip_match +
          "; destination_ip_match=" + rule.destination_ip_match +
          "; source_mac_match=" + rule.source_mac_match,
      ]),
      ...firewallRedirects.map((redirect) => [
        exportedAt, "Firewall NAT redirect", redirect.name,
        redirect.enabled ? "ENABLED" : "DISABLED",
        "source=" + (redirect.source_zone || "any") +
          "; destination=" + (redirect.destination_zone || "any") +
          "; protocol=" + (redirect.protocol || "any") +
          "; target=" + (redirect.target || "unspecified") +
          "; external_port=" + (redirect.external_port || "any") +
          "; internal_port=" + (redirect.internal_port || "same/unspecified") +
          "; destination_host_configured=" + redirect.destination_ip_match +
          "; source_ip_restricted=" + redirect.source_ip_match +
          "; source_mac_restricted=" + redirect.source_mac_match,
      ]),
      ...firewallPosture.checks.map((check) => [
        exportedAt, "Firewall posture review", check.title, check.status.toUpperCase(),
        check.scope + ": " + check.detail,
      ]),
      ...security.nft_tables.map((table) => [exportedAt, "nftables table", table, table === "inet/fw4" ? "FIREWALL4" : "PRESENT", ""]),
      [exportedAt, "Adblock Fast", "Init service", security.adblock_fast.installed ? "INSTALLED" : "MISSING", ""],
      [exportedAt, "Adblock Fast", "Configuration file", security.adblock_fast.config_available ? "PRESENT" : "MISSING", ""],
      [exportedAt, "Adblock Fast", "Configured enabled", security.adblock_fast.configured_enabled ? "YES" : "NO", "Configuration state only; not a live blocking test"],
      [exportedAt, "VPN", "WireGuard tool", security.vpn.wireguard_tool_installed ? "INSTALLED" : "MISSING", ""],
      [exportedAt, "VPN", "OpenVPN service", security.vpn.openvpn_service_installed ? "INSTALLED" : "MISSING", ""],
      [exportedAt, "VPN", "OpenVPN enabled instances", "REPORTED", security.vpn.openvpn_enabled_instances],
      ...security.vpn.wireguard_interfaces.map((iface) => [
        exportedAt, "WireGuard interface", iface.name, iface.up ? "UP" : "DOWN", iface.device,
      ]),
      [exportedAt, "WireGuard", "Peer telemetry", wireGuardPeersAvailable ? "AVAILABLE" : "UNAVAILABLE", security.vpn.wireguard_tool_installed ? "wg tool installed" : "wg tool not installed"],
      ...wireGuardPeers.map((peer) => {
        const rate = wireGuardPeerRates.get(wireGuardPeerCounterKey(peer));
        return [
          exportedAt, "WireGuard peer", peer.interface,
          peer.handshake_seen ? "HANDSHAKE SEEN" : "NO VALID HANDSHAKE",
          "handshake_age_seconds=" + (peer.handshake_age_seconds === undefined ? "unknown" : peer.handshake_age_seconds) +
            "; rx_bytes=" + peer.receive_bytes +
            "; tx_bytes=" + peer.transmit_bytes +
            "; measured_rx_mbps=" + (rate?.receiveMbps ?? "unknown") +
            "; measured_tx_mbps=" + (rate?.transmitMbps ?? "unknown") +
            "; sample_seconds=" + (rate?.sampleSeconds ?? "unknown") +
            "; allowed_ips=" + peer.allowed_ips.join(" "),
        ];
      }),
    ];
    const csv = rows.map((row) => row.map(csvCell).join(",")).join("\r\n");
    const objectUrl = URL.createObjectURL(new Blob(["\uFEFF", csv], { type: "text/csv;charset=utf-8" }));
    const link = document.createElement("a");
    link.href = objectUrl;
    link.download = "quantumgrid-security-inventory-" + exportedAt.replace(/[:.]/g, "-") + ".csv";
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(objectUrl), 0);
  };

  return (
    <div className="module-page">
      <section className="module-hero">
        <div className="module-icon"><Shield size={25} /></div>
        <div>
          <div className="setup-kicker">FIREWALL · DNS FILTERING · VPN</div>
          <h1>Security Center</h1>
          <p>Read-only firewall zone policy, nftables table presence, Adblock Fast configuration and VPN interface status from the authenticated router API.</p>
          <button className="hero-button security-export-button" onClick={exportSecurityInventory} disabled={!security}>Export security inventory CSV</button>
        </div>
      </section>

      <div className="metrics">
        <Metric title="Firewall Service" value={security ? (security.firewall_installed ? "INSTALLED" : "MISSING") : "N/A"} unit="" detail="firewall4 init service" icon={Shield} />
        <Metric title="fw4 nftables Table" value={security ? (fw4Present ? "PRESENT" : "NOT FOUND") : "N/A"} unit="" detail="inet/fw4 runtime table" icon={Network} />
        <Metric title="Firewall Zones" value={security?.firewall_config_readable ? fmt(zones.length) : "N/A"} unit="" detail="UCI zone sections" icon={Settings} />
        <Metric title="Rules / Redirects" value={security?.firewall_config_readable ? `${fmt(security.rules_count)} / ${fmt(security.redirects_count)}` : "N/A"} unit="" detail="Configured firewall entries" icon={Activity} />
      </div>

      <Panel title="Firewall posture review" eyebrow="READ-ONLY CONFIGURATION CHECKS">
        <div className="firewall-posture-summary">
          <div><small>REVIEW ITEMS</small><strong>{fmt(firewallPosture.reviewCount)}</strong></div>
          <div><small>RESTRICTIVE CHECKS</small><strong>{fmt(firewallPosture.okCount)}</strong></div>
          <div><small>UNKNOWN / NOT TESTED</small><strong>{fmt(firewallPosture.unknownCount)}</strong></div>
        </div>
        <div className="firewall-posture-list">
          {firewallPosture.checks.map((check) => (
            <div className={"firewall-posture-item " + check.status} key={check.id}>
              <div className="firewall-posture-heading">
                <div><strong>{check.title}</strong><span>{check.scope}</span></div>
                <Status active={check.status === "ok"}>{check.status === "ok" ? "OK" : check.status === "review" ? "REVIEW" : "UNKNOWN"}</Status>
              </div>
              <p>{check.detail}</p>
            </div>
          ))}
        </div>
        <div className="module-message">This is a narrow configuration review, not a vulnerability scan. External zones are identified only by standard WAN/WWAN naming. Enabled ACCEPT rule summaries are flagged when their source names a WAN/WWAN zone or has no explicit source-zone restriction. Full rule matching, rule order, port exposure, IPv6 policy and actual packet paths are not evaluated. A REVIEW item needs manual confirmation; UNKNOWN never means secure.</div>
      </Panel>
      <Panel title="Firewall rule inventory" eyebrow="UCI RULE SUMMARIES · ADDRESSES REDACTED">
        {!security ? (
          <div className="module-message">Waiting for authenticated firewall telemetry.</div>
        ) : firewallRules.length === 0 ? (
          <div className="module-message">No rule summaries were returned. The config may be unavailable or there may be no UCI firewall rules.</div>
        ) : (
          <>
            <div className="firewall-rule-toolbar">
              <input
                className="wifi-scan-filter"
                type="search"
                aria-label="Search firewall rule summaries"
                placeholder="Search name, zone, protocol, target or port"
                value={firewallRuleSearch}
                onChange={(event) => setFirewallRuleSearch(event.target.value)}
              />
              <select
                className="wifi-scan-sort"
                aria-label="Sort firewall rules"
                value={firewallRuleSort}
                onChange={(event) => setFirewallRuleSort(event.target.value as "name" | "source" | "destination" | "target")}
              >
                <option value="source">Source zone</option>
                <option value="destination">Destination zone</option>
                <option value="target">Target</option>
                <option value="name">Name A–Z</option>
              </select>
              <span>{visibleFirewallRules.length} shown · {firewallRules.length} returned · {security.rules_count} configured</span>
            </div>
            {visibleFirewallRules.length === 0 ? (
              <div className="module-message">No firewall rules match this search.</div>
            ) : (
              <div className="device-list">
                {visibleFirewallRules.map((rule, index) => (
                  <div className="device-row firewall-rule-row" key={rule.name + "-" + index}>
                    <div className="device-title">
                      <div className="device-icon"><Shield size={17} /></div>
                      <div><strong>{rule.name}</strong><span>{rule.enabled ? "Enabled" : "Disabled"} · {rule.family || "Any IP family"}{externalAllowRuleNames.has(rule.name) ? " · REVIEW EXTERNAL ALLOW" : ""}</span></div>
                    </div>
                    <div><small>SOURCE → DESTINATION</small><b>{rule.source_zone || "Any"} → {rule.destination_zone || "Any"}</b></div>
                    <div><small>PROTOCOL</small><b>{rule.protocol || "Any"}</b></div>
                    <div><small>TARGET</small><b>{rule.target || "N/A"}</b></div>
                    <div><small>PORTS</small><b>{rule.source_port || "Any"} → {rule.destination_port || "Any"}</b></div>
                    <div><small>MATCH FIELDS</small><b>{[rule.source_ip_match && "Source IP", rule.destination_ip_match && "Destination IP", rule.source_mac_match && "Source MAC"].filter(Boolean).join(" · ") || "No address match"}</b></div>
                  </div>
                ))}
              </div>
            )}
          </>
        )}
        <div className="module-message">The API returns at most 64 rule summaries. IP and MAC values are deliberately omitted; only the presence of those match fields is shown. Search and sorting run locally in this page. This inventory does not evaluate rule order, address ranges, connection state, NAT, IPv6 path behaviour or runtime packet matching.</div>
      </Panel>
      <Panel title="NAT port-forward inventory" eyebrow="UCI REDIRECT SECTIONS · INTERNAL IP ADDRESSES REDACTED">
        {!security ? (
          <div className="module-message">Waiting for authenticated NAT redirect telemetry.</div>
        ) : firewallRedirects.length === 0 ? (
          <div className="module-message">No NAT redirect summaries were returned. The firewall configuration may be unavailable or contain no port-forward sections.</div>
        ) : (
          <>
            <div className="firewall-rule-toolbar">
              <input
                className="wifi-scan-filter"
                type="search"
                aria-label="Search NAT redirect summaries"
                placeholder="Search name, source zone, protocol or port"
                value={firewallRedirectSearch}
                onChange={(event) => setFirewallRedirectSearch(event.target.value)}
              />
              <span>{visibleFirewallRedirects.length} shown · {firewallRedirects.length} returned · {security.redirects_count} configured</span>
            </div>
            {visibleFirewallRedirects.length === 0 ? (
              <div className="module-message">No NAT redirects match this search.</div>
            ) : (
              <div className="firewall-redirect-list">
                {visibleFirewallRedirects.map((redirect, index) => (
                  <div className="firewall-redirect-row" key={(redirect.section || redirect.name) + "-" + index}>
                    <div className="firewall-redirect-heading">
                      <strong>{redirect.name}</strong>
                      <span>{redirect.enabled ? "Enabled" : "Disabled"} · {redirect.family || "Any IP family"} · {redirect.target || "Target unspecified"}</span>
                      <small>UCI section {redirect.section || "identifier unavailable"}</small>
                    </div>
                    <div>
                      <small>SOURCE → DESTINATION ZONE</small>
                      <b>{redirect.source_zone || "Any"} → {redirect.destination_zone || "Any"}</b>
                    </div>
                    <div>
                      <small>PORT / PROTOCOL</small>
                      <b>{redirect.external_port || "Any external port"} → {redirect.internal_port || "Same / unspecified"} · {redirect.protocol || "Any"}</b>
                    </div>
                    <div>
                      <small>ADDRESS SELECTORS</small>
                      <b>{[
                        redirect.source_ip_match && "Source IP restricted",
                        redirect.source_mac_match && "Source MAC restricted",
                        redirect.destination_ip_match && "Internal host configured",
                        redirect.source_destination_ip_match && "External destination IP matched",
                      ].filter(Boolean).join(" · ") || "No address selectors reported"}</b>
                      <small>Internal IP values are deliberately not returned.</small>
                    </div>
                    <div className="firewall-redirect-flags">
                      <Status active={redirect.enabled}>{redirect.enabled ? "ENABLED" : "DISABLED"}</Status>
                      {reviewedRedirectNames.has(redirect.section || redirect.name) ? <span className="office-chip warning">EXTERNAL REVIEW</span> : null}
                      {wideRedirectNames.has(redirect.section || redirect.name) ? <span className="office-chip warning">NO EXTERNAL PORT LIMIT</span> : null}
                      {adminRedirectNames.has(redirect.section || redirect.name) ? <span className="office-chip warning">ADMIN / DATA PORT</span> : null}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </>
        )}
        {security?.redirects_truncated && <div className="module-message">The API returned the first 64 redirects only. The configured count is higher; review the full native firewall configuration before making exposure decisions.</div>}
        <div className="module-message">OpenWrt redirect sections define NAT/port-forward behaviour. External forwards, missing source-port constraints and mappings to common administrative/data-service ports are flagged for manual review. Private destination IP addresses are redacted. These are configuration findings only: QuantumGrid does not test public reachability, confirm that a service is listening, or evaluate live nftables rule order.</div>
      </Panel>

      <Panel title="Live fw4 chain inventory" eyebrow="NFTABLES JSON · RUNNING KERNEL STATE" action={<Status active={nftRuntime?.available === true}>{nftRuntime?.available ? "SNAPSHOT PARSED" : nftRuntime?.table_present ? "TABLE PRESENT" : "NOT AVAILABLE"}</Status>}>
        {!security ? (
          <div className="module-message">Waiting for authenticated firewall telemetry.</div>
        ) : !fw4Present ? (
          <div className="module-message">The running nftables inventory does not report inet/fw4. The active firewall backend may differ; this page does not assume fw4 is in use.</div>
        ) : !nftRuntime?.available ? (
          <div className="module-message">{nftRuntime?.truncated ? "The native fw4 JSON snapshot exceeded the 512 KiB safety limit. No partial chain inventory is shown." : "The inet/fw4 table is present, but its JSON chain inventory could not be parsed. The table-presence signal is kept separate from detailed runtime availability."}</div>
        ) : nftRuntime.chains.length === 0 ? (
          <div className="module-message">The fw4 table was parsed, but no supported chain summaries were returned.</div>
        ) : (
          <div className="firewall-runtime-list">
            <div className="firewall-runtime-row header"><span>CHAIN</span><span>HOOK / DEVICE</span><span>TYPE / PRIORITY</span><span>POLICY</span><span>RULES</span></div>
            {nftRuntime.chains.map((chain) => (
              <div className="firewall-runtime-row" key={chain.name}>
                <strong>{chain.name}</strong>
                <div><b>{chain.hook || "Base chain"}</b><small>{chain.device || "No device restriction"}</small></div>
                <div><b>{chain.type}</b><small>Priority {chain.priority ?? "not reported"}</small></div>
                <span className="firewall-runtime-policy">{chain.policy.toUpperCase()}</span>
                <strong className="firewall-runtime-count">{fmt(chain.rule_count)}</strong>
              </div>
            ))}
          </div>
        )}
        {nftRuntime?.truncated && <div className="module-message">The runtime inventory exceeded the 64-chain display limit. Additional chains were not included.</div>}
        <div className="module-message">This is a read-only snapshot of the inet/fw4 table only. It reports chain metadata and rule counts, not raw rule expressions, addresses, counters, execution order, verdict correctness or packet reachability. Other nftables tables and non-fw4 firewall backends are not included.</div>
      </Panel>

      <Panel title="Firewall zones" eyebrow="UCI · /ETC/CONFIG/FIREWALL" action={<Status active={Boolean(security?.firewall_config_readable)}>{security?.firewall_config_readable ? "CONFIG READ" : "WAITING"}</Status>}>
        {!security ? (
          <div className="module-message">Waiting for authenticated router security telemetry.</div>
        ) : !security.firewall_installed ? (
          <div className="module-message">The router does not report the firewall init service as installed.</div>
        ) : !security.firewall_config_readable ? (
          <div className="module-message">Firewall configuration could not be read.</div>
        ) : zones.length === 0 ? (
          <div className="module-message">No firewall zones were reported.</div>
        ) : (
          <div className="device-list">
            {zones.map((zone) => (
              <div className="device-row" key={zone.name}>
                <div className="device-title">
                  <div className="device-icon"><Shield size={17} /></div>
                  <div><strong>{zone.name || "Unnamed zone"}</strong><span>{zone.networks.length > 0 ? zone.networks.join(", ") : "No networks assigned"}</span></div>
                </div>
                <div><small>INPUT</small><b>{zone.input || "N/A"}</b></div>
                <div><small>OUTPUT</small><b>{zone.output || "N/A"}</b></div>
                <div><small>FORWARD</small><b>{zone.forward || "N/A"}</b></div>
                <div><small>MASQUERADE</small><b>{zone.masquerade ? "ON" : "OFF"}</b></div>
              </div>
            ))}
          </div>
        )}
      </Panel>

      <div className="module-grid">
        <Panel title="Adblock Fast" eyebrow="DNS FILTER CONFIGURATION">
          {!security ? (
            <div className="module-message">Waiting for router telemetry.</div>
          ) : (
            <InfoRows rows={[
              ["SERVICE", security.adblock_fast.installed ? "INSTALLED" : "NOT INSTALLED"],
              ["CONFIG FILE", security.adblock_fast.config_available ? "PRESENT" : "MISSING"],
              ["CONFIGURED ENABLED", security.adblock_fast.configured_enabled ? "YES" : "NO"],
            ]} />
          )}
          <div className="module-message">The enabled flag is configuration state only. This API does not claim that a filtering run completed or that DNS requests are currently being blocked.</div>
        </Panel>

        <Panel title="VPN services" eyebrow="WIREGUARD / OPENVPN">
          {!security ? (
            <div className="module-message">Waiting for router telemetry.</div>
          ) : (
            <>
              <InfoRows rows={[
                ["WIREGUARD TOOL", security.vpn.wireguard_tool_installed ? "INSTALLED" : "NOT INSTALLED"],
                ["OPENVPN SERVICE", security.vpn.openvpn_service_installed ? "INSTALLED" : "NOT INSTALLED"],
                ["OPENVPN ENABLED INSTANCES", fmt(security.vpn.openvpn_enabled_instances)],
                ["WIREGUARD LINKS UP", `${fmt(activeWireGuard.length)} / ${fmt(security.vpn.wireguard_interfaces.length)}`],
              ]} />
              {security.vpn.wireguard_interfaces.length > 0 && (
                <div className="info-rows">
                  {security.vpn.wireguard_interfaces.map((iface) => (
                    <div key={iface.name}>
                      <span>{iface.name}{iface.device ? ` · ${iface.device}` : ""}</span>
                      <Status active={iface.up}>{iface.up ? "UP" : "DOWN"}</Status>
                    </div>
                  ))}
                </div>
              )}
            </>
          )}
          <div className="module-message">Private keys, preshared keys and peer credentials are never returned by this telemetry endpoint.</div>
        </Panel>
        <Panel title="WireGuard peer health" eyebrow="WG SHOW ALL DUMP · REDACTED">
          {!security ? (
            <div className="module-message">Waiting for authenticated router telemetry.</div>
          ) : !security.vpn.wireguard_tool_installed ? (
            <div className="module-message">The WireGuard command-line tool is not installed.</div>
          ) : !wireGuardPeersAvailable ? (
            <div className="module-message">WireGuard peer telemetry is unavailable. This does not prove that every peer is disconnected.</div>
          ) : wireGuardPeers.length === 0 ? (
            <div className="module-message">No WireGuard peers were returned by the router.</div>
          ) : (
            <>
              {security.vpn.wireguard_peers_truncated ? <div className="module-message">The peer inventory is capped at 64 entries. Export contains the visible subset only.</div> : null}
              <div className="wireguard-peer-list">
                {wireGuardPeers.map((peer, index) => {
                  const rate = wireGuardPeerRates.get(wireGuardPeerCounterKey(peer));
                  return (
                    <div className="wireguard-peer-row" key={peer.interface + "-" + index}>
                      <div>
                        <small>INTERFACE</small>
                        <strong>{peer.interface}</strong>
                      </div>
                      <div>
                        <small>LAST HANDSHAKE</small>
                        <b>{peer.handshake_seen && peer.handshake_age_seconds !== undefined ? formatUptime(peer.handshake_age_seconds) + " ago" : "Never / unavailable"}</b>
                      </div>
                      <div>
                        <small>RECEIVED</small>
                        <b>{formatTrafficBytes(peer.receive_bytes)}</b>
                      </div>
                      <div>
                        <small>SENT</small>
                        <b>{formatTrafficBytes(peer.transmit_bytes)}</b>
                      </div>
                      <div className="wireguard-peer-rate">
                        <div><small>MEASURED RX RATE</small><b>{rate?.receiveMbps == null ? "N/A · no valid counter sample" : `${fmt(rate.receiveMbps, 2)} Mbps`}</b></div>
                        <div><small>MEASURED TX RATE</small><b>{rate?.transmitMbps == null ? "N/A · no valid counter sample" : `${fmt(rate.transmitMbps, 2)} Mbps`}</b></div>
                        <small>{rate?.sampleSeconds == null ? "Sample interval N/A" : `Sample interval ${fmt(rate.sampleSeconds, 1)} s`}</small>
                      </div>
                      <div className="wireguard-peer-allowed">
                        <small>ALLOWED IPs ({peer.allowed_ips.length})</small>
                        <span>{peer.allowed_ips.length > 0 ? peer.allowed_ips.join(" · ") : "None reported"}</span>
                      </div>
                    </div>
                  );
                })}
              </div>
            </>
          )}
          <div className="module-message">Peer RX/TX rates are calculated from successive transfer-counter samples. The first sample, a counter reset, a gap over 60 seconds or duplicate interface/AllowedIPs identities remain N/A rather than being estimated. A handshake timestamp is not a guarantee of end-to-end reachability. Private keys, preshared keys, public keys and endpoint addresses are deliberately omitted from this API and the security export.</div>
        </Panel>
      </div>

      <Panel title="nftables tables" eyebrow="KERNEL RUNTIME INVENTORY">
        {!security ? (
          <div className="module-message">Waiting for nftables telemetry.</div>
        ) : !security.nft_available ? (
          <div className="module-message">The router could not return an nftables table inventory.</div>
        ) : security.nft_tables.length === 0 ? (
          <div className="module-message">No nftables tables were reported.</div>
        ) : (
          <div className="info-rows">
            {security.nft_tables.map((table) => (
              <div key={table}><span>{table}</span><Status active={table === "inet/fw4"}>{table === "inet/fw4" ? "FIREWALL4 TABLE" : "TABLE PRESENT"}</Status></div>
            ))}
          </div>
        )}
        <div className="module-message">This is a table inventory, not a full rule evaluation or security audit. Zone policies and service configuration are shown separately.</div>
      </Panel>
    </div>
  );
}

type NativeOpenWrtApp = {
  title: string;
  description: string;
  section: "Status" | "Network" | "Security" | "Services" | "System";
  href: string;
  packageName: string;
};

const nativeOpenWrtApps: NativeOpenWrtApp[] = [
  { title: "System Overview", description: "OpenWrt status, board identity, uptime and health.", section: "Status", href: "/cgi-bin/luci/admin/status/overview", packageName: "luci-mod-status" },
  { title: "Realtime Bandwidth", description: "Native LuCI interface throughput graphs.", section: "Status", href: "/cgi-bin/luci/admin/status/realtime/bandwidth", packageName: "luci-mod-status" },
  { title: "Processes", description: "Inspect running processes and resource consumption.", section: "Status", href: "/cgi-bin/luci/admin/status/processes", packageName: "luci-mod-status" },
  { title: "System Log", description: "Read recent system and service log messages.", section: "Status", href: "/cgi-bin/luci/admin/status/logs/syslog", packageName: "luci-mod-status" },
  { title: "Kernel Log", description: "Inspect kernel, driver and hardware messages.", section: "Status", href: "/cgi-bin/luci/admin/status/logs/dmesg", packageName: "luci-mod-status" },
  { title: "Routing Table", description: "Inspect the router's active route inventory.", section: "Status", href: "/cgi-bin/luci/admin/status/routes", packageName: "luci-mod-status" },
  { title: "Realtime Load", description: "View live CPU, load and memory graphs.", section: "Status", href: "/cgi-bin/luci/admin/status/realtime/load", packageName: "luci-mod-status" },
  { title: "Realtime Wireless", description: "View radio signal and wireless throughput graphs.", section: "Status", href: "/cgi-bin/luci/admin/status/realtime/wireless", packageName: "luci-mod-status" },
  { title: "Realtime Connections", description: "Inspect live connection tracking and traffic graphs.", section: "Status", href: "/cgi-bin/luci/admin/status/realtime/connections", packageName: "luci-mod-status" },
  { title: "Channel Analysis", description: "Open the native wireless channel analysis view.", section: "Status", href: "/cgi-bin/luci/admin/status/channel_analysis", packageName: "luci-mod-status" },
  { title: "Network Interfaces", description: "Configure WAN, LAN, VLAN interfaces and devices.", section: "Network", href: "/cgi-bin/luci/admin/network/network", packageName: "luci-mod-network" },
  { title: "Wireless", description: "Native radio, access-point and client configuration.", section: "Network", href: "/cgi-bin/luci/admin/network/wireless", packageName: "luci-mod-network" },
  { title: "Wi-Fi Roaming (uSteer)", description: "Configure multi-AP neighbor reporting and opt-in client steering policies.", section: "Network", href: "/cgi-bin/luci/admin/network/usteer", packageName: "luci-app-usteer" },
  { title: "DHCP & DNS", description: "DHCP leases, static assignments and DNS settings.", section: "Network", href: "/cgi-bin/luci/admin/network/dhcp", packageName: "luci-mod-network" },
  { title: "DNS Settings", description: "Manage local DNS forwarding and resolver configuration.", section: "Network", href: "/cgi-bin/luci/admin/network/dns", packageName: "luci-mod-network" },
  { title: "Network Diagnostics", description: "Use native ping, route and connectivity diagnostics.", section: "Network", href: "/cgi-bin/luci/admin/network/diagnostics", packageName: "luci-mod-network" },
  { title: "Firewall", description: "Firewall zones, traffic rules, NAT and port forwards.", section: "Security", href: "/cgi-bin/luci/admin/network/firewall", packageName: "luci-app-firewall" },
  { title: "Port Forwards", description: "Manage inbound port-forward and destination-NAT rules.", section: "Security", href: "/cgi-bin/luci/admin/network/firewall/forwards", packageName: "luci-app-firewall" },
  { title: "Traffic Rules", description: "Manage firewall filter rules and zone permissions.", section: "Security", href: "/cgi-bin/luci/admin/network/firewall/rules", packageName: "luci-app-firewall" },
  { title: "NAT Rules", description: "Inspect and configure source NAT rules.", section: "Security", href: "/cgi-bin/luci/admin/network/firewall/snats", packageName: "luci-app-firewall" },
  { title: "IP Sets", description: "Configure firewall address sets and their matches.", section: "Security", href: "/cgi-bin/luci/admin/network/firewall/ipsets", packageName: "luci-app-firewall" },
  { title: "Firewall Status", description: "Inspect the runtime nftables firewall tables.", section: "Status", href: "/cgi-bin/luci/admin/status/nftables", packageName: "luci-mod-status" },
  { title: "Multi-WAN Manager", description: "Configure WAN members, health checks, failover policies and traffic rules.", section: "Network", href: "/cgi-bin/luci/admin/network/mwan3", packageName: "luci-app-mwan3" },
  { title: "Multi-WAN Status", description: "Inspect live multi-WAN state, failover and diagnostics.", section: "Status", href: "/cgi-bin/luci/admin/status/mwan3/overview", packageName: "luci-app-mwan3" },
  { title: "Smart Queue Management", description: "Native SQM queue configuration and queue scripts.", section: "Services", href: "/cgi-bin/luci/admin/network/sqm", packageName: "luci-app-sqm" },
  { title: "Adblock Fast", description: "DNS-based domain blocking and block-list services.", section: "Security", href: "/cgi-bin/luci/admin/services/adblock-fast", packageName: "luci-app-adblock-fast" },
  { title: "Dynamic DNS", description: "Maintain a hostname against changing WAN addresses.", section: "Services", href: "/cgi-bin/luci/admin/services/ddns", packageName: "luci-app-ddns" },
  { title: "OpenVPN", description: "Manage OpenVPN instances and configuration files.", section: "Security", href: "/cgi-bin/luci/admin/vpn/openvpn", packageName: "luci-app-openvpn" },
  { title: "Unbound DNS", description: "Recursive DNS resolver configuration and status.", section: "Services", href: "/cgi-bin/luci/admin/services/unbound", packageName: "luci-app-unbound" },
  { title: "UPnP", description: "Manage UPnP and NAT-PMP service settings.", section: "Services", href: "/cgi-bin/luci/admin/services/upnp", packageName: "luci-app-upnp" },
  { title: "Administrator", description: "Root password, SSH access and system settings.", section: "System", href: "/cgi-bin/luci/admin/system/admin", packageName: "luci-mod-system" },
  { title: "System Settings", description: "Configure hostname, timezone, logging and system settings.", section: "System", href: "/cgi-bin/luci/admin/system/system", packageName: "luci-mod-system" },
  { title: "Router Password", description: "Change the root administrator password.", section: "System", href: "/cgi-bin/luci/admin/system/admin/password", packageName: "luci-mod-system" },
  { title: "SSH Access", description: "Configure Dropbear SSH listener and access options.", section: "System", href: "/cgi-bin/luci/admin/system/admin/dropbear", packageName: "luci-mod-system" },
  { title: "SSH Keys", description: "Manage public keys for SSH administrator access.", section: "System", href: "/cgi-bin/luci/admin/system/admin/sshkeys", packageName: "luci-mod-system" },
  { title: "HTTPS Access", description: "Configure the native LuCI uHTTPd web server.", section: "System", href: "/cgi-bin/luci/admin/system/admin/uhttpd", packageName: "luci-mod-system" },
  { title: "Repository Keys", description: "Inspect package feed signing public keys.", section: "System", href: "/cgi-bin/luci/admin/system/admin/repokeys", packageName: "luci-mod-system" },
  { title: "Mount Points", description: "Inspect attached storage and filesystem mounts.", section: "System", href: "/cgi-bin/luci/admin/system/mounts", packageName: "luci-mod-system" },
  { title: "LED Configuration", description: "Configure activity and status LED triggers.", section: "System", href: "/cgi-bin/luci/admin/system/leds", packageName: "luci-mod-system" },
  { title: "Scheduled Tasks", description: "Edit scheduled cron jobs.", section: "System", href: "/cgi-bin/luci/admin/system/crontab", packageName: "luci-mod-system" },
  { title: "Reboot", description: "Open the native router restart control.", section: "System", href: "/cgi-bin/luci/admin/system/reboot", packageName: "luci-mod-system" },
  { title: "Startup & Services", description: "Init scripts, enabled services and scheduled tasks.", section: "System", href: "/cgi-bin/luci/admin/system/startup", packageName: "luci-mod-system" },
  { title: "Software & APK", description: "Install, remove and update native OpenWrt packages.", section: "System", href: "/cgi-bin/luci/admin/system/package-manager", packageName: "luci-app-package-manager" },
  { title: "Backup & Flash", description: "Back up configuration and inspect native firmware actions. Do not use generic flash actions for QuantumGrid AW1000 UBI images.", section: "System", href: "/cgi-bin/luci/admin/system/flash", packageName: "luci-mod-system" },
  { title: "FXS / RJ11 Phone", description: "AW1000 analogue phone service and line controls.", section: "Services", href: "/cgi-bin/luci/admin/services/fxs/status", packageName: "luci-app-fxs" },
  { title: "Statistics Graphs", description: "Native collectd graphs for CPU, interfaces, memory and services.", section: "Status", href: "/cgi-bin/luci/admin/statistics/graphs", packageName: "luci-app-statistics" },
  { title: "Statistics Setup", description: "Configure native collectd data collection plugins.", section: "Services", href: "/cgi-bin/luci/admin/statistics/collectd", packageName: "luci-app-statistics" },
  { title: "Watchcat", description: "Configure connectivity watchdog and recovery actions.", section: "Services", href: "/cgi-bin/luci/admin/services/watchcat", packageName: "luci-app-watchcat" },
];

function OpenWrtAppsPage() {
  const [inventory, setInventory] = useState<RouterPackageInventory | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [packageSearch, setPackageSearch] = useState("");
  const [appSection, setAppSection] = useState<"All" | NativeOpenWrtApp["section"]>("All");
  const [packageName, setPackageName] = useState("");
  const [confirmPackageAction, setConfirmPackageAction] = useState(false);
  const [packageBusy, setPackageBusy] = useState(false);
  const [packageActionMessage, setPackageActionMessage] = useState("");
  const [packageActionOutput, setPackageActionOutput] = useState("");
  const [packageActionError, setPackageActionError] = useState(false);

  const loadPackages = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      setInventory(await fetchRouterPackages());
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "The installed package inventory is unavailable.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    let active = true;
    fetchRouterPackages().then((result) => {
      if (active) setInventory(result);
    }).catch((cause) => {
      if (active) setError(cause instanceof Error ? cause.message : "The installed package inventory is unavailable.");
    }).finally(() => {
      if (active) setLoading(false);
    });
    return () => {
      active = false;
    };
  }, []);

  const runPackageAction = async (operation: "update" | "install" | "remove") => {
    const name = packageName.trim();
    if (operation !== "update" && !/^[A-Za-z0-9][A-Za-z0-9+_.-]{0,127}$/.test(name)) {
      setPackageActionError(true);
      setPackageActionMessage("Enter a valid package name before installing or removing a package.");
      return;
    }
    if (operation === "remove" &&
        (/^kmod-/.test(name) || /^wpad/.test(name) || /^qca-nss/.test(name))) {
      setPackageActionError(true);
      setPackageActionMessage("Kernel, wireless and NSS packages must be changed through an offline firmware build.");
      return;
    }
    if (!confirmPackageAction) {
      setPackageActionError(true);
      setPackageActionMessage("Confirm the package operation before continuing.");
      return;
    }
    setPackageBusy(true);
    setPackageActionError(false);
    setPackageActionMessage(
      operation === "update" ? "Refreshing package feeds…" :
      operation === "install" ? "Installing " + name + "…" :
      "Removing " + name + "…",
    );
    setPackageActionOutput("");
    try {
      const result = await runRouterPackageOperation(operation, name, true);
      setPackageActionMessage(
        operation === "update" ? "Package feeds refreshed successfully." :
        operation === "install" ? name + " installed successfully." :
        name + " removed successfully.",
      );
      setPackageActionOutput(result.output);
      setConfirmPackageAction(false);
      await loadPackages();
    } catch (cause) {
      setPackageActionError(true);
      setPackageActionMessage(cause instanceof Error ? cause.message : "Package operation failed.");
    } finally {
      setPackageBusy(false);
    }
  };

  const installed = new Set(inventory?.packages.map((item) => item.name) ?? []);
  const visiblePackages = (inventory?.packages ?? []).filter((item) =>
    (item.name + " " + item.version).toLocaleLowerCase().includes(packageSearch.trim().toLocaleLowerCase())
  );
  const appsInSection = nativeOpenWrtApps.filter((app) =>
    appSection === "All" || app.section === appSection
  );
  const installedAppCount = nativeOpenWrtApps.filter((app) => installed.has(app.packageName)).length;

  return (
    <div className="module-page openwrt-apps-page">
      <section className="module-hero">
        <div className="module-icon"><Monitor size={25} /></div>
        <div>
          <div className="setup-kicker">NATIVE LUCI · OPENWRT APPLICATIONS</div>
          <h1>OpenWrt Apps</h1>
          <p>Launch the router’s native OpenWrt configuration pages. QuantumGrid remains the control centre; LuCI apps provide the existing package-maintained interfaces for advanced administration.</p>
          <div className="openwrt-app-actions">
            <a className="hero-button" href="/cgi-bin/luci/admin/status/overview">Open native LuCI <ChevronRight size={15} /></a>
            <button className="hero-button" onClick={() => void loadPackages()} disabled={loading}>
              <RefreshCw size={15} /> {loading ? "Reading packages…" : "Refresh package inventory"}
            </button>
          </div>
        </div>
      </section>

      <div className="metrics">
        <Metric title="Package Manager" value={inventory?.manager.toUpperCase() ?? "N/A"} unit="" detail="Detected from the authenticated router" icon={Settings} />
        <Metric title="Installed Packages" value={inventory ? fmt(inventory.count) : "N/A"} unit="" detail={inventory?.truncated ? "Inventory is capped at 1,500 entries" : "Read from the local package database"} icon={HardDrive} />
        <Metric title="Available LuCI Pages" value={inventory ? fmt(installedAppCount) : "N/A"} unit="" detail={nativeOpenWrtApps.length + " launcher entries"} icon={Monitor} />
      </div>

      <Panel title="Native OpenWrt applications" eyebrow="SAME-ROUTER LUCI LINKS">
        <div className="openwrt-app-filter">
          {(["All", "Status", "Network", "Security", "Services", "System"] as const).map((section) => (
            <button
              key={section}
              className={appSection === section ? "openwrt-app-filter-button active" : "openwrt-app-filter-button"}
              onClick={() => setAppSection(section)}
            >
              {section}
            </button>
          ))}
        </div>
        <div className="openwrt-app-grid">
          {appsInSection.map((app) => {
            const available = installed.has(app.packageName);
            return (
              <a
                className={available ? "openwrt-app-card" : "openwrt-app-card unavailable"}
                href={app.href}
                key={app.title}
                aria-label={app.title + (available ? "" : " (package not found in inventory)")}
              >
                <div className="openwrt-app-card-top">
                  <span>{app.section.toUpperCase()}</span>
                  <Status active={available}>{available ? "INSTALLED" : inventory ? "NOT FOUND" : "CHECKING"}</Status>
                </div>
                <strong>{app.title}</strong>
                <p>{app.description}</p>
                <small>{app.packageName}</small>
              </a>
            );
          })}
        </div>
        <div className="module-message">App links open the router’s native LuCI pages in this browser session. “Not found” means the package inventory did not contain the expected package name; a menu entry may still be provided by a related LuCI module. The Backup & Flash link opens standard LuCI only—never upload QuantumGrid’s factory UBI image through a generic sysupgrade form.</div>
      </Panel>

      <Panel title="Package manager" eyebrow="APK / OPKG · AUTHENTICATED ROUTER OPERATIONS">
        <div className="openwrt-package-actions">
          <label className="wireless-config-field">
            <span>PACKAGE NAME</span>
            <input
              value={packageName}
              onChange={(event) => setPackageName(event.target.value)}
              placeholder="e.g. luci-app-sqm or kmod-…"
              autoComplete="off"
              spellCheck={false}
            />
          </label>
          <label className="wireless-config-confirm">
            <input
              type="checkbox"
              checked={confirmPackageAction}
              onChange={(event) => setConfirmPackageAction(event.target.checked)}
              disabled={packageBusy}
            />
            <span>I understand that installation runs package scripts and may change router services; removal may remove dependent applications. Core system, wireless, NSS and kernel-module removals are blocked.</span>
          </label>
        </div>
        <div className="openwrt-package-action-buttons">
          <button className="hero-button" onClick={() => void runPackageAction("update")} disabled={packageBusy || !confirmPackageAction}>
            {packageBusy ? "Working…" : "Refresh feeds"}
          </button>
          <button className="hero-button" onClick={() => void runPackageAction("install")} disabled={packageBusy || !confirmPackageAction || !/^[A-Za-z0-9][A-Za-z0-9+_.-]{0,127}$/.test(packageName.trim())}>
            Install package
          </button>
          <button className="hero-button" onClick={() => void runPackageAction("remove")} disabled={packageBusy || !confirmPackageAction || !/^[A-Za-z0-9][A-Za-z0-9+_.-]{0,127}$/.test(packageName.trim()) || /^(kmod-|wpad|qca-nss|ath11k|kernel-|luci-mod-)/.test(packageName.trim())}>
            Remove package
          </button>
        </div>
        {packageActionMessage ? (
          <div className={packageActionError ? "wireless-config-result error" : "wireless-config-result success"} role="status">
            {packageActionMessage}
          </div>
        ) : null}
        {packageActionOutput ? <pre className="openwrt-package-output">{packageActionOutput}</pre> : null}
        <div className="module-message">
          Package actions use the router's configured APK/OPKG feeds and run one package operation at a time. The in-app remover blocks base services, all kernel modules, wireless supplicants and NSS components; driver and firmware changes must be made in a matching offline image build. A successful package install may still require a service restart or router reboot, as reported by the package manager.
        </div>
      </Panel>

      <Panel title="Installed package inventory" eyebrow={inventory ? inventory.manager.toUpperCase() + " · " + new Date(inventory.sampled_at * 1000).toLocaleString() : "READ-ONLY LOCAL DATABASE"}>
        <div className="openwrt-package-toolbar">
          <input
            type="search"
            value={packageSearch}
            onChange={(event) => setPackageSearch(event.target.value)}
            placeholder="Search installed packages or versions"
            aria-label="Search installed packages"
          />
          <span>{loading ? "Loading…" : visiblePackages.length + " shown"}</span>
        </div>
        {error ? <div className="module-message" role="alert">{error}</div> : null}
        {!inventory && !loading ? (
          <div className="module-message">No package inventory has been read yet. Refresh the inventory to query APK or OPKG.</div>
        ) : visiblePackages.length === 0 ? (
          <div className="module-message">{inventory ? "No installed packages match this search." : "Reading the router package database…"}</div>
        ) : (
          <div className="openwrt-package-table">
            <div className="openwrt-package-row header"><span>PACKAGE</span><span>VERSION</span><span>MANAGER</span></div>
            {visiblePackages.slice(0, 500).map((item) => (
              <div className="openwrt-package-row" key={item.name}>
                <strong>{item.name}</strong>
                <span>{item.version}</span>
                <small>{item.manager.toUpperCase()}</small>
              </div>
            ))}
          </div>
        )}
        {inventory?.truncated ? <div className="module-message">The router has {inventory.count.toLocaleString()} installed packages. The API returned the first 1,500; the displayed list is further limited to 500 rows for browser performance.</div> : null}
      </Panel>
    </div>
  );
}


function DashboardPage({
  stats,
  refresh,
  page,
  telemetryError,
  routerOverview,
  trafficHistory,
  cellularHistory,
  interfaceCounterDeltas,
  wireGuardPeerRates,
}: {
  stats: Stats;
  refresh: () => void;
  page: Page;
  telemetryError: string;
  routerOverview: RouterOverview | null;
  trafficHistory: number[];
  cellularHistory: CellularHistorySample[];
  interfaceCounterDeltas: Map<string, InterfaceCounterDelta>;
  wireGuardPeerRates: Map<string, WireGuardPeerMeasuredRate>;
}) {
  const wanOnline = routerOverview?.interfaces.some((item) => item.is_wan && item.up) ?? false;
  const wifiOnline = routerOverview?.wireless.some((radio) => radio.up) ?? false;
  const modemDetected = routerOverview?.cellular.modem_present ?? false;
  const clients = routerOverview?.clients ?? [];
  const inventoryAvailable = Array.isArray(routerOverview?.clients);

  if (page === "phone") return <PhonePage routerOverview={routerOverview} />;
  if (page === "network") return <NetworkControlPage routerOverview={routerOverview} stats={stats} interfaceCounterDeltas={interfaceCounterDeltas} />;
  if (page === "diagnostics") return <DiagnosticsControlPage stats={stats} telemetryError={telemetryError} routerOverview={routerOverview} refresh={refresh} />;
  if (page === "system") return <SystemControlPage routerOverview={routerOverview} stats={stats} refresh={refresh} />;
  if (page === "analytics") return <AnalyticsControlPage stats={stats} trafficHistory={trafficHistory} />;
  if (page === "5g") return <CellularControlPage routerOverview={routerOverview} cellularHistory={cellularHistory} />;

  if (page === "dashboard") {
    return (
      <div className="dashboard-page">
        <section className="dashboard-hero">
          <div className="hero-copy">
            <div className="setup-kicker">QUANTUMGRID NETWORK COMMAND CENTER</div>

            <h1>
              Your network is
              <span> operating at full power.</span>
            </h1>

            <p>
              Real-time visibility across WAN, Wi-Fi, gaming traffic,
              security and hardware acceleration.
            </p>

            <button className="hero-button" onClick={refresh}>
              <Sparkles size={17} />
              Refresh Telemetry
            </button>
          </div>

          <div className="health-card">
            <Status active={Boolean(routerOverview) && !telemetryError}>
              {telemetryError ? "TELEMETRY UNAVAILABLE" : routerOverview ? "ROUTER CONNECTED" : "CONNECTING"}
            </Status>

            <strong>{stats.cpu === null ? "N/A" : `${fmt(stats.cpu, 1)}%`}</strong>
            <span>CPU utilisation</span>

            <div className="health-mini">
              <div><span>CLIENTS</span><b>{inventoryAvailable ? fmt(clients.length) : "N/A"}</b></div>
              <div><span>WAN</span><b>{routerOverview ? (wanOnline ? "ONLINE" : "OFFLINE") : "—"}</b></div>
              <div><span>UPTIME</span><b>{formatUptime(routerOverview?.system.uptime_seconds)}</b></div>
            </div>
          </div>
        </section>

        <div className="metrics">
          <Metric title="Latency" value={stats.latency === null ? "N/A" : fmt(stats.latency)} unit={stats.latency === null ? "" : "ms"} detail={stats.probeDelta === null ? "Awaiting second sample" : `${fmt(stats.probeDelta, 1)} ms change between probes`} icon={Activity} />
          <Metric title="Download" value={stats.wanAvailable ? fmt(stats.download, 2) : "N/A"} unit={stats.wanAvailable ? "Mbps" : ""} detail="WAN byte-counter rate" icon={Download} />
          <Metric title="Upload" value={stats.wanAvailable ? fmt(stats.upload, 2) : "N/A"} unit={stats.wanAvailable ? "Mbps" : ""} detail="WAN byte-counter rate" icon={Upload} />
          <Metric title="Internet Probe" value={routerOverview ? (stats.reachable ? "ONLINE" : "NO REPLY") : "N/A"} unit="" detail="Single ICMP probe · 1.1.1.1" icon={Signal} />
        </div>

        <div className="dashboard-grid">
          <Panel title="WAN Traffic Samples" eyebrow="MEASURED THROUGHPUT" action={<Status active={Boolean(routerOverview) && !telemetryError}>{routerOverview && !telemetryError ? "LIVE" : "WAITING"}</Status>}>
            <div className="traffic-demo">
              {trafficHistory.map((value, i) => {
                const maximum = Math.max(1, ...trafficHistory);
                const height = value > 0 ? Math.max(3, (value / maximum) * 90) : 3;

                return (
                  <div key={i} className="traffic-column">
                    <span style={{ height: `${height}%` }} />
                  </div>
                );
              })}
            </div>

            <div className="traffic-labels">
              <span>90s ago</span>
              <span>45s</span>
              <span>NOW</span>
            </div>
          </Panel>

          <Panel title="Gaming Engine" eyebrow="LATENCY OBSERVABILITY" action={<Status active={false}>POLICY NOT CONFIGURED</Status>}>
            <div className="gaming-score">
              <div className="gaming-ring">
                <strong>N/A</strong>
                <span>NO SCORE</span>
              </div>

              <div className="gaming-stats">
                <div><span>LATENCY</span><b>{stats.latency === null ? "N/A" : `${fmt(stats.latency)} ms`}</b></div>
                <div><span>PROBE DELTA</span><b>{stats.probeDelta === null ? "N/A" : `${fmt(stats.probeDelta, 1)} ms`}</b></div>
                <div><span>INTERNET PROBE</span><b>{routerOverview ? (stats.reachable ? "ONLINE" : "NO REPLY") : "N/A"}</b></div>
                <div><span>BUFFERBLOAT</span><b>N/A</b></div>
              </div>
            </div>

            <div className="mode-row">
              <span className="selected">POLICY PRESETS NOT APPLIED</span>
            </div>
          </Panel>
        </div>

        <div className="three-grid">
          <Panel title="Acceleration" eyebrow="DATA PLANE">
            <InfoRows
              rows={[
                ["NSS", "NOT INCLUDED"],
                ["EDMA", "UNVERIFIED"],
                ["PPE", "UNVERIFIED"],
                ["2.5GbE", "LINK SPEED UNKNOWN"],
              ]}
            />
          </Panel>

          <Panel title="System Health" eyebrow="LIVE HARDWARE">
            <div className="health-grid">
              <Health icon={Cpu} label="CPU" value={stats.cpu === null ? "N/A" : `${fmt(stats.cpu, 1)}%`} />
              <Health icon={Thermometer} label="TEMP" value={stats.temp === null ? "N/A" : `${fmt(stats.temp, 1)}°C`} />
              <Health icon={Database} label="RAM" value={stats.ram === null ? "N/A" : `${fmt(stats.ram, 1)}%`} />
              <Health icon={HardDrive} label="STORAGE" value="N/A" />
            </div>
          </Panel>

          <Panel title="Network Status" eyebrow="CONNECTIVITY">
            <InfoRows
              rows={[
                ["WAN", routerOverview ? (wanOnline ? "ONLINE" : "OFFLINE") : "UNKNOWN"],
                ["WI-FI", routerOverview ? (wifiOnline ? "ONLINE" : "OFFLINE") : "UNKNOWN"],
                ["5G MODEM", routerOverview ? (modemDetected ? "DETECTED" : "NOT DETECTED") : "UNKNOWN"],
              ]}
            />
          </Panel>
        </div>

        <Panel title="Known Network Clients" eyebrow="UNEXPIRED DHCPV4 LEASES">
          <ClientLeaseList clients={clients} available={inventoryAvailable} maxRows={6} />
        </Panel>
      </div>
    );
  }

  const titles: Record<Exclude<Page, "dashboard">, [string, string, React.ElementType]> = {
    gaming: ["Gaming", "Gaming Engine", Gamepad2],
    devices: ["Devices", "Client Intelligence", Users],
    wifi: ["Wi-Fi", "Wireless Intelligence", Wifi],
    "5g": ["5G", "Cellular Control Center", Signal],
    phone: ["Phone", "Analogue Voice & FXS", PhoneCall],
    network: ["Network", "Network Control", Network],
    security: ["Security", "Security Center", Shield],
    diagnostics: ["Diagnostics", "Network Diagnostics", Activity],
    analytics: ["Analytics", "Network Analytics", Database],
    system: ["System", "System Control", Cpu],
    advanced: ["Advanced", "Advanced Control", Settings],
    hardware: ["Hardware I/O", "GPIO, Buttons & LEDs", Cpu],
    office: ["Office Networks", "VLAN & Network Segmentation", Network],
    audit: ["Admin Audit", "Administrative Change History", Shield],
    apps: ["OpenWrt Apps", "Native LuCI & APK", Monitor],
  };

  if (page === "gaming") {
    return <GamingControlPage routerOverview={routerOverview} refresh={refresh} />;
  }

  if (page === "security") {
    return <SecurityControlPage routerOverview={routerOverview} wireGuardPeerRates={wireGuardPeerRates} />;
  }

  if (page === "wifi") {
    return <WifiControlPage routerOverview={routerOverview} refresh={refresh} />;
  }

  if (page === "devices") {
    return <DevicesControlPage routerOverview={routerOverview} />;
  }

  if (page === "advanced") {
    return <AdvancedControlPage routerOverview={routerOverview} refresh={refresh} />;
  }

  if (page === "hardware") {
    return <HardwareIoControlPage routerOverview={routerOverview} refresh={refresh} />;
  }

  if (page === "office") {
    return <OfficeNetworksPage routerOverview={routerOverview} refresh={refresh} />;
  }

  if (page === "audit") {
    return <AuditLogPage />;
  }

  if (page === "apps") {
    return <OpenWrtAppsPage />;
  }

  const [title, eyebrow, Icon] =
    titles[page as Exclude<Page, "dashboard">];

  return (
    <GenericModulePage
      title={title}
      eyebrow={eyebrow}
      Icon={Icon}
    />
  );
}


function WirelessRadioInventory({
  radios,
  available,
}: {
  radios: RouterOverview["wireless"];
  available: boolean;
}) {
  if (!available) {
    return <div className="module-message">Waiting for authenticated wireless telemetry.</div>;
  }
  if (radios.length === 0 || radios.every((radio) => radio.interfaces.length === 0)) {
    return <div className="module-message">No wireless interfaces were reported by the router.</div>;
  }

  return (
    <>
    <div className="device-list">
      {radios.map((radio) => radio.interfaces.map((iface) => (
        <div className="device-row wireless-radio-row" key={`${radio.name}-${iface.ifname}`}>
          <div className="device-title">
            <div className="device-icon"><Wifi size={17} /></div>
            <div>
              <strong>{iface.ssid || iface.ifname || radio.name}</strong>
              <span>{radio.name} · {iface.ifname || "No interface"} · {iface.mode || "mode N/A"} · {iface.up ? "UP" : "DOWN"} · {iface.country || "Region N/A"} · {iface.htmode || "Width N/A"}</span>
              <span className="wireless-mode-capabilities">PHY: {iface.hardware_modes?.join(" / ") || iface.hwmode || "N/A"} · Widths: {iface.ht_modes?.join(" / ") || iface.htmode || "N/A"}</span>
            </div>
          </div>
          <div><small>CHANNEL / FREQ</small><b>{iface.channel === undefined ? "N/A" : fmt(iface.channel)}{iface.frequency_mhz === undefined ? "" : ` · ${fmt(iface.frequency_mhz)} MHz`}{iface.center_channel_1 === undefined ? "" : ` · Center ${iface.center_channel_1}`}{iface.center_channel_2 === undefined || iface.center_channel_2 === 0 ? "" : `/${iface.center_channel_2}`}</b></div>
          <div><small>AP SIGNAL / NOISE</small><b>{iface.signal_dbm === undefined ? "N/A" : `${fmt(iface.signal_dbm)} dBm`}{iface.noise_dbm === undefined ? "" : ` / ${fmt(iface.noise_dbm)} dBm`}</b></div>
          <div><small>BITRATE</small><b>{formatKbps(iface.bitrate_kbps)}</b></div>
          <div><small>QUALITY / TX POWER</small><b>{iface.quality === undefined ? "N/A" : `${fmt(iface.quality)}/${fmt(iface.quality_max ?? 0)}`}{iface.txpower_dbm === undefined ? "" : ` · ${fmt(iface.txpower_dbm)} dBm`}</b></div>
          <div><small>CHANNEL BUSY</small><b>{iface.channel_busy_percent === undefined ? (iface.survey_supported ? "COLLECTING" : "N/A") : `${fmt(iface.channel_busy_percent, 1)}% · ${fmt(iface.survey_interval_seconds ?? 0)}s`}</b></div>
        </div>
      )))}
    </div>
    <div className="wireless-channel-inventory">
      {radios.map((radio) => (
        <section className="wireless-channel-section" key={radio.name}>
          <div className="wireless-channel-heading">
            <strong>{radio.name} · Driver frequency list</strong>
            <span>{radio.channels?.length ? `${radio.channels.length} channel entries` : "Not reported"}</span>
          </div>
          {radio.channels?.length ? (
            <div className="wireless-channel-chips">
              {radio.channels.map((channel) => (
                <div className={`wireless-channel-chip${channel.restricted ? " restricted" : ""}`} key={channel.band + "-" + channel.channel + "-" + channel.frequency_mhz}>
                  <strong>{channel.band} · CH {channel.channel}</strong>
                  <span>{fmt(channel.frequency_mhz)} MHz{channel.active ? " · CURRENT" : ""}</span>
                  {channel.restricted || channel.flags.length > 0 ? (
                    <small>{[channel.restricted ? "RESTRICTED" : "", ...channel.flags].filter(Boolean).join(" · ")}</small>
                  ) : null}
                </div>
              ))}
            </div>
          ) : (
            <div className="module-message">The radio driver did not return a frequency/channel list.</div>
          )}
        </section>
      ))}
    </div>
    <div className="module-message">The inventory comes from iwinfo.freqlist. Restricted flags and driver capabilities are shown as reported; they are not a substitute for the router's complete regulatory database or a guarantee that a channel is usable in every operating mode.</div>
    <div className="wireless-channel-inventory">
      {radios.map((radio) => (
        <section className="wireless-channel-section" key={radio.name + "-txpower"}>
          <div className="wireless-channel-heading">
            <strong>{radio.name} · Driver-supported transmit power</strong>
            <span>{radio.txpower_levels?.length ? `${radio.txpower_levels.length} levels` : "Not reported"}</span>
          </div>
          {radio.txpower_levels?.length ? (
            <div className="wireless-channel-chips">
              {radio.txpower_levels.map((level) => (
                <div className={`wireless-channel-chip${level.active ? " active" : ""}`} key={level.dbm + "-" + level.mw}>
                  <strong>{fmt(level.dbm)} dBm{level.active ? " · CURRENT" : ""}</strong>
                  <span>{fmt(level.mw)} mW</span>
                </div>
              ))}
            </div>
          ) : (
            <div className="module-message">The radio driver did not return a supported transmit-power list.</div>
          )}
        </section>
      ))}
    </div>
    <div className="module-message">The transmit-power levels are the driver's iwinfo.txpowerlist response, not regulatory permission to use every listed level. Current power is only marked when the driver identifies an active entry. QuantumGrid does not change transmit power here.</div>
    <div className="module-message">Channel busy is calculated from changes in the current channel's iwinfo busy-time and active-time counters between samples. It is a short-window airtime estimate, not a neighbouring-access-point scan; drivers without survey counters show N/A.</div>
    </>
  );
}


type WifiChannelGroup = {
  band: string;
  channel: number | null;
  networks: RouterWifiScan["results"];
  strongestSignal: number | null;
  strongestSsid: string;
};

function summarizeWifiChannels(results: RouterWifiScan["results"]): WifiChannelGroup[] {
  const groups = new Map<string, WifiChannelGroup>();
  for (const network of results) {
    const channel = typeof network.channel === "number" && Number.isFinite(network.channel)
      ? network.channel
      : null;
    const band = network.band || "Unknown";
    const key = band + ":" + (channel === null ? "unknown" : String(channel));
    let group = groups.get(key);
    if (!group) {
      group = { band, channel, networks: [], strongestSignal: null, strongestSsid: "" };
      groups.set(key, group);
    }
    group.networks.push(network);
    if (
      typeof network.signal_dbm === "number" &&
      Number.isFinite(network.signal_dbm) &&
      (group.strongestSignal === null || network.signal_dbm > group.strongestSignal)
    ) {
      group.strongestSignal = network.signal_dbm;
      group.strongestSsid = network.ssid || "Hidden network";
    }
  }
  return [...groups.values()].sort((left, right) => {
    if (right.networks.length !== left.networks.length) {
      return right.networks.length - left.networks.length;
    }
    if (left.band !== right.band) return left.band.localeCompare(right.band);
    return (left.channel ?? Number.MAX_SAFE_INTEGER) - (right.channel ?? Number.MAX_SAFE_INTEGER);
  });
}

function csvCell(value: string | number | boolean | null | undefined): string {
  let text = value === null || value === undefined ? "" : String(value);
  // Treat network-controlled SSIDs and other fields as text in spreadsheet applications.
  if (/^[\t\r\n ]*[=+\-@]/.test(text)) text = "'" + text;
  return '"' + text.replace(/"/g, '""') + '"';
}

type WifiScanHistoryNetwork = Pick<
  RouterWifiScan["results"][number],
  "bssid" | "ssid" | "band" | "channel" | "signal_dbm"
>;

type WifiScanHistorySample = {
  scannedAt: number;
  accessPoints: number;
  bandCounts: Record<string, number>;
  networks: WifiScanHistoryNetwork[];
};

type WifiScanComparison = {
  newlyObserved: WifiScanHistoryNetwork[];
  notObserved: WifiScanHistoryNetwork[];
  signalChanges: Array<{
    network: WifiScanHistoryNetwork;
    previousDbm: number;
    currentDbm: number;
    deltaDb: number;
  }>;
};

function compareWifiScanHistory(
  current: WifiScanHistorySample,
  previous: WifiScanHistorySample,
): WifiScanComparison {
  const previousByBssid = new Map<string, WifiScanHistoryNetwork>(
    previous.networks
      .filter((network) => network.bssid.trim().length > 0)
      .map((network): [string, WifiScanHistoryNetwork] => [network.bssid.toLowerCase(), network]),
  );
  const currentByBssid = new Map<string, WifiScanHistoryNetwork>(
    current.networks
      .filter((network) => network.bssid.trim().length > 0)
      .map((network): [string, WifiScanHistoryNetwork] => [network.bssid.toLowerCase(), network]),
  );

  const newlyObserved = current.networks.filter(
    (network) => network.bssid.trim().length > 0 && !previousByBssid.has(network.bssid.toLowerCase()),
  );
  const notObserved = previous.networks.filter(
    (network) => network.bssid.trim().length > 0 && !currentByBssid.has(network.bssid.toLowerCase()),
  );
  const signalChanges = current.networks.flatMap((network) => {
    const previousSignal = previousByBssid.get(network.bssid.toLowerCase())?.signal_dbm;
    const currentSignal = network.signal_dbm;
    if (
      previousSignal === undefined ||
      currentSignal === undefined ||
      !Number.isFinite(previousSignal) ||
      !Number.isFinite(currentSignal) ||
      previousSignal === currentSignal
    ) {
      return [];
    }
    return [{
      network,
      previousDbm: previousSignal,
      currentDbm: currentSignal,
      deltaDb: currentSignal - previousSignal,
    }];
  }).sort((left, right) => Math.abs(right.deltaDb) - Math.abs(left.deltaDb));

  return { newlyObserved, notObserved, signalChanges };
}

function describeScanOperation(network: RouterWifiScan["results"][number]): string {
  const describeWidth = (kind: "HT" | "VHT" | "HE" | "EHT", width: number | undefined) => {
    if (width === undefined) return "width unknown";
    if (kind === "HT") {
      if (width === 20) return "20 MHz";
      if (width === 2040) return "40 MHz or higher";
    } else if (kind === "VHT") {
      const widths: Record<number, string> = {
        40: "20 or 40 MHz", 80: "80 MHz", 8080: "80+80 MHz", 160: "160 MHz",
      };
      return widths[width] ?? "width unknown";
    } else {
      const widths: Record<number, string> = {
        20: "20 MHz", 40: "40 MHz", 80: "80 MHz", 160: "160 MHz", 320: "320 MHz",
      };
      return widths[width] ?? "width unknown";
    }
    return "width unknown";
  };

  const operations = [
    { name: "EHT", value: network.eht_operation },
    { name: "HE", value: network.he_operation },
    { name: "VHT", value: network.vht_operation },
    { name: "HT", value: network.ht_operation },
  ] as const;
  const selected = operations.find((operation) => operation.value !== undefined);
  if (!selected) return "N/A";
  const details = [selected.name, describeWidth(selected.name, selected.value?.channel_width)];
  if (selected.name === "HT" && selected.value?.primary_channel !== undefined) {
    details.push("primary CH " + selected.value.primary_channel);
    if (selected.value.secondary_channel_offset) details.push(selected.value.secondary_channel_offset);
  } else {
    if (selected.value?.center_freq_1 !== undefined) details.push("center CH " + selected.value.center_freq_1);
    if (selected.value?.center_freq_2 !== undefined && selected.value.center_freq_2 > 0) {
      details.push("center 2 CH " + selected.value.center_freq_2);
    }
  }
  return details.join(" · ");
}

type WirelessTrafficSample = {
  rx_mbps: number;
  tx_mbps: number;
};

type InterfaceCounterSnapshot = {
  rx_bytes: number;
  tx_bytes: number;
  rx_errors?: number;
  tx_errors?: number;
  rx_dropped?: number;
  tx_dropped?: number;
  sampledAt: number;
};

type InterfaceCounterDelta = {
  rxErrors: number | null;
  txErrors: number | null;
  rxDropped: number | null;
  txDropped: number | null;
  rxMbps: number | null;
  txMbps: number | null;
  sampleSeconds: number | null;
};

function WirelessConfigEditor({
  config,
  radio,
  networkInterfaces,
  officeInventory,
  refresh,
}: {
  config: RouterWirelessConfig;
  radio?: RouterWirelessRadio;
  networkInterfaces: RouterOfficeInterface[];
  officeInventory?: RouterOfficeNetworks;
  refresh: () => void;
}) {
  const currentNetwork = config.networks.length === 1 ? config.networks[0] : "";
  const [ssid, setSsid] = useState(config.ssid);
  const [network, setNetwork] = useState(currentNetwork);
  const [encryption, setEncryption] = useState<"psk2" | "sae" | "sae-mixed" | "wpa2" | "wpa3" | "none">(
    config.encryption === "sae" || config.encryption === "sae-mixed" ||
    config.encryption === "wpa2" || config.encryption === "wpa3" || config.encryption === "none"
      ? config.encryption
      : "psk2",
  );
  const [passphrase, setPassphrase] = useState("");
  const [radiusServer, setRadiusServer] = useState(config.radius_auth_server || "");
  const [radiusPort, setRadiusPort] = useState(String(config.radius_auth_port || 1812));
  const [radiusSecret, setRadiusSecret] = useState("");
  const [accountingServer, setAccountingServer] = useState(config.accounting_server || "");
  const [accountingPort, setAccountingPort] = useState(String(config.accounting_port || 1813));
  const [accountingSecret, setAccountingSecret] = useState("");
  const [accountingEnabled, setAccountingEnabled] = useState(Boolean(config.accounting_server));
  const [radiusDynamicVlanEnabled, setRadiusDynamicVlanEnabled] = useState(
    config.dynamic_vlan === 2 && !config.radius_vlan_unmanaged,
  );
  const [radiusVlanMappings, setRadiusVlanMappings] = useState<Array<{ vid: string; network: string }>>(
    config.radius_vlan_mappings.filter((mapping) => mapping.managed)
      .map((mapping) => ({ vid: String(mapping.vid), network: mapping.network })),
  );
  const [hidden, setHidden] = useState(config.hidden);
  const [channel, setChannel] = useState(config.channel || "auto");
  const [htmode, setHtmode] = useState(config.htmode || "auto");
  const [txpower, setTxpower] = useState(config.txpower === undefined ? "auto" : String(config.txpower));
  const [allowOpen, setAllowOpen] = useState(false);
  const [confirmDisconnect, setConfirmDisconnect] = useState(false);
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState<{ success: boolean; message: string } | null>(null);

  const supportedChannels = [...new Set(
    (radio?.channels ?? []).filter((item) => !item.restricted).map((item) => item.channel),
  )].sort((left, right) => left - right);
  const currentChannel = config.channel || "auto";
  const channelSupported = channel === "auto" || supportedChannels.includes(Number(channel)) ||
    channel === currentChannel;
  const currentHtmode = config.htmode || "auto";
  const supportedHtModes = [...new Set(config.htmodes ?? [])].sort();
  const htmodeSupported = htmode === "auto" || supportedHtModes.includes(htmode) || htmode === currentHtmode;
  const currentTxpower = config.txpower === undefined ? "auto" : String(config.txpower);
  const supportedTxPower = [...new Set((config.txpower_levels ?? []).map((item) => item.dbm))].sort((left, right) => left - right);
  const txpowerSupported = txpower === "auto" || supportedTxPower.includes(Number(txpower)) || txpower === currentTxpower;
  const enterpriseMode = encryption === "wpa2" || encryption === "wpa3";
  const externalZoneNames = new Set(["wan", "wan6", "wwan", "cellular"]);
  const eligibleNetworkInterfaces = networkInterfaces.filter((item) =>
    item.protocol === "static" && item.device.length > 0 && item.firewall_zones.length > 0 &&
    item.firewall_zones.every((zone) => !externalZoneNames.has(zone.toLowerCase()))
  );
  const networkSupported = eligibleNetworkInterfaces.some((item) => item.name === network);
  const networkChanged = network !== currentNetwork;
  const eligibleRadiusVlans = (officeInventory?.interfaces ?? []).flatMap((iface) => {
    const deviceMatch = /^(.+)\.([0-9]{1,4})$/.exec(iface.device);
    if (!deviceMatch || iface.protocol !== "static" || iface.ipv4.length === 0) return [];
    const bridgeName = deviceMatch[1];
    const vid = Number(deviceMatch[2]);
    const bridge = officeInventory?.bridges.find((item) =>
      item.name === bridgeName && item.vlan_filtering && item.ports.length > 0);
    const vlan = officeInventory?.vlans.find((item) =>
      item.device === bridgeName && item.vlan_id === vid && item.ports.length > 0);
    const attachedZones = (officeInventory?.zones ?? []).filter((zone) =>
      zone.networks.includes(iface.name));
    if (!bridge || !vlan || attachedZones.length !== 1) return [];
    const zone = attachedZones[0];
    if (externalZoneNames.has(zone.name.toLowerCase()) ||
        zone.networks.some((item) => externalZoneNames.has(item.toLowerCase())) ||
        !["REJECT", "DROP"].includes(zone.input) ||
        !["REJECT", "DROP"].includes(zone.forward)) return [];
    return [{ vid: String(vid), network: iface.name, device: iface.device, zone: zone.name }];
  });
  const radiusVlanManaged = !config.radius_vlan_unmanaged;
  const currentManagedRadiusMappings = config.radius_vlan_mappings
    .filter((mapping) => mapping.managed)
    .map((mapping) => ({ vid: String(mapping.vid), network: mapping.network }));
  const effectiveRadiusMappings = radiusDynamicVlanEnabled ? radiusVlanMappings : [];
  const radiusVlanMappingsValid = effectiveRadiusMappings.length >= 1 &&
    effectiveRadiusMappings.length <= 16 &&
    effectiveRadiusMappings.every((mapping) =>
      eligibleRadiusVlans.some((item) => item.vid === mapping.vid && item.network === mapping.network)) &&
    new Set(effectiveRadiusMappings.map((item) => item.vid)).size === effectiveRadiusMappings.length &&
    new Set(effectiveRadiusMappings.map((item) => item.network)).size === effectiveRadiusMappings.length;
  const radiusVlanConfigurationChanged = radiusVlanManaged &&
    (radiusDynamicVlanEnabled !== (config.dynamic_vlan === 2) ||
      JSON.stringify([...effectiveRadiusMappings].sort((a, b) => Number(a.vid) - Number(b.vid))) !==
      JSON.stringify([...currentManagedRadiusMappings].sort((a, b) => Number(a.vid) - Number(b.vid))));
  const radiusVlanReady = !radiusDynamicVlanEnabled || !enterpriseMode || radiusVlanMappingsValid;
  const encryptionChanged = encryption !== config.encryption;
  const pmfNeedsRepair = config.encryption === "wpa3" && config.ieee80211w !== "2";
  const passphraseRequired = encryption !== "none" && !enterpriseMode &&
    (encryptionChanged || !config.key_set) && passphrase.length === 0;
  const radiusLabels = radiusServer.split(".");
  const radiusServerValid = radiusServer.length >= 1 && radiusServer.length <= 253 &&
    /^[A-Za-z0-9.-]+$/.test(radiusServer) && !radiusServer.startsWith(".") &&
    !radiusServer.endsWith(".") && !radiusServer.includes("..") &&
    radiusLabels.every((label) => label.length >= 1 && label.length <= 63 &&
      /^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$/.test(label)) &&
    !(radiusLabels.length === 4 && radiusLabels.every((label) => /^\d+$/.test(label)) &&
      !radiusLabels.every((label) => Number(label) >= 0 && Number(label) <= 255));
  const radiusPortValid = /^[0-9]{1,5}$/.test(radiusPort) &&
    Number(radiusPort) >= 1 && Number(radiusPort) <= 65535;
  const radiusSecretBytes = new TextEncoder().encode(radiusSecret).length;
  const currentEnterpriseMode = config.encryption === "wpa2" || config.encryption === "wpa3";
  const radiusSecretRequired = enterpriseMode &&
    (!currentEnterpriseMode || radiusServer !== config.radius_auth_server ||
      !config.radius_secret_set) && radiusSecret.length === 0;
  const radiusReady = !enterpriseMode ||
    (radiusServerValid && radiusPortValid && !radiusSecretRequired &&
      (radiusSecret.length === 0 || (radiusSecretBytes >= 16 && radiusSecretBytes <= 128 &&
        !/[\u0000-\u001f\u007f]/.test(radiusSecret))));
  const accountingServerValue = accountingServer || radiusServer;
  const accountingLabels = accountingServerValue.split(".");
  const accountingServerValid = accountingServerValue.length >= 1 && accountingServerValue.length <= 253 &&
    /^[A-Za-z0-9.-]+$/.test(accountingServerValue) && !accountingServerValue.startsWith(".") &&
    !accountingServerValue.endsWith(".") && !accountingServerValue.includes("..") &&
    accountingLabels.every((label) => label.length >= 1 && label.length <= 63 &&
      /^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$/.test(label)) &&
    !(accountingLabels.length === 4 && accountingLabels.every((label) => /^\d+$/.test(label)) &&
      !accountingLabels.every((label) => Number(label) >= 0 && Number(label) <= 255));
  const accountingPortValid = /^[0-9]{1,5}$/.test(accountingPort) &&
    Number(accountingPort) >= 1 && Number(accountingPort) <= 65535;
  const accountingSecretBytes = new TextEncoder().encode(accountingSecret).length;
  const accountingSecretRequired = enterpriseMode && accountingEnabled &&
    (!config.accounting_secret_set || accountingServerValue !== config.accounting_server) &&
    accountingSecret.length === 0;
  const accountingReady = !enterpriseMode || !accountingEnabled ||
    (accountingServerValid && accountingPortValid && !accountingSecretRequired &&
      (accountingSecret.length === 0 || (accountingSecretBytes >= 16 && accountingSecretBytes <= 128 &&
        !/[\u0000-\u001f\u007f]/.test(accountingSecret))));
  const changed = pmfNeedsRepair || radiusVlanConfigurationChanged ||
    ssid !== config.ssid || networkChanged || encryptionChanged || passphrase.length > 0 ||
    (enterpriseMode && (radiusServer !== config.radius_auth_server ||
      radiusPort !== String(config.radius_auth_port || 1812) || radiusSecret.length > 0 ||
      accountingEnabled !== Boolean(config.accounting_server) ||
      (accountingEnabled && (accountingServerValue !== config.accounting_server ||
        accountingPort !== String(config.accounting_port || 1813) || accountingSecret.length > 0)))) ||
    hidden !== config.hidden || channel !== currentChannel || htmode !== currentHtmode || txpower !== currentTxpower;
  const ready = changed && channelSupported && htmodeSupported && txpowerSupported &&
    networkSupported && !passphraseRequired && radiusReady && accountingReady && radiusVlanReady &&
    (encryption !== "none" || allowOpen) && confirmDisconnect && !saving;

  const apply = async () => {
    if (!ready) return;
    setSaving(true);
    setNotice(null);
    try {
      await updateRouterWirelessConfig({
        radio: config.radio,
        section: config.section,
        ssid,
        network,
        encryption,
        key: passphrase,
        radiusServer,
        radiusPort,
        radiusSecret,
        manageRadiusVlans: radiusVlanManaged,
        dynamicVlanEnabled: radiusVlanManaged && enterpriseMode && radiusDynamicVlanEnabled,
        radiusVlans: radiusVlanManaged && enterpriseMode && radiusDynamicVlanEnabled ? radiusVlanMappings : [],
        accountingServer: enterpriseMode && accountingEnabled ? accountingServerValue : "",
        accountingPort,
        accountingSecret,
        hidden,
        channel,
        htmode,
        txpower,
        allowOpen,
      });
      setPassphrase("");
      setRadiusSecret("");
      setAccountingSecret("");
      setAllowOpen(false);
      setConfirmDisconnect(false);
      setNotice({
        success: true,
        message: "Wireless settings were saved and the radio reload completed. Devices may need to reconnect.",
      });
      refresh();
    } catch (error) {
      setNotice({
        success: false,
        message: error instanceof Error ? error.message : "Wireless configuration failed.",
      });
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="wireless-config-editor">
      <div className="wireless-config-heading">
        <div>
          <strong>{config.ssid || "Hidden / unnamed network"}</strong>
          <span>{config.radio} · {config.section} · {config.interface_disabled || config.radio_disabled ? "DISABLED" : "AP CONFIGURED"} · {config.encryption === "wpa3" ? (config.ieee80211w === "2" ? "WPA3-E PMF REQUIRED" : "WPA3-E PMF MISSING") : null} · {(config.encryption === "wpa2" || config.encryption === "wpa3")
            ? (config.radius_secret_set
              ? (config.accounting_secret_set ? "RADIUS AUTH + ACCOUNTING SET" : "RADIUS AUTH SET")
              : "RADIUS NOT CONFIGURED")
            : (config.key_set ? "PASSPHRASE SET" : "NO PASSPHRASE")}</span>
        </div>
        <Status active={!config.interface_disabled && !config.radio_disabled}>
          {config.interface_disabled || config.radio_disabled ? "DISABLED" : "CONFIGURED"}
        </Status>
      </div>
      <div className="wireless-config-grid">
        <label className="wireless-config-field">
          <span>NETWORK NAME (SSID)</span>
          <input value={ssid} maxLength={32} onChange={(event) => setSsid(event.target.value)} autoComplete="off" />
        </label>
        <label className="wireless-config-field">
          <span>ROUTED NETWORK / VLAN</span>
          <select
            value={network}
            onChange={(event) => {
              setNetwork(event.target.value);
              setConfirmDisconnect(false);
              setNotice(null);
            }}
            disabled={saving || eligibleNetworkInterfaces.length === 0}
          >
            <option value="">Select one internal static network</option>
            {eligibleNetworkInterfaces.map((item) => (
              <option value={item.name} key={item.name}>
                {item.name} · {item.device} · {item.firewall_zones.join(", ")}
              </option>
            ))}
          </select>
          <small>Each SSID maps to one existing routed interface. Create its VLAN, gateway, DHCP pool and firewall zone in Office Networks first.</small>
        </label>
        <label className="wireless-config-field">
          <span>SECURITY</span>
          <select value={encryption} onChange={(event) => {
            setEncryption(event.target.value as "psk2" | "sae" | "sae-mixed" | "wpa2" | "wpa3" | "none");
            setPassphrase("");
            setRadiusSecret("");
            setAllowOpen(false);
          }}>
            <option value="psk2">WPA2-Personal (AES)</option>
            <option value="sae">WPA3-Personal (SAE)</option>
            <option value="sae-mixed">WPA2 / WPA3 transition</option>
            <option value="wpa2">WPA2-Enterprise (RADIUS)</option>
            <option value="wpa3">WPA3-Enterprise (RADIUS · PMF required)</option>
            <option value="none">Open (no encryption)</option>
          </select>
        </label>
        <label className="wireless-config-field">
          <span>NEW PASSPHRASE</span>
          <input
            type="password"
            value={passphrase}
            onChange={(event) => setPassphrase(event.target.value)}
            placeholder={enterpriseMode ? "Not used with Enterprise security" :
              config.key_set && !encryptionChanged ? "Leave blank to keep the current key" : "Enter 8–63 characters"}
            autoComplete="new-password"
            disabled={encryption === "none" || enterpriseMode}
          />
        </label>
        {enterpriseMode ? (
          <>
            <label className="wireless-config-field">
              <span>RADIUS AUTHENTICATION SERVER</span>
              <input
                value={radiusServer}
                onChange={(event) => setRadiusServer(event.target.value)}
                placeholder="radius.example.com or 192.0.2.10"
                autoComplete="off"
              />
              <small>Use an IPv4 address or DNS hostname reachable from this router.</small>
            </label>
            <label className="wireless-config-field">
              <span>RADIUS AUTHENTICATION PORT</span>
              <input
                type="number"
                min={1}
                max={65535}
                step={1}
                value={radiusPort}
                onChange={(event) => setRadiusPort(event.target.value)}
                inputMode="numeric"
              />
              <small>UDP authentication port; the standard default is 1812.</small>
            </label>
            <label className="wireless-config-field">
              <span>RADIUS SHARED SECRET</span>
              <input
                type="password"
                value={radiusSecret}
                onChange={(event) => setRadiusSecret(event.target.value)}
                placeholder={config.radius_secret_set && !encryptionChanged &&
                  radiusServer === config.radius_auth_server
                    ? "Leave blank to retain the existing secret"
                    : "Enter 16–128 characters"}
                autoComplete="new-password"
              />
              <small>The secret is stored only in router configuration and is never returned by the API.</small>
            </label>
            <label className="wireless-config-field wireless-config-accounting-toggle">
              <input type="checkbox" checked={accountingEnabled} onChange={(event) => setAccountingEnabled(event.target.checked)} />
              <span>Enable RADIUS accounting (optional)</span>
            </label>
            {accountingEnabled ? (
              <>
                <label className="wireless-config-field">
                  <span>RADIUS ACCOUNTING SERVER</span>
                  <input
                    value={accountingServer}
                    onChange={(event) => setAccountingServer(event.target.value)}
                    placeholder={radiusServer || "accounting.example.com"}
                    autoComplete="off"
                  />
                  <small>Defaults to the authentication server when left blank.</small>
                </label>
                <label className="wireless-config-field">
                  <span>RADIUS ACCOUNTING PORT</span>
                  <input
                    type="number"
                    min={1}
                    max={65535}
                    step={1}
                    value={accountingPort}
                    onChange={(event) => setAccountingPort(event.target.value)}
                    inputMode="numeric"
                  />
                  <small>UDP accounting port; the standard default is 1813.</small>
                </label>
                <label className="wireless-config-field">
                  <span>RADIUS ACCOUNTING SHARED SECRET</span>
                  <input
                    type="password"
                    value={accountingSecret}
                    onChange={(event) => setAccountingSecret(event.target.value)}
                    placeholder={config.accounting_secret_set &&
                      accountingServerValue === config.accounting_server
                        ? "Leave blank to retain the existing secret"
                        : "Enter 16–128 characters"}
                    autoComplete="new-password"
                  />
                  <small>The accounting secret is stored only on the router and is never returned by the API.</small>
                </label>
              </>
            ) : null}
          </>
        ) : null}
        {enterpriseMode ? (
          <div className="wireless-radius-vlan">
            <div className="wireless-radius-vlan-heading">
              <strong>RADIUS dynamic VLAN assignment</strong>
              <span>Use RADIUS Tunnel-Type=VLAN, Tunnel-Medium-Type=IEEE-802 and Tunnel-Private-Group-ID matching one configured VLAN ID.</span>
            </div>
            {config.radius_vlan_unmanaged ? (
              <div className="module-message">
                Existing RADIUS VLAN settings are not wholly owned by QuantumGrid and are left unchanged.
                {config.dynamic_vlan > 0 ? " The AP currently reports dynamic_vlan=" + config.dynamic_vlan + "." : " Custom hostapd VLAN options or manually defined wifi-vlan mappings were detected."}
                Edit them through administrator-managed hostapd configuration or remove the external mapping before using this editor.
              </div>
            ) : (
              <>
                <label className="wireless-config-field wireless-config-accounting-toggle">
                  <input
                    type="checkbox"
                    checked={radiusDynamicVlanEnabled}
                    onChange={(event) => {
                      setRadiusDynamicVlanEnabled(event.target.checked);
                      setConfirmDisconnect(false);
                      setNotice(null);
                    }}
                    disabled={saving || !enterpriseMode}
                  />
                  <span>Require a valid RADIUS VLAN assignment (dynamic_vlan=2)</span>
                </label>
                {radiusDynamicVlanEnabled ? (
                  <>
                    <small>Only pre-provisioned office VLANs with a VLAN-filtered bridge, switch-port membership and a default-deny internal firewall zone are available. Unlisted RADIUS VLANs are rejected by hostapd.</small>
                    <div className="wireless-radius-vlan-list">
                      {radiusVlanMappings.map((mapping, index) => {
                        const selected = eligibleRadiusVlans.find((item) =>
                          item.vid === mapping.vid && item.network === mapping.network);
                        return (
                          <div className="wireless-radius-vlan-row" key={mapping.vid + ":" + mapping.network}>
                            <div>
                              <strong>VLAN {mapping.vid}</strong>
                              <span>{selected ? selected.device + " · " + selected.zone : mapping.network + " · not eligible"}</span>
                            </div>
                            <select
                              value={mapping.network}
                              onChange={(event) => {
                                const candidate = eligibleRadiusVlans.find((item) => item.network === event.target.value);
                                if (!candidate) return;
                                setRadiusVlanMappings((current) => current.map((item, position) =>
                                  position === index ? { vid: candidate.vid, network: candidate.network } : item));
                                setConfirmDisconnect(false);
                                setNotice(null);
                              }}
                              disabled={saving || eligibleRadiusVlans.length === 0}
                            >
                              {eligibleRadiusVlans.map((item) => (
                                <option value={item.network} key={item.network}>
                                  VLAN {item.vid} · {item.network} · {item.zone}
                                </option>
                              ))}
                            </select>
                            <button
                              type="button"
                              className="office-remove-start"
                              onClick={() => {
                                setRadiusVlanMappings((current) => current.filter((_, position) => position !== index));
                                setConfirmDisconnect(false);
                                setNotice(null);
                              }}
                              disabled={saving}
                            >Remove</button>
                          </div>
                        );
                      })}
                    </div>
                    <button
                      type="button"
                      className="office-remove-start"
                      onClick={() => {
                        const usedNetworks = new Set(radiusVlanMappings.map((item) => item.network));
                        const next = eligibleRadiusVlans.find((item) => !usedNetworks.has(item.network) &&
                          !radiusVlanMappings.some((entry) => entry.vid === item.vid));
                        if (!next || radiusVlanMappings.length >= 16) return;
                        setRadiusVlanMappings((current) => [...current, { vid: next.vid, network: next.network }]);
                        setConfirmDisconnect(false);
                        setNotice(null);
                      }}
                      disabled={saving || radiusVlanMappings.length >= 16 ||
                        !eligibleRadiusVlans.some((item) =>
                          !radiusVlanMappings.some((entry) => entry.network === item.network || entry.vid === item.vid))}
                    >Add VLAN mapping</button>
                    {eligibleRadiusVlans.length === 0 ? (
                      <div className="module-message">Create routed office VLAN interfaces and default-deny firewall zones in Office Networks before assigning RADIUS VLANs.</div>
                    ) : null}
                  </>
                ) : (
                  <small>RADIUS dynamic VLAN assignment is disabled for this AP. Saving removes only QuantumGrid-managed mappings.</small>
                )}
              </>
            )}
          </div>
        ) : null}
        <label className="wireless-config-field">
          <span>RADIO CHANNEL</span>
          <select value={channel} onChange={(event) => setChannel(event.target.value)}>
            <option value="auto">Auto (driver chooses)</option>
            {channel !== "auto" && channel === currentChannel && !supportedChannels.includes(Number(channel)) ? (
              <option value={channel}>Current channel {channel} (not in driver list)</option>
            ) : null}
            {supportedChannels.map((item) => (
              <option value={String(item)} key={item}>Channel {item}</option>
            ))}
          </select>
          <small>Changing this channel affects every SSID on {config.radio}.</small>
        </label>
        <label className="wireless-config-field">
          <span>CHANNEL WIDTH / PHY MODE</span>
          <select value={htmode} onChange={(event) => setHtmode(event.target.value)}>
            <option value="auto">Auto / driver default</option>
            {htmode !== "auto" && htmode === currentHtmode && !supportedHtModes.includes(htmode) ? (
              <option value={htmode}>Current {htmode} (not in driver list)</option>
            ) : null}
            {supportedHtModes.map((mode) => (
              <option value={mode} key={mode}>{mode}</option>
            ))}
          </select>
          <small>Only driver-reported modes are selectable; width changes affect every AP on this radio.</small>
        </label>
        <label className="wireless-config-field">
          <span>TRANSMIT POWER</span>
          <select value={txpower} onChange={(event) => setTxpower(event.target.value)}>
            <option value="auto">Auto / regulatory default</option>
            {txpower !== "auto" && txpower === currentTxpower && !supportedTxPower.includes(Number(txpower)) ? (
              <option value={txpower}>Current {txpower} dBm (not in driver list)</option>
            ) : null}
            {supportedTxPower.map((power) => (
              <option value={String(power)} key={power}>{power} dBm</option>
            ))}
          </select>
          <small>Values are limited to the radio driver’s reported power levels and local regulatory configuration.</small>
        </label>
      </div>
      <div className="wireless-config-options">
        <label>
          <input type="checkbox" checked={hidden} onChange={(event) => setHidden(event.target.checked)} />
          <span>Hide network name (SSID)</span>
        </label>
        {encryption === "none" ? (
          <label className="wireless-config-risk">
            <input type="checkbox" checked={allowOpen} onChange={(event) => setAllowOpen(event.target.checked)} />
            <span>I explicitly want an unencrypted, open Wi-Fi network.</span>
          </label>
        ) : null}
      </div>
      <div className="module-message wireless-config-note">
        The existing AP is edited in place; no new SSID or radio is created. Each AP is attached to one existing static L3 network interface. The optional RADIUS dynamic VLAN manager is limited to pre-provisioned bridge VLANs with a routed static interface, switch-port membership and a default-deny firewall zone. It enables hostapd dynamic_vlan=2 (required VLAN assignment), writes explicit native wifi-vlan mappings, and rolls those mappings back with the AP configuration if Wi-Fi reload fails. Unmanaged/custom hostapd VLAN settings are preserved and made read-only. RADIUS dynamic assignment uses one allow-listed VLAN per RADIUS response; it does not create VLANs or subnets dynamically. WPA3-Enterprise requires Protected Management Frames. Channel, width and transmit power remain radio-wide. Applying changes reloads Wi-Fi and can disconnect clients.
      </div>
      <label className="wireless-config-confirm">
        <input type="checkbox" checked={confirmDisconnect} onChange={(event) => setConfirmDisconnect(event.target.checked)} />
        <span>I understand that applying these settings may disconnect my current Wi-Fi session.</span>
      </label>
      {notice ? <div className={notice.success ? "wireless-config-result success" : "wireless-config-result error"} role="status">{notice.message}</div> : null}
      <div className="wireless-config-actions">
        <button className="hero-button" onClick={() => {
          setSsid(config.ssid);
          setNetwork(currentNetwork);
          setEncryption(config.encryption === "sae" || config.encryption === "sae-mixed" ||
            config.encryption === "wpa2" || config.encryption === "wpa3" || config.encryption === "none" ? config.encryption : "psk2");
          setPassphrase("");
          setRadiusServer(config.radius_auth_server || "");
          setRadiusPort(String(config.radius_auth_port || 1812));
          setRadiusSecret("");
          setAccountingServer(config.accounting_server || "");
          setAccountingPort(String(config.accounting_port || 1813));
          setAccountingSecret("");
          setAccountingEnabled(Boolean(config.accounting_server));
          setRadiusDynamicVlanEnabled(config.dynamic_vlan === 2 && !config.radius_vlan_unmanaged);
          setRadiusVlanMappings(config.radius_vlan_mappings.filter((mapping) => mapping.managed)
            .map((mapping) => ({ vid: String(mapping.vid), network: mapping.network })));
          setHidden(config.hidden);
          setChannel(currentChannel);
          setHtmode(currentHtmode);
          setTxpower(currentTxpower);
          setAllowOpen(false);
          setConfirmDisconnect(false);
          setNotice(null);
        }} disabled={!changed || saving}>Discard changes</button>
        <button className="hero-button" onClick={() => void apply()} disabled={!ready}>
          {saving ? "Applying…" : "Save & reload Wi-Fi"}
        </button>
      </div>
      {!channelSupported ? <div className="module-message">Choose Auto or a non-restricted channel reported by the radio driver.</div> : null}
      {!htmodeSupported ? <div className="module-message">Choose Auto or a width/PHY mode reported by the radio driver.</div> : null}
      {!txpowerSupported ? <div className="module-message">Choose Auto or a transmit-power level reported by the radio driver.</div> : null}
      {passphraseRequired ? <div className="module-message">A new passphrase is required when enabling personal security or changing the personal security mode.</div> : null}
      {!networkSupported ? <div className="module-message">Select one existing static network attached to a single internal firewall zone. No WAN/WWAN or ambiguous network mapping may be used.</div> : null}
      {config.networks.length !== 1 ? <div className="module-message">This AP currently has {config.networks.length === 0 ? "no" : "multiple"} network attachment(s). Choose one explicit internal network before saving to normalize its VLAN binding.</div> : null}
      {enterpriseMode && encryption === "wpa3" ? <div className="module-message">WPA3-Enterprise enforces Protected Management Frames (802.11w) as required.</div> : null}
      {pmfNeedsRepair ? <div className="module-message">This existing WPA3-Enterprise AP is missing mandatory Protected Management Frames. Saving will set 802.11w to required.</div> : null}
      {enterpriseMode && !radiusServerValid ? <div className="module-message">Enter a valid IPv4 RADIUS server address or DNS hostname.</div> : null}
      {enterpriseMode && radiusDynamicVlanEnabled && !radiusVlanMappingsValid
        ? <div className="module-message">Add at least one unique RADIUS VLAN mapping from the pre-provisioned default-deny office VLAN list. Each VLAN ID and routed network may appear only once.</div>
        : null}
      {enterpriseMode && config.radius_vlan_unmanaged
        ? <div className="module-message">This AP has externally managed RADIUS VLAN options. QuantumGrid will preserve them and will not overwrite their UCI mappings.</div>
        : null}

      {enterpriseMode && !radiusPortValid ? <div className="module-message">Enter a RADIUS authentication port from 1 to 65535.</div> : null}
      {radiusSecretRequired ? <div className="module-message">A new RADIUS shared secret is required when enabling enterprise security or changing its server.</div> : null}
      {enterpriseMode && accountingEnabled && !accountingServerValid ? <div className="module-message">Enter a valid accounting server or authentication server fallback.</div> : null}
      {enterpriseMode && accountingEnabled && !accountingPortValid ? <div className="module-message">Enter a RADIUS accounting port from 1 to 65535.</div> : null}
      {accountingSecretRequired ? <div className="module-message">A new accounting shared secret is required when enabling accounting or changing its server.</div> : null}
      {enterpriseMode && accountingEnabled && accountingSecret.length > 0 &&
        (accountingSecretBytes < 16 || accountingSecretBytes > 128 || /[\u0000-\u001f\u007f]/.test(accountingSecret))
        ? <div className="module-message">Accounting shared secret must be 16–128 bytes and contain no control characters.</div> : null}
      {enterpriseMode && radiusSecret.length > 0 &&
        (radiusSecretBytes < 16 || radiusSecretBytes > 128 || /[\u0000-\u001f\u007f]/.test(radiusSecret))
        ? <div className="module-message">RADIUS shared secret must be 16–128 bytes and contain no control characters.</div> : null}
    </div>
  );
}


function WifiControlPage({ routerOverview, refresh }: { routerOverview: RouterOverview | null; refresh: () => void }) {
  const radios = routerOverview?.wireless ?? [];
  const wirelessConfigs = routerOverview?.wireless_configs;
  const clients = routerOverview?.clients ?? [];
  const inventoryAvailable = Array.isArray(routerOverview?.clients);
  const wirelessClients = routerOverview?.wireless_clients ?? [];
  const wirelessInventoryAvailable = Array.isArray(routerOverview?.wireless_clients);
  const [scan, setScan] = useState<RouterWifiScan | null>(null);
  const [scanLoading, setScanLoading] = useState(false);
  const [scanError, setScanError] = useState("");
  const [scanHistory, setScanHistory] = useState<WifiScanHistorySample[]>([]);
  const [clientHistoryState, setClientHistoryState] = useState(() => {
    try {
      let enabled = false;
      let retentionDays: WifiClientHistoryRetentionDays = 7;
      const settingsRaw = window.localStorage.getItem(WIFI_CLIENT_HISTORY_SETTINGS_KEY);
      if (settingsRaw) {
        const settings: unknown = JSON.parse(settingsRaw);
        if (typeof settings === "object" && settings !== null) {
          const value = settings as { enabled?: unknown; retentionDays?: unknown };
          enabled = value.enabled === true;
          if (value.retentionDays === 1 || value.retentionDays === 7 || value.retentionDays === 30) {
            retentionDays = value.retentionDays;
          }
        }
      }
      const stored = readWifiClientHistory(window.localStorage.getItem(WIFI_CLIENT_HISTORY_KEY));
      const samples = pruneWifiClientHistory(stored, Math.floor(Date.now() / 1000), retentionDays);
      return { samples, enabled, retentionDays, error: "" };
    } catch {
      return {
        samples: [] as WifiClientHistorySample[],
        enabled: false,
        retentionDays: 7 as WifiClientHistoryRetentionDays,
        error: "Browser storage could not be read. Client history remains unavailable on this browser.",
      };
    }
  });
  const clientHistory = clientHistoryState.samples;
  const clientHistoryEnabled = clientHistoryState.enabled;
  const clientHistoryRetention = clientHistoryState.retentionDays;
  const clientHistoryError = clientHistoryState.error;
  const [scanFilter, setScanFilter] = useState("");
  const [scanSecurityFilter, setScanSecurityFilter] = useState<"all" | "open" | "encrypted" | "unknown">("all");
  const [scanBandFilter, setScanBandFilter] = useState("all");
  const [scanSort, setScanSort] = useState<"signal" | "channel" | "ssid">("signal");

  const availableScanBands = scan
    ? [...new Set(scan.results.map((network) => network.band || "Unknown"))].sort()
    : [];
  const visibleScanResults = scan
    ? scan.results
      .filter((network) => {
        const query = scanFilter.trim().toLocaleLowerCase();
        const matchesText = !query || [
          network.ssid, network.bssid, network.radio, network.ifname, network.band,
          network.security, network.mode, network.channel === undefined ? "" : String(network.channel),
        ].some((value) => value.toLocaleLowerCase().includes(query));
        const matchesSecurity = scanSecurityFilter === "all" ||
          (scanSecurityFilter === "open" && network.security === "Open") ||
          (scanSecurityFilter === "unknown" && network.security === "Unknown") ||
          (scanSecurityFilter === "encrypted" && !["Open", "Unknown"].includes(network.security));
        const matchesBand = scanBandFilter === "all" || (network.band || "Unknown") === scanBandFilter;
        return matchesText && matchesSecurity && matchesBand;
      })
      .sort((left, right) => {
        if (scanSort === "ssid") return (left.ssid || "").localeCompare(right.ssid || "");
        if (scanSort === "channel") {
          if (left.band !== right.band) return left.band.localeCompare(right.band);
          return (left.channel ?? Number.MAX_SAFE_INTEGER) - (right.channel ?? Number.MAX_SAFE_INTEGER);
        }
        return (right.signal_dbm ?? -Infinity) - (left.signal_dbm ?? -Infinity);
      })
    : [];
  const channelGroups = scan ? summarizeWifiChannels(scan.results) : [];
  const channelPlans = scan ? planWifiChannels(scan.results, radios) : [];
  const latestScanHistory = scanHistory[scanHistory.length - 1] ?? null;
  const previousScanHistory = scanHistory.length > 1 ? scanHistory[scanHistory.length - 2] : null;
  const scanComparison = latestScanHistory && previousScanHistory
    ? compareWifiScanHistory(latestScanHistory, previousScanHistory)
    : null;
  const scanComparisonHasChanges = Boolean(scanComparison && (
    scanComparison.newlyObserved.length > 0 ||
    scanComparison.notObserved.length > 0 ||
    scanComparison.signalChanges.length > 0
  ));
  const strongestNetwork = scan?.results
    .filter((network) => typeof network.signal_dbm === "number" && Number.isFinite(network.signal_dbm))
    .reduce<RouterWifiScan["results"][number] | null>(
      (strongest, network) => !strongest || (network.signal_dbm ?? -Infinity) > (strongest.signal_dbm ?? -Infinity)
        ? network
        : strongest,
      null,
    ) ?? null;
  const bandsObserved = scan ? new Set(scan.results.map((network) => network.band)).size : 0;
  const clientHistoryUniqueCount = new Set(clientHistory.map((sample) => sample.mac)).size;
  const recentClientHistory = clientHistory.slice(-12).reverse();
  const openNetworkCount = scan ? scan.results.filter((network) => network.security === "Open").length : 0;
  const unknownSecurityCount = scan ? scan.results.filter((network) => network.security === "Unknown").length : 0;
  const exportScanHistory = () => {
    if (scanHistory.length === 0) return;
    const rows: Array<Array<string | number | null | undefined>> = [
      ["Scanned at (UTC)", "Access points", "2.4 GHz", "5 GHz", "6 GHz", "Other bands"],
      ...scanHistory.map((sample) => [
        new Date(sample.scannedAt * 1000).toISOString(),
        sample.accessPoints,
        sample.bandCounts["2.4 GHz"] ?? 0,
        sample.bandCounts["5 GHz"] ?? 0,
        sample.bandCounts["6 GHz"] ?? 0,
        Object.entries(sample.bandCounts)
          .filter(([band]) => !["2.4 GHz", "5 GHz", "6 GHz"].includes(band))
          .map(([band, count]) => band + ": " + count)
          .join(" / "),
      ]),
    ];
    const csv = rows.map((row) => row.map(csvCell).join(",")).join("\r\n");
    const objectUrl = URL.createObjectURL(new Blob(["\uFEFF", csv], { type: "text/csv;charset=utf-8" }));
    const link = document.createElement("a");
    link.href = objectUrl;
    link.download = `quantumgrid-wifi-history-${new Date().toISOString().replace(/[:.]/g, "-")}.csv`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(objectUrl), 0);
  };

  const exportScanComparison = () => {
    if (!scanComparison || !previousScanHistory || !latestScanHistory || !scanComparisonHasChanges) return;
    const previousAt = new Date(previousScanHistory.scannedAt * 1000).toISOString();
    const latestAt = new Date(latestScanHistory.scannedAt * 1000).toISOString();
    const rows: Array<Array<string | number | null | undefined>> = [
      ["Previous scan (UTC)", "Latest scan (UTC)", "Change type", "SSID", "BSSID", "Band", "Channel", "Previous signal dBm", "Latest signal dBm", "Signal delta dB"],
      ...scanComparison.newlyObserved.map((network) => [
        previousAt, latestAt, "NEWLY OBSERVED", network.ssid, network.bssid, network.band, network.channel, "", network.signal_dbm, "",
      ]),
      ...scanComparison.notObserved.map((network) => [
        previousAt, latestAt, "NOT OBSERVED IN LATEST", network.ssid, network.bssid, network.band, network.channel, network.signal_dbm, "", "",
      ]),
      ...scanComparison.signalChanges.map(({ network, previousDbm, currentDbm, deltaDb }) => [
        previousAt, latestAt, "SIGNAL CHANGED", network.ssid, network.bssid, network.band, network.channel, previousDbm, currentDbm, deltaDb,
      ]),
    ];
    const csv = rows.map((row) => row.map(csvCell).join(",")).join("\r\n");
    const objectUrl = URL.createObjectURL(new Blob(["\uFEFF", csv], { type: "text/csv;charset=utf-8" }));
    const link = document.createElement("a");
    link.href = objectUrl;
    link.download = `quantumgrid-wifi-scan-comparison-${latestAt.replace(/[:.]/g, "-")}.csv`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(objectUrl), 0);
  };

  const exportWifiScan = () => {
    if (!scan || visibleScanResults.length === 0) return;
    const scannedAt = new Date(scan.scanned_at * 1000).toISOString();
    const exportedAt = new Date().toISOString();
    const rows: Array<Array<string | number | null | undefined>> = [
      ["Scanned at (UTC)", "Exported at (UTC)", "Search filter", "Band filter", "Security filter", "Radio", "Interface", "SSID", "BSSID", "Band", "Channel", "Frequency MHz", "Signal dBm", "Quality", "Quality max", "Security", "Authentication", "Cipher suites", "Mode", "PHY operation"],
      ...visibleScanResults.map((network) => [
        scannedAt, exportedAt, scanFilter, scanBandFilter, scanSecurityFilter, network.radio, network.ifname, network.ssid, network.bssid,
        network.band, network.channel, network.frequency_mhz, network.signal_dbm,
        network.quality, network.quality_max, network.security,
        network.authentication?.join("/"), network.ciphers?.join("/"), network.mode, describeScanOperation(network),
      ]),
    ];
    const csv = rows.map((row) => row.map(csvCell).join(",")).join("\r\n");
    const objectUrl = URL.createObjectURL(new Blob(["\uFEFF", csv], { type: "text/csv;charset=utf-8" }));
    const link = document.createElement("a");
    link.href = objectUrl;
    link.download = `quantumgrid-wifi-scan-filtered-${scannedAt.replace(/[:.]/g, "-")}.csv`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(objectUrl), 0);
  };


  const exportClientHistory = () => {
    if (clientHistory.length === 0) return;
    const rows: Array<Array<string | number | boolean | null | undefined>> = [
      ["Sampled at (UTC)", "MAC", "Hostname", "IP", "SSID", "Radio", "Band", "Authorized", "Signal dBm", "RX Mbps", "TX Mbps"],
      ...clientHistory.map((sample) => [
        new Date(sample.sampledAt * 1000).toISOString(),
        sample.mac, sample.hostname, sample.ip, sample.ssid, sample.radio, sample.band,
        sample.authorized, sample.signalDbm, sample.rxMbps, sample.txMbps,
      ]),
    ];
    const csv = rows.map((row) => row.map(csvCell).join(",")).join("\r\n");
    const objectUrl = URL.createObjectURL(new Blob(["\uFEFF", csv], { type: "text/csv;charset=utf-8" }));
    const link = document.createElement("a");
    link.href = objectUrl;
    link.download = `quantumgrid-wifi-client-history-${new Date().toISOString().replace(/[:.]/g, "-")}.csv`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(objectUrl), 0);
  };

  const setClientHistoryEnabled = (enabled: boolean) => {
    let error = "";
    try {
      window.localStorage.setItem(WIFI_CLIENT_HISTORY_SETTINGS_KEY, JSON.stringify({
        enabled,
        retentionDays: clientHistoryRetention,
      }));
    } catch {
      error = "Browser settings could not be saved. Check the browser's local storage permissions.";
    }
    setClientHistoryState((current) => ({ ...current, enabled, error }));
  };

  const changeClientHistoryRetention = (retentionDays: WifiClientHistoryRetentionDays) => {
    const next = pruneWifiClientHistory(clientHistory, Math.floor(Date.now() / 1000), retentionDays);
    let error = "";
    try {
      window.localStorage.setItem(WIFI_CLIENT_HISTORY_SETTINGS_KEY, JSON.stringify({
        enabled: clientHistoryEnabled,
        retentionDays,
      }));
      window.localStorage.setItem(WIFI_CLIENT_HISTORY_KEY, JSON.stringify(next));
    } catch {
      error = "Browser storage could not be updated. Export or clear history.";
    }
    setClientHistoryState((current) => ({ ...current, retentionDays, samples: next, error }));
  };

  const saveClientHistorySnapshot = () => {
    if (!clientHistoryEnabled) {
      setClientHistoryState((current) => ({ ...current, error: "Enable local history before saving a snapshot." }));
      return;
    }
    if (!routerOverview) {
      setClientHistoryState((current) => ({ ...current, error: "Waiting for live router telemetry." }));
      return;
    }
    const sampledAt = Math.floor(Date.now() / 1000);
    const incoming = collectWifiClientHistory(routerOverview, sampledAt);
    if (incoming.length === 0) {
      setClientHistoryState((current) => ({ ...current, error: "No associated Wi-Fi clients were reported in this sample." }));
      return;
    }
    const hasUnsavedObservation = incoming.some((sample) =>
      !clientHistory.some((saved) => saved.sampledAt === sample.sampledAt && saved.mac === sample.mac)
    );
    if (!hasUnsavedObservation) {
      setClientHistoryState((current) => ({ ...current, error: "This client snapshot has already been saved." }));
      return;
    }
    const next = mergeWifiClientHistory(clientHistory, incoming, sampledAt, clientHistoryRetention);
    let error = "";
    try {
      window.localStorage.setItem(WIFI_CLIENT_HISTORY_KEY, JSON.stringify(next));
    } catch {
      error = "Browser storage is full or unavailable. Export or clear history, or disable local collection.";
    }
    setClientHistoryState((current) => ({ ...current, samples: next, error }));
  };

  const clearClientHistory = () => {
    let error = "";
    try {
      window.localStorage.removeItem(WIFI_CLIENT_HISTORY_KEY);
    } catch {
      error = "The browser could not delete the saved history. Clear this site's local storage in browser settings.";
    }
    setClientHistoryState((current) => ({ ...current, samples: [], error }));
  };
  const runWirelessScan = async () => {
    setScanLoading(true);
    setScanError("");
    try {
      const result = await scanRouterWifi();
      setScan(result);
      if (!result.cached) {
        const bandCounts = result.results.reduce<Record<string, number>>((counts, network) => {
          const band = network.band || "Unknown";
          counts[band] = (counts[band] ?? 0) + 1;
          return counts;
        }, {});
        setScanHistory((history) => {
          if (history[history.length - 1]?.scannedAt === result.scanned_at) return history;
          return [...history.slice(-9), {
            scannedAt: result.scanned_at,
            accessPoints: result.results.length,
            bandCounts,
            networks: result.results.map(({ bssid, ssid, band, channel, signal_dbm }) => ({
              bssid, ssid, band, channel, signal_dbm,
            })),
          }];
        });
      }
    }
    catch (error) { setScanError(error instanceof Error ? error.message : "Wireless scan failed."); }
    finally { setScanLoading(false); }
  };

  return (
    <div className="module-page">
      <section className="module-hero">
        <div className="module-icon"><Wifi size={25} /></div>
        <div>
          <div className="setup-kicker">LIVE WIRELESS TELEMETRY</div>
          <h1>Wi-Fi</h1>
          <p>Live radio diagnostics, nearby access-point scanning, client history and guarded edits to existing access-point settings.</p>
        </div>
      </section>
      <div className="module-grid">
        <Panel title="Wireless radios" eyebrow="NETWORK.WIRELESS STATUS" action={<Status active={Boolean(routerOverview)}>{routerOverview ? "LIVE" : "WAITING"}</Status>}>
          <WirelessRadioInventory radios={radios} available={Boolean(routerOverview)} />
        </Panel>
        <Panel title="Wireless configuration" eyebrow="AUTHENTICATED UCI · GUARDED WIFI RELOAD">
          {!wirelessConfigs ? (
            <div className="module-message">Waiting for the router's wireless configuration inventory.</div>
          ) : !wirelessConfigs.available ? (
            <div className="module-message">The router could not read /etc/config/wireless. Configuration controls remain unavailable.</div>
          ) : wirelessConfigs.sections.length === 0 ? (
            <div className="module-message">No existing AP-mode wireless interfaces were found. QuantumGrid does not create a new radio or SSID from this panel.</div>
          ) : (
            <>
              <div className="module-message">Edit existing AP interfaces only. SSID, WPA security, hidden-network state and the selected radio channel are saved together. The server checks channel availability, commits UCI and reloads Wi-Fi; on reload failure it attempts to restore the previous settings.</div>
              <div className="wireless-config-list">
                {wirelessConfigs.sections.map((config) => (
                  <WirelessConfigEditor
                    key={[config.section, config.ssid, config.networks.join(","), config.encryption, config.hidden, config.dynamic_vlan, config.radius_vlan_unmanaged, config.radius_vlan_mappings.map((item) => item.vid + ":" + item.network).join(","), config.channel, config.htmode, config.txpower, config.key_set].join(":")}
                    config={config}
                    radio={radios.find((item) => item.name === config.radio)}
                    networkInterfaces={routerOverview?.office_networks?.interfaces ?? []}
                    officeInventory={routerOverview?.office_networks}
                    refresh={refresh}
                  />
                ))}
              </div>
            </>
          )}
        </Panel>
      </div>
      <Panel title="Associated Wi-Fi clients" eyebrow="IWINFO ASSOCIATION DATA">
        <WirelessClientList clients={wirelessClients} available={wirelessInventoryAvailable} leases={clients} />
        <div className="module-message">AP signal/noise and link bitrate are radio-interface measurements. Per-station signal, noise, rates, counters, connected time and retries are shown separately from iwinfo association data; drivers may omit fields.</div>
      </Panel>
      <Panel
        title="Nearby access points"
        eyebrow="MANUAL IWINFO SCAN"
        action={
          <div className="wifi-scan-actions">
            <button className="hero-button wifi-scan-button" onClick={() => void runWirelessScan()} disabled={!routerOverview || scanLoading}>{scanLoading ? "Scanning…" : scan ? "Scan again" : "Scan nearby networks"}</button>
            <button className="hero-button wifi-export-button" onClick={exportWifiScan} disabled={!scan || visibleScanResults.length === 0}>Export filtered CSV</button>
          </div>
        }
      >
        {scanError ? <div className="module-message" role="alert">{scanError}</div> : null}
        {!scan ? (
          <div className="module-message">Run a manual scan to list nearby access points reported by the wireless driver. Scanning is not part of the automatic telemetry refresh.</div>
        ) : (
          <>
            <div className="module-message">
              {new Date(scan.scanned_at * 1000).toLocaleString()} · {scan.interfaces_scanned} interface(s) scanned
              {scan.interfaces_failed > 0 ? ` · ${scan.interfaces_failed} interface(s) unavailable` : ""}
              {scan.cached ? " · cached result (30-second scan limit)" : " · fresh result"}
              {scan.truncated ? " · result list limited to 128 access points" : ""}
            </div>
            {scan.results.length === 0 ? (
              <div className="module-message">No nearby access points were returned by iwinfo. The radio may not support scanning in its current mode.</div>
            ) : (
              <>
                <div className="wifi-scan-tools">
                  <input className="wifi-scan-filter" type="search" aria-label="Filter nearby access points" placeholder="Filter SSID, BSSID or radio" value={scanFilter} onChange={(event) => setScanFilter(event.target.value)} />
                  <select className="wifi-scan-security" aria-label="Filter nearby access point security" value={scanSecurityFilter} onChange={(event) => setScanSecurityFilter(event.target.value as "all" | "open" | "encrypted" | "unknown")}>
                    <option value="all">All security states</option>
                    <option value="open">Open networks</option>
                    <option value="encrypted">Encrypted networks</option>
                    <option value="unknown">Security unknown</option>
                  </select>
                  <select className="wifi-scan-band" aria-label="Filter nearby access point band" value={scanBandFilter} onChange={(event) => setScanBandFilter(event.target.value)}>
                    <option value="all">All bands</option>
                    {availableScanBands.map((band) => <option value={band} key={band}>{band}</option>)}
                  </select>
                  <select className="wifi-scan-sort" aria-label="Sort nearby access points" value={scanSort} onChange={(event) => setScanSort(event.target.value as "signal" | "channel" | "ssid")}>
                    <option value="signal">Strongest signal first</option>
                    <option value="channel">Band and channel</option>
                    <option value="ssid">SSID A–Z</option>
                  </select>
                  <span>{visibleScanResults.length} of {scan.results.length} access points</span>
                  <button className="hero-button wifi-export-button" onClick={() => {
                    setScanFilter("");
                    setScanSecurityFilter("all");
                    setScanBandFilter("all");
                  }} disabled={!scanFilter && scanSecurityFilter === "all" && scanBandFilter === "all"}>Reset filters</button>
                </div>
                {visibleScanResults.length === 0 ? (
                  <div className="module-message">No access points match this filter.</div>
                ) : (
              <div className="device-list">
                {visibleScanResults.map((network) => (
                  <div className="device-row wifi-scan-row" key={network.ifname + "-" + network.bssid}>
                    <div className="device-title">
                      <div className="device-icon"><Wifi size={17} /></div>
                      <div><strong>{network.ssid || "Hidden network"}</strong><span>{network.radio} · {network.ifname} · {network.bssid}</span></div>
                    </div>
                    <div><small>BAND / MODE</small><b>{network.band} · {network.mode || "N/A"}</b></div>
                    <div><small>CHANNEL / FREQ</small><b>{network.channel === undefined ? "N/A" : fmt(network.channel)}{network.frequency_mhz === undefined ? "" : " · " + fmt(network.frequency_mhz) + " MHz"}</b></div>
                    <div><small>SIGNAL</small><b>{network.signal_dbm === undefined ? "N/A" : fmt(network.signal_dbm) + " dBm"}</b></div>
                    <div><small>QUALITY</small><b>{network.quality === undefined ? "N/A" : fmt(network.quality) + "/" + fmt(network.quality_max ?? 0)}</b></div>
                    <div><small>PHY / WIDTH</small><b>{describeScanOperation(network)}</b></div>
                    <div><small>SECURITY</small><b>{network.security}{network.authentication?.length ? ` · ${network.authentication.join("/")}` : ""}{network.ciphers?.length ? ` · ${network.ciphers.join("/")}` : ""}</b></div>
                  </div>
                ))}
              </div>
                )}
              </>
            )}
          </>
        )}
        <div className="module-message">Scans use the router’s native iwinfo API and do not change Wi-Fi configuration. Depending on the radio driver, a scan may briefly interrupt or slow wireless traffic. Results are cached for 30 seconds to prevent repeated scans. CSV export quotes fields and neutralises spreadsheet formula prefixes in network-controlled text.</div>
      </Panel>
      <Panel title="Channel visibility" eyebrow="SCAN INVENTORY · NOT AIRTIME">
        {!scan ? (
          <div className="module-message">Scan nearby networks to build a channel inventory.</div>
        ) : scan.results.length === 0 ? (
          <div className="module-message">There are no access-point observations to group into channels.</div>
        ) : (
          <>
            <div className="metrics">
              <Metric title="Detected access points" value={fmt(scan.results.length)} unit="" detail="Unique BSSIDs reported in this scan" icon={Wifi} />
              <Metric title="Bands observed" value={fmt(bandsObserved)} unit="" detail={[...new Set(scan.results.map((network) => network.band))].join(" · ") || "N/A"} icon={RadioTower} />
              <Metric title="Strongest neighbour" value={strongestNetwork?.signal_dbm === undefined ? "N/A" : `${fmt(strongestNetwork.signal_dbm)} dBm`} unit="" detail={strongestNetwork?.ssid || "Signal not reported"} icon={Signal} />
              <Metric title="Open networks" value={fmt(openNetworkCount)} unit="" detail="No encryption reported by iwinfo" icon={Lock} />
              <Metric title="Unknown security" value={fmt(unknownSecurityCount)} unit="" detail="Driver did not return encryption state" icon={Shield} />
            </div>
            <div className="device-list">
              {channelGroups.map((group) => (
                <div className="device-row wifi-channel-row" key={group.band + "-" + (group.channel ?? "unknown")}>
                  <div className="device-title">
                    <div className="device-icon"><RadioTower size={17} /></div>
                    <div><strong>{group.band} · {group.channel === null ? "Channel N/A" : `Channel ${group.channel}`}</strong><span>{group.strongestSsid ? `Strongest: ${group.strongestSsid}` : "No signal readings reported"}</span></div>
                  </div>
                  <div><small>OBSERVED APS</small><b>{fmt(group.networks.length)}</b></div>
                  <div><small>STRONGEST SIGNAL</small><b>{group.strongestSignal === null ? "N/A" : `${fmt(group.strongestSignal)} dBm`}</b></div>
                  <div><small>VISIBLE NETWORKS</small><b>{group.networks.map((network) => network.ssid || "Hidden").slice(0, 3).join(", ")}{group.networks.length > 3 ? ` +${group.networks.length - 3}` : ""}</b></div>
                </div>
              ))}
            </div>
          </>
        )}
        <div className="module-message">Groups count distinct BSSIDs returned by this scan on each reported band/channel. A higher count means more networks were visible to this scan; it is not channel airtime, interference, channel width overlap or a channel recommendation. Security labels come from iwinfo encryption metadata; missing metadata is marked Unknown rather than treated as an open network. Take repeat scans from the router’s actual installation location before comparing environments.</div>
      </Panel>
      <Panel title="Channel shortlist" eyebrow="SUPPORTED CHANNELS · OBSERVED OVERLAP">
        {!scan ? (
          <div className="module-message">Run a manual scan first. The shortlist compares only the current scan with channels reported by the radio driver.</div>
        ) : channelPlans.length === 0 ? (
          <div className="module-message">The driver did not provide any unrestricted channel frequencies for an active radio. No channel shortlist can be calculated.</div>
        ) : (
          <div className="wifi-channel-plans">
            {channelPlans.map((plan) => (
              <section className="wifi-channel-plan" key={plan.radio + "-" + plan.band}>
                <div className="wifi-channel-plan-heading">
                  <div>
                    <strong>{plan.radio} · {plan.band}</strong>
                    <span>Compared at {plan.widthMhz} MHz {plan.widthAssumed ? "planning baseline (radio width unavailable or non-contiguous)" : "reported radio width"}</span>
                  </div>
                  <Status active={plan.options.length > 0}>{fmt(plan.options.length)} unrestricted channels</Status>
                </div>
                {plan.options.length === 0 ? (
                  <div className="module-message">No unrestricted channels were returned for this band.</div>
                ) : (
                  <div className="wifi-channel-plan-list">
                    {plan.options.slice(0, 5).map((option, index) => (
                      <div className="wifi-channel-plan-row" key={plan.radio + "-" + plan.band + "-" + option.channel}>
                        <div>
                          <small>{option.relativeScore !== null && index === 0 ? "LOWEST OBSERVED OVERLAP" : option.current ? "CURRENT CHANNEL" : "CANDIDATE"}</small>
                          <strong>Channel {option.channel}{option.current ? " · CURRENT" : ""}</strong>
                          <span>{fmt(option.frequencyMhz)} MHz{option.flags.length ? " · " + option.flags.join(", ") : ""}</span>
                        </div>
                        <div>
                          <small>RELATIVE SCORE</small>
                          <strong>{option.relativeScore === null ? "N/A" : fmt(option.relativeScore, 0) + " / 100"}</strong>
                          <span>{option.relativeScore === null ? "No neighbouring APs observed" : "Lower is less observed overlap"}</span>
                        </div>
                        <div>
                          <small>OVERLAPPING APs</small>
                          <strong>{fmt(option.observedAccessPoints)}</strong>
                          <span>{option.knownSignalAccessPoints} with signal · {option.unknownSignalAccessPoints} without</span>
                        </div>
                        <div>
                          <small>WIDTH COVERAGE</small>
                          <strong>{option.unknownWidthAccessPoints === 0 ? "Known" : "Partial"}</strong>
                          <span>{option.unknownWidthAccessPoints} AP width(s) used 20 MHz fallback</span>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </section>
            ))}
          </div>
        )}
        <div className="module-message">Candidates come only from the radio driver's frequency list and exclude channels marked restricted. The router's own BSSID is excluded when iwinfo identifies it. The relative score is normalised within each radio/band shortlist: 0 is the lowest estimated overlap and 100 the highest. The estimate uses scanned signal strength, advertised width and channel geometry; it is not airtime, CCA busy time, noise, regulatory approval or a guarantee of better performance. Unknown widths use an explicitly marked 20 MHz fallback. DFS/no-IR and other driver flags still need to be respected. This page does not change any radio setting.</div>
      </Panel>
      <Panel
        title="Scan-to-scan changes"
        eyebrow="LATEST TWO DISTINCT MANUAL SCANS"
        action={<button className="hero-button wifi-export-button" onClick={exportScanComparison} disabled={!scanComparisonHasChanges}>Export comparison CSV</button>}
      >
        {!scanComparison ? (
          <div className="module-message">Complete two distinct manual scans to compare access-point visibility and signal readings.</div>
        ) : (
          <>
            <div className="wifi-scan-comparison-metrics">
              <div><small>NEWLY OBSERVED</small><strong>{fmt(scanComparison.newlyObserved.length)}</strong></div>
              <div><small>NOT OBSERVED NOW</small><strong>{fmt(scanComparison.notObserved.length)}</strong></div>
              <div><small>SIGNAL CHANGED</small><strong>{fmt(scanComparison.signalChanges.length)}</strong></div>
            </div>
            <div className="wifi-scan-change-columns">
              <section>
                <div className="wifi-scan-change-heading"><strong>Newly observed</strong><span>{scanComparison.newlyObserved.length} BSSID(s)</span></div>
                {scanComparison.newlyObserved.length === 0 ? (
                  <div className="module-message">No new BSSIDs in the latest scan.</div>
                ) : (
                  <div className="wifi-scan-change-list">
                    {scanComparison.newlyObserved.slice(0, 6).map((network) => (
                      <div key={network.bssid} className="wifi-scan-change-row">
                        <strong>{network.ssid || "Hidden network"}</strong>
                        <span>{network.band || "Unknown band"} · {network.channel === undefined ? "Channel N/A" : `CH ${network.channel}`}</span>
                        <small>{network.bssid}</small>
                      </div>
                    ))}
                  </div>
                )}
                {scanComparison.newlyObserved.length > 6 ? <small className="wifi-scan-change-overflow">Showing 6 of {scanComparison.newlyObserved.length} new BSSIDs.</small> : null}
              </section>
              <section>
                <div className="wifi-scan-change-heading"><strong>Not observed in latest</strong><span>{scanComparison.notObserved.length} BSSID(s)</span></div>
                {scanComparison.notObserved.length === 0 ? (
                  <div className="module-message">All prior BSSIDs were also observed in the latest scan.</div>
                ) : (
                  <div className="wifi-scan-change-list">
                    {scanComparison.notObserved.slice(0, 6).map((network) => (
                      <div key={network.bssid} className="wifi-scan-change-row">
                        <strong>{network.ssid || "Hidden network"}</strong>
                        <span>{network.band || "Unknown band"} · {network.channel === undefined ? "Channel N/A" : `CH ${network.channel}`}</span>
                        <small>{network.bssid}</small>
                      </div>
                    ))}
                  </div>
                )}
                {scanComparison.notObserved.length > 6 ? <small className="wifi-scan-change-overflow">Showing 6 of {scanComparison.notObserved.length} not observed.</small> : null}
              </section>
            </div>
            <section className="wifi-scan-signal-changes">
              <div className="wifi-scan-change-heading"><strong>Largest signal changes</strong><span>Absolute dB change · max 6</span></div>
              {scanComparison.signalChanges.length === 0 ? (
                <div className="module-message">No comparable numeric signal changes were returned for the same BSSIDs.</div>
              ) : (
                <div className="wifi-scan-change-list">
                  {scanComparison.signalChanges.slice(0, 6).map(({ network, previousDbm, currentDbm, deltaDb }) => (
                    <div key={network.bssid} className="wifi-scan-change-row wifi-scan-signal-row">
                      <strong>{network.ssid || "Hidden network"}</strong>
                      <span>{fmt(previousDbm)} → {fmt(currentDbm)} dBm · {deltaDb > 0 ? "+" : ""}{fmt(deltaDb)} dB</span>
                      <small>{network.bssid}</small>
                    </div>
                  ))}
                </div>
              )}
            </section>
            <div className="module-message">A BSSID not observed in one scan may simply have been missed by the radio or driver; it is not proof that the access point is offline. Signal deltas compare driver-reported RSSI for matching BSSIDs only. These observations do not measure airtime, interference or recommend a channel.</div>
          </>
        )}
      </Panel>
      <Panel
        title="Manual scan history"
        eyebrow="LAST 10 DISTINCT SCANS · THIS UI SESSION"
        action={
          <div className="wifi-scan-actions">
            <button className="hero-button wifi-export-button" onClick={exportScanHistory} disabled={scanHistory.length === 0}>Export history CSV</button>
            <button className="hero-button wifi-export-button" onClick={() => setScanHistory([])} disabled={scanHistory.length === 0}>Clear history</button>
          </div>
        }
      >
        {scanHistory.length === 0 ? (
          <div className="module-message">Completed manual scans will appear here. Cached repeat requests are not added as new samples.</div>
        ) : (
          <div className="device-list">
            {scanHistory.map((sample, index) => {
              const previous = index > 0 ? scanHistory[index - 1] : null;
              const change = previous ? sample.accessPoints - previous.accessPoints : null;
              return (
                <div className="device-row wifi-history-row" key={sample.scannedAt}>
                  <div className="device-title">
                    <div className="device-icon"><Activity size={17} /></div>
                    <div><strong>Scan {index + 1}</strong><span>{new Date(sample.scannedAt * 1000).toLocaleString()}</span></div>
                  </div>
                  <div><small>ACCESS POINTS</small><b>{fmt(sample.accessPoints)}</b></div>
                  <div><small>CHANGE VS PRIOR</small><b>{change === null ? "BASELINE" : `${change > 0 ? "+" : ""}${fmt(change)}`}</b></div>
                  <div><small>BANDS</small><b>{Object.entries(sample.bandCounts).map(([band, count]) => `${band}: ${count}`).join(" · ") || "None"}</b></div>
                </div>
              );
            })}
          </div>
        )}
        <div className="module-message">Only distinct, completed manual scans are recorded. The last ten summaries and the minimum BSSID/SSID/band/channel/signal fields needed for comparison stay in page memory only; they are cleared when this page is left, reloaded or the history is cleared. No scan history is written to browser storage or sent to another service.</div>
      </Panel>
      <Panel
        title="Persistent client history"
        eyebrow="OPT-IN · STORED IN THIS BROWSER"
        action={
          <div className="wifi-client-history-actions">
            <label className="wifi-client-history-toggle">
              <input
                type="checkbox"
                checked={clientHistoryEnabled}
                onChange={(event) => setClientHistoryEnabled(event.target.checked)}
              />
              <span>Enable local history</span>
            </label>
            <select
              className="wifi-client-history-retention"
              aria-label="Client history retention"
              value={clientHistoryRetention}
              onChange={(event) => {
                const next = Number(event.target.value);
                if (next === 1 || next === 7 || next === 30) {
                  changeClientHistoryRetention(next as WifiClientHistoryRetentionDays);
                }
              }}
            >
              <option value={1}>Keep 1 day</option>
              <option value={7}>Keep 7 days</option>
              <option value={30}>Keep 30 days</option>
            </select>
            <button className="hero-button wifi-export-button" onClick={saveClientHistorySnapshot} disabled={!clientHistoryEnabled || !routerOverview}>Save snapshot</button>
            <button className="hero-button wifi-export-button" onClick={exportClientHistory} disabled={clientHistory.length === 0}>Export CSV</button>
            <button className="hero-button wifi-export-button" onClick={clearClientHistory} disabled={clientHistory.length === 0}>Clear history</button>
          </div>
        }
      >
        <div className="wifi-client-history-summary">
          <div><small>SAVED OBSERVATIONS</small><strong>{fmt(clientHistory.length)}</strong></div>
          <div><small>DISTINCT CLIENTS</small><strong>{fmt(clientHistoryUniqueCount)}</strong></div>
          <div><small>RETENTION</small><strong>{clientHistoryRetention} DAYS</strong></div>
          <div><small>COLLECTION</small><strong>{clientHistoryEnabled ? "ENABLED" : "OFF"}</strong></div>
        </div>
        {clientHistoryError && <div className="module-message" role="alert">{clientHistoryError}</div>}
        {recentClientHistory.length === 0 ? (
          <div className="module-message">History is empty. Enable local history, then use Save snapshot to store the currently associated Wi-Fi clients in this browser.</div>
        ) : (
          <div className="device-list">
            {recentClientHistory.map((sample, index) => (
              <div className="device-row wifi-client-history-row" key={sample.sampledAt + "-" + sample.mac + "-" + index}>
                <div className="device-title">
                  <div className="device-icon"><Users size={17} /></div>
                  <div><strong>{sample.hostname || sample.mac}</strong><span>{sample.mac} · {sample.ip || "No DHCP lease recorded"}</span></div>
                </div>
                <div><small>NETWORK</small><b>{sample.ssid || "Hidden"} · {sample.band}</b></div>
                <div><small>RADIO / ACCESS</small><b>{sample.radio} · {sample.authorized ? "AUTHORIZED" : "ASSOCIATED"}</b></div>
                <div><small>SIGNAL / RATES</small><b>{sample.signalDbm === null ? "N/A" : sample.signalDbm + " dBm"} · RX {sample.rxMbps === null ? "N/A" : fmt(sample.rxMbps, 1) + " Mbps"} / TX {sample.txMbps === null ? "N/A" : fmt(sample.txMbps, 1) + " Mbps"}</b></div>
                <div><small>OBSERVED AT</small><b>{new Date(sample.sampledAt * 1000).toLocaleString()}</b></div>
              </div>
            ))}
          </div>
        )}
        <div className="module-message">Off by default. When enabled, Save snapshot stores the currently associated Wi-Fi client MAC addresses and available DHCP hostname/IP details only in this browser's local storage. Snapshots are manual, not automatic; the selected retention period (1, 7 or 30 days) is applied when saving or changing retention, up to 10,000 observations. The history is not uploaded, encrypted or synced to another device. Disable collection or clear the history at any time, especially on a shared administrator computer.</div>
      </Panel>
      <Panel title="Known network clients" eyebrow="UNEXPIRED DHCPV4 LEASES">
        <ClientLeaseList clients={clients} available={inventoryAvailable} />
      </Panel>
    </div>
  );
}

function formatKbps(value: number | undefined): string {
  if (value === undefined || !Number.isFinite(value) || value < 0) return "N/A";
  return value >= 1000 ? `${fmt(value / 1000, 2)} Mbps` : `${fmt(value)} Kbps`;
}

function SqmQueueEditor({
  queue,
  saving,
  onApply,
}: {
  queue: RouterSqmQueue;
  saving: boolean;
  onApply: (section: string, enabled: boolean, download: number, upload: number, linklayer: string, overhead: number, tcMpu: number) => Promise<void>;
}) {
  const [enabled, setEnabled] = useState(queue.enabled);
  const [download, setDownload] = useState(queue.download_kbps === undefined ? "" : String(queue.download_kbps));
  const [upload, setUpload] = useState(queue.upload_kbps === undefined ? "" : String(queue.upload_kbps));
  const [linklayer, setLinklayer] = useState(queue.linklayer || "none");
  const [overhead, setOverhead] = useState(String(queue.overhead ?? 0));
  const [tcMpu, setTcMpu] = useState(String(queue.tc_mpu ?? 0));
  const [acknowledged, setAcknowledged] = useState(false);
  const parseRate = (value: string) => /^\d+$/.test(value) ? Number(value) : NaN;
  const parseInteger = (value: string) => /^-?\d+$/.test(value) ? Number(value) : NaN;
  const downloadRate = parseRate(download);
  const uploadRate = parseRate(upload);
  const overheadBytes = parseInteger(overhead);
  const mpuBytes = parseInteger(tcMpu);
  const validRates = Number.isInteger(downloadRate) && Number.isInteger(uploadRate) &&
    downloadRate >= 64 && downloadRate <= 1000000 &&
    uploadRate >= 64 && uploadRate <= 1000000;
  const validTuning = ["none", "ethernet", "atm", "ptm"].includes(linklayer) &&
    Number.isInteger(overheadBytes) && overheadBytes >= -64 && overheadBytes <= 256 &&
    Number.isInteger(mpuBytes) && mpuBytes >= 0 && mpuBytes <= 256;
  const changed = enabled !== queue.enabled ||
    downloadRate !== (queue.download_kbps ?? NaN) ||
    uploadRate !== (queue.upload_kbps ?? NaN) ||
    linklayer !== (queue.linklayer || "none") ||
    overheadBytes !== (queue.overhead ?? 0) ||
    mpuBytes !== (queue.tc_mpu ?? 0);

  return (
    <div className="sqm-policy-editor">
      <div className="sqm-policy-heading">
        <div><strong>{queue.name}</strong><span>{queue.interface || "Interface not set"} · {queue.qdisc || "qdisc not set"}</span></div>
        <Status active={queue.enabled}>{queue.enabled ? "ENABLED" : "DISABLED"}</Status>
      </div>
      <div className="sqm-policy-fields">
        <label className="sqm-policy-enabled">
          <input type="checkbox" checked={enabled} onChange={(event) => { setEnabled(event.target.checked); setAcknowledged(false); }} />
          <span>Enable SQM shaping for this queue</span>
        </label>
        <label>
          <span>Download limit (kbit/s)</span>
          <input type="number" min={64} max={1000000} step={1} inputMode="numeric" value={download}
            onChange={(event) => { setDownload(event.target.value); setAcknowledged(false); }} />
        </label>
        <label>
          <span>Upload limit (kbit/s)</span>
          <input type="number" min={64} max={1000000} step={1} inputMode="numeric" value={upload}
            onChange={(event) => { setUpload(event.target.value); setAcknowledged(false); }} />
        </label>
        <label><span>Link-layer type</span>
          <select value={linklayer} onChange={(event) => { setLinklayer(event.target.value); setAcknowledged(false); }}>
            <option value="none">None</option><option value="ethernet">Ethernet</option>
            <option value="atm">ATM / ADSL</option><option value="ptm">PTM / VDSL</option>
          </select>
        </label>
        <label><span>Packet overhead (bytes)</span>
          <input type="number" min={-64} max={256} step={1} value={overhead}
            onChange={(event) => { setOverhead(event.target.value); setAcknowledged(false); }} />
        </label>
        <label><span>Minimum packet unit (bytes)</span>
          <input type="number" min={0} max={256} step={1} value={tcMpu}
            onChange={(event) => { setTcMpu(event.target.value); setAcknowledged(false); }} />
        </label>
      </div>
      <p className="sqm-policy-help">Choose the link layer from your ISP connection details. Incorrect framing assumptions can reduce throughput or weaken latency control; QuantumGrid does not infer these values.</p>
      <label className="sqm-policy-ack">
        <input type="checkbox" checked={acknowledged} onChange={(event) => setAcknowledged(event.target.checked)} />
        <span>I understand applying queue or link-layer changes restarts SQM and may briefly interrupt traffic.</span>
      </label>
      <div className="sqm-policy-actions">
        <span>Interface, queue discipline and setup script stay unchanged. Link-layer calibration affects packet-size accounting.</span>
        <button className="hero-button" disabled={!changed || !validRates || !validTuning || !acknowledged || saving}
          onClick={() => { void onApply(queue.name, enabled, downloadRate, uploadRate, linklayer, overheadBytes, mpuBytes); }}>
          {saving ? "Applying…" : "Apply & restart SQM"}
        </button>
      </div>
    </div>
  );
}

function GamingControlPage({ routerOverview, refresh }: {
  routerOverview: RouterOverview | null;
  refresh: () => void;
}) {
  const sqm = routerOverview?.sqm;
  const queues = sqm?.queues ?? [];
  const enabledQueues = queues.filter((queue) => queue.enabled);
  const qdiscs = sqm?.qdiscs ?? [];
  const [qdiscSearch, setQdiscSearch] = useState("");
  const [qdiscSort, setQdiscSort] = useState<"kind" | "bytes" | "drops" | "backlog">("kind");
  const visibleQdiscs = qdiscs.filter((qdisc) =>
    [qdisc.kind, qdisc.handle, qdisc.device ?? "", qdisc.parent ?? ""]
      .some((value) => value.toLocaleLowerCase().includes(qdiscSearch.trim().toLocaleLowerCase()))
  ).slice().sort((left, right) => {
    if (qdiscSort === "bytes") return (right.bytes ?? -1) - (left.bytes ?? -1);
    if (qdiscSort === "drops") return (right.dropped ?? -1) - (left.dropped ?? -1);
    if (qdiscSort === "backlog") return (right.backlog_bytes ?? -1) - (left.backlog_bytes ?? -1);
    return left.kind.localeCompare(right.kind) || left.handle.localeCompare(right.handle);
  });
  const cakeCount = qdiscs.filter((qdisc) => qdisc.kind.toLowerCase() === "cake").length;
  const queueConfigAvailable = sqm?.config_available === true && sqm.config_readable;
  const runtimeAvailable = sqm?.runtime_available === true;
  const [savingQueue, setSavingQueue] = useState<string | null>(null);
  const [sqmNotice, setSqmNotice] = useState<{ success: boolean; message: string } | null>(null);
  const applySqmQueue = async (section: string, enabled: boolean, download: number, upload: number, linklayer: string, overhead: number, tcMpu: number) => {
    setSavingQueue(section);
    setSqmNotice(null);
    try {
      await updateRouterSqmQueue(section, enabled, download, upload, linklayer, overhead, tcMpu);
      setSqmNotice({ success: true, message: "SQM settings were saved and the service restarted." });
      refresh();
    } catch (error) {
      setSqmNotice({
        success: false,
        message: error instanceof Error ? error.message : "SQM queue update failed.",
      });
    } finally {
      setSavingQueue(null);
    }
  };
  const exportQdiscs = () => {
    if (visibleQdiscs.length === 0) return;
    const exportedAt = new Date().toISOString();
    const rows: Array<Array<string | number | boolean | null | undefined>> = [
      ["Exported at (UTC)", "Search filter", "Sort order", "Qdisc", "Handle", "Device", "Parent", "Root", "Bytes", "Packets", "Dropped", "Overlimits", "Requeues", "Backlog bytes", "Backlog packets"],
      ...visibleQdiscs.map((qdisc) => [
        exportedAt, qdiscSearch, qdiscSort, qdisc.kind, qdisc.handle, qdisc.device, qdisc.parent,
        qdisc.root, qdisc.bytes, qdisc.packets, qdisc.dropped, qdisc.overlimits,
        qdisc.requeues, qdisc.backlog_bytes, qdisc.backlog_packets,
      ]),
    ];
    const csv = rows.map((row) => row.map(csvCell).join(",")).join("\r\n");
    const objectUrl = URL.createObjectURL(new Blob(["\uFEFF", csv], { type: "text/csv;charset=utf-8" }));
    const link = document.createElement("a");
    link.href = objectUrl;
    link.download = "quantumgrid-qdisc-inventory-" + exportedAt.replace(/[:.]/g, "-") + ".csv";
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(objectUrl), 0);
  };

  return (
    <div className="module-page gaming-page">
      <section className="module-hero">
        <div className="module-icon"><Gamepad2 size={25} /></div>
        <div>
          <div className="setup-kicker">SMART QUEUE MANAGEMENT · LIVE INSPECTION</div>
          <h1>Gaming & Latency</h1>
          <p>Inspect configured SQM queues and kernel queue disciplines. Edit existing queue enable state and rates with a guarded restart; advanced classification and per-client priority stay locked.</p>
        </div>
      </section>

      <div className="metrics">
        <Metric title="SQM Package" value={sqm ? (sqm.installed ? "INSTALLED" : "MISSING") : "N/A"} unit="" detail="sqm init service detection" icon={Settings} />
        <Metric title="Enabled Queue Configs" value={queueConfigAvailable ? fmt(enabledQueues.length) : "N/A"} unit="" detail={queueConfigAvailable ? `${queues.length} queue section(s) found` : "SQM config unavailable"} icon={CircleGauge} />
        <Metric title="CAKE qdiscs" value={runtimeAvailable ? fmt(cakeCount) : "N/A"} unit="" detail="Observed in kernel qdisc inventory" icon={Activity} />
        <Metric title="Runtime qdiscs" value={runtimeAvailable ? fmt(qdiscs.length) : "N/A"} unit="" detail="All interfaces · tc statistics" icon={Network} />
      </div>

      <Panel title="Configured SQM queues" eyebrow="UCI · /ETC/CONFIG/SQM" action={<Status active={Boolean(queueConfigAvailable)}>{queueConfigAvailable ? "CONFIG READ" : "WAITING"}</Status>}>
        {!sqm ? (
          <div className="module-message">Waiting for authenticated router telemetry.</div>
        ) : !sqm.installed ? (
          <div className="module-message">The router does not report the SQM init service as installed.</div>
        ) : !queueConfigAvailable ? (
          <div className="module-message">SQM is installed, but its configuration file or queue data could not be read.</div>
        ) : queues.length === 0 ? (
          <div className="module-message">No SQM queue sections are configured.</div>
        ) : (
          <div className="device-list">
            {queues.map((queue) => (
              <div className="device-row" key={queue.name}>
                <div className="device-title">
                  <div className="device-icon"><Gamepad2 size={17} /></div>
                  <div><strong>{queue.name || "Unnamed queue"}</strong><span>{queue.interface || "Interface not set"}</span></div>
                </div>
                <div><small>CONFIGURATION</small><b>{queue.enabled ? "ENABLED" : "DISABLED"}</b></div>
                <div><small>QDISC / SCRIPT</small><b>{queue.qdisc || "N/A"} · {queue.script || "N/A"}</b></div>
                <div><small>DOWNLOAD</small><b>{formatKbps(queue.download_kbps)}</b></div>
                <div><small>UPLOAD</small><b>{formatKbps(queue.upload_kbps)}</b></div>
              </div>
            ))}
          </div>
        )}
        <div className="module-message">Queue rates are configured SQM values in kbit/s. An enabled UCI section alone does not prove that its shaper is attached to the live WAN path.</div>
      </Panel>

      <Panel title="SQM queue controls" eyebrow="BOUNDED · EXISTING UCI QUEUES ONLY">
        {!queueConfigAvailable ? (
          <div className="module-message">SQM configuration is unavailable. No changes can be made.</div>
        ) : queues.length === 0 ? (
          <div className="module-message">No existing SQM queue sections are available to edit. QuantumGrid will not create a queue or guess a WAN interface.</div>
        ) : (
          <div className="sqm-policy-list">
            {queues.map((queue) => (
              <SqmQueueEditor key={queue.name + "-" + queue.enabled + "-" + (queue.download_kbps ?? "") + "-" + (queue.upload_kbps ?? "") + "-" + queue.linklayer + "-" + (queue.overhead ?? "") + "-" + (queue.tc_mpu ?? "")} queue={queue} saving={savingQueue === queue.name} onApply={applySqmQueue} />
            ))}
          </div>
        )}
        {sqmNotice ? (
          <div className={sqmNotice.success ? "sqm-policy-notice success" : "sqm-policy-notice error"} role="status">{sqmNotice.message}</div>
        ) : null}
        <div className="module-message">Rate limits must be whole numbers from 64 to 1,000,000 kbit/s. Link-layer overhead accepts -64 to 256 bytes and minimum packet unit accepts 0 to 256 bytes. Changes apply only to the selected existing queue; the router snapshots all changed UCI values and attempts rollback if the SQM restart fails.</div>
      </Panel>

      <Panel title="Kernel qdisc inventory" eyebrow="TC -S QDISC SHOW" action={
        <div className="qdisc-export-actions">
          <Status active={runtimeAvailable}>{runtimeAvailable ? "RUNTIME READ" : "NOT AVAILABLE"}</Status>
          <button className="hero-button wifi-export-button" onClick={exportQdiscs} disabled={visibleQdiscs.length === 0}>Export qdisc CSV</button>
        </div>
      }>
        {!sqm ? (
          <div className="module-message">Waiting for router qdisc telemetry.</div>
        ) : !runtimeAvailable ? (
          <div className="module-message">The router could not return kernel qdisc statistics.</div>
        ) : qdiscs.length === 0 ? (
          <div className="module-message">No qdisc entries were returned by the kernel.</div>
        ) : (
          <>
          <div className="qdisc-tools">
            <input type="search" aria-label="Search kernel qdiscs" placeholder="Search qdisc, handle or device" value={qdiscSearch} onChange={(event) => setQdiscSearch(event.target.value)} />
            <select aria-label="Sort kernel qdiscs" value={qdiscSort} onChange={(event) => setQdiscSort(event.target.value as "kind" | "bytes" | "drops" | "backlog")}>
              <option value="kind">Qdisc name</option>
              <option value="bytes">Highest bytes</option>
              <option value="drops">Most dropped packets</option>
              <option value="backlog">Highest backlog</option>
            </select>
            <span>{visibleQdiscs.length} of {qdiscs.length} qdiscs</span>
          </div>
          {visibleQdiscs.length === 0 ? (
            <div className="module-message">No kernel qdiscs match the current search.</div>
          ) : (
          <div className="device-list">
            {visibleQdiscs.map((qdisc, index) => (
              <div className="device-row" key={`${qdisc.device ?? "unknown"}-${qdisc.handle}-${index}`}>
                <div className="device-title">
                  <div className="device-icon"><Activity size={17} /></div>
                  <div><strong>{qdisc.kind}</strong><span>{qdisc.handle} · {qdisc.root ? "root" : qdisc.parent || "child"}</span></div>
                </div>
                <div><small>DEVICE</small><b>{qdisc.device || "N/A"}</b></div>
                <div><small>TRAFFIC SENT</small><b>{qdisc.bytes === undefined ? "N/A" : formatTrafficBytes(qdisc.bytes)}</b></div>
                <div><small>DROPPED / OVERLIMITS</small><b>{qdisc.dropped === undefined ? "N/A" : `${fmt(qdisc.dropped)} / ${fmt(qdisc.overlimits ?? 0)}`}</b></div>
                <div><small>BACKLOG</small><b>{qdisc.backlog_bytes === undefined ? "N/A" : `${formatTrafficBytes(qdisc.backlog_bytes)} · ${fmt(qdisc.backlog_packets ?? 0)} pkt`}</b></div>
              </div>
            ))}
          </div>
          )}
          </>
        )}
        <div className="module-message">This inventory covers kernel qdiscs across interfaces; entries are not automatically attributed to a particular SQM queue. Compare the configured interface and runtime device before concluding that SQM is shaping the WAN. CSV export follows the visible search result and sort order.</div>
      </Panel>

      <div className="module-grid">
        <Panel title="Gaming measurement status" eyebrow="NO SYNTHETIC SCORES">
          <InfoRows rows={[
            ["LATENCY / JITTER", "NOT MEASURED"],
            ["PACKET LOSS", "NOT MEASURED"],
            ["BUFFERBLOAT GRADE", "NOT MEASURED"],
            ["PER-CLIENT PRIORITY", "NOT CONFIGURED"],
          ]} />
        </Panel>
        <Panel title="Advanced traffic policy" eyebrow="NOT YET AVAILABLE">
          <Status active={false}>CLASSIFICATION LOCKED</Status>
          <div className="module-message">This first write-capable SQM control changes only existing queue enable state and rate limits. CAKE tuning, firewall marks, per-client priority and traffic classification remain locked until their packet-path and rollback behaviour can be tested.</div>
        </Panel>
      </div>
    </div>
  );
}


function AuditLogPage() {
  const [inventory, setInventory] = useState<RouterAuditLog | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [search, setSearch] = useState("");
  const [outcomeFilter, setOutcomeFilter] = useState<"all" | "success" | "failed">("all");

  const loadAudit = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      setInventory(await fetchRouterAuditLog());
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "The administrative audit log is unavailable.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    let active = true;
    fetchRouterAuditLog()
      .then((result) => {
        if (active) setInventory(result);
      })
      .catch((cause) => {
        if (active) {
          setError(cause instanceof Error ? cause.message : "The administrative audit log is unavailable.");
        }
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, []);

  const events = inventory?.events ?? [];
  const visible = events.filter((event) => {
    const matchesOutcome = outcomeFilter === "all" || event.outcome === outcomeFilter;
    const query = search.trim().toLocaleLowerCase();
    const matchesText = !query || [
      event.actor, event.remote_ip, event.action, event.target, event.outcome,
    ].some((value) => value.toLocaleLowerCase().includes(query));
    return matchesOutcome && matchesText;
  });

  const exportAudit = () => {
    if (visible.length === 0) return;
    const exportedAt = new Date().toISOString();
    const rows: Array<Array<string | number>> = [
      ["Exported at (UTC)", "Event at (UTC)", "Actor", "Remote IP", "Action", "Target", "Outcome"],
      ...visible.map((event) => [
        exportedAt,
        new Date(event.timestamp * 1000).toISOString(),
        event.actor,
        event.remote_ip,
        event.action,
        event.target,
        event.outcome,
      ]),
    ];
    const csv = rows.map((row) => row.map(csvCell).join(",")).join("\r\n");
    const objectUrl = URL.createObjectURL(new Blob(["\uFEFF", csv], { type: "text/csv;charset=utf-8" }));
    const link = document.createElement("a");
    link.href = objectUrl;
    link.download = "quantumgrid-admin-audit-" + exportedAt.replace(/[:.]/g, "-") + ".csv";
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(objectUrl), 0);
  };

  const successCount = events.filter((event) => event.outcome === "success").length;
  const failedCount = events.filter((event) => event.outcome === "failed").length;

  return (
    <div className="module-page audit-log-page">
      <section className="module-hero">
        <div className="module-icon"><Shield size={25} /></div>
        <div>
          <div className="setup-kicker">OFFICE OPERATIONS · ADMINISTRATION HISTORY</div>
          <h1>Admin Audit</h1>
          <p>Review supported administrative operations, their outcome and source address. The logger excludes submitted credentials, Wi-Fi keys, VPN private keys and configuration values.</p>
        </div>
      </section>

      <div className="metrics">
        <Metric title="Stored Events" value={inventory ? fmt(inventory.count) : "N/A"} unit="" detail="Current + one rotated log" icon={Database} />
        <Metric title="Successful Changes" value={inventory ? fmt(successCount) : "N/A"} unit="" detail="Supported operations recorded" icon={Check} />
        <Metric title="Failed Operations" value={inventory ? fmt(failedCount) : "N/A"} unit="" detail="Execution failures recorded" icon={Activity} />
        <Metric title="Returned Events" value={inventory ? fmt(events.length) : "N/A"} unit="" detail="Newest 200 records maximum" icon={HardDrive} />
      </div>

      <Panel
        title="Administrative event history"
        eyebrow={inventory?.available ? new Date(inventory.sampled_at * 1000).toLocaleString() : "LOCAL PERMISSION-RESTRICTED LOG"}
        action={
          <div className="audit-log-actions">
            <button className="hero-button" onClick={() => { void loadAudit(); }} disabled={loading}>
              <RefreshCw size={14} /> {loading ? "Refreshing…" : "Refresh"}
            </button>
            <button className="hero-button" onClick={exportAudit} disabled={visible.length === 0}>
              <Download size={14} /> Export CSV
            </button>
          </div>
        }
      >
        <div className="audit-log-toolbar">
          <input
            type="search"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Search action, target, actor or source address"
            aria-label="Search audit events"
          />
          <select
            value={outcomeFilter}
            onChange={(event) => setOutcomeFilter(event.target.value as "all" | "success" | "failed")}
            aria-label="Filter audit outcome"
          >
            <option value="all">All outcomes</option>
            <option value="success">Successful</option>
            <option value="failed">Failed</option>
          </select>
          <span>{loading ? "Loading…" : visible.length + " of " + events.length + " events"}</span>
        </div>
        {error ? <div className="module-message" role="alert">{error}</div> : null}
        {!inventory && !loading ? (
          <div className="module-message">The audit log could not be loaded.</div>
        ) : inventory && !inventory.available ? (
          <div className="module-message">No audit events have been recorded yet. Supported administrative operations will appear here after they execute.</div>
        ) : visible.length === 0 ? (
          <div className="module-message">{events.length === 0 ? "No audit events are available." : "No audit events match the current search and outcome filter."}</div>
        ) : (
          <div className="audit-event-list">
            <div className="audit-event-row header"><span>TIME</span><span>ADMIN / SOURCE</span><span>ACTION / TARGET</span><span>OUTCOME</span></div>
            {visible.map((event, index) => (
              <div className="audit-event-row" key={event.timestamp + "-" + event.action + "-" + event.target + "-" + index}>
                <div><strong>{new Date(event.timestamp * 1000).toLocaleString()}</strong><small>{new Date(event.timestamp * 1000).toISOString()}</small></div>
                <div><b>{event.actor || "root"}</b><small>{event.remote_ip || "Source unavailable"}</small></div>
                <div><b>{event.action}</b><small>{event.target || "No target recorded"}</small></div>
                <Status active={event.outcome === "success"}>{event.outcome.toUpperCase()}</Status>
              </div>
            ))}
          </div>
        )}
        {inventory?.truncated && <div className="module-message">The UI is showing the newest 200 records. Older records are not included in this response.</div>}
      </Panel>

      <Panel title="Audit coverage and retention" eyebrow="LOCAL OPERATIONAL HISTORY">
        <div className="audit-coverage-grid">
          <div><strong>Recorded actions</strong><span>First-boot administrator password setup, Wi-Fi/SQM changes, DHCP pool updates and static reservation add/remove, package install/remove/feed updates, LED brightness changes and configuration backup downloads.</span></div>
          <div><strong>Secret handling</strong><span>Only allowlisted action names, outcome, target label, actor and source IP are stored. Submitted passwords, keys, SSIDs, package output and configuration values are excluded.</span></div>
          <div><strong>Storage</strong><span>Stored under /etc/quantumgrid with restrictive directory/file permissions and one rotated log file. The read API returns at most 200 valid events.</span></div>
          <div><strong>Limitations</strong><span>This is a local operational log, not tamper-proof accounting or a compliance certification. Root access can alter it, and some rejected or pre-validation requests are not recorded.</span></div>
        </div>
      </Panel>
    </div>
  );
}


function ipv4ToUint32(value: string): number | null {
  const parts = value.split(".");
  if (parts.length !== 4) return null;
  const octets = parts.map((part) => Number(part));
  if (octets.some((part, index) =>
    !/^(0|[1-9][0-9]{0,2})$/.test(parts[index]) ||
    !Number.isInteger(part) || part < 0 || part > 255
  )) return null;
  return (((octets[0] * 256 + octets[1]) * 256 + octets[2]) * 256 + octets[3]);
}

function ipv4SubnetContainsHost(address: string, interfaceAddress: string, netmask: string): boolean {
  const ip = ipv4ToUint32(address);
  const router = ipv4ToUint32(interfaceAddress);
  const mask = ipv4ToUint32(netmask);
  if (ip === null || router === null || mask === null || mask === 0 || mask === 0xffffffff) return false;
  const inverse = (~mask) >>> 0;
  if (((inverse & (inverse + 1)) >>> 0) !== 0) return false;
  const prefix = mask.toString(2).replace(/0/g, "").length;
  if (prefix < 1 || prefix > 30) return false;
  const network = (router & mask) >>> 0;
  const broadcast = (network | inverse) >>> 0;
  return ((ip & mask) >>> 0) === network && ip > network && ip < broadcast && ip !== router;
}


function DhcpScopeCreateForm({ networks, refresh }: {
  networks: RouterOfficeInterface[];
  refresh: () => void;
}) {
  const [network, setNetwork] = useState(networks[0]?.name ?? "");
  const selectedNetwork = networks.some((item) => item.name === network)
    ? network
    : networks[0]?.name ?? "";
  const [start, setStart] = useState("");
  const [limit, setLimit] = useState("");
  const [leaseTime, setLeaseTime] = useState("12h");
  const [confirmedNetwork, setConfirmedNetwork] = useState<string | null>(null);
  const confirmed = confirmedNetwork === selectedNetwork;
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<{ success: boolean; message: string } | null>(null);

  const create = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!confirmed || busy || !selectedNetwork) return;
    setBusy(true);
    setNotice(null);
    try {
      const result = await createRouterDhcpScope({
        network: selectedNetwork,
        start: start.trim(),
        limit: limit.trim(),
        lease_time: leaseTime.trim(),
      });
      setNotice({
        success: true,
        message: "New DHCP scope created: " + result.pool_start_ip + " – " + result.pool_end_ip + ". dnsmasq restarted.",
      });
      setStart("");
      setLimit("");
      setLeaseTime("12h");
      setConfirmedNetwork(null);
      refresh();
    } catch (cause) {
      setNotice({
        success: false,
        message: cause instanceof Error ? cause.message : "The DHCP scope could not be created.",
      });
    } finally {
      setBusy(false);
    }
  };

  if (networks.length === 0) {
    return (
      <div className="office-dhcp-create-form">
        <div className="module-message">Every eligible static LAN already has a DHCP scope, or no unused static IPv4 LAN is available. Enable or edit an existing scope above; create new network interfaces and VLANs through the separately managed network workflow.</div>
      </div>
    );
  }

  return (
    <form className="office-dhcp-create-form" onSubmit={create}>
      <div className="office-reservation-grid">
        <label>
          <span>Existing static LAN</span>
          <select value={selectedNetwork} onChange={(event) => { setNetwork(event.target.value); setConfirmedNetwork(null); }} required>
            {networks.map((item) => (
              <option key={item.name} value={item.name}>{item.name} · {item.ipv4[0]} / {item.netmask}</option>
            ))}
          </select>
        </label>
        <label>
          <span>Lease duration</span>
          <input
            type="text"
            value={leaseTime}
            onChange={(event) => { setLeaseTime(event.target.value); setConfirmedNetwork(null); }}
            placeholder="12h"
            maxLength={16}
            pattern="[1-9][0-9]{0,8}[smhdw]?"
            required
          />
        </label>
        <label>
          <span>Start offset</span>
          <input
            type="number"
            min={1}
            max={4294967294}
            step={1}
            value={start}
            onChange={(event) => { setStart(event.target.value); setConfirmedNetwork(null); }}
            placeholder="100"
            required
          />
        </label>
        <label>
          <span>Pool size (addresses)</span>
          <input
            type="number"
            min={1}
            max={4294967294}
            step={1}
            value={limit}
            onChange={(event) => { setLimit(event.target.value); setConfirmedNetwork(null); }}
            placeholder="120"
            required
          />
        </label>
      </div>
      <label className="office-reservation-confirm">
        <input
          type="checkbox"
          checked={confirmed}
          disabled={busy}
          onChange={(event) => setConfirmedNetwork(event.target.checked ? selectedNetwork : null)}
        />
        <span>I confirm this LAN should start issuing DHCP leases from the calculated address pool, and authorize QuantumGrid to create the scope and restart dnsmasq.</span>
      </label>
      <div className="office-reservation-edit-actions">
        <button className="hero-button" type="submit" disabled={!confirmed || busy || !selectedNetwork || !start || !limit}>
          <Check size={14} /> {busy ? "Creating DHCP scope…" : "Create DHCP scope"}
        </button>
        <span>Only an existing static IPv4 interface is used. The router validates pool boundaries and overlap. This does not create VLANs, firewall zones, Wi-Fi SSIDs or network interfaces.</span>
      </div>
      {notice && (
        <div className={notice.success ? "module-message office-reservation-success" : "module-message office-reservation-error"} role={notice.success ? "status" : "alert"}>
          {notice.message}
        </div>
      )}
    </form>
  );
}


function DhcpScopeToggle({ scope, refresh }: {
  scope: RouterOfficeDhcpScope;
  refresh: () => void;
}) {
  const [confirmed, setConfirmed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [deletePending, setDeletePending] = useState(false);
  const [deleteConfirmed, setDeleteConfirmed] = useState(false);
  const [deleteBusy, setDeleteBusy] = useState(false);
  const [notice, setNotice] = useState<{ success: boolean; message: string } | null>(null);
  const enable = scope.ignore;

  const removeScope = async () => {
    if (!deleteConfirmed || deleteBusy) return;
    setDeleteBusy(true);
    setNotice(null);
    try {
      await removeRouterDhcpScope(scope.section);
      setNotice({
        success: true,
        message: "The DHCP scope was removed and dnsmasq restarted. Existing clients may retain leases until expiry.",
      });
      setDeletePending(false);
      setDeleteConfirmed(false);
      refresh();
    } catch (cause) {
      setNotice({
        success: false,
        message: cause instanceof Error ? cause.message : "The DHCP scope could not be removed.",
      });
    } finally {
      setDeleteBusy(false);
    }
  };

  const apply = async () => {
    if (!confirmed || busy) return;
    setBusy(true);
    setNotice(null);
    try {
      const result = await updateRouterDhcpScopeEnabled(scope.section, enable);
      setNotice({
        success: true,
        message: result.changed
          ? (enable ? "DHCP scope enabled and dnsmasq restarted." : "DHCP scope disabled and dnsmasq restarted.")
          : (enable ? "DHCP scope was already enabled." : "DHCP scope was already disabled."),
      });
      setConfirmed(false);
      refresh();
    } catch (cause) {
      setNotice({
        success: false,
        message: cause instanceof Error ? cause.message : "The DHCP scope state could not be changed.",
      });
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="office-dhcp-toggle">
      <label className="office-reservation-confirm">
        <input
          type="checkbox"
          checked={confirmed}
          disabled={busy}
          onChange={(event) => setConfirmed(event.target.checked)}
        />
        <span>{enable
          ? "I confirm this DHCP server scope may be enabled on its existing LAN. QuantumGrid will validate its pool and restart dnsmasq."
          : "I understand disabling this DHCP scope may stop new clients on this LAN from receiving addresses. Existing clients may continue until their leases expire."
        }</span>
      </label>
      <div className="office-dhcp-editor-actions">
        <button className="hero-button" type="button" onClick={() => { void apply(); }} disabled={!confirmed || busy}>
          <Check size={14} /> {busy ? "Applying…" : enable ? "Enable DHCP scope" : "Disable DHCP scope"}
        </button>
      </div>
      <div className="office-dhcp-remove">
        {!deletePending ? (
          <button
            className="office-remove-start"
            type="button"
            onClick={() => {
              setDeletePending(true);
              setDeleteConfirmed(false);
              setConfirmed(false);
            }}
            disabled={busy || deleteBusy}
          >Delete DHCP scope</button>
        ) : (
          <>
            <div className="module-message office-dhcp-remove-warning">
              Deleting this scope stops this dnsmasq instance from assigning new addresses on {scope.interface}. Existing clients may keep their current leases until expiry. Static host reservations are separate and will not be deleted.
            </div>
            <label className="office-reservation-confirm">
              <input
                type="checkbox"
                checked={deleteConfirmed}
                disabled={deleteBusy}
                onChange={(event) => setDeleteConfirmed(event.target.checked)}
              />
              <span>I understand this DHCP scope will be permanently removed from UCI.</span>
            </label>
            <div className="office-dhcp-editor-actions">
              <button className="office-remove-confirm" type="button" onClick={() => { void removeScope(); }} disabled={!deleteConfirmed || deleteBusy}>
                {deleteBusy ? "Deleting…" : "Confirm delete scope"}
              </button>
              <button className="office-remove-cancel" type="button" onClick={() => { setDeletePending(false); setDeleteConfirmed(false); }} disabled={deleteBusy}>Cancel</button>
            </div>
          </>
        )}
      </div>
      {notice && (
        <div className={notice.success ? "module-message office-reservation-success" : "module-message office-reservation-error"} role={notice.success ? "status" : "alert"}>
          {notice.message}
        </div>
      )}
    </div>
  );
}


function DhcpScopeEditor({ scope, refresh }: {
  scope: RouterOfficeDhcpScope;
  refresh: () => void;
}) {
  const [start, setStart] = useState(scope.start);
  const [limit, setLimit] = useState(String(scope.limit ?? ""));
  const [leaseTime, setLeaseTime] = useState(scope.lease_time || "12h");
  const [dhcpv6, setDhcpv6] = useState<"UNCHANGED" | "disabled" | "server">("UNCHANGED");
  const [ra, setRa] = useState<"UNCHANGED" | "disabled" | "server">("UNCHANGED");
  const [ndp, setNdp] = useState<"UNCHANGED" | "disabled">("UNCHANGED");
  const [raFlags, setRaFlags] = useState<"UNCHANGED" | "none" | "other-config" | "managed-config" | "managed-config+other-config">("UNCHANGED");
  const [raSlaac, setRaSlaac] = useState<"UNCHANGED" | "0" | "1">("UNCHANGED");
  const [raDns, setRaDns] = useState<"UNCHANGED" | "0" | "1">("UNCHANGED");
  const [raPreference, setRaPreference] = useState<"UNCHANGED" | "low" | "medium" | "high">("UNCHANGED");
  const [raLifetime, setRaLifetime] = useState("UNCHANGED");
  const [dhcpv6Na, setDhcpv6Na] = useState<"UNCHANGED" | "0" | "1">("UNCHANGED");
  const [dhcpv6Pd, setDhcpv6Pd] = useState<"UNCHANGED" | "0" | "1">("UNCHANGED");
  const [dhcpv6AssignAll, setDhcpv6AssignAll] = useState<"UNCHANGED" | "0" | "1">("UNCHANGED");
  const [dhcpv6PdMinLen, setDhcpv6PdMinLen] = useState("UNCHANGED");
  const [confirmed, setConfirmed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<{ success: boolean; message: string } | null>(null);

  const changed = start !== scope.start || limit !== String(scope.limit ?? "") ||
    leaseTime !== (scope.lease_time || "12h") || dhcpv6 !== "UNCHANGED" ||
    ra !== "UNCHANGED" || ndp !== "UNCHANGED" || raFlags !== "UNCHANGED" ||
    raSlaac !== "UNCHANGED" || raDns !== "UNCHANGED" || raPreference !== "UNCHANGED" ||
    raLifetime !== "UNCHANGED" || dhcpv6Na !== "UNCHANGED" || dhcpv6Pd !== "UNCHANGED" ||
    dhcpv6AssignAll !== "UNCHANGED" || dhcpv6PdMinLen !== "UNCHANGED";
  const save = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!confirmed || !changed || busy || scope.ignore) return;
    setBusy(true);
    setNotice(null);
    try {
      const result = await updateRouterDhcpScope({
        section: scope.section,
        start: start.trim(),
        limit: limit.trim(),
        lease_time: leaseTime.trim(),
        dhcpv6,
        ra,
        ndp,
        ra_flags: raFlags,
        ra_slaac: raSlaac,
        ra_dns: raDns,
        ra_preference: raPreference,
        ra_lifetime: raLifetime,
        dhcpv6_na: dhcpv6Na,
        dhcpv6_pd: dhcpv6Pd,
        dhcpv6_assignall: dhcpv6AssignAll,
        dhcpv6_pd_min_len: dhcpv6PdMinLen,
      });
      setNotice({
        success: true,
        message: "DHCP pool updated: " + result.pool_start_ip + " – " + result.pool_end_ip +
          ". dnsmasq restarted" + (result.odhcpd_restarted ? " and odhcpd restarted." : "."),

      });
      setConfirmed(false);
      setDhcpv6("UNCHANGED");
      setRa("UNCHANGED");
      setNdp("UNCHANGED");
      setRaFlags("UNCHANGED");
      setRaSlaac("UNCHANGED");
      setRaDns("UNCHANGED");
      setRaPreference("UNCHANGED");
      setRaLifetime("UNCHANGED");
      setDhcpv6Na("UNCHANGED");
      setDhcpv6Pd("UNCHANGED");
      setDhcpv6AssignAll("UNCHANGED");
      setDhcpv6PdMinLen("UNCHANGED");
      refresh();
    } catch (cause) {
      setNotice({
        success: false,
        message: cause instanceof Error ? cause.message : "The DHCP scope could not be updated.",
      });
    } finally {
      setBusy(false);
    }
  };

  return (
    <form className="office-dhcp-editor" onSubmit={save}>
      {scope.ignore ? (
        <div className="module-message">This DHCP scope is disabled. Enable it in native DHCP configuration before editing the pool.</div>
      ) : (
        <>
          <div className="office-dhcp-editor-fields">
            <label>
              <span>Start offset</span>
              <input type="number" min={1} step={1} value={start} onChange={(event) => { setStart(event.target.value); setConfirmed(false); }} required />
            </label>
            <label>
              <span>Pool size (addresses)</span>
              <input type="number" min={1} step={1} value={limit} onChange={(event) => { setLimit(event.target.value); setConfirmed(false); }} required />
            </label>
            <label>
              <span>Lease time</span>
              <input
                type="text"
                value={leaseTime}
                onChange={(event) => { setLeaseTime(event.target.value); setConfirmed(false); }}
                placeholder="12h"
                maxLength={16}
                pattern="[1-9][0-9]{0,8}[smhdw]?"
                required
              />
            </label>
            <label>
              <span>DHCPv6 SERVER</span>
              <select value={dhcpv6} onChange={(event) => { setDhcpv6(event.target.value as "UNCHANGED" | "disabled" | "server"); setConfirmed(false); }} disabled={busy}>
                <option value="UNCHANGED">Keep current ({scope.dhcpv6 || "default"})</option>
                <option value="disabled">Disabled</option>
                <option value="server">Server</option>
              </select>
            </label>
            <label>
              <span>ROUTER ADVERTISEMENTS (RA)</span>
              <select value={ra} onChange={(event) => { setRa(event.target.value as "UNCHANGED" | "disabled" | "server"); setConfirmed(false); }} disabled={busy}>
                <option value="UNCHANGED">Keep current ({scope.ra || "default"})</option>
                <option value="disabled">Disabled</option>
                <option value="server">Server</option>
              </select>
            </label>
            <label>
              <span>NEIGHBOUR DISCOVERY PROXY (NDP)</span>
              <select value={ndp} onChange={(event) => { setNdp(event.target.value as "UNCHANGED" | "disabled"); setConfirmed(false); }} disabled={busy}>
                <option value="UNCHANGED">Keep current ({scope.ndp || "default"})</option>
                <option value="disabled">Disabled</option>
              </select>
            </label>
          </div>
          <div className="office-dhcp-ipv6-advanced">
            <div className="office-dhcp-ipv6-advanced-heading">
              <strong>Advanced IPv6 address allocation</strong>
              <span>RA flags, SLAAC, DNS advertisement and DHCPv6 prefix services</span>
            </div>
            <div className="office-dhcp-ipv6-advanced-fields">
              <label>
                <span>ROUTER ADVERTISEMENT FLAGS</span>
                <select value={raFlags} onChange={(event) => { setRaFlags(event.target.value as typeof raFlags); setConfirmed(false); }} disabled={busy}>
                  <option value="UNCHANGED">Keep current ({scope.ra_flags?.join(" + ") || "default"})</option>
                  <option value="none">None</option>
                  <option value="other-config">Other configuration (O)</option>
                  <option value="managed-config">Managed address configuration (M)</option>
                  <option value="managed-config+other-config">Managed + other configuration (M + O)</option>
                </select>
              </label>
              <label>
                <span>RA ROUTE PREFERENCE</span>
                <select value={raPreference} onChange={(event) => { setRaPreference(event.target.value as typeof raPreference); setConfirmed(false); }} disabled={busy}>
                  <option value="UNCHANGED">Keep current ({scope.ra_preference || "medium"})</option>
                  <option value="low">Low</option>
                  <option value="medium">Medium</option>
                  <option value="high">High</option>
                </select>
              </label>
              <label>
                <span>RA ROUTER LIFETIME (SECONDS)</span>
                <select value={raLifetime} onChange={(event) => { setRaLifetime(event.target.value); setConfirmed(false); }} disabled={busy}>
                  <option value="UNCHANGED">Keep current ({scope.ra_lifetime ?? 2700}s)</option>
                  <option value="0">0 · No default route</option>
                  <option value="600">600 seconds</option>
                  <option value="900">900 seconds</option>
                  <option value="1800">1800 seconds</option>
                  <option value="2100">2100 seconds</option>
                  <option value="2400">2400 seconds</option>
                  <option value="2700">2700 seconds</option>
                </select>
              </label>
              <label>
                <span>RA SLAAC</span>
                <select value={raSlaac} onChange={(event) => { setRaSlaac(event.target.value as typeof raSlaac); setConfirmed(false); }} disabled={busy}>
                  <option value="UNCHANGED">Keep current ({scope.ra_slaac ? "enabled" : "disabled"})</option>
                  <option value="1">Enabled</option>
                  <option value="0">Disabled</option>
                </select>
              </label>
              <label>
                <span>RA DNS ADVERTISEMENT</span>
                <select value={raDns} onChange={(event) => { setRaDns(event.target.value as typeof raDns); setConfirmed(false); }} disabled={busy}>
                  <option value="UNCHANGED">Keep current ({scope.ra_dns ? "enabled" : "disabled"})</option>
                  <option value="1">Enabled</option>
                  <option value="0">Disabled</option>
                </select>
              </label>
              <label>
                <span>DHCPv6 IA_NA ADDRESSES</span>
                <select value={dhcpv6Na} onChange={(event) => { setDhcpv6Na(event.target.value as typeof dhcpv6Na); setConfirmed(false); }} disabled={busy}>
                  <option value="UNCHANGED">Keep current ({scope.dhcpv6_na ? "enabled" : "disabled"})</option>
                  <option value="1">Enabled</option>
                  <option value="0">Disabled</option>
                </select>
              </label>
              <label>
                <span>DHCPv6 PREFIX DELEGATION (IA_PD)</span>
                <select value={dhcpv6Pd} onChange={(event) => { setDhcpv6Pd(event.target.value as typeof dhcpv6Pd); setConfirmed(false); }} disabled={busy}>
                  <option value="UNCHANGED">Keep current ({scope.dhcpv6_pd ? "enabled" : "disabled"})</option>
                  <option value="1">Enabled</option>
                  <option value="0">Disabled</option>
                </select>
              </label>
              <label>
                <span>DELEGATE TO ALL DOWNSTREAM REQUESTERS</span>
                <select value={dhcpv6AssignAll} onChange={(event) => { setDhcpv6AssignAll(event.target.value as typeof dhcpv6AssignAll); setConfirmed(false); }} disabled={busy}>
                  <option value="UNCHANGED">Keep current ({scope.dhcpv6_assignall ? "enabled" : "disabled"})</option>
                  <option value="1">Enabled</option>
                  <option value="0">Disabled</option>
                </select>
              </label>
              <label>
                <span>MINIMUM DELEGATED PREFIX LENGTH</span>
                <select value={dhcpv6PdMinLen} onChange={(event) => { setDhcpv6PdMinLen(event.target.value); setConfirmed(false); }} disabled={busy}>
                  <option value="UNCHANGED">Keep current (/{scope.dhcpv6_pd_min_len || 62})</option>
                  <option value="48">/48</option>
                  <option value="52">/52</option>
                  <option value="56">/56</option>
                  <option value="60">/60</option>
                  <option value="62">/62</option>
                  <option value="64">/64</option>
                </select>
              </label>
            </div>
            <div className="module-message">Prefix delegation requires the WAN/ upstream interface to receive a usable delegated prefix, and each downstream LAN must have a suitable IPv6 assignment configured. The minimum length is the downstream prefix-size constraint; changing it cannot create an ISP prefix or configure network interfaces automatically.</div>
          </div>
          <div className="module-message">Relay and hybrid modes are preserved as-is but are not configured here. They require an odhcpd master/relay topology that must be established and validated separately in native LuCI. DHCPv6 does not provide the default router by itself; clients that need an IPv6 default route generally also need working RA service and prefix configuration.</div>
          <label className="office-reservation-confirm">
            <input
              type="checkbox"
              checked={confirmed}
              disabled={busy || !changed}
              onChange={(event) => setConfirmed(event.target.checked)}
            />
            <span>I confirm these DHCP and IPv6 settings and authorize QuantumGrid to update this scope, restart dnsmasq, and restart odhcpd when IPv6 settings change.</span>
          </label>
          <div className="office-dhcp-editor-actions">
            <button className="hero-button" type="submit" disabled={!confirmed || !changed || busy}>
              <Check size={14} /> {busy ? "Applying scope…" : "Apply DHCP scope"}
            </button>
            <span>IPv4 pool range and lease values, DHCPv6 server, router advertisements and NDP are managed independently. Unchanged retains any existing relay/hybrid configuration.</span>
          </div>
        </>
      )}
      {notice && (
        <div className={notice.success ? "module-message office-reservation-success" : "module-message office-reservation-error"} role={notice.success ? "status" : "alert"}>
          {notice.message}
        </div>
      )}
    </form>
  );
}


function DhcpReservationEditor({ lease, networks, onCancel, onComplete }: {
  lease: RouterOfficeStaticLease;
  networks: RouterOfficeInterface[];
  onCancel: () => void;
  onComplete: (notice: { success: boolean; message: string }) => void;
}) {
  const [name, setName] = useState(lease.name);
  const [mac, setMac] = useState(lease.mac);
  const [ipv4, setIpv4] = useState(lease.ipv4);
  const [network, setNetwork] = useState(networks[0]?.name ?? "");
  const [confirmed, setConfirmed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const changed = name.trim() !== lease.name || mac.trim().toLowerCase() !== lease.mac ||
    ipv4.trim() !== lease.ipv4;

  const save = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!confirmed || !changed || busy || !network) return;
    setBusy(true);
    setError("");
    try {
      const result = await updateRouterDhcpReservation({
        section: lease.section,
        name: name.trim(),
        mac: mac.trim(),
        ipv4: ipv4.trim(),
        network,
      });
      onComplete({
        success: true,
        message: "Reservation " + result.name + " was updated and dnsmasq restarted successfully.",
      });
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "The DHCP reservation could not be updated.");
    } finally {
      setBusy(false);
    }
  };

  if (networks.length === 0) {
    return (
      <div className="office-reservation-edit-form">
        <div className="module-message">No enabled DHCP scope is attached to a static IPv4 interface with a readable subnet. Configure an eligible LAN before editing this reservation.</div>
        <button className="office-remove-cancel" type="button" onClick={onCancel}>Close editor</button>
      </div>
    );
  }

  return (
    <form className="office-reservation-edit-form" onSubmit={save}>
      <div className="office-reservation-edit-heading">
        <strong>Edit {lease.name}</strong>
        <span>UCI section {lease.section}</span>
      </div>
      <div className="office-reservation-grid">
        <label>
          <span>Host name</span>
          <input
            type="text"
            value={name}
            onChange={(event) => { setName(event.target.value); setConfirmed(false); }}
            maxLength={63}
            pattern="[A-Za-z0-9][A-Za-z0-9-]*"
            autoComplete="off"
            required
          />
        </label>
        <label>
          <span>MAC address</span>
          <input
            type="text"
            value={mac}
            onChange={(event) => { setMac(event.target.value); setConfirmed(false); }}
            maxLength={17}
            pattern="[A-Fa-f0-9]{2}(:[A-Fa-f0-9]{2}){5}"
            autoComplete="off"
            required
          />
        </label>
        <label>
          <span>Reserved IPv4</span>
          <input
            type="text"
            inputMode="decimal"
            value={ipv4}
            onChange={(event) => { setIpv4(event.target.value); setConfirmed(false); }}
            maxLength={15}
            pattern="[0-9]{1,3}(\.[0-9]{1,3}){3}"
            autoComplete="off"
            required
          />
        </label>
        <label>
          <span>Subnet validation LAN</span>
          <select value={network} onChange={(event) => { setNetwork(event.target.value); setConfirmed(false); }} required>
            {networks.map((item) => (
              <option key={item.name} value={item.name}>{item.name} · {item.ipv4[0]} / {item.netmask}</option>
            ))}
          </select>
        </label>
      </div>
      <label className="office-reservation-confirm">
        <input
          type="checkbox"
          checked={confirmed}
          disabled={busy || !changed}
          onChange={(event) => setConfirmed(event.target.checked)}
        />
        <span>I confirm these replacement host details and authorize QuantumGrid to update the existing DHCP reservation and restart dnsmasq.</span>
      </label>
      <div className="office-reservation-edit-actions">
        <button className="hero-button" type="submit" disabled={!confirmed || !changed || busy || !network}>
          <Check size={14} /> {busy ? "Updating reservation…" : "Save reservation changes"}
        </button>
        <button className="office-remove-cancel" type="button" onClick={onCancel} disabled={busy}>Cancel</button>
        <span>The selected LAN is used for IPv4 subnet validation only. Standard dnsmasq host reservations remain global to this dnsmasq instance.</span>
      </div>
      {error && <div className="module-message office-reservation-error" role="alert">{error}</div>}
    </form>
  );
}


function OfficeNetworksPage({ routerOverview, refresh }: {
  routerOverview: RouterOverview | null;
  refresh: () => void;
}) {
  const inventory = routerOverview?.office_networks;
  const [reservationName, setReservationName] = useState("");
  const [reservationMac, setReservationMac] = useState("");
  const [reservationIp, setReservationIp] = useState("");
  const [reservationNetwork, setReservationNetwork] = useState("");
  const [reservationConfirmed, setReservationConfirmed] = useState(false);
  const [reservationBusy, setReservationBusy] = useState(false);
  const [pendingReservationRemoval, setPendingReservationRemoval] = useState("");
  const [pendingReservationEdit, setPendingReservationEdit] = useState("");
  const [reservationRemoveBusy, setReservationRemoveBusy] = useState(false);
  const [reservationNotice, setReservationNotice] = useState<{ success: boolean; message: string } | null>(null);
  const existingDhcpNetworks = new Set((inventory?.dhcp_scopes ?? []).map((scope) => scope.interface));
  const dhcpCreationNetworks = (inventory?.interfaces ?? []).filter((item) =>
    item.protocol === "static" && item.ipv4.length > 0 && Boolean(item.netmask) &&
    !existingDhcpNetworks.has(item.name)
  );
  const enabledDhcpScopes = inventory?.dhcp_scopes.filter((scope) => !scope.ignore) ?? [];
  const liveDhcpClients = routerOverview?.clients ?? [];
  const reservationNetworks = (inventory?.interfaces ?? []).filter((item) =>
    item.protocol === "static" && item.ipv4.length > 0 && Boolean(item.netmask) &&
    enabledDhcpScopes.some((scope) => scope.interface === item.name)
  );
  const selectedReservationNetwork = reservationNetworks.some((item) => item.name === reservationNetwork)
    ? reservationNetwork
    : reservationNetworks[0]?.name ?? "";
  const saveReservation = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!reservationConfirmed || reservationBusy || !selectedReservationNetwork) return;
    setReservationBusy(true);
    setReservationNotice(null);
    try {
      await createRouterDhcpReservation({
        name: reservationName.trim(),
        mac: reservationMac.trim(),
        ipv4: reservationIp.trim(),
        network: selectedReservationNetwork,
      });
      setReservationNotice({
        success: true,
        message: "The static reservation was saved and dnsmasq restarted successfully.",
      });
      setReservationName("");
      setReservationMac("");
      setReservationIp("");
      setReservationConfirmed(false);
      refresh();
    } catch (cause) {
      setReservationNotice({
        success: false,
        message: cause instanceof Error ? cause.message : "The DHCP reservation could not be created.",
      });
    } finally {
      setReservationBusy(false);
    }
  };
  const removeReservation = async (section: string) => {
    if (!section || reservationRemoveBusy) return;
    setReservationRemoveBusy(true);
    setReservationNotice(null);
    try {
      const result = await removeRouterDhcpReservation(section);
      setReservationNotice({
        success: true,
        message: "Reservation " + result.name + " was removed and dnsmasq restarted successfully.",
      });
      setPendingReservationRemoval("");
      refresh();
    } catch (cause) {
      setReservationNotice({
        success: false,
        message: cause instanceof Error ? cause.message : "The DHCP reservation could not be removed.",
      });
    } finally {
      setReservationRemoveBusy(false);
    }
  };
  const interfaces = inventory?.interfaces ?? [];
  const bridges = inventory?.bridges ?? [];
  const vlans = inventory?.vlans ?? [];
  const zones = inventory?.zones ?? [];
  const exportInventory = () => {
    if (!inventory) return;
    const exportedAt = new Date().toISOString();
    const rows: Array<Array<string | number | boolean | null | undefined>> = [
      ["Exported at (UTC)", "Category", "Name", "Device / Bridge", "Protocol / VLAN ID", "State / Ports", "Firewall Zones", "Wi-Fi SSIDs", "IPv4", "Netmask", "IPv6", "MAC"],
      ...interfaces.map((item) => [
        exportedAt, "Network interface", item.name, item.device, item.protocol,
        item.up ? "UP" : "DOWN", item.firewall_zones.join(" "),
        item.wifi_aps.map((ap) => ap.ssid + (ap.disabled ? " (disabled)" : "")).join(" "),
        item.ipv4.join(" "), item.netmask,
        item.ipv6.join(" ") + (item.ip6assign ? " · delegated /" + item.ip6assign : ""), "",
      ]),
      ...bridges.map((item) => [
        exportedAt, "Bridge", item.name, item.name, item.type,
        item.ports.join(" ") + "; vlan_filtering=" + item.vlan_filtering, "", "", "", "", "", "",
      ]),
      ...vlans.map((item) => [
        exportedAt, "Bridge VLAN", item.name, item.device, item.vlan_id,
        item.ports.map((port) => port.name + (port.mode === "tagged" ? ":t" : port.mode === "untagged" ? ":u" + (port.pvid ? "*" : "") : "")).join(" "),
        "", "", "", "", "", "",
      ]),
      ...zones.map((item) => [
        exportedAt, "Firewall zone", item.name, "", "input=" + item.input,
        "output=" + item.output + "; forward=" + item.forward + "; masquerade=" + item.masquerade,
        item.networks.join(" "), "", "", "", "", "",
      ]),
      ...(inventory.forwardings ?? []).map((item) => [
        exportedAt, "Firewall forwarding", item.name, "", item.source + " → " + item.destination,
        "CONFIGURED", "", "", "", "", "", "",
      ]),
      ...(inventory.dhcp_scopes ?? []).map((item) => [
        exportedAt, "DHCP scope", item.name, item.interface, "start=" + item.start,
        "limit=" + (item.limit ?? "unknown") + "; lease=" + item.lease_time + "; ignored=" + item.ignore + "; dhcpv6=" + item.dhcpv6 + "; ra=" + item.ra + "; pool=" + (item.range_valid ? item.pool_start_ip + "-" + item.pool_end_ip : item.range_error) + "; overlaps=" + item.overlap,
        "", "", "", "", "", "",
      ]),
      ...(inventory.static_leases ?? []).map((item) => [
        exportedAt, "Static DHCP lease", item.name, "", "", "",
        "", "", item.ipv4, "", "", item.mac,
      ]),
    ];
    const csv = rows.map((row) => row.map(csvCell).join(",")).join("\r\n");
    const objectUrl = URL.createObjectURL(new Blob(["\uFEFF", csv], { type: "text/csv;charset=utf-8" }));
    const link = document.createElement("a");
    link.href = objectUrl;
    link.download = "quantumgrid-office-network-inventory-" + exportedAt.replace(/[:.]/g, "-") + ".csv";
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(objectUrl), 0);
  };
  return (
    <div className="module-page office-networks-page">
      <section className="module-hero">
        <div className="module-icon"><Network size={25} /></div>
        <div>
          <div className="setup-kicker">OFFICE LAN · VLAN SEGMENTATION · FIREWALL ZONES</div>
          <h1>Office Networks</h1>
          <p>Map configured LAN interfaces to bridge VLANs, switch ports, wireless access points and firewall zones. This is a live configuration inventory, not a simulated office template or a security certification.</p>
          <button className="hero-button office-export-button" onClick={exportInventory} disabled={!inventory?.available}>
            <Download size={15} /> Export network inventory CSV
          </button>
        </div>
      </section>

      {!routerOverview ? (
        <div className="module-message">Waiting for authenticated router telemetry.</div>
      ) : !inventory?.available ? (
        <div className="module-message" role="alert">The router could not read its network UCI inventory. Refresh router telemetry or inspect native LuCI before making network changes.</div>
      ) : null}

      <div className="metrics">
        <Metric title="LAN Interfaces" value={inventory?.available ? fmt(inventory.interface_count) : "N/A"} unit="" detail="Network UCI interface sections" icon={Network} />
        <Metric title="Bridge Devices" value={inventory?.available ? fmt(inventory.bridge_count) : "N/A"} unit="" detail={inventory ? inventory.vlan_filtering_bridge_count + " with VLAN filtering" : "Waiting for router inventory"} icon={Database} />
        <Metric title="Bridge VLANs" value={inventory?.available ? fmt(inventory.vlan_count) : "N/A"} unit="" detail={inventory ? inventory.segmented_interface_count + " L3 interfaces linked to a VLAN" : "Waiting for router inventory"} icon={SlidersHorizontal} />
        <Metric title="Wi-Fi Access Points" value={inventory?.available ? fmt(inventory.wifi_ap_count) : "N/A"} unit="" detail="Configured AP sections, including disabled entries" icon={Wifi} />
        <Metric title="DHCP / Reservations" value={inventory?.dhcp_available ? fmt(inventory.dhcp_scope_count) + " / " + fmt(inventory.static_lease_count) : "N/A"} unit="" detail="Scopes / static host mappings" icon={Database} />
      </div>

      {inventory && (
        <Panel title="Inventory source status" eyebrow={new Date(inventory.sampled_at * 1000).toLocaleString()}>
          <div className="office-source-status">
            <div><span>Network interfaces / bridges / VLANs</span><Status active={inventory.available}>{inventory.available ? "READABLE" : "UNAVAILABLE"}</Status></div>
            <div><span>Firewall zones</span><Status active={inventory.firewall_available}>{inventory.firewall_available ? "READABLE" : "UNAVAILABLE"}</Status></div>
            <div><span>Wireless AP configuration</span><Status active={inventory.wireless_available}>{inventory.wireless_available ? "READABLE" : "UNAVAILABLE"}</Status></div>
            <div><span>DHCP pools / reservations</span><Status active={inventory.dhcp_available}>{inventory.dhcp_available ? "READABLE" : "UNAVAILABLE"}</Status></div>
          </div>
          {inventory.truncated && <div className="module-message">One or more inventories exceeded the API display limit. Exported data is also limited to the returned entries.</div>}
        </Panel>
      )}

      <Panel title="Network interface map" eyebrow="NETWORK UCI · UBUS LIVE LINK STATE">
        {!inventory?.available ? (
          <div className="module-message">No network interface inventory is available yet.</div>
        ) : interfaces.length === 0 ? (
          <div className="module-message">No network interface sections were returned.</div>
        ) : (
          <div className="office-network-table">
            <div className="office-network-row header"><span>NETWORK</span><span>DEVICE / VLAN</span><span>ADDRESSING</span><span>FIREWALL ZONE</span><span>WI-FI SSIDS</span><span>STATE</span></div>
            {interfaces.map((item) => (
              <div className="office-network-row" key={item.name}>
                <div><strong>{item.name}</strong><small>{item.protocol || "Protocol not set"}</small></div>
                <div><b>{item.device || "Device not set"}</b><small>{item.vlan_ids.length ? "VLAN " + item.vlan_ids.join(", ") : "No direct bridge-VLAN match"}</small></div>
                <div><b>{item.ipv4.join(", ") || "No IPv4 address"}</b><small>{item.netmask ? "Netmask " + item.netmask : "Netmask not set"} · {item.ipv6.join(", ") || "No IPv6 address reported"}{item.ip6assign ? " · IPv6 assignment /" + item.ip6assign : ""}</small></div>
                <div>{item.firewall_zones.length ? item.firewall_zones.map((zone) => <span className="office-chip" key={zone}>{zone}</span>) : <small>Not mapped to a reported zone</small>}</div>
                <div>{item.wifi_aps.length ? item.wifi_aps.map((ap) => <span className={ap.disabled ? "office-chip disabled" : "office-chip"} key={ap.section}>{ap.ssid || ap.section}{ap.disabled ? " · OFF" : ""}</span>) : <small>No AP mapped</small>}</div>
                <Status active={item.up}>{item.up ? "UP" : "DOWN"}</Status>
              </div>
            ))}
          </div>
        )}
        <div className="module-message">Zone and SSID associations are correlated by their configured network names. Device names and VLAN matches are derived from the configured L3 device (for example, br-lan.20). No firewall packet-flow, switch hardware forwarding or client isolation test is performed here.</div>
      </Panel>

      <div className="office-two-column">
        <Panel title="DHCP server scopes" eyebrow="DHCP UCI · RANGE OFFSETS AND OPTIONS">
          {!inventory?.dhcp_available ? (
            <div className="module-message">DHCP configuration could not be read.</div>
          ) : inventory.dhcp_scopes.length === 0 ? (
            <div className="module-message">No DHCP scope sections were returned.</div>
          ) : (
            <div className="office-dhcp-scope-list">
              {inventory.dhcp_scopes.map((scope) => (
                <div className="office-dhcp-scope-card" key={scope.section}>
                  <div className="office-bridge-row">
                    <div><strong>{scope.name}</strong><span>{scope.interface}</span></div>
                    <div>
                      <small>START OFFSET / LIMIT / LEASE</small>
                      <b>{scope.start || "?"} / {scope.limit ?? "?"} / {scope.lease_time || "unspecified"}</b>
                      <small>CALCULATED POOL RANGE</small>
                      <b>{scope.range_valid ? scope.pool_start_ip + " – " + scope.pool_end_ip : scope.range_error || "Not calculated"}</b>
                      <small>DHCPv6 {scope.dhcpv6 || "default"} · RA {scope.ra || "default"} · NDP {scope.ndp || "default"}</small>
                      {scope.overlap ? <span className="office-chip warning">OVERLAPS ANOTHER DHCP POOL</span> : null}
                    </div>
                    <Status active={scope.range_valid && !scope.overlap}>{scope.ignore ? "DISABLED" : scope.overlap ? "OVERLAP" : scope.range_valid ? "RANGE VALID" : "RANGE INVALID"}</Status>
                  </div>
                  <DhcpScopeToggle scope={scope} refresh={refresh} />
                  <DhcpScopeEditor
                    key={`${scope.section}:${scope.start}:${scope.limit ?? ""}:${scope.lease_time || "12h"}:${scope.dhcpv6}:${scope.ra}:${scope.ndp}:${scope.ra_flags.join(",")}:${scope.ra_slaac}:${scope.ra_dns}:${scope.ra_preference}:${scope.ra_lifetime}:${scope.dhcpv6_na}:${scope.dhcpv6_pd}:${scope.dhcpv6_assignall}:${scope.dhcpv6_pd_min_len}`}
                    scope={scope}
                    refresh={refresh}
                  />
                </div>
              ))}
            </div>
          )}
          <div className="module-message">Start is interpreted as an offset from the subnet network address and limit as the pool size. The range preview checks subnet boundaries and overlap between configured scopes; it does not calculate static exclusions or prove that every address is unused.</div>
        </Panel>
        <Panel title="Static DHCP reservations" eyebrow="HOST NAME · MAC · IPV4">
          {!inventory?.dhcp_available ? (
            <div className="module-message">DHCP host configuration could not be read.</div>
          ) : inventory.static_leases.length === 0 ? (
            <div className="module-message">No valid static DHCP reservations were found.</div>
          ) : (
            <div className="office-zone-list">
              {inventory.static_leases.map((lease, index) => (
                <div className="office-reservation-entry" key={lease.section || lease.mac + "-" + lease.ipv4 + "-" + index}>
                  <div className="office-zone-row">
                    <div><strong>{lease.name}</strong><small>{lease.mac}</small></div>
                    <div><small>RESERVED IPV4</small><b>{lease.ipv4}</b></div>
                    <div className="office-reservation-row-actions">
                      <Status active={true}>STATIC</Status>
                      <button
                        className="office-remove-start"
                        type="button"
                        onClick={() => {
                          setReservationNotice(null);
                          setPendingReservationRemoval("");
                          setPendingReservationEdit(lease.section);
                        }}
                        disabled={!lease.section || reservationRemoveBusy}
                      >Edit</button>
                      {pendingReservationRemoval === lease.section ? (
                        <div className="office-reservation-remove-confirm">
                          <button className="office-remove-confirm" type="button" onClick={() => { void removeReservation(lease.section); }} disabled={reservationRemoveBusy}>
                            {reservationRemoveBusy ? "Removing…" : "Confirm remove"}
                          </button>
                          <button className="office-remove-cancel" type="button" onClick={() => setPendingReservationRemoval("")} disabled={reservationRemoveBusy}>Cancel</button>
                        </div>
                      ) : (
                        <button className="office-remove-start" type="button" onClick={() => { setReservationNotice(null); setPendingReservationEdit(""); setPendingReservationRemoval(lease.section); }} disabled={!lease.section || reservationRemoveBusy}>
                          Remove
                        </button>
                      )}
                    </div>
                  </div>
                  {pendingReservationEdit === lease.section && (
                    <DhcpReservationEditor
                      lease={lease}
                      networks={reservationNetworks}
                      onCancel={() => setPendingReservationEdit("")}
                      onComplete={(notice) => {
                        setReservationNotice(notice);
                        setPendingReservationEdit("");
                        refresh();
                      }}
                    />
                  )}
                </div>
              ))}
            </div>
          )}
          {reservationNotice && (
            <div className={reservationNotice.success ? "module-message office-reservation-success" : "module-message office-reservation-error"} role={reservationNotice.success ? "status" : "alert"}>
              {reservationNotice.message}
            </div>
          )}
          <div className="module-message">Only configured UCI host reservations are shown. Dynamic leases are listed separately on the Devices page; a reservation does not prove that the client is currently connected. Reservations are global to the active dnsmasq instance and are not bound to one VLAN by this selector. Removing a reservation restarts dnsmasq; confirm only when you intend to remove that host mapping.</div>
        </Panel>
      </div>

      <Panel title="Add a static DHCP reservation" eyebrow="OFFICE DEVICE MANAGEMENT · GUARDED WRITE">
        {reservationNetworks.length === 0 ? (
          <div className="module-message">No enabled DHCP scope is attached to a static IPv4 interface with a readable subnet mask. Configure an appropriate LAN interface and DHCP scope before creating reservations.</div>
        ) : (
          <form className="office-reservation-form" onSubmit={saveReservation}>
            {liveDhcpClients.length > 0 && (
              <div className="office-live-lease-list">
                <div className="office-live-lease-heading">
                  <strong>Prefill from a live DHCP lease</strong>
                  <span>{liveDhcpClients.length} active lease record(s) reported by dnsmasq</span>
                </div>
                {liveDhcpClients.map((client) => {
                  const matchingNetwork = reservationNetworks.find((item) =>
                    ipv4SubnetContainsHost(client.ip, item.ipv4[0] ?? "", item.netmask)
                  );
                  const existingReservation = inventory?.static_leases.find((lease) =>
                    lease.mac.toLowerCase() === client.mac.toLowerCase() || lease.ipv4 === client.ip
                  );
                  const exactReservation = existingReservation?.mac.toLowerCase() === client.mac.toLowerCase()
                    && existingReservation?.ipv4 === client.ip;
                  const safeHost = /^[A-Za-z0-9][A-Za-z0-9-]{0,62}$/.test(client.hostname)
                    ? client.hostname
                    : "Client-" + client.mac.replace(/:/g, "").slice(-8);
                  const remaining = client.lease_remaining_seconds === null
                    ? "No expiry reported"
                    : client.lease_remaining_seconds <= 0
                      ? "Expiring"
                      : client.lease_remaining_seconds < 3600
                        ? Math.ceil(client.lease_remaining_seconds / 60) + " min left"
                        : Math.floor(client.lease_remaining_seconds / 3600) + " h " + Math.ceil((client.lease_remaining_seconds % 3600) / 60) + " min left";
                  return (
                    <div className="office-live-lease-row" key={client.mac + "-" + client.ip}>
                      <div>
                        <strong>{client.hostname || "Unknown client"}</strong>
                        <span>{client.mac} · {client.ip} · {remaining}</span>
                        {existingReservation ? (
                          <span className="office-live-lease-reservation">
                            {exactReservation ? "Already has static reservation: " : "Reservation conflict: "}
                            {existingReservation.name} · {existingReservation.ipv4}
                          </span>
                        ) : null}
                      </div>
                      {existingReservation ? (
                        <Status active={exactReservation}>{exactReservation ? "RESERVED" : "CONFLICT"}</Status>
                      ) : (
                        <button
                          className="office-remove-start"
                          type="button"
                          onClick={() => {
                            setReservationName(safeHost);
                            setReservationMac(client.mac);
                            setReservationIp(client.ip);
                            setReservationNetwork(matchingNetwork?.name ?? reservationNetworks[0]?.name ?? "");
                            setReservationConfirmed(false);
                            setReservationNotice({
                              success: true,
                              message: matchingNetwork
                                ? "Details prefilled from this lease. Verify the LAN and confirm to create the reservation."
                                : "Details prefilled, but no eligible LAN subnet matched this lease IP. Select and verify the correct LAN before saving.",
                            });
                          }}
                        >Use lease</button>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
            <div className="office-reservation-grid">
              <label>
                <span>Host name</span>
                <input
                  type="text"
                  value={reservationName}
                  onChange={(event) => { setReservationName(event.target.value); setReservationConfirmed(false); }}
                  placeholder="Office-Printer"
                  maxLength={63}
                  pattern="[A-Za-z0-9][A-Za-z0-9-]*"
                  autoComplete="off"
                  required
                />
              </label>
              <label>
                <span>MAC address</span>
                <input
                  type="text"
                  value={reservationMac}
                  onChange={(event) => { setReservationMac(event.target.value); setReservationConfirmed(false); }}
                  placeholder="AA:BB:CC:DD:EE:FF"
                  maxLength={17}
                  pattern="[A-Fa-f0-9]{2}(:[A-Fa-f0-9]{2}){5}"
                  autoComplete="off"
                  required
                />
              </label>
              <label>
                <span>Reserved IPv4</span>
                <input
                  type="text"
                  inputMode="decimal"
                  value={reservationIp}
                  onChange={(event) => { setReservationIp(event.target.value); setReservationConfirmed(false); }}
                  placeholder="192.168.20.30"
                  maxLength={15}
                  pattern="[0-9]{1,3}(\.[0-9]{1,3}){3}"
                  autoComplete="off"
                  required
                />
              </label>
              <label>
                <span>LAN / DHCP scope</span>
                <select
                  value={selectedReservationNetwork}
                  onChange={(event) => { setReservationNetwork(event.target.value); setReservationConfirmed(false); }}
                  required
                >
                  {reservationNetworks.map((item) => (
                    <option key={item.name} value={item.name}>{item.name} · {item.ipv4[0]} / {item.netmask}</option>
                  ))}
                </select>
              </label>
            </div>
            <label className="office-reservation-confirm">
              <input
                type="checkbox"
                checked={reservationConfirmed}
                disabled={reservationBusy}
                onChange={(event) => setReservationConfirmed(event.target.checked)}
              />
              <span>I confirm this device and IP assignment, and authorize QuantumGrid to update DHCP configuration and restart dnsmasq.</span>
            </label>
            <div className="office-reservation-actions">
              <button className="hero-button" type="submit" disabled={!reservationConfirmed || reservationBusy || !selectedReservationNetwork}>
                <Check size={15} /> {reservationBusy ? "Saving reservation…" : "Add reservation"}
              </button>
              <span>The selected scope validates the subnet only: OpenWrt stores this as a global dnsmasq host entry, not a VLAN-specific reservation. Duplicate MAC/IP entries, out-of-subnet addresses and addresses leased to another MAC are rejected.</span>
            </div>
            {reservationNotice && (
              <div className={reservationNotice.success ? "module-message office-reservation-success" : "module-message office-reservation-error"} role={reservationNotice.success ? "status" : "alert"}>
                {reservationNotice.message}
              </div>
            )}
          </form>
        )}
      </Panel>

      <Panel title="Create a DHCP scope" eyebrow="EXISTING STATIC LAN · NEW DHCP POOL">
        <DhcpScopeCreateForm networks={dhcpCreationNetworks} refresh={refresh} />
      </Panel>

      <OfficeBridgeVlanManager
        available={Boolean(inventory?.available)}
        truncated={Boolean(inventory?.truncated)}
        bridges={bridges}
        vlans={vlans}
        refresh={refresh}
      />

      <OfficeSegmentManager
        available={Boolean(inventory?.available && inventory?.firewall_available && inventory?.dhcp_available)}
        truncated={Boolean(inventory?.truncated)}
        interfaces={interfaces}
        bridges={bridges}
        vlans={vlans}
        zones={zones}
        refresh={refresh}
      />

      <div className="office-two-column">
        <Panel title="Bridge devices" eyebrow="NETWORK DEVICE SECTIONS">
          {!inventory?.available || bridges.length === 0 ? (
            <div className="module-message">No bridge device sections were returned.</div>
          ) : (
            <div className="office-bridge-list">
              {bridges.map((bridge) => (
                <div className="office-bridge-row" key={bridge.name}>
                  <div><strong>{bridge.name}</strong><span>{bridge.type || "Device"}</span></div>
                  <div><small>PORTS</small><b>{bridge.ports.join(" · ") || "No ports reported"}</b></div>
                  <Status active={bridge.vlan_filtering}>{bridge.vlan_filtering ? "VLAN FILTERING ON" : "VLAN FILTERING OFF"}</Status>
                </div>
              ))}
            </div>
          )}
        </Panel>
        <OfficeFirewallZoneManager
          available={Boolean(inventory?.firewall_available)}
          truncated={Boolean(inventory?.truncated)}
          zones={zones}
          refresh={refresh}
        />
      </div>

      <OfficeForwardingManager
        available={Boolean(inventory?.firewall_available)}
        truncated={Boolean(inventory?.truncated)}
        zones={zones}
        forwardings={inventory?.forwardings ?? []}
        refresh={refresh}
      />
      <OfficeWifiNetworkManager
        available={Boolean(inventory?.available)}
        truncated={Boolean(inventory?.truncated)}
        aps={inventory?.wifi_aps ?? []}
        interfaces={interfaces}
        zones={zones}
        refresh={refresh}
      />


      <Panel title="Office deployment readiness" eyebrow="CONFIGURATION INVENTORY · NOT A COMPLIANCE RESULT">
        <div className="office-readiness-list">
          <div><strong>Separate L3 networks</strong><span>{inventory?.interface_count ?? 0} network interface(s) found. Review the interface map to identify corporate, guest, IoT and management networks.</span></div>
          <div><strong>VLAN-aware bridges</strong><span>{inventory?.vlan_filtering_bridge_count ?? 0} bridge(s) report VLAN filtering enabled, with {inventory?.vlan_count ?? 0} bridge VLAN section(s).</span></div>
          <div><strong>Firewall segmentation</strong><span>{inventory?.firewall_available ? zones.length + " firewall zone(s) and " + inventory.forwarding_count + " explicit zone forwarding(s) are inventoried." : "Firewall configuration inventory unavailable."} Actual rule evaluation and inter-VLAN traffic tests are not performed.</span></div>
          <div><strong>Wireless mapping</strong><span>{inventory?.wireless_available ? (inventory.wifi_ap_count + " configured AP section(s); inspect the SSID-to-network associations above.") : "Wireless configuration inventory unavailable."}</span></div>
        </div>
        <div className="module-message">QuantumGrid now provides guarded bridge VLAN membership and explicit inter-zone forwarding controls, with confirmed UCI writes, service reload checks, rollback attempts and audit events. L3 interface/address provisioning, complete firewall zone/rule/NAT management, RADIUS/802.1X, site-to-site VPN policy, Wi-Fi SSID-to-VLAN provisioning and downstream switch configuration remain separate tasks. The inventory and configured rules are not proof that a network is safe for production office deployment.</div>
      </Panel>
    </div>
  );
}


function OfficeWifiNetworkManager({
  available,
  truncated,
  aps,
  interfaces,
  zones,
  refresh,
}: {
  available: boolean;
  truncated: boolean;
  aps: Array<{ section: string; ssid: string; device: string; networks: string[]; disabled: boolean }>;
  interfaces: RouterOfficeInterface[];
  zones: RouterOfficeFirewallZone[];
  refresh: () => void;
}) {
  const externalNetworks = new Set(
    zones.filter((zone) =>
      ["wan", "wan6", "wwan", "cellular"].includes(zone.name.toLowerCase()) ||
      zone.networks.some((network) => ["wan", "wan6", "wwan", "cellular"].includes(network.toLowerCase())),
    ).flatMap((zone) => zone.networks),
  );
  const eligibleNetworks = interfaces.filter((iface) =>
    /^[A-Za-z0-9_.-]{1,64}$/.test(iface.name) &&
    !["wan", "wan6", "wwan", "cellular"].includes(iface.name.toLowerCase()) &&
    !externalNetworks.has(iface.name),
  );
  const [selected, setSelected] = useState<Record<string, string>>({});
  const [confirmed, setConfirmed] = useState<Record<string, boolean>>({});
  const [saving, setSaving] = useState("");
  const [notices, setNotices] = useState<Record<string, { success: boolean; message: string }>>({});
  const bind = async (ap: { section: string; ssid: string; networks: string[] }) => {
    const target = selected[ap.section] ?? (ap.networks.length === 1 ? ap.networks[0] : "");
    if (!target || saving || !confirmed[ap.section]) return;
    setSaving(ap.section);
    setNotices((current) => ({ ...current, [ap.section]: undefined as never }));
    try {
      const result = await updateRouterOfficeWifiNetwork({ section: ap.section, network: target });
      setConfirmed((current) => ({ ...current, [ap.section]: false }));
      setNotices((current) => ({
        ...current,
        [ap.section]: {
          success: true,
          message: result.reloaded
            ? "SSID network binding saved to " + result.network + "; Wi-Fi reload completed."
            : "SSID is already assigned to " + result.network + ". No reload was needed.",
        },
      }));
      refresh();
    } catch (cause) {
      setNotices((current) => ({
        ...current,
        [ap.section]: {
          success: false,
          message: cause instanceof Error ? cause.message : "The SSID network binding could not be updated.",
        },
      }));
    } finally {
      setSaving("");
    }
  };
  return (
    <Panel title="SSID-to-network binding" eyebrow="WIRELESS AP → OFFICE LAN / VLAN">
      {!available ? (
        <div className="module-message">Office network inventory is unavailable. SSID binding changes are disabled.</div>
      ) : truncated ? (
        <div className="module-message">The office network inventory is truncated. Resolve it before changing SSID bindings.</div>
      ) : eligibleNetworks.length === 0 ? (
        <div className="module-message">No eligible non-WAN office network interfaces were found. Create and validate a LAN/VLAN interface in native LuCI first.</div>
      ) : aps.length === 0 ? (
        <div className="module-message">No wireless AP sections were found in UCI.</div>
      ) : (
        <div className="office-wifi-binding-list">
          {aps.map((ap) => {
            const currentBinding = ap.networks.length === 1 ? ap.networks[0] : "";
            const target = selected[ap.section] ?? currentBinding;
            const changed = ap.networks.length !== 1 || target !== currentBinding;
            const validTarget = eligibleNetworks.some((iface) => iface.name === target);
            const ready = available && !truncated && !ap.disabled && validTarget &&
              changed && Boolean(confirmed[ap.section]) && saving !== ap.section && !saving;
            return (
              <div className="office-wifi-binding-row" key={ap.section}>
                <div className="office-wifi-binding-identity">
                  <strong>{ap.ssid || "Hidden / unnamed SSID"}</strong>
                  <span>{ap.section} · {ap.device} · {ap.disabled ? "DISABLED" : "AP MODE"}</span>
                  <small>Currently bound to: {ap.networks.join(", ") || "No network / unknown"}</small>
                </div>
                <label>
                  <span>ASSIGN TO EXISTING LAN / VLAN INTERFACE</span>
                  <select
                    value={target}
                    onChange={(event) => {
                      setSelected((current) => ({ ...current, [ap.section]: event.target.value }));
                      setConfirmed((current) => ({ ...current, [ap.section]: false }));
                    }}
                    disabled={!available || truncated || ap.disabled || Boolean(saving) || eligibleNetworks.length === 0}
                  >
                    <option value="">Choose an interface…</option>
                    {eligibleNetworks.map((iface) => (
                      <option value={iface.name} key={iface.name}>
                        {iface.name} · {iface.protocol} · {iface.ipv4[0] || iface.device || "No IPv4 address"}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="office-reservation-confirm">
                  <input
                    type="checkbox"
                    checked={Boolean(confirmed[ap.section])}
                    onChange={(event) => setConfirmed((current) => ({ ...current, [ap.section]: event.target.checked }))}
                    disabled={!changed || !validTarget || ap.disabled || Boolean(saving)}
                  />
                  <span>Replace this SSID’s network binding with {target || "the selected network"} and reload Wi-Fi. Connected clients may disconnect.</span>
                </label>
                <div className="office-wifi-binding-actions">
                  <button className="hero-button" type="button" onClick={() => void bind(ap)} disabled={!ready}>
                    {saving === ap.section ? "Applying…" : "Save SSID binding"}
                  </button>
                  <Status active={validTarget && ap.networks.length === 1}>
                    {ap.networks.length === 1 && validTarget ? "BOUND" : "REVIEW"}
                  </Status>
                </div>
                {notices[ap.section] ? (
                  <div className={notices[ap.section].success ? "module-message office-reservation-success" : "module-message office-reservation-error"} role={notices[ap.section].success ? "status" : "alert"}>
                    {notices[ap.section].message}
                  </div>
                ) : null}
              </div>
            );
          })}
        </div>
      )}
      <div className="module-message">This binds an existing AP to exactly one existing non-WAN network interface. It does not create an interface, VLAN, IP address, DHCP scope or firewall zone. The active administrator management network is protected by the backend; use a separate AP or out-of-band access to move a management SSID. Verify switch tagging, firewall isolation, DHCP and IPv6 on the destination network before using it for corporate or guest clients.</div>
    </Panel>
  );
}

function OfficeFirewallZoneManager({
  available,
  truncated,
  zones,
  refresh,
}: {
  available: boolean;
  truncated: boolean;
  zones: RouterOfficeFirewallZone[];
  refresh: () => void;
}) {
  return (
    <Panel title="Firewall zone policy" eyebrow="UCI OUTPUT / FORWARD / MASQUERADE">
      {!available ? (
        <div className="module-message">Firewall configuration is unavailable. Zone policy changes are disabled.</div>
      ) : truncated ? (
        <div className="module-message">The firewall inventory is truncated. Resolve the inventory before changing zone policy.</div>
      ) : zones.length === 0 ? (
        <div className="module-message">No firewall zones were returned.</div>
      ) : (
        <div className="office-zone-policy-list">
          {zones.map((zone) => (
            <OfficeFirewallZoneEditor
              key={zone.section}
              zone={zone}
              disabled={!available || truncated}
              refresh={refresh}
            />
          ))}
        </div>
      )}
      <div className="module-message">Router INPUT policy is deliberately read-only here. Output policy affects traffic generated by the router; forward policy affects routed traffic; masquerading changes source NAT behaviour for this zone. Tightening output on the active administrator route is blocked when the route can be identified. Review existing firewall rules and test actual connectivity before applying changes.</div>
    </Panel>
  );
}

function OfficeFirewallZoneEditor({
  zone,
  disabled,
  refresh,
}: {
  zone: RouterOfficeFirewallZone;
  disabled: boolean;
  refresh: () => void;
}) {
  type PolicyChoice = "UNCHANGED" | "INHERIT" | "ACCEPT" | "REJECT" | "DROP";
  const initialOutput: PolicyChoice = zone.output === "ACCEPT" || zone.output === "REJECT" || zone.output === "DROP"
    ? zone.output
    : "UNCHANGED";
  const initialForward: PolicyChoice = zone.forward === "ACCEPT" || zone.forward === "REJECT" || zone.forward === "DROP"
    ? zone.forward
    : "UNCHANGED";
  const [output, setOutput] = useState<PolicyChoice>(initialOutput);
  const [forward, setForward] = useState<PolicyChoice>(initialForward);
  const [masquerade, setMasquerade] = useState(zone.masquerade);
  const [confirmed, setConfirmed] = useState(false);
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState<{ success: boolean; message: string } | null>(null);
  useEffect(() => {
    setOutput(initialOutput);
    setForward(initialForward);
    setMasquerade(zone.masquerade);
    setConfirmed(false);
    setNotice(null);
  }, [zone.section, zone.output, zone.forward, zone.masquerade]);

  const changed = output !== initialOutput || forward !== initialForward || masquerade !== zone.masquerade;
  const ready = changed && confirmed && !disabled && !saving;
  const apply = async () => {
    if (!ready) return;
    setSaving(true);
    setNotice(null);
    try {
      const result = await updateRouterOfficeZonePolicy({
        section: zone.section,
        output,
        forward,
        masquerade,
      });
      setNotice({
        success: true,
        message: result.name + " zone policy was saved and the firewall reload completed. INPUT remains " + result.input + ".",
      });
      setConfirmed(false);
      refresh();
    } catch (cause) {
      setNotice({
        success: false,
        message: cause instanceof Error ? cause.message : "The firewall zone policy could not be updated.",
      });
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="office-zone-policy-card">
      <div className="office-zone-policy-heading">
        <div>
          <strong>{zone.name}</strong>
          <span>{zone.networks.join(", ") || "No networks mapped"} · {zone.section}</span>
        </div>
        <Status active={zone.forward !== "ACCEPT"}>{zone.masquerade ? "MASQUERADE ON" : "MASQUERADE OFF"}</Status>
      </div>
      <div className="office-zone-policy-current">
        <span>ROUTER INPUT · READ ONLY</span>
        <strong>{zone.input || "INHERITED / DEFAULT"}</strong>
      </div>
      <div className="office-zone-policy-current office-zone-policy-current-secondary">
        <span>CURRENT OUTPUT / FORWARD</span>
        <strong>{(zone.output || "INHERITED") + " / " + (zone.forward || "INHERITED")}</strong>
      </div>
      <div className="office-zone-policy-fields">
        <label>
          <span>ROUTER OUTPUT POLICY</span>
          <select value={output} onChange={(event) => { setOutput(event.target.value as PolicyChoice); setConfirmed(false); }} disabled={disabled || saving}>
            <option value="UNCHANGED">Keep current / inherited</option>
            <option value="INHERIT">Remove override / inherit global default</option>
            <option value="ACCEPT">ACCEPT</option>
            <option value="REJECT">REJECT</option>
            <option value="DROP">DROP</option>
          </select>
        </label>
        <label>
          <span>FORWARD POLICY</span>
          <select value={forward} onChange={(event) => { setForward(event.target.value as PolicyChoice); setConfirmed(false); }} disabled={disabled || saving}>
            <option value="UNCHANGED">Keep current / inherited</option>
            <option value="INHERIT">Remove override / inherit global default</option>
            <option value="ACCEPT">ACCEPT</option>
            <option value="REJECT">REJECT</option>
            <option value="DROP">DROP</option>
          </select>
        </label>
        <label className="office-zone-masquerade">
          <input type="checkbox" checked={masquerade} onChange={(event) => { setMasquerade(event.target.checked); setConfirmed(false); }} disabled={disabled || saving} />
          <span>Enable masquerading (source NAT) for this zone</span>
        </label>
      </div>
      <label className="office-reservation-confirm">
        <input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} disabled={!changed || disabled || saving} />
        <span>I authorize this zone policy change and understand it may alter routed traffic or NAT. Router INPUT policy will not be modified.</span>
      </label>
      <div className="office-zone-policy-actions">
        <button className="hero-button" type="button" onClick={() => {
          setOutput(initialOutput);
          setForward(initialForward);
          setMasquerade(zone.masquerade);
          setConfirmed(false);
          setNotice(null);
        }} disabled={!changed || saving}>Discard</button>
        <button className="hero-button" type="button" onClick={() => void apply()} disabled={!ready}>
          {saving ? "Applying…" : "Save zone policy"}
        </button>
      </div>
      {notice ? (
        <div className={notice.success ? "module-message office-reservation-success" : "module-message office-reservation-error"} role={notice.success ? "status" : "alert"}>
          {notice.message}
        </div>
      ) : null}
    </div>
  );
}

function OfficeForwardingManager({
  available,
  truncated,
  zones,
  forwardings,
  refresh,
}: {
  available: boolean;
  truncated: boolean;
  zones: RouterOfficeFirewallZone[];
  forwardings: RouterOfficeForwarding[];
  refresh: () => void;
}) {
  const externalZone = (zone: RouterOfficeFirewallZone) =>
    ["wan", "wan6", "wwan", "cellular"].includes(zone.name.toLowerCase()) ||
    zone.networks.some((network) => ["wan", "wan6", "wwan", "cellular"].includes(network.toLowerCase()));
  const sourceZones = zones.filter((zone) => !externalZone(zone));
  const [source, setSource] = useState(sourceZones[0]?.name ?? "");
  const activeSource = sourceZones.some((zone) => zone.name === source)
    ? source
    : sourceZones[0]?.name ?? "";
  const destinationOptions = zones.filter((zone) => zone.name !== activeSource);
  const [destination, setDestination] = useState("");
  const activeDestination = destinationOptions.some((zone) => zone.name === destination)
    ? destination
    : destinationOptions.find((zone) => ["wan", "wan6", "wwan"].includes(zone.name.toLowerCase()))?.name ??
      destinationOptions[0]?.name ?? "";
  const [confirmed, setConfirmed] = useState(false);
  const [saving, setSaving] = useState(false);
  const [pendingRemoval, setPendingRemoval] = useState("");
  const [removalBusy, setRemovalBusy] = useState(false);
  const [notice, setNotice] = useState<{ success: boolean; message: string } | null>(null);
  const canCreate = available && !truncated && sourceZones.length > 0 &&
    Boolean(activeSource) && Boolean(activeDestination) && activeDestination !== activeSource &&
    confirmed && !saving;
  const create = async () => {
    if (!canCreate) return;
    setSaving(true);
    setNotice(null);
    try {
      const result = await createRouterOfficeForwarding({ source: activeSource, destination: activeDestination });
      setNotice({
        success: true,
        message: "Forwarding " + result.source + " → " + result.destination +
          " was saved and the firewall reload completed.",
      });
      setConfirmed(false);
      refresh();
    } catch (cause) {
      setNotice({
        success: false,
        message: cause instanceof Error ? cause.message : "The firewall forwarding could not be created.",
      });
    } finally {
      setSaving(false);
    }
  };
  const remove = async (section: string) => {
    if (!section || removalBusy) return;
    setRemovalBusy(true);
    setNotice(null);
    try {
      const result = await removeRouterOfficeForwarding(section);
      setPendingRemoval("");
      setNotice({
        success: true,
        message: "Forwarding " + result.source + " → " + result.destination +
          " was removed and the firewall reload completed.",
      });
      refresh();
    } catch (cause) {
      setNotice({
        success: false,
        message: cause instanceof Error ? cause.message : "The firewall forwarding could not be removed.",
      });
    } finally {
      setRemovalBusy(false);
    }
  };

  return (
    <Panel title="Inter-zone forwarding" eyebrow="FIREWALL UCI · GUARDED SOURCE → DESTINATION">
      {!available ? (
        <div className="module-message">Firewall configuration is unavailable. Forwarding changes are disabled.</div>
      ) : truncated ? (
        <div className="module-message">The firewall inventory is truncated. Resolve the inventory before changing inter-zone forwarding.</div>
      ) : zones.length < 2 ? (
        <div className="module-message">At least two existing firewall zones are required before a forwarding can be configured.</div>
      ) : null}
      <div className="office-forwarding-manager">
        <div className="office-forwarding-list">
          {forwardings.length === 0 ? (
            <div className="module-message">No explicit inter-zone forwarding sections were returned. Zone policies and firewall rules can still affect traffic.</div>
          ) : (
            forwardings.map((forwarding) => (
              <div className="office-forwarding-row" key={forwarding.section}>
                <div><strong>{forwarding.source}</strong><span>{forwarding.name} · {forwarding.section}</span></div>
                <span className="office-forwarding-arrow">→</span>
                <div><strong>{forwarding.destination}</strong><span>Explicit UCI forwarding</span></div>
                {pendingRemoval === forwarding.section ? (
                  <div className="office-forwarding-remove-confirm">
                    <span>Remove this permitted path?</span>
                    <button className="office-remove-start" type="button" onClick={() => void remove(forwarding.section)} disabled={removalBusy}>
                      {removalBusy ? "Removing…" : "Confirm"}
                    </button>
                    <button className="office-remove-start" type="button" onClick={() => setPendingRemoval("")} disabled={removalBusy}>Cancel</button>
                  </div>
                ) : (
                  <button className="office-remove-start" type="button" onClick={() => setPendingRemoval(forwarding.section)} disabled={!forwarding.section || removalBusy || saving}>
                    Remove forwarding
                  </button>
                )}
              </div>
            ))
          )}
        </div>
        <div className="office-forwarding-editor">
          <div>
            <strong>Add an inter-zone forwarding</strong>
            <span>Permit traffic initiated from one zone to a second zone. Router input policy is not changed.</span>
          </div>
          <div className="office-forwarding-fields">
            <label>
              <span>SOURCE ZONE</span>
              <select value={activeSource} onChange={(event) => {
                setSource(event.target.value);
                setConfirmed(false);
                if (event.target.value === activeDestination) {
                  setDestination(zones.find((zone) => zone.name !== event.target.value)?.name ?? "");
                }
              }} disabled={!available || truncated || saving || sourceZones.length === 0}>
                {sourceZones.map((zone) => (
                  <option value={zone.name} key={zone.name}>{zone.name} · {zone.networks.join(", ") || "No network mapped"}</option>
                ))}
              </select>
            </label>
            <label>
              <span>DESTINATION ZONE</span>
              <select value={activeDestination} onChange={(event) => {
                setDestination(event.target.value);
                setConfirmed(false);
              }} disabled={!available || truncated || saving || destinationOptions.length === 0}>
                {destinationOptions.map((zone) => (
                  <option value={zone.name} key={zone.name}>{zone.name} · {zone.networks.join(", ") || "No network mapped"}</option>
                ))}
              </select>
            </label>
          </div>
          <label className="office-reservation-confirm">
            <input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} disabled={!available || truncated || saving || !activeSource || !activeDestination || activeSource === activeDestination} />
            <span>I explicitly permit sessions initiated in {source || "the source zone"} to reach {destination || "the destination zone"} and authorize a firewall reload.</span>
          </label>
          <button className="hero-button" type="button" onClick={() => void create()} disabled={!canCreate}>
            {saving ? "Applying…" : "Add forwarding"}
          </button>
        </div>
      </div>
      {notice ? (
        <div className={notice.success ? "module-message office-reservation-success" : "module-message office-reservation-error"} role={notice.success ? "status" : "alert"}>
          {notice.message}
        </div>
      ) : null}
      <div className="module-message">The API never edits zone input/output policies through this control. WAN/WWAN zones cannot be selected as a forwarding source; an external zone may be a destination (for example, staff → WAN). Forwardings are directional and are not a substitute for reviewing the full firewall ruleset or testing the packet path. Changes are committed to UCI, followed by firewall reload and rollback attempts on failure.</div>
    </Panel>
  );
}

function OfficeSegmentManager({
  available,
  truncated,
  interfaces,
  bridges,
  vlans,
  zones,
  refresh,
}: {
  available: boolean;
  truncated: boolean;
  interfaces: RouterOfficeInterface[];
  bridges: RouterOfficeBridge[];
  vlans: RouterOfficeVlan[];
  zones: RouterOfficeFirewallZone[];
  refresh: () => void;
}) {
  const [name, setName] = useState("corp20");
  const [vlanSection, setVlanSection] = useState("");
  const [address, setAddress] = useState("192.168.20.1");
  const [netmask, setNetmask] = useState("255.255.255.0");
  const [zoneSection, setZoneSection] = useState("");
  const [dhcpStart, setDhcpStart] = useState("100");
  const [dhcpLimit, setDhcpLimit] = useState("100");
  const [leaseTime, setLeaseTime] = useState("12h");
  const [confirmed, setConfirmed] = useState(false);
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState<{ success: boolean; message: string } | null>(null);

  const eligibleVlans = vlans.filter((vlan) =>
    bridges.some((bridge) => bridge.name === vlan.device && bridge.vlan_filtering &&
      bridge.ports.length > 0) && vlan.ports.length > 0
  );
  const selectedVlan = eligibleVlans.find((vlan) => vlan.name === vlanSection) ?? eligibleVlans[0];
  const externalNames = ["wan", "wan6", "wwan", "cellular"];
  const eligibleZones = zones.filter((zone) =>
    !externalNames.includes(zone.name.toLowerCase()) &&
    !zone.networks.some((network) => externalNames.includes(network.toLowerCase())) &&
    (zone.input === "REJECT" || zone.input === "DROP") &&
    (zone.forward === "REJECT" || zone.forward === "DROP")
  );
  const selectedZone = eligibleZones.find((zone) => zone.section === zoneSection) ?? eligibleZones[0];
  const nameValid = /^[A-Za-z][A-Za-z0-9_-]{0,31}$/.test(name) &&
    !["lan", "wan", "wan6", "loopback", "wwan", "cellular"].includes(name);
  const nameUnique = !interfaces.some((item) => item.name === name);
  const addressParts = address.split(".");
  const addressValid = addressParts.length === 4 && addressParts.every((part) =>
    /^(0|[1-9][0-9]{0,2})$/.test(part) && Number(part) <= 255
  );
  const addressNumbers = addressValid ? addressParts.map(Number) : [];
  const privateAddress = addressValid && (
    addressNumbers[0] === 10 ||
    (addressNumbers[0] === 172 && addressNumbers[1] >= 16 && addressNumbers[1] <= 31) ||
    (addressNumbers[0] === 192 && addressNumbers[1] === 168)
  );
  const maskParts = netmask.split(".");
  const maskValidOctets = maskParts.length === 4 && maskParts.every((part) =>
    /^(0|[1-9][0-9]{0,2})$/.test(part) && Number(part) <= 255
  );
  const maskBits = maskValidOctets
    ? maskParts.map((part) => Number(part).toString(2).padStart(8, "0")).join("")
    : "";
  const maskValid = /^1{1,30}0*$/.test(maskBits) && maskBits.length === 32;
  const dhcpValid = /^[1-9][0-9]{0,9}$/.test(dhcpStart) &&
    /^[1-9][0-9]{0,9}$/.test(dhcpLimit) &&
    /^[1-9][0-9]{0,8}[smhdw]?$/.test(leaseTime);
  const ready = available && !truncated && Boolean(selectedVlan) && Boolean(selectedZone) &&
    nameValid && nameUnique && privateAddress && maskValid && dhcpValid &&
    confirmed && !saving;

  const updateField = (setter: (value: string) => void) => (value: string) => {
    setter(value);
    setConfirmed(false);
    setNotice(null);
  };
  const provision = async () => {
    if (!ready || !selectedVlan || !selectedZone) return;
    setSaving(true);
    setNotice(null);
    try {
      const result = await createRouterOfficeSegment({
        name,
        bridge: selectedVlan.device,
        vlanId: String(selectedVlan.vlan_id),
        address,
        netmask,
        zone: selectedZone.section,
        dhcpStart,
        dhcpLimit,
        leaseTime,
      });
      setNotice({
        success: true,
        message: result.name + " is configured on " + result.device + " at " +
          result.address + "/" + maskBits.replace(/0/g, "").length +
          ". DHCP serves " + result.pool_start_ip + " – " + result.pool_end_ip +
          "; DHCP/DNS firewall rules were installed and all three services reloaded.",
      });
      setConfirmed(false);
      refresh();
    } catch (cause) {
      setNotice({
        success: false,
        message: cause instanceof Error ? cause.message : "The office network could not be provisioned.",
      });
    } finally {
      setSaving(false);
    }
  };

  return (
    <Panel title="Provision an IPv4 office network" eyebrow="EXISTING VLAN · STATIC GATEWAY · DHCP · DEFAULT-DENY FIREWALL">
      {!available ? (
        <div className="module-message">Network, firewall or DHCP configuration is unavailable. Segment provisioning is disabled.</div>
      ) : truncated ? (
        <div className="module-message">The router inventory is truncated. Resolve the inventory before provisioning so subnet, VLAN and DHCP conflicts can be checked completely.</div>
      ) : eligibleVlans.length === 0 ? (
        <div className="module-message">Create and verify an existing bridge VLAN with explicit switch-port membership before provisioning an L3 network.</div>
      ) : null}
      <div className="office-segment-manager">
        <div className="office-segment-fields">
          <label>
            <span>NETWORK NAME</span>
            <input value={name} onChange={(event) => updateField(setName)(event.target.value)} maxLength={32} placeholder="corp20" autoComplete="off" />
            {!nameValid ? <small>Use 1–32 letters, digits, underscores or hyphens; reserved WAN/LAN names are blocked.</small> :
              !nameUnique ? <small>A network interface with this name already exists.</small> : null}
          </label>
          <label>
            <span>EXISTING VLAN / BRIDGE</span>
            <select
              value={selectedVlan?.name ?? ""}
              onChange={(event) => { setVlanSection(event.target.value); setConfirmed(false); setNotice(null); }}
              disabled={saving || eligibleVlans.length === 0}
            >
              {eligibleVlans.map((vlan) => (
                <option key={vlan.name} value={vlan.name}>VLAN {vlan.vlan_id} · {vlan.device} · {vlan.ports.length} port memberships</option>
              ))}
            </select>
          </label>
          <label>
            <span>GATEWAY IPv4</span>
            <input value={address} onChange={(event) => updateField(setAddress)(event.target.value)} maxLength={15} placeholder="192.168.20.1" inputMode="decimal" />
            {address.length > 0 && !privateAddress ? <small>Use an RFC1918 private gateway address in canonical dotted-decimal format.</small> : null}
          </label>
          <label>
            <span>SUBNET MASK</span>
            <input value={netmask} onChange={(event) => updateField(setNetmask)(event.target.value)} maxLength={15} placeholder="255.255.255.0" inputMode="decimal" />
            {!maskValid ? <small>Use a contiguous IPv4 mask from /1 through /30.</small> : null}
          </label>
          <label>
            <span>FIREWALL ZONE</span>
            <select
              value={selectedZone?.section ?? ""}
              onChange={(event) => { setZoneSection(event.target.value); setConfirmed(false); setNotice(null); }}
              disabled={saving || eligibleZones.length === 0}
            >
              {eligibleZones.map((zone) => (
                <option key={zone.section} value={zone.section}>{zone.name} · input {zone.input} · forward {zone.forward}</option>
              ))}
            </select>
            {eligibleZones.length === 0 ? <small>Configure an internal zone with router INPUT and inter-zone FORWARD set to REJECT or DROP first.</small> : null}
          </label>
          <label>
            <span>DHCP START OFFSET</span>
            <input type="number" min={1} step={1} value={dhcpStart} onChange={(event) => updateField(setDhcpStart)(event.target.value)} inputMode="numeric" />
          </label>
          <label>
            <span>DHCP POOL SIZE</span>
            <input type="number" min={1} step={1} value={dhcpLimit} onChange={(event) => updateField(setDhcpLimit)(event.target.value)} inputMode="numeric" />
          </label>
          <label>
            <span>DHCP LEASE TIME</span>
            <input value={leaseTime} onChange={(event) => updateField(setLeaseTime)(event.target.value)} maxLength={16} placeholder="12h" />
          </label>
        </div>
        <div className="office-segment-policy">
          <div>
            <strong>Built-in isolation baseline</strong>
            <span>The selected firewall zone must already reject router INPUT and inter-zone FORWARD by default. QuantumGrid leaves those zone policies unchanged and adds only three IPv4 rules: DHCP UDP/67 and DNS TCP/UDP 53, each limited to this gateway address.</span>
          </div>
          <div>
            <strong>Provisioning transaction</strong>
            <span>Creates one static L3 interface on the existing bridge VLAN, attaches it to the selected zone, creates one DHCP pool, commits network/firewall/DHCP UCI and reloads network, firewall and dnsmasq. Failure triggers a cross-package rollback attempt.</span>
          </div>
        </div>
        <label className="office-reservation-confirm">
          <input
            type="checkbox"
            checked={confirmed}
            onChange={(event) => setConfirmed(event.target.checked)}
            disabled={!available || truncated || saving || !selectedVlan || !selectedZone}
          />
          <span>I confirm this VLAN, gateway subnet, DHCP pool and firewall zone. I understand that network/firewall reloads can interrupt connectivity and that this operation creates a routed IPv4 segment.</span>
        </label>
        <div className="office-segment-actions">
          <button className="hero-button" type="button" onClick={() => void provision()} disabled={!ready}>
            {saving ? "Provisioning…" : "Provision office network"}
          </button>
        </div>
        {notice ? (
          <div className={notice.success ? "module-message office-reservation-success" : "module-message office-reservation-error"} role={notice.success ? "status" : "alert"}>
            {notice.message}
          </div>
        ) : null}
      </div>
      <div className="module-message">This provisions IPv4 only and requires a pre-existing bridge VLAN. It does not add Wi-Fi SSIDs, DHCPv6/RA, static leases, IPv6 addresses, inter-zone forwarding or downstream switch configuration. Validate the switch/AP path from an out-of-band management connection before production use.</div>
    </Panel>
  );
}

type OfficeVlanPortMode = "excluded" | "unspecified" | "tagged" | "untagged" | "untagged-pvid";

function OfficeBridgeVlanManager({
  available,
  truncated,
  bridges,
  vlans,
  refresh,
}: {
  available: boolean;
  truncated: boolean;
  bridges: RouterOfficeBridge[];
  vlans: RouterOfficeVlan[];
  refresh: () => void;
}) {
  const vlanBridges = bridges.filter((bridge) => bridge.vlan_filtering && bridge.ports.length > 0);
  const [device, setDevice] = useState("");
  const [editingSection, setEditingSection] = useState("");
  const [vlanId, setVlanId] = useState("");
  const [portModes, setPortModes] = useState<Record<string, OfficeVlanPortMode>>({});
  const [confirmed, setConfirmed] = useState(false);
  const [saving, setSaving] = useState(false);
  const [removing, setRemoving] = useState("");
  const [removalBusy, setRemovalBusy] = useState(false);
  const [notice, setNotice] = useState<{ success: boolean; message: string } | null>(null);
  const activeDevice = vlanBridges.some((bridge) => bridge.name === device)
    ? device
    : vlanBridges[0]?.name ?? "";
  const activeBridge = vlanBridges.find((bridge) => bridge.name === activeDevice);
  const selectedPorts = activeBridge?.ports.flatMap((name) => {
    const mode = portModes[name] ?? "excluded";
    if (mode === "excluded" || mode === "unspecified") return [];
    return [{
      name,
      mode: mode === "tagged" ? "tagged" as const : "untagged" as const,
      pvid: mode === "untagged-pvid",
    }];
  }) ?? [];
  const pvidCount = selectedPorts.filter((port) => port.pvid).length;
  const vlanNumber = Number(vlanId);
  const validVlanId = /^[1-9][0-9]{0,3}$/.test(vlanId) && vlanNumber >= 1 && vlanNumber <= 4094;
  const unresolvedPortModes = activeBridge?.ports.some((port) => portModes[port] === "unspecified") ?? false;
  const ready = available && !truncated && Boolean(activeBridge) &&
    validVlanId && selectedPorts.length > 0 && !unresolvedPortModes &&
    pvidCount <= selectedPorts.length && confirmed && !saving;

  const resetEditor = () => {
    setEditingSection("");
    setVlanId("");
    setPortModes({});
    setConfirmed(false);
  };
  const editVlan = (vlan: RouterOfficeVlan) => {
    const next: Record<string, OfficeVlanPortMode> = {};
    for (const port of vlan.ports) {
      next[port.name] = port.mode === "tagged"
        ? "tagged"
        : port.mode === "unspecified" ? "unspecified"
          : port.pvid ? "untagged-pvid" : "untagged";
    }
    setDevice(vlan.device);
    setEditingSection(vlan.name);
    setVlanId(String(vlan.vlan_id));
    setPortModes(next);
    setConfirmed(false);
    setNotice(null);
  };
  const saveVlan = async () => {
    if (!ready || !activeBridge) return;
    setSaving(true);
    setNotice(null);
    try {
      const result = await updateRouterOfficeVlan({
        section: editingSection || undefined,
        device: activeBridge.name,
        vlanId,
        ports: selectedPorts,
      });
      setNotice({
        success: true,
        message: "VLAN " + result.vlan_id + " membership on " + result.device +
          " was saved and the network reload completed.",
      });
      resetEditor();
      refresh();
    } catch (cause) {
      setNotice({
        success: false,
        message: cause instanceof Error ? cause.message : "The bridge VLAN could not be saved.",
      });
    } finally {
      setSaving(false);
    }
  };
  const removeVlan = async (section: string) => {
    if (!section || removalBusy) return;
    setRemovalBusy(true);
    setNotice(null);
    try {
      const result = await removeRouterOfficeVlan(section);
      setRemoving("");
      if (editingSection === section) resetEditor();
      setNotice({
        success: true,
        message: "VLAN " + result.vlan_id + " was removed from " + result.device +
          " and the network reload completed.",
      });
      refresh();
    } catch (cause) {
      setNotice({
        success: false,
        message: cause instanceof Error ? cause.message : "The bridge VLAN could not be removed.",
      });
    } finally {
      setRemovalBusy(false);
    }
  };

  return (
    <Panel title="Bridge VLAN management" eyebrow="NETWORK UCI · GUARDED CONFIGURATION">
      {!available ? (
        <div className="module-message">Network configuration is unavailable. VLAN changes are disabled.</div>
      ) : truncated ? (
        <div className="module-message">The network inventory is truncated. Resolve the inventory limit before editing VLANs so duplicate IDs and PVID assignments can be checked completely.</div>
      ) : vlanBridges.length === 0 ? (
        <div className="module-message">No bridge with VLAN filtering enabled and declared switch ports was found. Configure and verify bridge VLAN filtering through native LuCI before using this manager.</div>
      ) : null}
      <div className="office-vlan-manager">
        <div className="office-vlan-manager-list">
          {vlans.length === 0 ? (
            <div className="module-message">No bridge VLAN sections are currently configured.</div>
          ) : (
            vlans.map((vlan) => {
              const filtering = vlanBridges.some((bridge) => bridge.name === vlan.device);
              return (
                <div className="office-vlan-card" key={vlan.name}>
                  <div className="office-vlan-heading">
                    <div>
                      <strong>VLAN {vlan.vlan_id}</strong>
                      <span>{vlan.name} · {vlan.device}</span>
                    </div>
                    <Status active={filtering}>{filtering ? "FILTERING ON" : "NOT MANAGEABLE"}</Status>
                  </div>
                  <div className="office-vlan-ports">
                    {vlan.ports.map((port) => (
                      <div className="office-vlan-port" key={port.name}>
                        <strong>{port.name}</strong>
                        <span>{port.mode.toUpperCase()}</span>
                        {port.pvid ? <small>PVID</small> : null}
                      </div>
                    ))}
                    {vlan.ports.length === 0 ? <small>No parseable switch ports were reported.</small> : null}
                  </div>
                  <div className="office-vlan-actions">
                    <button className="office-remove-start" type="button" onClick={() => editVlan(vlan)} disabled={!filtering || saving || removalBusy}>
                      Edit membership
                    </button>
                    {removing === vlan.name ? (
                      <div className="office-vlan-remove-confirm">
                        <span>Remove VLAN {vlan.vlan_id} and reload networking?</span>
                        <button className="office-remove-start" type="button" onClick={() => void removeVlan(vlan.name)} disabled={removalBusy}>
                          {removalBusy ? "Removing…" : "Confirm removal"}
                        </button>
                        <button className="office-remove-start" type="button" onClick={() => setRemoving("")} disabled={removalBusy}>Cancel</button>
                      </div>
                    ) : (
                      <button className="office-remove-start" type="button" onClick={() => setRemoving(vlan.name)} disabled={!filtering || saving || removalBusy}>
                        Remove VLAN
                      </button>
                    )}
                  </div>
                </div>
              );
            })
          )}
        </div>
        <div className="office-vlan-editor">
          <div className="office-vlan-editor-heading">
            <strong>{editingSection ? "Edit bridge VLAN" : "Create bridge VLAN"}</strong>
            <span>{editingSection ? "Update existing membership" : "Add a VLAN to an existing bridge"}</span>
          </div>
          <div className="office-vlan-editor-fields">
            <label>
              <span>VLAN-FILTERED BRIDGE</span>
              <select
                value={activeDevice}
                onChange={(event) => {
                  setDevice(event.target.value);
                  resetEditor();
                  setNotice(null);
                }}
                disabled={saving || vlanBridges.length === 0}
              >
                {vlanBridges.map((bridge) => (
                  <option value={bridge.name} key={bridge.name}>{bridge.name} · {bridge.ports.length} port(s)</option>
                ))}
              </select>
            </label>
            <label>
              <span>VLAN ID</span>
              <input
                type="number"
                min={1}
                max={4094}
                step={1}
                value={vlanId}
                onChange={(event) => { setVlanId(event.target.value); setConfirmed(false); }}
                placeholder="20"
                inputMode="numeric"
                disabled={saving || !activeBridge}
              />
            </label>
          </div>
          <div className="office-vlan-port-editor">
            <div className="office-vlan-port-editor-heading">
              <strong>Switch port membership</strong>
              <span>Port modes must be explicit; a port can be assigned only one PVID across this bridge.</span>
            </div>
            {!activeBridge ? (
              <div className="module-message">No manageable bridge is selected.</div>
            ) : (
              activeBridge.ports.map((port) => (
                <label className="office-vlan-port-edit-row" key={port}>
                  <strong>{port}</strong>
                  <select
                    value={portModes[port] ?? "excluded"}
                    onChange={(event) => {
                      setPortModes((current) => ({ ...current, [port]: event.target.value as OfficeVlanPortMode }));
                      setConfirmed(false);
                    }}
                    disabled={saving}
                  >
                    <option value="excluded">Not a member</option>
                    <option value="unspecified">Current mode unknown — choose explicitly</option>
                    <option value="tagged">Tagged</option>
                    <option value="untagged">Untagged</option>
                    <option value="untagged-pvid">Untagged · PVID</option>
                  </select>
                </label>
              ))
            )}
          </div>
          <div className="office-vlan-membership-summary">
            <span>{selectedPorts.length} selected port(s)</span>
            <span>{selectedPorts.filter((port) => port.mode === "tagged").length} tagged</span>
            <span>{selectedPorts.filter((port) => port.mode === "untagged").length} untagged</span>
            <span>{pvidCount} PVID</span>
            {unresolvedPortModes ? <span>Resolve unknown existing port modes before saving</span> : null}
          </div>
          <label className="office-reservation-confirm">
            <input
              type="checkbox"
              checked={confirmed}
              onChange={(event) => setConfirmed(event.target.checked)}
              disabled={!activeBridge || saving || !validVlanId || selectedPorts.length === 0}
            />
            <span>I understand that reloading network configuration can interrupt connectivity. I have checked the management-port tagging and VLAN assignments before applying this change.</span>
          </label>
          <div className="office-vlan-editor-actions">
            <button className="hero-button" type="button" onClick={resetEditor} disabled={!editingSection && !vlanId && !Object.keys(portModes).length || saving}>
              {editingSection ? "Cancel edit" : "Clear form"}
            </button>
            <button className="hero-button" type="button" onClick={() => void saveVlan()} disabled={!ready}>
              {saving ? "Applying…" : editingSection ? "Save VLAN membership" : "Create VLAN"}
            </button>
          </div>
          {notice ? (
            <div className={notice.success ? "module-message office-reservation-success" : "module-message office-reservation-error"} role={notice.success ? "status" : "alert"}>
              {notice.message}
            </div>
          ) : null}
        </div>
      </div>
      <div className="module-message">Changes update native OpenWrt network UCI and trigger a network reload. Incorrect VLAN membership can disconnect wireless clients, wired devices or the administrator session. QuantumGrid validates bridge ports, duplicate IDs and PVID collisions, and restores the previous UCI section when a reload fails; it cannot prove that downstream switches or access points are configured correctly.</div>
    </Panel>
  );
}

function HardwareBoardPinList({ title, entries }: {
  title: string;
  entries: RouterBoardGpioLineReference[];
}) {
  return (
    <section className="hardware-board-pin-group">
      <div className="hardware-board-pin-group-title">{title}</div>
      <div className="hardware-board-pin-list">
        {entries.map((entry) => (
          <div className="hardware-board-pin-row" key={entry.name}>
            <div>
              <strong>{entry.name}</strong>
              <span>{entry.purpose}</span>
              <small>{entry.owner}{entry.linux_key ? " · " + entry.linux_key : ""}{entry.initial_level ? " · DTS initial " + entry.initial_level : ""}</small>
              {entry.note ? <small>{entry.note}</small> : null}
            </div>
            <div className="hardware-board-pin-meta">
              <b>TLMM GPIO {entry.tlmm_offset}</b>
              <span>{entry.direction.toUpperCase()} · ACTIVE {entry.active_level.toUpperCase()}</span>
            </div>
            <Status active={false}>REFERENCE ONLY</Status>
          </div>
        ))}
      </div>
    </section>
  );
}


function HardwareIoControlPage({ routerOverview, refresh }: {
  routerOverview: RouterOverview | null;
  refresh: () => void;
}) {
  const hardware = routerOverview?.hardware_io;
  const gpio = hardware?.gpio;
  const lines = gpio?.lines ?? [];
  const buttonLines = lines.filter((line) => line.is_button);
  const sysfsGpioChips = gpio?.sysfs?.chips ?? [];
  const leds = hardware?.leds ?? [];
  const inputDevices = hardware?.input_devices?.devices ?? [];
  const boardReference = hardware?.board_reference;
  const [brightnessValues, setBrightnessValues] = useState<Record<string, number>>({});
  const [savingLed, setSavingLed] = useState<string | null>(null);
  const [notice, setNotice] = useState<{ success: boolean; message: string } | null>(null);

  const getBrightness = (name: string, current: number | undefined) =>
    brightnessValues[name] ?? current ?? 0;

  const applyLed = async (led: (typeof leds)[number]) => {
    if (!led.controllable || led.max_brightness === undefined) return;
    const brightness = getBrightness(led.name, led.brightness);
    setSavingLed(led.name);
    setNotice(null);
    try {
      await updateRouterLedBrightness(led.name, brightness);
      setNotice({ success: true, message: `Applied ${brightness} brightness to ${led.name}. The setting is runtime-only.` });
      setBrightnessValues((previous) => ({ ...previous, [led.name]: brightness }));
      refresh();
    } catch (error) {
      setNotice({
        success: false,
        message: error instanceof Error ? error.message : "The LED brightness update failed.",
      });
    } finally {
      setSavingLed(null);
    }
  };

  return (
    <div className="module-page hardware-io-page">
      <section className="module-hero">
        <div className="module-icon"><Cpu size={25} /></div>
        <div>
          <div className="setup-kicker">AW1000 HARDWARE · KERNEL I/O</div>
          <h1>Hardware I/O</h1>
          <p>Inspect GPIO lines and physical button consumers reported by the running kernel, then adjust supported LED-class devices. GPIO lines stay read-only until the AW1000 pin mapping and safe ownership rules are validated.</p>
        </div>
      </section>

      <div className="metrics">
        <Metric title="GPIO Debugfs" value={gpio?.available ? "AVAILABLE" : gpio?.sysfs?.available ? "CHIPS ONLY" : "UNAVAILABLE"} unit="" detail={gpio?.available ? "Kernel-owned line inventory" : "Sysfs fallback does not expose line state"} icon={Cpu} />
        <Metric title="GPIO Chips" value={gpio?.available ? fmt(gpio.chip_count) : gpio?.sysfs?.available ? fmt(gpio.sysfs.count) : "N/A"} unit="" detail={gpio?.available ? (gpio.truncated ? "Debugfs inventory is capped" : "Reported by debugfs") : "Reported by GPIO sysfs"} icon={Database} />
        <Metric title="Button-like Lines" value={gpio?.available ? fmt(buttonLines.length) : "N/A"} unit="" detail="Label/consumer name matches only" icon={Settings} />
        <Metric title="LED Devices" value={hardware?.leds_available ? fmt(leds.length) : "N/A"} unit="" detail={leds.filter((led) => led.controllable).length + " with safe manual control"} icon={Zap} />
      </div>

      {notice && (
        <div className={notice.success ? "module-message hardware-io-notice success" : "module-message hardware-io-notice error"} role={notice.success ? "status" : "alert"}>
          {notice.message}
        </div>
      )}

      <Panel title="GPIO chips and line inventory" eyebrow="READ-ONLY · DEBUGFS + SYSFS" action={<button className="hero-button" onClick={refresh}><RefreshCw size={14} /> Refresh hardware</button>}>
        {!routerOverview ? (
          <div className="module-message">Waiting for authenticated router telemetry.</div>
        ) : !gpio?.available ? (
          <>
            {sysfsGpioChips.length > 0 && (
              <div className="hardware-chip-list">
                {sysfsGpioChips.map((chip) => (
                  <div className="hardware-chip" key={chip.name}>
                    <strong>{chip.name}</strong>
                    <span>{chip.label || "Unlabelled controller"} · base {chip.base} · {chip.ngpio} lines</span>
                  </div>
                ))}
              </div>
            )}
            <div className="module-message">{sysfsGpioChips.length > 0
              ? "GPIO debugfs is unavailable, but kernel sysfs exposes chip labels, base offsets and line counts. It does not expose per-line consumers, direction or level; enable debugfs locally for that read-only detail."
              : "Neither GPIO debugfs nor GPIO sysfs chip metadata is available on this firmware. QuantumGrid will not guess pin numbers or export arbitrary GPIO controls."}</div>
          </>
        ) : (
          <>
            <div className="hardware-chip-list">
              {gpio.chips.map((chip) => (
                <div className="hardware-chip" key={chip.name}>
                  <strong>{chip.name}</strong>
                  <span>GPIO {chip.first_gpio ?? "?"}–{chip.last_gpio ?? "?"}</span>
                </div>
              ))}
              {gpio.chips.length === 0 && <div className="module-message">The kernel exposed the GPIO debugfs file but did not report a parseable chip header.</div>}
            </div>
            <div className="hardware-io-table">
              <div className="hardware-io-row header"><span>LINE</span><span>LABEL / CONSUMER</span><span>DIRECTION</span><span>LEVEL</span><span>CLASSIFICATION</span></div>
              {lines.map((line) => (
                <div className="hardware-io-row" key={line.number}>
                  <strong>GPIO {line.number}</strong>
                  <span><b>{line.label || "Unnamed line"}</b><small>{line.consumer || "No consumer reported"}</small></span>
                  <span>{line.direction.toUpperCase()}</span>
                  <span>{line.state.toUpperCase()}</span>
                  <span><Status active={line.is_button}>{line.is_button ? "BUTTON-LIKE" : "GENERAL I/O"}</Status></span>
                </div>
              ))}
              {lines.length === 0 && <div className="module-message">No GPIO line entries were exposed by the running kernel.</div>}
            </div>
            {gpio.truncated && <div className="module-message">The raw GPIO inventory exceeded the 128-line display cap. The chip and line counts above indicate the full reported count where available.</div>}
            <div className="module-message">Button-like is a label/consumer-name hint, not a verified physical pin map. GPIO line state remains read-only: the page does not change pin direction, drive output lines, export GPIOs, or alter kernel ownership.</div>
          </>
        )}
      </Panel>

      <Panel title="AW1000 board pin reference" eyebrow="UPSTREAM DEVICE TREE · READ-ONLY MAP" action={<Status active={boardReference?.available === true}>{boardReference?.available ? "BOARD MATCHED" : "NOT MATCHED"}</Status>}>
        {!boardReference?.available ? (
          <div className="module-message">The running device tree does not identify this router as Arcadyan AW1000. The AW1000-specific pin map is intentionally hidden rather than applied to an unknown board.</div>
        ) : (
          <>
            <div className="hardware-board-profile-head">
              <div>
                <strong>{boardReference.model}</strong>
                <span>{boardReference.compatible} · {boardReference.offset_namespace}</span>
              </div>
              <a href={boardReference.source_url} target="_blank" rel="noreferrer">Open upstream DTS source</a>
            </div>
            <HardwareBoardPinList title="Physical buttons · active-low inputs" entries={boardReference.buttons} />
            <HardwareBoardPinList title="Modem and USB control · kernel-owned outputs/regulator" entries={boardReference.auxiliary} />
            <HardwareBoardPinList title="SPI and management bus signals" entries={boardReference.bus_signals} />
            <HardwareBoardPinList title="Ethernet PHY resets" entries={boardReference.phy_resets} />
            {boardReference.led_expander && (
              <section className="hardware-board-pin-group">
                <div className="hardware-board-pin-group-title">
                  {boardReference.led_expander.part} · {boardReference.led_expander.register_count} registers · outputs are not TLMM GPIO offsets
                </div>
                <div className="hardware-board-expander-summary">
                  <span>SCK TLMM {boardReference.led_expander.clock_tlmm_offset}</span>
                  <span>MOSI TLMM {boardReference.led_expander.data_tlmm_offset}</span>
                  <span>Enable TLMM {boardReference.led_expander.enable_tlmm_offset}</span>
                </div>
                <div className="hardware-board-pin-list">
                  {boardReference.led_expander.outputs.map((output) => (
                    <div className="hardware-board-pin-row" key={output.output_index}>
                      <div>
                        <strong>{output.name}</strong>
                        <span>{output.label}</span>
                      </div>
                      <div className="hardware-board-pin-meta">
                        <b>74HC595 output {output.output_index}</b>
                        <span>ACTIVE {output.active_level.toUpperCase()}</span>
                      </div>
                      <Status active={false}>KERNEL LED CLASS</Status>
                    </div>
                  ))}
                </div>
              </section>
            )}
            <div className="module-message hardware-board-warning">{boardReference.warning} The panel is a reference only: QuantumGrid does not export or drive these pins, change pinmux, reset the modem, toggle USB power or bit-bang the LED shift register.</div>
            <div className="hardware-board-source-hash">DTS blob {boardReference.source_blob_sha}</div>
          </>
        )}
      </Panel>

      <Panel title="Native button event hooks" eyebrow="PROCD · EXISTING SYSTEM HANDLERS">
        <div className="hardware-button-status">
          <div><span>gpio-button-hotplug driver</span><Status active={hardware?.button_driver_loaded === true}>{hardware?.button_driver_loaded ? "DETECTED" : "NOT DETECTED"}</Status></div>
          <div><span>/etc/rc.button directory</span><Status active={hardware?.button_hooks_available === true}>{hardware?.button_hooks_available ? "AVAILABLE" : "UNAVAILABLE"}</Status></div>
        </div>
        {!hardware?.button_hooks_available ? (
          <div className="module-message">Native button handler inventory is unavailable on this firmware.</div>
        ) : (hardware.button_handlers ?? []).length === 0 ? (
          <div className="module-message">The native handler directory exists, but it contains no named button handlers.</div>
        ) : (
          <div className="hardware-button-handlers">
            {(hardware.button_handlers ?? []).map((name) => <span key={name}>{name}</span>)}
          </div>
        )}
        <div className="module-message">OpenWrt procd dispatches Linux button events to the matching /etc/rc.button handler. QuantumGrid observes the separate procd hotplug.button ubus notification stream; it does not replace, wrap, intercept or delay reset/WPS handlers.</div>
      </Panel>

      <Panel title="Live press/release events" eyebrow="PROCD UBUS · READ-ONLY OBSERVER" action={<Status active={hardware?.button_events?.monitor_available === true}>{hardware?.button_events?.monitor_available ? "MONITORING" : "WAITING"}</Status>}>
        <div className="hardware-button-status">
          <div><span>Event listener</span><Status active={hardware?.button_events?.monitor_available === true}>{hardware?.button_events?.monitor_available ? "CONNECTED" : "NOT CONNECTED"}</Status></div>
          <div><span>Captured since boot</span><strong>{fmt(hardware?.button_events?.count ?? 0)}</strong></div>
        </div>
        {!hardware?.button_events?.monitor_available ? (
          <div className="module-message">The read-only event observer is not connected yet. Confirm the QuantumGrid button-event service is enabled and procd exposes hotplug.button.</div>
        ) : (hardware.button_events.events ?? []).length === 0 ? (
          <div className="module-message">The observer is connected, but no button press/release events have been captured since boot. A button event is shown only when the kernel button driver reports it.</div>
        ) : (
          <div className="hardware-button-event-list">
            {hardware.button_events.events.slice().reverse().slice(0, 20).map((event) => (
              <div className="hardware-button-event-row" key={event.sequence + "-" + event.button + "-" + event.action}>
                <div>
                  <strong>{event.button}</strong>
                  <span>{event.action.toUpperCase()} · {event.type.toUpperCase()} · SEQ {event.sequence}</span>
                </div>
                <div>
                  <strong>{event.action === "released" ? "Held " + event.seen_seconds + " s" : "Press started"}</strong>
                  <span>{new Date(event.timestamp * 1000).toLocaleString()}</span>
                </div>
              </div>
            ))}
          </div>
        )}
        {(hardware?.button_events?.count ?? 0) >= 64 && <div className="module-message">The on-router event ring keeps the most recent 64 records; older events roll off automatically.</div>}
        <div className="module-message">Events are copied from procd's ubus notification payload into a bounded local ring. SEEN is the duration reported by the kernel between state transitions; release events normally carry the hold duration. QuantumGrid never opens /dev/input/event* or changes /etc/rc.button.</div>
      </Panel>

      <Panel title="Linux input devices" eyebrow="READ-ONLY · /PROC/BUS/INPUT/DEVICES">
        {!hardware?.input_devices?.available ? (
          <div className="module-message">The kernel input-device inventory is unavailable on this firmware.</div>
        ) : inputDevices.length === 0 ? (
          <div className="module-message">No Linux input devices were reported.</div>
        ) : (
          <div className="hardware-input-list">
            {inputDevices.map((device) => (
              <div className="hardware-input-row" key={device.name}>
                <div><strong>{device.name}</strong><span>{device.bus ? `Bus ${device.bus}` : "Bus type unavailable"}</span></div>
                <div><small>HANDLERS</small><span>{device.handlers.join(" · ") || "None reported"}</span></div>
                <div><small>EVENT NODES</small><span>{device.event_nodes.join(", ") || "None reported"}</span></div>
                <Status active={device.button_like}>{device.button_like ? "BUTTON-LIKE NAME" : "INPUT DEVICE"}</Status>
              </div>
            ))}
          </div>
        )}
        {hardware?.input_devices?.truncated && <div className="module-message">The input inventory is capped at 32 devices.</div>}
        <div className="module-message">Event node names are discovered from the kernel inventory only. QuantumGrid does not open /dev/input/event* or consume press/release events; native procd button actions remain untouched.</div>
      </Panel>

      <Panel title="LED class devices" eyebrow="KERNEL LED CLASS · BOUNDED RUNTIME CONTROL">
        {!hardware?.leds_available ? (
          <div className="module-message">The kernel LED class directory is unavailable. No LED controls are exposed.</div>
        ) : leds.length === 0 ? (
          <div className="module-message">No LED class devices were found under /sys/class/leds.</div>
        ) : (
          <div className="hardware-led-grid">
            {leds.map((led) => {
              const value = getBrightness(led.name, led.brightness);
              const max = led.max_brightness ?? 0;
              const changed = led.brightness !== undefined && value !== led.brightness;
              return (
                <section className="hardware-led-card" key={led.name}>
                  <div className="hardware-led-heading">
                    <div><strong>{led.name}</strong><span>{led.trigger_available ? `Trigger: ${led.trigger}` : "Trigger state unavailable"}</span></div>
                    <Status active={led.controllable}>{led.controllable ? "MANUAL" : "LOCKED"}</Status>
                  </div>
                  <div className="hardware-led-values">
                    <strong>{led.brightness === undefined ? "N/A" : fmt(led.brightness)}</strong>
                    <span>/ {max > 0 ? fmt(max) : "N/A"} max</span>
                  </div>
                  <label className="hardware-led-slider">
                    <span>Brightness</span>
                    <input
                      type="range"
                      min={0}
                      max={Math.max(1, max)}
                      step={1}
                      value={Math.max(0, Math.min(value, Math.max(1, max)))}
                      disabled={!led.controllable || savingLed !== null}
                      onChange={(event) => setBrightnessValues((previous) => ({ ...previous, [led.name]: Number(event.target.value) }))}
                      aria-label={`Brightness for ${led.name}`}
                    />
                  </label>
                  <div className="hardware-led-actions">
                    <small>{led.controllable ? "Manual control available while trigger is none." : led.trigger_available ? "Kernel trigger owns this LED, or brightness metadata is unavailable." : "Manual control is disabled until trigger state is readable."}</small>
                    <button className="hero-button" onClick={() => { void applyLed(led); }} disabled={!led.controllable || !changed || savingLed !== null}>
                      {savingLed === led.name ? "Applying…" : "Apply brightness"}
                    </button>
                  </div>
                </section>
              );
            })}
          </div>
        )}
        <div className="module-message">LED brightness writes are authenticated, limited to discovered LED-class devices and verified after writing. Devices with an active kernel trigger are locked to avoid fighting the trigger owner. Changes are runtime-only and may reset after reboot or when a trigger is re-enabled.</div>
      </Panel>

      <Panel title="Hardware safety boundary" eyebrow="AW1000 PIN-MAP VALIDATION">
        <div className="hardware-safety-grid">
          <div><strong>GPIO input</strong><Status active={gpio?.available === true}>READ-ONLY</Status><span>GPIO line ownership, direction and level are reported only when the kernel debugfs interface exposes them.</span></div>
          <div><strong>Button events</strong><Status active={hardware?.button_events?.monitor_available === true}>READ-ONLY UBUS</Status><span>Recent procd press/release notifications are recorded locally; native handlers remain untouched.</span></div>
          <div><strong>GPIO outputs</strong><Status active={false}>LOCKED</Status><span>No direct pin writes without a verified AW1000 pin map, ownership checks and recovery-safe policy.</span></div>
          <div><strong>LED class</strong><Status active={leds.some((led) => led.controllable)}>BOUNDED CONTROL</Status><span>Only kernel-exported LED devices with a confirmed none trigger can be adjusted.</span></div>
        </div>
      </Panel>
    </div>
  );
}


function AdvancedControlPage({ routerOverview, refresh }: {
  routerOverview: RouterOverview | null;
  refresh: () => void;
}) {
  const platform = routerOverview?.platform;
  const conntrack = routerOverview?.conntrack;
  const system = routerOverview?.system;
  const memory = system?.memory;
  const load = system?.load_avg ?? [];
  const modules = platform?.modules ?? [];
  const kernelModuleInventory = platform?.kernel_modules;
  const [kernelModuleQuery, setKernelModuleQuery] = useState("");
  const [kernelModuleState, setKernelModuleState] = useState<"all" | "loaded" | "installed">("all");
  const visibleKernelModules = (kernelModuleInventory?.modules ?? []).filter((item) => {
    const query = kernelModuleQuery.trim().toLocaleLowerCase();
    const matchesQuery = !query || item.name.toLocaleLowerCase().includes(query) ||
      item.path.toLocaleLowerCase().includes(query);
    const matchesState = kernelModuleState === "all" ||
      (kernelModuleState === "loaded" ? item.loaded : !item.loaded);
    return matchesQuery && matchesState;
  });
  const tools = platform?.tools ?? [];
  const services = platform?.services ?? [];
  const acceleration = platform?.acceleration;
  const storage = platform?.storage ?? [];
  const [conntrackHistory, setConntrackHistory] = useState<ConntrackHistorySample[]>([]);
  useEffect(() => {
    if (!routerOverview) return;
    let active = true;
    const sample = routerOverview.conntrack;
    const sampledAt = routerOverview.timestamp;
    queueMicrotask(() => {
      if (!active) return;
      setConntrackHistory((previous) => appendConntrackSample(previous, sample, sampledAt));
    });
    return () => {
      active = false;
    };
  }, [routerOverview]);
  const conntrackSummary = summarizeConntrackHistory(conntrackHistory);
  const exportConntrackHistory = () => {
    if (conntrackHistory.length === 0) return;
    const exportedAt = new Date().toISOString();
    const rows: Array<Array<string | number>> = [
      ["Exported at (UTC)", "Sampled at (UTC)", "Current entries", "Configured maximum", "Free entries", "Utilization percent"],
      ...conntrackHistory.map((sample) => [
        exportedAt,
        new Date(sample.sampledAt * 1000).toISOString(),
        sample.count,
        sample.maximum,
        sample.free,
        sample.usedPercent,
      ]),
    ];
    const csv = rows.map((row) => row.map(csvCell).join(",")).join("\r\n");
    const objectUrl = URL.createObjectURL(new Blob(["\uFEFF", csv], { type: "text/csv;charset=utf-8" }));
    const link = document.createElement("a");
    link.href = objectUrl;
    link.download = "quantumgrid-conntrack-history-" + exportedAt.replace(/[:.]/g, "-") + ".csv";
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(objectUrl), 0);
  };
  const exportPlatformInventory = () => {
    if (!platform?.available) return;
    const generatedAt = new Date().toISOString();
    const runtimeRows: Array<Array<string | number | null | undefined>> = [
      [generatedAt, platform.hostname, "Runtime", "Uptime", system ? "REPORTED" : "UNAVAILABLE", "Since last boot", "", "", "", formatUptime(system?.uptime_seconds)],
      [generatedAt, platform.hostname, "Runtime", "CPU utilization", system?.cpu_percent == null ? "UNAVAILABLE" : "REPORTED", "Percent of total CPU time", "", "", system?.cpu_percent ?? "", system?.cpu_percent == null ? "" : fmt(system.cpu_percent, 1) + "%"],
      [generatedAt, platform.hostname, "Runtime", "Memory", memory ? "REPORTED" : "UNAVAILABLE", "MemTotal / MemAvailable from /proc/meminfo", memory ? memory.total_kib * 1024 : "", memory ? memory.available_kib * 1024 : "", memory?.used_percent ?? "", memory ? fmt(memory.total_kib / 1024, 0) + " MiB total" : ""],
      [generatedAt, platform.hostname, "Runtime", "Temperature", system?.temperature_c == null ? "UNAVAILABLE" : "REPORTED", "First available thermal zone", "", "", "", system?.temperature_c == null ? "" : fmt(system.temperature_c, 1) + " °C"],
      [generatedAt, platform.hostname, "Runtime", "Load average (1m)", load[0] === undefined ? "UNAVAILABLE" : "REPORTED", "Linux /proc/loadavg", "", "", "", load[0] === undefined ? "" : fmt(load[0], 2)],
      [generatedAt, platform.hostname, "Runtime", "Load average (5m)", load[1] === undefined ? "UNAVAILABLE" : "REPORTED", "Linux /proc/loadavg", "", "", "", load[1] === undefined ? "" : fmt(load[1], 2)],
      [generatedAt, platform.hostname, "Runtime", "Load average (15m)", load[2] === undefined ? "UNAVAILABLE" : "REPORTED", "Linux /proc/loadavg", "", "", "", load[2] === undefined ? "" : fmt(load[2], 2)],
    ];
    const rows: Array<Array<string | number | null | undefined>> = [
      ["Generated at (UTC)", "Hostname", "Section", "Item", "Status", "Detail", "Total bytes", "Available bytes", "Used percent", "Value"],
      [generatedAt, platform.hostname, "Platform", "Firmware identity", "AVAILABLE",
        [platform.model, platform.board_name, platform.distribution, platform.version, platform.revision,
          platform.target, platform.kernel, platform.description].filter(Boolean).join(" | "), "", "", "", ""],
      [generatedAt, platform.hostname, "Package manager", platform.package_manager, "DETECTED", "", "", "", "", ""],
      ...runtimeRows,
      [generatedAt, platform.hostname, "Kernel networking", "Connection tracking", conntrack?.available ? (conntrack.status?.toUpperCase() ?? "UNKNOWN") : "UNAVAILABLE", "Read-only nf_conntrack_count / nf_conntrack_max; warning at 75%, critical at 90%", "", "", conntrack?.used_percent ?? "", conntrack?.available ? `${conntrack.count?.toLocaleString() ?? "N/A"} / ${conntrack.maximum?.toLocaleString() ?? "N/A"} entries; ${conntrack.free?.toLocaleString() ?? "N/A"} free` : ""],
      ...modules.map((item) => [generatedAt, platform.hostname, "Kernel module", item.name, item.loaded ? "LOADED" : "NOT LOADED", "", "", "", "", ""]),
      ...(kernelModuleInventory?.modules ?? []).map((item) => [generatedAt, platform.hostname, "Installed kernel module", item.name, item.loaded ? "LOADED" : "INSTALLED / NOT LOADED", item.path, "", "", "", ""]),
      ...(acceleration?.components ?? []).map((item) => [generatedAt, platform.hostname, "Acceleration component", item.name, item.present ? "PRESENT" : "MISSING", item.kind + " · " + item.detail, "", "", "", ""]),
      ...(acceleration ? [[generatedAt, platform.hostname, "Acceleration summary", "NSS / EDMA / PPE", acceleration.status.toUpperCase(), acceleration.note, "", "", "", acceleration.offload_verified ? "VERIFIED" : "UNVERIFIED"]] : []),
      ...tools.map((item) => [generatedAt, platform.hostname, "Diagnostic tool", item.name, item.available ? "AVAILABLE" : "MISSING", "", "", "", "", ""]),
      ...services.map((item) => [generatedAt, platform.hostname, "Init script", item.name, item.installed ? "PRESENT" : "MISSING", "Presence is not runtime health", "", "", "", ""]),
      ...storage.map((item) => [generatedAt, platform.hostname, "MTD partition", item.device, item.name, "erase block " + item.erase_size_bytes + " bytes", item.size_bytes, "", "", ""]),
      ...(platform.block_devices ?? []).map((item) => [generatedAt, platform.hostname, "Block device", item.name, "REPORTED", "major:minor " + item.major + ":" + item.minor, item.size_bytes, "", "", ""]),
      ...(platform.mounts ?? []).map((item) => [generatedAt, platform.hostname, "Mount", item.mountpoint, item.read_only ? "READ ONLY" : "READ / WRITE", item.source + " · " + item.filesystem, item.total_bytes, item.available_bytes, item.used_percent, ""]),
    ];
    const csv = rows.map((row) => row.map(csvCell).join(",")).join("\r\n");
    const objectUrl = URL.createObjectURL(new Blob(["\uFEFF", csv], { type: "text/csv;charset=utf-8" }));
    const link = document.createElement("a");
    link.href = objectUrl;
    link.download = "quantumgrid-platform-inventory-" + generatedAt.replace(/[:.]/g, "-") + ".csv";
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(objectUrl), 0);
  };
  return (
    <div className="module-page">
      <section className="module-hero">
        <div className="module-icon"><Settings size={25} /></div>
        <div>
          <div className="setup-kicker">READ-ONLY PLATFORM INVENTORY</div>
          <h1>Advanced</h1>
          <p>Firmware identity, target platform, loaded kernel modules, installed service scripts, diagnostic tools and flash partitions reported by the running router.</p>
          <div className="platform-actions">
            <button className="hero-button" onClick={refresh}><RefreshCw size={16} /> Refresh platform inventory</button>
            <button className="hero-button" onClick={exportPlatformInventory} disabled={!platform?.available}>Export inventory CSV</button>
          </div>
        </div>
      </section>
      {!platform?.available ? (
        <div className="module-message">Waiting for the authenticated system.board response. No platform identity is inferred from the device name.</div>
      ) : (
        <>
          <div className="metrics">
            <Metric title="Hardware Model" value={platform.model || "N/A"} unit="" detail={platform.board_name || "Board identifier unavailable"} icon={Router} />
            <Metric title="OpenWrt Release" value={platform.version || "N/A"} unit="" detail={platform.distribution || "Distribution unavailable"} icon={HardDrive} />
            <Metric title="Kernel" value={platform.kernel || "N/A"} unit="" detail={platform.target || "Build target unavailable"} icon={Cpu} />
            <Metric title="Package Manager" value={platform.package_manager} unit="" detail="Detected executable on router" icon={Settings} />
          </div>
          <Panel title="Firmware and board identity" eyebrow="UBUS · SYSTEM.BOARD">
            <div className="platform-detail-grid">
              <div><small>HOSTNAME</small><strong>{platform.hostname || "N/A"}</strong></div>
              <div><small>BOARD NAME</small><strong>{platform.board_name || "N/A"}</strong></div>
              <div><small>SYSTEM</small><strong>{platform.system || "N/A"}</strong></div>
              <div><small>RELEASE VERSION</small><strong>{platform.version || "N/A"}</strong></div>
              <div><small>REVISION</small><strong>{platform.revision || "N/A"}</strong></div>
              <div><small>TARGET</small><strong>{platform.target || "N/A"}</strong></div>
              <div className="platform-detail-wide"><small>BUILD DESCRIPTION</small><strong>{platform.description || "N/A"}</strong></div>
            </div>
          </Panel>
          <Panel title="Runtime health snapshot" eyebrow="READ-ONLY · LIVE SYSTEM TELEMETRY">
            <div className="platform-detail-grid">
              <div><small>UPTIME</small><strong>{formatUptime(system?.uptime_seconds)}</strong></div>
              <div><small>CPU UTILIZATION</small><strong>{system?.cpu_percent == null ? "N/A" : fmt(system.cpu_percent, 1) + "%"}</strong></div>
              <div><small>MEMORY UTILIZATION</small><strong>{memory?.used_percent == null ? "N/A" : fmt(memory.used_percent, 1) + "%"}</strong></div>
              <div><small>TEMPERATURE</small><strong>{system?.temperature_c == null ? "N/A" : fmt(system.temperature_c, 1) + " °C"}</strong></div>
              <div className="platform-detail-wide"><small>LOAD AVERAGE · 1 / 5 / 15 MIN</small><strong>{load.length === 0 ? "N/A" : load.slice(0, 3).map((value) => fmt(value, 2)).join(" / ")}</strong></div>
            </div>
            <div className="module-message">Values come from the authenticated router telemetry sample. Unavailable CPU or thermal readings stay marked N/A; this panel does not estimate missing values.</div>
          </Panel>
          <Panel title="NSS / EDMA / PPE readiness" eyebrow="DEVICE TREE · KERNEL MODULES · FIRMWARE">
            {acceleration ? (
              <>
                <div className="acceleration-summary">
                  <div>
                    <small>NSS COMPONENT STATUS</small>
                    <strong>{acceleration.status === "components-present-unverified" ? "COMPONENTS PRESENT" : acceleration.status === "partial" ? "PARTIAL" : "NOT DETECTED"}</strong>
                  </div>
                  <div>
                    <small>REPORTED COMPONENTS</small>
                    <strong>{fmt(acceleration.present_components)} / {fmt(acceleration.required_components)}</strong>
                  </div>
                  <div>
                    <small>END-TO-END OFFLOAD</small>
                    <strong>NOT VERIFIED</strong>
                  </div>
                </div>
                <div className="platform-check-list acceleration-components">
                  {acceleration.components.map((component) => (
                    <div className="platform-check-row" key={component.name}>
                      <div className="acceleration-component-copy">
                        <span>{component.name}</span>
                        <small>{component.kind.toUpperCase()} · {component.detail}</small>
                      </div>
                      <Status active={component.present}>{component.present ? "PRESENT" : "MISSING"}</Status>
                    </div>
                  ))}
                </div>
                <div className="module-message">{acceleration.note}</div>
              </>
            ) : (
              <div className="module-message">Waiting for read-only NSS, EDMA and PPE component inventory.</div>
            )}
          </Panel>
          <Panel title="Connection tracking capacity" eyebrow="READ-ONLY · NETFILTER KERNEL COUNTERS">
            {conntrack?.available ? (
              <>
                <InfoRows rows={[
                  ["CURRENT ENTRIES", conntrack.count?.toLocaleString() ?? "N/A"],
                  ["CONFIGURED MAXIMUM", conntrack.maximum?.toLocaleString() ?? "N/A"],
                  ["FREE ENTRIES", conntrack.free?.toLocaleString() ?? "N/A"],
                  ["TABLE UTILIZATION", conntrack.used_percent == null ? "N/A" : fmt(conntrack.used_percent, 1) + "%"],
                  ["CAPACITY STATE", conntrack.status?.toUpperCase() ?? "UNKNOWN"],
                ]} />
                <div className="module-message">Warning begins at 75% and critical at 90% of the configured table maximum. This is a capacity indicator, not proof of dropped traffic; the view is read-only and does not change kernel limits.</div>
              </>
            ) : (
              <div className="module-message">Kernel connection-tracking counters are unavailable on this build or are not exposed by the running kernel. QuantumGrid leaves the reading unavailable instead of assuming the table is empty.</div>
            )}
          </Panel>
          <Panel
            title="Connection tracking history"
            eyebrow="LAST 30 VALID KERNEL SAMPLES · SESSION ONLY"
            action={
              <button className="hero-button wifi-export-button" onClick={exportConntrackHistory} disabled={conntrackHistory.length === 0}>
                Export history CSV
              </button>
            }
          >
            {conntrackHistory.length === 0 ? (
              <div className="module-message">Waiting for the first valid connection-tracking sample. History is kept in this page session only and is not stored in browser or router configuration.</div>
            ) : (
              <>
                <div className="conntrack-history-summary">
                  <div><small>SAMPLES</small><strong>{fmt(conntrackSummary?.samples ?? 0)}</strong></div>
                  <div><small>OBSERVED WINDOW</small><strong>{formatDurationSeconds(conntrackSummary?.durationSeconds)}</strong></div>
                  <div><small>ENTRY DELTA</small><strong>{conntrackSummary && conntrackSummary.entryDelta > 0 ? "+" : ""}{fmt(conntrackSummary?.entryDelta ?? 0)}</strong></div>
                  <div><small>UTILIZATION RANGE</small><strong>{conntrackSummary ? `${fmt(conntrackSummary.minimumUsedPercent, 1)}–${fmt(conntrackSummary.maximumUsedPercent, 1)}%` : "N/A"}</strong></div>
                </div>
                <div className="conntrack-history-chart" role="img" aria-label="Connection tracking table utilization over the last valid samples">
                  {conntrackHistory.map((sample, index) => {
                    const maxPercent = Math.max(100, conntrackSummary?.maximumUsedPercent ?? 100);
                    const height = Math.max(2, sample.usedPercent / maxPercent * 100);
                    return (
                      <div className="conntrack-history-point" key={sample.sampledAt + "-" + index} title={`${new Date(sample.sampledAt * 1000).toLocaleTimeString()} · ${fmt(sample.count)} / ${fmt(sample.maximum)} entries · ${fmt(sample.usedPercent, 1)}%`}>
                        <div className="conntrack-history-track">
                          <div className="conntrack-history-bar" style={{ height: `${height}%` }} />
                        </div>
                      </div>
                    );
                  })}
                </div>
                <div className="module-message">Each bar is one valid authenticated telemetry sample. The trend shows table occupancy, not dropped packets or connection quality. Samples replace duplicate timestamps, are capped at 30 and disappear when this page session ends.</div>
              </>
            )}
          </Panel>
          <Panel title="Installed kernel modules (kmods)" eyebrow={kernelModuleInventory?.available ? `MODULES.DEP · ${kernelModuleInventory.count.toLocaleString()} INSTALLED · ${kernelModuleInventory.loaded_count.toLocaleString()} LOADED` : "MODULES.DEP UNAVAILABLE · /PROC/MODULES FALLBACK"}>
            <div className="kernel-module-toolbar">
              <input
                type="search"
                value={kernelModuleQuery}
                onChange={(event) => setKernelModuleQuery(event.target.value)}
                placeholder="Search module name or .ko path"
                aria-label="Search installed kernel modules"
              />
              <div className="kernel-module-filter">
                {(["all", "loaded", "installed"] as const).map((state) => (
                  <button
                    key={state}
                    className={kernelModuleState === state ? "active" : ""}
                    onClick={() => setKernelModuleState(state)}
                  >
                    {state === "all" ? "All" : state === "loaded" ? "Loaded" : "Not loaded"}
                  </button>
                ))}
              </div>
              <span>{visibleKernelModules.length.toLocaleString()} shown</span>
            </div>
            {!kernelModuleInventory ? (
              <div className="module-message">Waiting for the running kernel module inventory.</div>
            ) : visibleKernelModules.length === 0 ? (
              <div className="module-message">No kernel modules match this filter.</div>
            ) : (
              <div className="kernel-module-list">
                {visibleKernelModules.slice(0, 400).map((item) => (
                  <div className="kernel-module-row" key={item.name}>
                    <div>
                      <strong>{item.name}</strong>
                      <small>{item.path || "Runtime-loaded module not found in modules.dep"}</small>
                    </div>
                    <Status active={item.loaded}>{item.loaded ? "LOADED" : "ON DISK"}</Status>
                  </div>
                ))}
              </div>
            )}
            {kernelModuleInventory?.truncated ? <div className="module-message">The inventory contains {kernelModuleInventory.count.toLocaleString()} module entries; the API result is capped at 2,000. The browser displays at most 400 rows at once.</div> : null}
            <div className="module-message">Installed module paths come from the running kernel's modules.dep; loaded state comes from /proc/modules. Out-of-tree modules can appear as runtime-only entries. This is an inventory, not a safe live module-load/unload interface.</div>
          </Panel>
          <div className="module-grid">
            <Panel title="Key platform drivers" eyebrow="SYSFS · SELECTED /SYS/MODULE CHECKS">
              {modules.length === 0 ? <div className="module-message">No module inventory was returned.</div> : (
                <div className="platform-check-list">
                  {modules.map((module) => <div className="platform-check-row" key={module.name}><span>{module.name}</span><Status active={module.loaded}>{module.loaded ? "LOADED" : "NOT LOADED"}</Status></div>)}
                </div>
              )}
            </Panel>
            <Panel title="Router diagnostic tools" eyebrow="EXECUTABLE PRESENCE">
              {tools.length === 0 ? <div className="module-message">No tool inventory was returned.</div> : (
                <div className="platform-check-list">
                  {tools.map((tool) => <div className="platform-check-row" key={tool.name}><span>{tool.name}</span><Status active={tool.available}>{tool.available ? "AVAILABLE" : "MISSING"}</Status></div>)}
                </div>
              )}
            </Panel>
          </div>
          <Panel title="Service integration inventory" eyebrow="INIT SCRIPT PRESENCE">
            <div className="platform-check-list">
              {services.map((service) => <div className="platform-check-row" key={service.name}><span>{service.name}</span><Status active={service.installed}>{service.installed ? "INSTALLED" : "NOT INSTALLED"}</Status></div>)}
            </div>
            <div className="module-message">Presence means the init script exists; it does not mean the service is enabled, running, healthy or configured.</div>
          </Panel>
          <Panel title="Flash partition inventory" eyebrow="READ-ONLY · /PROC/MTD">
            {storage.length === 0 ? (
              <div className="module-message">This device did not expose MTD partitions through /proc/mtd. eMMC/UFS and overlay space are listed separately through block-device and mount telemetry when the kernel reports them.</div>
            ) : (
              <div className="device-list">
                {storage.map((partition) => <div className="device-row platform-storage-row" key={partition.device}>
                  <div className="device-title"><div className="device-icon"><HardDrive size={17} /></div><div><strong>{partition.name}</strong><span>{partition.device}</span></div></div>
                  <div><small>CAPACITY</small><b>{fmt(partition.size_bytes / 1048576, 2)} MiB</b></div>
                  <div><small>ERASE BLOCK</small><b>{fmt(partition.erase_size_bytes / 1024, 0)} KiB</b></div>
                </div>)}
              </div>
            )}
          </Panel>
          <div className="module-grid">
            <Panel title="Block device inventory" eyebrow="READ-ONLY · /PROC/PARTITIONS">
              {(platform.block_devices ?? []).length === 0 ? (
                <div className="module-message">No block devices were reported by /proc/partitions.</div>
              ) : (
                <div className="device-list">
                  {platform.block_devices.map((device) => (
                    <div className="device-row platform-storage-row" key={device.name}>
                      <div className="device-title"><div className="device-icon"><HardDrive size={17} /></div><div><strong>{device.name}</strong><span>{device.major}:{device.minor}</span></div></div>
                      <div><small>CAPACITY</small><b>{fmt(device.size_bytes / 1073741824, 2)} GiB</b></div>
                      <div><small>DEVICE</small><b>/dev/{device.name}</b></div>
                    </div>
                  ))}
                </div>
              )}
            </Panel>
            <Panel title="Mounted system filesystems" eyebrow="READ-ONLY · /PROC/MOUNTS">
              {(platform.mounts ?? []).length === 0 ? (
                <div className="module-message">No root, overlay, ROM, temporary or /mnt mounts were reported.</div>
              ) : (
                <div className="platform-check-list">
                  {platform.mounts.map((mount) => (
                    <div className="platform-mount-row" key={mount.mountpoint + "-" + mount.source}>
                      <div className="platform-mount-identity"><strong>{mount.mountpoint}</strong><span>{mount.source} · {mount.filesystem}</span></div>
                      <div className="platform-mount-capacity">
                        <span>{mount.total_bytes === undefined ? "Capacity N/A" : `${fmt(mount.total_bytes / 1073741824, 2)} GiB total`}</span>
                        <span>{mount.available_bytes === undefined ? "Available N/A" : `${fmt(mount.available_bytes / 1073741824, 2)} GiB available`}</span>
                        <span>{mount.used_percent === undefined ? "Usage N/A" : `${fmt(mount.used_percent, 1)}% used`}</span>
                      </div>
                      <Status active={!mount.read_only}>{mount.read_only ? "READ ONLY" : "READ / WRITE"}</Status>
                    </div>
                  ))}
                </div>
              )}
            </Panel>
          </div>
        </>
      )}
      <div className="module-message">This page is read-only. It does not install packages, load/unload modules, change service state or write firmware. Export quotes values and neutralises spreadsheet formula prefixes. Module and service presence are reported separately from operational status.</div>
    </div>
  );
}

function GenericModulePage({
  title,
  eyebrow,
  Icon,
}: {
  title: string;
  eyebrow: string;
  Icon: React.ElementType;
}) {
  return (
    <div className="module-page">
      <section className="module-hero">
        <div className="module-icon"><Icon size={25} /></div>
        <div>
          <div className="setup-kicker">{eyebrow.toUpperCase()}</div>
          <h1>{title}</h1>
          <p>This module is not connected to an authenticated router service yet. QuantumGrid will not display simulated readings or apply local-only settings here.</p>
        </div>
      </section>
      <Panel title="Service integration" eyebrow="NOT YET CONNECTED">
        <Status active={false}>INTEGRATION PENDING</Status>
        <div className="module-message">Controls remain unavailable until the router-side API, capability checks, validation and recovery behaviour are implemented and tested.</div>
      </Panel>
    </div>
  );
}

function Panel({
  title,
  eyebrow,
  action,
  children,
}: {
  title: string;
  eyebrow?: string;
  action?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <section className="panel">
      <div className="panel-header">
        <div>
          {eyebrow && <div className="panel-eyebrow">{eyebrow}</div>}
          <h2>{title}</h2>
        </div>
        {action}
      </div>
      {children}
    </section>
  );
}

function Metric({
  title,
  value,
  unit,
  detail,
  icon: Icon,
}: {
  title: string;
  value: string;
  unit: string;
  detail: string;
  icon: React.ElementType;
}) {
  return (
    <div className="metric">
      <div className="metric-icon">
        <Icon size={18} />
      </div>
      <div>
        <span>{title}</span>
        <strong>{value}<small>{unit}</small></strong>
        <em>{detail}</em>
      </div>
    </div>
  );
}

function Health({
  icon: Icon,
  label,
  value,
}: {
  icon: React.ElementType;
  label: string;
  value: string;
}) {
  return (
    <div className="health">
      <Icon size={16} />
      <span>{label}</span>
      <b>{value}</b>
    </div>
  );
}

function InfoRows({ rows }: { rows: string[][] }) {
  return (
    <div className="info-rows">
      {rows.map(([name, value]) => (
        <div key={name}>
          <span>{name}</span>
          <Status>{value}</Status>
        </div>
      ))}
    </div>
  );
}

function App() {
  const forceFirstBoot =
    new URLSearchParams(window.location.search).get("firstboot") === "1";

  const [setupComplete, setSetupComplete] = useState(
    () =>
      !forceFirstBoot &&
      localStorage.getItem("quantumgrid-setup-complete") === "1",
  );

  const [setupStep, setSetupStep] = useState<SetupStep>("welcome");

  // OpenWrt's built-in administrator account is root; the password is never stored locally.
  const [username, setUsername] = useState("root");

  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [wifiPassword, setWifiPassword] = useState("");
  const [ssid, setSsid] = useState("QuantumGrid");
  const [wanType, setWanType] = useState<"dhcp" | "pppoe" | "static">("dhcp");

  const [loggedIn, setLoggedIn] = useState(false);
  const [loginPassword, setLoginPassword] = useState("");
  const [loginError, setLoginError] = useState("");

  const [page, setPage] = useState<Page>("dashboard");
  const [collapsed, setCollapsed] = useState(false);
  const [secondsUntilRefresh, setSecondsUntilRefresh] = useState(3);

  const [stats, setStats] = useState<Stats>({
    latency: null,
    probeDelta: null,
    download: 0,
    upload: 0,
    wanAvailable: false,
    reachable: false,
    cpu: null,
    ram: null,
    temp: null,
  });
  const [telemetryError, setTelemetryError] = useState("");
  const [routerOverview, setRouterOverview] = useState<RouterOverview | null>(null);
  const previousInterfaceCounters = useRef(new Map<string, InterfaceCounterSnapshot>());
  const [interfaceCounterDeltas, setInterfaceCounterDeltas] = useState<Map<string, InterfaceCounterDelta>>(new Map());
  const previousWireGuardPeerCounters = useRef(new Map<string, WireGuardPeerCounterSnapshot>());
  const [wireGuardPeerRates, setWireGuardPeerRates] = useState<Map<string, WireGuardPeerMeasuredRate>>(new Map());
  const previousWirelessCounters = useRef(new Map<string, { rx: number; tx: number; sampledAt: number }>());
  const [trafficHistory, setTrafficHistory] = useState<number[]>(() => Array(30).fill(0));
  const [cellularHistory, setCellularHistory] = useState<CellularHistorySample[]>([]);
  const previousNetworkSample = useRef<{
    device: string;
    rx: number;
    tx: number;
    sampledAt: number;
    latency: number | null;
  } | null>(null);

  const refresh = useCallback(async () => {
    try {
      const overview = await fetchRouterOverview();
      const now = Date.now();
      const nextInterfaceCounters = new Map<string, InterfaceCounterSnapshot>();
      const nextInterfaceDeltas = new Map<string, InterfaceCounterDelta>();
      const counterDelta = (current: number | undefined, previous: number | undefined) =>
        current === undefined || previous === undefined || current < previous ? null : current - previous;
      for (const item of overview.interfaces) {
        const previousCounters = previousInterfaceCounters.current.get(item.name);
        if (previousCounters) {
          const sampleSeconds = (now - previousCounters.sampledAt) / 1000;
          const validSampleInterval = Number.isFinite(sampleSeconds) && sampleSeconds > 0 && sampleSeconds <= 60;
          nextInterfaceDeltas.set(item.name, {
            rxErrors: counterDelta(item.rx_errors, previousCounters.rx_errors),
            txErrors: counterDelta(item.tx_errors, previousCounters.tx_errors),
            rxDropped: counterDelta(item.rx_dropped, previousCounters.rx_dropped),
            txDropped: counterDelta(item.tx_dropped, previousCounters.tx_dropped),
            rxMbps: calculateCounterRateMbps(item.rx_bytes, previousCounters.rx_bytes, sampleSeconds),
            txMbps: calculateCounterRateMbps(item.tx_bytes, previousCounters.tx_bytes, sampleSeconds),
            sampleSeconds: validSampleInterval ? sampleSeconds : null,
          });
        }
        nextInterfaceCounters.set(item.name, {
          rx_bytes: item.rx_bytes,
          tx_bytes: item.tx_bytes,
          rx_errors: item.rx_errors,
          tx_errors: item.tx_errors,
          rx_dropped: item.rx_dropped,
          tx_dropped: item.tx_dropped,
          sampledAt: now,
        });
      }
      previousInterfaceCounters.current = nextInterfaceCounters;
      setInterfaceCounterDeltas(nextInterfaceDeltas);
      const wireGuardSamples = sampleWireGuardPeerRates(
        overview.security?.vpn.wireguard_peers ?? [],
        previousWireGuardPeerCounters.current,
        now,
      );
      previousWireGuardPeerCounters.current = wireGuardSamples.nextCounters;
      setWireGuardPeerRates(wireGuardSamples.rates);
      const wan =
        overview.interfaces.find((item) => item.name === "wan" && item.up) ??
        overview.interfaces.find((item) => item.is_wan && item.up) ??
        overview.interfaces.find((item) => item.up);
      const previous = previousNetworkSample.current;
      const previousWireless = previousWirelessCounters.current;
      const nextWireless = new Map<string, { rx: number; tx: number; sampledAt: number }>();
      const wirelessRates: Record<string, WirelessTrafficSample> = {};
      for (const client of overview.wireless_clients ?? []) {
        const key = client.ifname + "-" + client.mac.toLowerCase();
        const rx = client.rx_bytes;
        const tx = client.tx_bytes;
        if (rx === undefined || tx === undefined || !Number.isFinite(rx) || !Number.isFinite(tx) || rx < 0 || tx < 0) continue;
        const prior = previousWireless.get(key);
        if (prior && now > prior.sampledAt && rx >= prior.rx && tx >= prior.tx) {
          const seconds = (now - prior.sampledAt) / 1000;
          wirelessRates[key] = {
            rx_mbps: ((rx - prior.rx) * 8) / seconds / 1_000_000,
            tx_mbps: ((tx - prior.tx) * 8) / seconds / 1_000_000,
          };
        }
        nextWireless.set(key, { rx, tx, sampledAt: now });
      }
      previousWirelessCounters.current = nextWireless;
      const wirelessClientsWithRates = overview.wireless_clients?.map((client) => {
        const key = client.ifname + "-" + client.mac.toLowerCase();
        const rate = wirelessRates[key];
        return {
          ...client,
          measured_rx_mbps: rate?.rx_mbps,
          measured_tx_mbps: rate?.tx_mbps,
        };
      });
      let download = 0;
      let upload = 0;
      let probeDelta: number | null = null;

      if (wan && previous && previous.device === wan.device) {
        const elapsedSeconds = Math.max(0.001, (now - previous.sampledAt) / 1000);
        download = Math.max(0, ((wan.rx_bytes - previous.rx) * 8) / elapsedSeconds / 1_000_000);
        upload = Math.max(0, ((wan.tx_bytes - previous.tx) * 8) / elapsedSeconds / 1_000_000);
        if (previous.latency !== null && overview.system.ping_ms !== null) {
          probeDelta = Math.abs(overview.system.ping_ms - previous.latency);
        }
      }

      previousNetworkSample.current = wan
        ? {
            device: wan.device,
            rx: wan.rx_bytes,
            tx: wan.tx_bytes,
            sampledAt: now,
            latency: overview.system.ping_ms,
          }
        : null;

      setStats({
        latency: overview.system.ping_ms,
        probeDelta,
        download,
        upload,
        wanAvailable: Boolean(wan),
        reachable: overview.system.ping_ok,
        cpu: overview.system.cpu_percent,
        ram: overview.system.memory.used_percent,
        temp: overview.system.temperature_c,
      });
      setRouterOverview({ ...overview, wireless_clients: wirelessClientsWithRates });
      setTrafficHistory((history) => [...history.slice(1), wan ? download + upload : 0]);

      const cellular = overview.cellular;
      if (!cellular.qmi_available) {
        setCellularHistory([]);
      } else if (Number.isFinite(cellular.sampled_at)) {
        const sample: CellularHistorySample = {
          sampledAt: cellular.sampled_at,
          rssi_dbm: typeof cellular.rssi_dbm === "number" && Number.isFinite(cellular.rssi_dbm) ? cellular.rssi_dbm : null,
          rsrp_dbm: typeof cellular.rsrp_dbm === "number" && Number.isFinite(cellular.rsrp_dbm) ? cellular.rsrp_dbm : null,
          rsrq_db: typeof cellular.rsrq_db === "number" && Number.isFinite(cellular.rsrq_db) ? cellular.rsrq_db : null,
          snr_db: typeof cellular.snr_db === "number" && Number.isFinite(cellular.snr_db) ? cellular.snr_db : null,
        };
        if ([sample.rssi_dbm, sample.rsrp_dbm, sample.rsrq_db, sample.snr_db].some((value) => value !== null)) {
          setCellularHistory((history) => {
            const latest = history[history.length - 1];
            if (latest && latest.sampledAt >= sample.sampledAt) return history;
            return [...history.slice(-29), sample];
          });
        }
      }
      setTelemetryError("");
    } catch (error) {
      setTelemetryError(error instanceof Error ? error.message : "Router telemetry is unavailable.");
    } finally {
      setSecondsUntilRefresh(3);
    }
  }, []);

  useEffect(() => {
    if (!setupComplete || !loggedIn) return;

    const initialRefresh = window.setTimeout(() => {
      void refresh();
    }, 0);
    const refreshTimer = window.setInterval(() => {
      void refresh();
    }, 3000);

    const countdownTimer = window.setInterval(() => {
      setSecondsUntilRefresh((value) => (value <= 1 ? 3 : value - 1));
    }, 1000);

    return () => {
      window.clearTimeout(initialRefresh);
      window.clearInterval(refreshTimer);
      window.clearInterval(countdownTimer);
    };
  }, [setupComplete, loggedIn, refresh]);

  function finishSetup() {
    localStorage.setItem("quantumgrid-setup-complete", "1");
    localStorage.setItem("quantumgrid-username", username);
    localStorage.setItem("quantumgrid-wifi-ssid", ssid);
    localStorage.setItem("quantumgrid-wan-type", wanType);

    setLoginPassword(password);
    setSetupComplete(true);
    setSetupStep("welcome");
  }

  function logout() {
    void fetch("/cgi-bin/luci/admin/logout", {
      credentials: "same-origin",
      cache: "no-store",
    }).finally(() => {
      setLoggedIn(false);
      setCellularHistory([]);
      previousInterfaceCounters.current.clear();
      setInterfaceCounterDeltas(new Map());
      previousWirelessCounters.current.clear();
      setLoginPassword("");
      setLoginError("");
      setPage("dashboard");
      setCollapsed(false);
    });
  }

  async function login() {
    const saved = localStorage.getItem("quantumgrid-username") || "root";
    try {
      await loginToRouter(saved, loginPassword);
      setSecondsUntilRefresh(3);
      setLoginPassword("");
      setLoggedIn(true);
      setLoginError("");
    } catch (error) {
      setLoginError(error instanceof Error ? error.message : "Router sign-in failed.");
    }
  }

  if (!setupComplete) {
    if (setupStep === "welcome") {
      return <Welcome next={() => setSetupStep("account")} />;
    }

    if (setupStep === "account") {
      return (
        <AccountSetup
          username={username}
          setUsername={setUsername}
          password={password}
          setPassword={setPassword}
          confirm={confirm}
          setConfirm={setConfirm}
          next={() => setSetupStep("wifi")}
          back={() => setSetupStep("welcome")}
        />
      );
    }

    if (setupStep === "wifi") {
      return (
        <WifiSetup
          ssid={ssid}
          setSsid={setSsid}
          password={wifiPassword}
          setPassword={setWifiPassword}
          next={() => setSetupStep("wan")}
          back={() => setSetupStep("account")}
        />
      );
    }

    return (
      <WanSetup
        type={wanType}
        setType={setWanType}
        next={finishSetup}
        back={() => setSetupStep("wifi")}
      />
    );
  }

  if (!loggedIn) {
    return (
      <Login
        username={localStorage.getItem("quantumgrid-username") || "root"}
        password={loginPassword}
        setPassword={setLoginPassword}
        login={login}
        error={loginError}
        clearError={() => setLoginError("")}
      />
    );
  }

  return (
    <Dashboard
      stats={stats}
      refresh={refresh}
      secondsUntilRefresh={secondsUntilRefresh}
      collapsed={collapsed}
      setCollapsed={setCollapsed}
      page={page}
      setPage={setPage}
      logout={logout}
      telemetryError={telemetryError}
      routerOverview={routerOverview}
      trafficHistory={trafficHistory}
      cellularHistory={cellularHistory}
      interfaceCounterDeltas={interfaceCounterDeltas}
      wireGuardPeerRates={wireGuardPeerRates}
    />
  );
}

export default App;
