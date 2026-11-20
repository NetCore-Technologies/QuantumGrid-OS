import { useCallback, useEffect, useRef, useState } from "react";
import { fetchRouterOverview, loginToRouter, runRouterLatencyTest, scanRouterWifi, updateRouterSqmQueue, type RouterClient, type RouterLatencyTest, type RouterOverview, type RouterWifiScan, type RouterWifiRateDetails, type RouterWirelessClient, type RouterSqmQueue } from "./routerApi";
import { planWifiChannels } from "./wifiChannelPlanner";
import { auditFirewallPosture } from "./firewallPosture";
import { analyzePolicyRouting } from "./policyRouting";
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
  | "advanced";

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
  ["analytics", "Analytics", Database],
  ["system", "System", Cpu],
  ["advanced", "Advanced", Settings],
] as const;

function fmt(value: number, digits = 0) {
  return value.toLocaleString("en-US", {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  });
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

          <NavSection title="System" collapsed={collapsed}>
            {nav.slice(9).map(([id, label, Icon]) => (
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
      ["Exported at (UTC)", "State filter", "Search filter", "Sort order", "Interface", "Enabled", "Netifd up", "mwan3 status", "Tracker state", "Tracker running", "Age seconds", "Online seconds", "Offline seconds", "Interface uptime seconds", "Score", "Lost", "Turn", "Tracking targets"],
      ...visibleMwanInterfaces.map((iface) => [
        exportedAt, mwanStateFilter, mwanSearch, mwanSort, iface.name, iface.enabled, iface.up,
        iface.status, iface.tracking, iface.running, iface.age_seconds, iface.online_seconds,
        iface.offline_seconds, iface.interface_uptime_seconds, iface.score, iface.lost, iface.turn,
        iface.track_targets.map((target) =>
          [target.ip, target.status, target.latency_ms, target.packet_loss_percent].join("/")
        ).join(" | "),
      ]),
    ];
    const csv = rows.map((row) => row.map(csvCell).join(",")).join("\\r\\n");
    const objectUrl = URL.createObjectURL(new Blob(["\\uFEFF", csv], { type: "text/csv;charset=utf-8" }));
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
        action={<Status active={Boolean(mwan3?.available)}>{!mwan3?.installed ? "NOT INSTALLED" : mwan3.available ? "LIVE" : "UNAVAILABLE"}</Status>}
      >
        {!routerOverview ? (
          <div className="module-message">Waiting for authenticated router telemetry.</div>
        ) : !mwan3?.installed ? (
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

function SystemControlPage({ routerOverview, stats }: { routerOverview: RouterOverview | null; stats: Stats }) {
  const memory = routerOverview?.system.memory;
  const load = routerOverview?.system.load_avg ?? [];

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


function SecurityControlPage({ routerOverview }: { routerOverview: RouterOverview | null }) {
  const security = routerOverview?.security;
  const zones = security?.zones ?? [];
  const fw4Present = security?.nft_tables.includes("inet/fw4") ?? false;
  const activeWireGuard = security?.vpn.wireguard_interfaces.filter((item) => item.up) ?? [];
  const firewallPosture = auditFirewallPosture(security);
  const [firewallRuleSearch, setFirewallRuleSearch] = useState("");
  const [firewallRuleSort, setFirewallRuleSort] = useState<"name" | "source" | "destination" | "target">("source");
  const firewallRules = security?.rules ?? [];
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
      [exportedAt, "Firewall", "fw4 table", fw4Present ? "PRESENT" : "NOT FOUND", "inet/fw4"],
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

function DashboardPage({
  stats,
  refresh,
  page,
  telemetryError,
  routerOverview,
  trafficHistory,
  cellularHistory,
  interfaceCounterDeltas,
}: {
  stats: Stats;
  refresh: () => void;
  page: Page;
  telemetryError: string;
  routerOverview: RouterOverview | null;
  trafficHistory: number[];
  cellularHistory: CellularHistorySample[];
  interfaceCounterDeltas: Map<string, InterfaceCounterDelta>;
}) {
  const wanOnline = routerOverview?.interfaces.some((item) => item.is_wan && item.up) ?? false;
  const wifiOnline = routerOverview?.wireless.some((radio) => radio.up) ?? false;
  const modemDetected = routerOverview?.cellular.modem_present ?? false;
  const clients = routerOverview?.clients ?? [];
  const inventoryAvailable = Array.isArray(routerOverview?.clients);

  if (page === "phone") return <PhonePage routerOverview={routerOverview} />;
  if (page === "network") return <NetworkControlPage routerOverview={routerOverview} stats={stats} interfaceCounterDeltas={interfaceCounterDeltas} />;
  if (page === "diagnostics") return <DiagnosticsControlPage stats={stats} telemetryError={telemetryError} routerOverview={routerOverview} refresh={refresh} />;
  if (page === "system") return <SystemControlPage routerOverview={routerOverview} stats={stats} />;
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
  };

  if (page === "gaming") {
    return <GamingControlPage routerOverview={routerOverview} refresh={refresh} />;
  }

  if (page === "security") {
    return <SecurityControlPage routerOverview={routerOverview} />;
  }

  if (page === "wifi") {
    return <WifiControlPage routerOverview={routerOverview} />;
  }

  if (page === "devices") {
    return <DevicesControlPage routerOverview={routerOverview} />;
  }

  if (page === "advanced") {
    return <AdvancedControlPage routerOverview={routerOverview} refresh={refresh} />;
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
  rx_errors?: number;
  tx_errors?: number;
  rx_dropped?: number;
  tx_dropped?: number;
};

type InterfaceCounterDelta = {
  rxErrors: number | null;
  txErrors: number | null;
  rxDropped: number | null;
  txDropped: number | null;
};

function WifiControlPage({ routerOverview }: { routerOverview: RouterOverview | null }) {
  const radios = routerOverview?.wireless ?? [];
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
          <p>Radio and wireless-interface status from the authenticated OpenWrt API. Configuration changes remain disabled until safe router-side handlers and rollback checks are implemented.</p>
        </div>
      </section>
      <div className="module-grid">
        <Panel title="Wireless radios" eyebrow="NETWORK.WIRELESS STATUS" action={<Status active={Boolean(routerOverview)}>{routerOverview ? "LIVE" : "WAITING"}</Status>}>
          <WirelessRadioInventory radios={radios} available={Boolean(routerOverview)} />
        </Panel>
        <Panel title="Configuration controls" eyebrow="SAFE READ-ONLY MODE">
          <Status active={false}>NOT CONNECTED</Status>
          <div className="module-message">Channel, power, width, band steering, roaming and radio enable/disable are not writable here. Driver-reported channel/frequency/signal/bitrate/quality are live measurements; configuration remains read-only until safe service handlers and rollback checks exist.</div>
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
  onApply: (section: string, enabled: boolean, download: number, upload: number) => Promise<void>;
}) {
  const [enabled, setEnabled] = useState(queue.enabled);
  const [download, setDownload] = useState(queue.download_kbps === undefined ? "" : String(queue.download_kbps));
  const [upload, setUpload] = useState(queue.upload_kbps === undefined ? "" : String(queue.upload_kbps));
  const [acknowledged, setAcknowledged] = useState(false);

  const parseRate = (value: string) => /^\d+$/.test(value) ? Number(value) : NaN;
  const downloadRate = parseRate(download);
  const uploadRate = parseRate(upload);
  const validRates = Number.isInteger(downloadRate) && Number.isInteger(uploadRate) &&
    downloadRate >= 64 && downloadRate <= 1000000 &&
    uploadRate >= 64 && uploadRate <= 1000000;
  const changed = enabled !== queue.enabled ||
    downloadRate !== (queue.download_kbps ?? NaN) ||
    uploadRate !== (queue.upload_kbps ?? NaN);

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
      </div>
      <label className="sqm-policy-ack">
        <input type="checkbox" checked={acknowledged} onChange={(event) => setAcknowledged(event.target.checked)} />
        <span>I understand applying changes restarts SQM and may briefly interrupt traffic.</span>
      </label>
      <div className="sqm-policy-actions">
        <span>Only enabled, download and upload options are changed. Interface, qdisc and script are preserved.</span>
        <button className="hero-button" disabled={!changed || !validRates || !acknowledged || saving}
          onClick={() => { void onApply(queue.name, enabled, downloadRate, uploadRate); }}>
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
  const applySqmQueue = async (section: string, enabled: boolean, download: number, upload: number) => {
    setSavingQueue(section);
    setSqmNotice(null);
    try {
      await updateRouterSqmQueue(section, enabled, download, upload);
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
              <SqmQueueEditor key={queue.name + "-" + queue.enabled + "-" + (queue.download_kbps ?? "") + "-" + (queue.upload_kbps ?? "")} queue={queue} saving={savingQueue === queue.name} onApply={applySqmQueue} />
            ))}
          </div>
        )}
        {sqmNotice ? (
          <div className={sqmNotice.success ? "sqm-policy-notice success" : "sqm-policy-notice error"} role="status">{sqmNotice.message}</div>
        ) : null}
        <div className="module-message">Limits must be whole numbers from 64 to 1,000,000 kbit/s. Applying a change restarts SQM. The router API modifies only the selected existing queue's enabled/download/upload values and attempts to restore the previous values if the restart fails.</div>
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


function AdvancedControlPage({ routerOverview, refresh }: {
  routerOverview: RouterOverview | null;
  refresh: () => void;
}) {
  const platform = routerOverview?.platform;
  const system = routerOverview?.system;
  const memory = system?.memory;
  const load = system?.load_avg ?? [];
  const modules = platform?.modules ?? [];
  const tools = platform?.tools ?? [];
  const services = platform?.services ?? [];
  const storage = platform?.storage ?? [];
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
      ...modules.map((item) => [generatedAt, platform.hostname, "Kernel module", item.name, item.loaded ? "LOADED" : "NOT LOADED", "", "", "", "", ""]),
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
          <div className="module-grid">
            <Panel title="Loaded kernel modules" eyebrow="SYSFS · /SYS/MODULE">
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
      const nextInterfaceCounters = new Map<string, InterfaceCounterSnapshot>();
      const nextInterfaceDeltas = new Map<string, InterfaceCounterDelta>();
      const counterDelta = (current: number | undefined, previous: number | undefined) =>
        current === undefined || previous === undefined || current < previous ? null : current - previous;
      for (const item of overview.interfaces) {
        const previousCounters = previousInterfaceCounters.current.get(item.name);
        if (previousCounters) {
          nextInterfaceDeltas.set(item.name, {
            rxErrors: counterDelta(item.rx_errors, previousCounters.rx_errors),
            txErrors: counterDelta(item.tx_errors, previousCounters.tx_errors),
            rxDropped: counterDelta(item.rx_dropped, previousCounters.rx_dropped),
            txDropped: counterDelta(item.tx_dropped, previousCounters.tx_dropped),
          });
        }
        nextInterfaceCounters.set(item.name, {
          rx_errors: item.rx_errors, tx_errors: item.tx_errors,
          rx_dropped: item.rx_dropped, tx_dropped: item.tx_dropped,
        });
      }
      previousInterfaceCounters.current = nextInterfaceCounters;
      setInterfaceCounterDeltas(nextInterfaceDeltas);
      const wan =
        overview.interfaces.find((item) => item.name === "wan" && item.up) ??
        overview.interfaces.find((item) => item.is_wan && item.up) ??
        overview.interfaces.find((item) => item.up);
      const now = Date.now();
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
    />
  );
}

export default App;
