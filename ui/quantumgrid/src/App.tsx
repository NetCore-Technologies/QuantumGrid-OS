import { useEffect, useState } from "react";
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
  Bot,
  GripVertical,
  Globe2,
  HardDrive,
  KeyRound,
  Lock,
  Menu,
  Monitor,
  Network,
  RefreshCw,
  Router,
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
  RadioTower,
} from "lucide-react";

type Page =
  | "dashboard"
  | "gaming"
  | "devices"
  | "wifi"
  | "5g"
  | "network"
  | "security"
  | "diagnostics"
  | "analytics"
  | "system"
  | "advanced";

type SetupStep = "welcome" | "account" | "wifi" | "wan";

type Stats = {
  latency: number;
  jitter: number;
  download: number;
  upload: number;
  loss: number;
  cpu: number;
  ram: number;
  temp: number;
};

const nav = [
  ["dashboard", "Dashboard", CircleGauge],
  ["gaming", "Gaming", Gamepad2],
  ["devices", "Devices", Users],
  ["wifi", "Wi-Fi", Wifi],
  ["5g", "5G", Signal],
  ["network", "Network", Network],
  ["security", "Security", Shield],
  ["diagnostics", "Diagnostics", Activity],
  ["analytics", "Analytics", Database],
  ["system", "System", Cpu],
  ["advanced", "Advanced", Settings],
] as const;

const devices = [
  ["QuantumGrid PC", "Gaming workstation", "192.168.1.100", "2.5GbE", 428],
  ["PlayStation 5", "Console", "192.168.1.112", "Wi-Fi 6", 186],
  ["iPhone", "Mobile", "192.168.1.121", "Wi-Fi 6", 38],
  ["Living Room TV", "Smart TV", "192.168.1.140", "Wi-Fi 6", 12],
];

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

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

  const validUser = username.trim().length >= 3;
  const validPassword = password.length >= 8;
  const validMatch = password.length > 0 && password === confirm;

  function submit() {
    if (!validUser) {
      setError("Your username must contain at least 3 characters.");
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
            Create your
            <span> administrator account.</span>
          </h1>

          <p>
            This account protects access to your QuantumGrid control center.
          </p>

          <div className="account-form">
            <Field
              label="USERNAME"
              icon={User}
              value={username}
              placeholder="Choose a username"
              onChange={setUsername}
              valid={validUser}
            />

            <Field
              label="PASSWORD"
              icon={Lock}
              value={password}
              placeholder="Create a secure password"
              onChange={setPassword}
              type="password"
              valid={validPassword}
            />

            <Field
              label="CONFIRM PASSWORD"
              icon={Lock}
              value={confirm}
              placeholder="Enter the password again"
              onChange={setConfirm}
              type="password"
              valid={validMatch}
            />
          </div>

          <div className="rules">
            <Rule text="3+ character username" valid={validUser} />
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
}: {
  label: string;
  icon: React.ElementType;
  value: string;
  placeholder: string;
  onChange: (v: string) => void;
  valid: boolean;
  type?: string;
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
}: {
  username: string;
  password: string;
  setPassword: (v: string) => void;
  login: () => void;
  error: string;
}) {
  const [showError, setShowError] = useState(true);

  useEffect(() => {
    setShowError(Boolean(error));
  }, [error]);

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
                    setShowError(false);
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

              <button onClick={() => setShowError(false)}>
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
}: {
  stats: Stats;
  refresh: () => void;
  secondsUntilRefresh: number;
  collapsed: boolean;
  setCollapsed: (v: boolean) => void;
  page: Page;
  setPage: (v: Page) => void;
  logout: () => void;
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
            {nav.slice(3, 8).map(([id, label, Icon]) => (
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
            {nav.slice(8).map(([id, label, Icon]) => (
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
            <Status>SYSTEM OPTIMAL</Status>

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
          <DashboardPage stats={stats} refresh={refresh} page={page} />
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

function DashboardPage({
  stats,
  refresh,
  page,
}: {
  stats: Stats;
  refresh: () => void;
  page: Page;
}) {
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
              Optimize Network
            </button>
          </div>

          <div className="health-card">
            <Status>SYSTEM OPTIMAL</Status>

            <strong>98</strong>
            <span>QuantumGrid Health Score</span>

            <div className="health-mini">
              <div><span>CLIENTS</span><b>18</b></div>
              <div><span>WAN</span><b>2.5GbE</b></div>
              <div><span>UPTIME</span><b>12d</b></div>
            </div>
          </div>
        </section>

        <div className="metrics">
          <Metric title="Latency" value={fmt(stats.latency)} unit="ms" detail={`${fmt(stats.jitter, 1)} ms jitter`} icon={Activity} />
          <Metric title="Download" value={fmt(stats.download)} unit="Mbps" detail="Current WAN throughput" icon={Download} />
          <Metric title="Upload" value={fmt(stats.upload)} unit="Mbps" detail="Current WAN throughput" icon={Upload} />
          <Metric title="Packet Loss" value={fmt(stats.loss, 1)} unit="%" detail="Connection quality" icon={Signal} />
        </div>

        <div className="dashboard-grid">
          <Panel title="Live Network Traffic" eyebrow="THROUGHPUT" action={<Status>LIVE</Status>}>
            <div className="traffic-demo">
              {Array.from({ length: 30 }, (_, i) => {
                const height = clamp(
                  25 +
                    Math.sin(i / 2.3) * 18 +
                    Math.sin(i / 4.5) * 22 +
                    (i % 5) * 4,
                  8,
                  90,
                );

                return (
                  <div key={i} className="traffic-column">
                    <span style={{ height: `${height}%` }} />
                  </div>
                );
              })}
            </div>

            <div className="traffic-labels">
              <span>60s ago</span>
              <span>30s</span>
              <span>NOW</span>
            </div>
          </Panel>

          <Panel title="Gaming Engine" eyebrow="LOW LATENCY" action={<Status>ACTIVE</Status>}>
            <div className="gaming-score">
              <div className="gaming-ring">
                <strong>98</strong>
                <span>/100</span>
              </div>

              <div className="gaming-stats">
                <div><span>LATENCY</span><b>{fmt(stats.latency)} ms</b></div>
                <div><span>JITTER</span><b>{fmt(stats.jitter, 1)} ms</b></div>
                <div><span>LOSS</span><b>{fmt(stats.loss, 1)}%</b></div>
                <div><span>BUFFERBLOAT</span><b>A</b></div>
              </div>
            </div>

            <div className="mode-row">
              <span className="selected">GAMING</span>
              <span>BALANCED</span>
              <span>TURBO</span>
            </div>
          </Panel>
        </div>

        <div className="three-grid">
          <Panel title="Acceleration" eyebrow="DATA PLANE">
            <InfoRows
              rows={[
                ["NSS", "READY"],
                ["EDMA", "READY"],
                ["PPE", "READY"],
                ["2.5GbE", "READY"],
              ]}
            />
          </Panel>

          <Panel title="System Health" eyebrow="LIVE HARDWARE">
            <div className="health-grid">
              <Health icon={Cpu} label="CPU" value={`${fmt(stats.cpu, 1)}%`} />
              <Health icon={Thermometer} label="TEMP" value={`${fmt(stats.temp, 1)}°C`} />
              <Health icon={Database} label="RAM" value={`${fmt(stats.ram, 1)}%`} />
              <Health icon={HardDrive} label="STORAGE" value="28%" />
            </div>
          </Panel>

          <Panel title="Network Status" eyebrow="CONNECTIVITY">
            <InfoRows
              rows={[
                ["WAN", "ONLINE"],
                ["WI-FI", "ONLINE"],
                ["5G", "STANDBY"],
              ]}
            />
          </Panel>
        </div>

        <Panel title="Connected Devices" eyebrow="CLIENT INTELLIGENCE">
          <div className="device-list">
            {devices.map(([name, type, ip, link, speed]) => (
              <div className="device-row" key={name}>
                <div className="device-title">
                  <div className="device-icon">
                    <Monitor size={17} />
                  </div>

                  <div>
                    <strong>{name}</strong>
                    <span>{type}</span>
                  </div>
                </div>

                <div><small>IP</small><b>{ip}</b></div>
                <div><small>LINK</small><b>{link}</b></div>
                <div><small>DOWNLOAD</small><b>{fmt(Number(speed))} Mbps</b></div>
                <div><small>PRIORITY</small><b className="priority">HIGH</b></div>
              </div>
            ))}
          </div>
        </Panel>
      </div>
    );
  }

  const titles: Record<Exclude<Page, "dashboard">, [string, string, React.ElementType]> = {
    gaming: ["Gaming", "Gaming Engine", Gamepad2],
    devices: ["Devices", "Client Intelligence", Users],
    wifi: ["Wi-Fi", "Wireless Intelligence", Wifi],
    "5g": ["5G", "Cellular Control Center", Signal],
    network: ["Network", "Network Control", Network],
    security: ["Security", "Security Center", Shield],
    diagnostics: ["Diagnostics", "Network Diagnostics", Activity],
    analytics: ["Analytics", "Network Analytics", Database],
    system: ["System", "System Control", Cpu],
    advanced: ["Advanced", "Advanced Control", Settings],
  };

  if (page === "gaming") {
    return <GamingControlPage />;
  }

  if (page === "wifi") {
    return <WifiControlPage />;
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


function WifiControlPage() {
  const [bandSteering, setBandSteering] = useState(true);
  const [autoChannel, setAutoChannel] = useState(true);

  const [radio24, setRadio24] = useState(true);
  const [radio5, setRadio5] = useState(true);

  const [power24, setPower24] = useState("High");
  const [power5, setPower5] = useState("High");

  const [clients, setClients] = useState([
    {
      name: "QuantumGrid PC",
      band: "5 GHz",
      signal: "-39 dBm",
      rate: "842 Mbps",
      priority: "HIGH",
    },
    {
      name: "PlayStation 5",
      band: "5 GHz",
      signal: "-46 dBm",
      rate: "486 Mbps",
      priority: "HIGH",
    },
    {
      name: "iPhone",
      band: "2.4 GHz",
      signal: "-48 dBm",
      rate: "312 Mbps",
      priority: "NORMAL",
    },
    {
      name: "Living Room TV",
      band: "2.4 GHz",
      signal: "-61 dBm",
      rate: "186 Mbps",
      priority: "LOW",
    },
  ]);

  const [dragIndex, setDragIndex] = useState<number | null>(null);

  function moveClient(from: number, to: number) {
    if (
      from === to ||
      from < 0 ||
      to < 0 ||
      from >= clients.length ||
      to >= clients.length
    ) {
      return;
    }

    setClients((current) => {
      const next = [...current];
      const [item] = next.splice(from, 1);
      next.splice(to, 0, item);
      return next;
    });
  }

  return (
    <div className="real-page wifi-control-page">
      <section className="real-page-header wifi-real-header">
        <div>
          <div className="setup-kicker">WIRELESS INTELLIGENCE • LIVE</div>

          <h1>
            Wi-Fi
            <span> Control Center.</span>
          </h1>

          <p>
            Control your radios, intelligent band steering, channels,
            security, transmit power and connected clients.
          </p>

          <div className="wifi-header-controls">
            <AdvancedToggle
              icon={Sparkles}
              title="Band Steering"
              description="Automatic"
              enabled={bandSteering}
              setEnabled={setBandSteering}
            />

            <AdvancedToggle
              icon={Bot}
              title="Auto Channel"
              description="Intelligent"
              enabled={autoChannel}
              setEnabled={setAutoChannel}
            />
          </div>
        </div>

        <div className="wifi-health-card">
          <Status>WIRELESS HEALTH</Status>

          <strong>98</strong>

          <span>
            Excellent wireless environment
          </span>

          <div className="wifi-health-bar">
            <span style={{ width: "98%" }} />
          </div>
        </div>
      </section>

      <div className="radio-overview-grid">
        <WifiRadioPanel
          band="2.4 GHz"
          enabled={radio24}
          setEnabled={setRadio24}
          channel={autoChannel ? "AUTO" : "6"}
          width="20 MHz"
          clients={2}
          power={power24}
          setPower={setPower24}
        />

        <WifiRadioPanel
          band="5 GHz"
          enabled={radio5}
          setEnabled={setRadio5}
          channel={autoChannel ? "AUTO" : "36"}
          width="80 MHz"
          clients={2}
          power={power5}
          setPower={setPower5}
          primary
        />
      </div>

      <div className="wifi-feature-grid">
        <Panel title="Band Steering" eyebrow="CLIENT INTELLIGENCE">
          <div className="feature-big-toggle">
            <div className="feature-icon">
              <Sparkles size={23} />
            </div>

            <div>
              <strong>
                Intelligent client steering
              </strong>

              <span>
                QuantumGrid can move compatible clients between
                2.4 GHz and 5 GHz based on signal, capabilities,
                utilization and priority.
              </span>
            </div>

            <button
              className={
                bandSteering
                  ? "qg-switch enabled large"
                  : "qg-switch large"
              }
              onClick={() => setBandSteering(!bandSteering)}
            >
              <span />
            </button>
          </div>

          <div className="steering-rule-grid">
            <div>
              <span>SIGNAL</span>
              <strong>SMART</strong>
            </div>

            <div>
              <span>CAPABILITY</span>
              <strong>SMART</strong>
            </div>

            <div>
              <span>PRIORITY</span>
              <strong>SMART</strong>
            </div>

            <div>
              <span>LOAD</span>
              <strong>SMART</strong>
            </div>
          </div>
        </Panel>

        <Panel title="Wireless Security" eyebrow="PROTECTION">
          <div className="security-status-card">
            <div className="security-status-icon">
              <Shield size={21} />
            </div>

            <div>
              <strong>WPA2 / WPA3</strong>
              <span>
                Protected wireless authentication
              </span>
            </div>

            <Status>SECURE</Status>
          </div>

          <div className="security-option-row">
            <div>
              <span>PRIMARY SECURITY</span>
              <strong>WPA3-SAE</strong>
            </div>

            <button className="secondary-button">
              Configure
              <ChevronRight size={15} />
            </button>
          </div>

          <div className="security-option-row">
            <div>
              <span>COMPATIBILITY</span>
              <strong>WPA2/WPA3</strong>
            </div>

            <button className="secondary-button">
              Advanced
              <ChevronRight size={15} />
            </button>
          </div>
        </Panel>
      </div>

      <Panel title="Connected Clients" eyebrow="DRAG TO PRIORITIZE">
        <div className="wifi-client-help">
          <GripVertical size={14} />
          Drag a device to change its network priority.
        </div>

        <div className="wifi-client-table">
          <div className="wifi-client-table-head">
            <span>DEVICE</span>
            <span>BAND</span>
            <span>SIGNAL</span>
            <span>RATE</span>
            <span>PRIORITY</span>
          </div>

          {clients.map((client, index) => (
            <div
              key={client.name}
              className={
                dragIndex === index
                  ? "wifi-client-table-row dragging"
                  : "wifi-client-table-row"
              }
              draggable
              onDragStart={() => setDragIndex(index)}
              onDragOver={(event) => event.preventDefault()}
              onDrop={() => {
                if (dragIndex !== null) {
                  moveClient(dragIndex, index);
                }

                setDragIndex(null);
              }}
              onDragEnd={() => setDragIndex(null)}
            >
              <div className="wifi-client-name">
                <div className="drag-handle">
                  <GripVertical size={16} />
                </div>

                <div className="device-icon">
                  <Monitor size={16} />
                </div>

                <div>
                  <strong>{client.name}</strong>
                  <span>Connected</span>
                </div>
              </div>

              <b>{client.band}</b>
              <b>{client.signal}</b>
              <b>{client.rate}</b>

              <span
                className={
                  client.priority === "HIGH"
                    ? "priority-pill high"
                    : client.priority === "LOW"
                      ? "priority-pill low"
                      : "priority-pill normal"
                }
              >
                {client.priority}
              </span>
            </div>
          ))}
        </div>
      </Panel>

      <div className="wifi-bottom-actions premium-bottom-actions">
        <div>
          <div className="bottom-action-icon">
            <RadioTower size={16} />
          </div>

          <div>
            <strong>Wireless environment monitored</strong>
            <span>
              QuantumGrid is continuously evaluating radio conditions.
            </span>
          </div>
        </div>

        <button
          className="hero-button"
          onClick={() => window.location.reload()}
        >
          <RefreshCw size={16} />
          Rescan Environment
        </button>
      </div>
    </div>
  );
}

function WifiRadioPanel({
  band,
  enabled,
  setEnabled,
  channel,
  width,
  clients,
  power,
  setPower,
  primary = false,
}: {
  band: string;
  enabled: boolean;
  setEnabled: (value: boolean) => void;
  channel: string;
  width: string;
  clients: number;
  power: string;
  setPower: (value: string) => void;
  primary?: boolean;
}) {
  return (
    <section className={primary ? "radio-card primary wifi-radio-real" : "radio-card wifi-radio-real"}>
      <div className="radio-card-header">
        <div>
          <div className="panel-eyebrow">
            WIRELESS RADIO
          </div>

          <h2>{band}</h2>
        </div>

        <button
          className={
            enabled
              ? "radio-power active"
              : "radio-power"
          }
          onClick={() => setEnabled(!enabled)}
        >
          <span />
          {enabled ? "ACTIVE" : "OFF"}
        </button>
      </div>

      <div className="radio-live-line">
        <Status>
          {enabled ? "RADIO ONLINE" : "RADIO DISABLED"}
        </Status>

        <span>
          802.11AX
        </span>
      </div>

      <div className="radio-stats">
        <div>
          <span>CHANNEL</span>
          <strong>{channel}</strong>
        </div>

        <div>
          <span>WIDTH</span>
          <strong>{width}</strong>
        </div>

        <div>
          <span>CLIENTS</span>
          <strong>{clients}</strong>
        </div>

        <div>
          <span>POWER</span>
          <strong>{power}</strong>
        </div>
      </div>

      <div className="radio-controls">
        <label>
          <span>TRANSMIT POWER</span>

          <select
            value={power}
            onChange={(e) => setPower(e.target.value)}
          >
            <option>Low</option>
            <option>Medium</option>
            <option>High</option>
          </select>
        </label>

        <button className="secondary-button">
          <SlidersHorizontal size={14} />
          Configure Radio
        </button>
      </div>
    </section>
  );
}



function GamingControlPage() {
  const [engine, setEngine] = useState(true);
  const [smartQueue, setSmartQueue] = useState(true);
  const [gamingPriority, setGamingPriority] = useState(true);
  const [autoOptimize, setAutoOptimize] = useState(true);
  const [scheduled, setScheduled] = useState(false);
  const [optimizing, setOptimizing] = useState(false);

  const [mode, setMode] = useState<
    "latency" | "balanced" | "throughput"
  >("latency");

  const [downloadLimit, setDownloadLimit] = useState("950");
  const [uploadLimit, setUploadLimit] = useState("45");

  const [latency, setLatency] = useState(8);
  const [jitter, setJitter] = useState(1.1);
  const [packetLoss, setPacketLoss] = useState(0);
  const [score, setScore] = useState(98);

  const [clients, setClients] = useState([
    {
      name: "QuantumGrid PC",
      ip: "192.168.1.100",
      link: "2.5GbE",
      latency: 8,
      priority: "HIGH",
    },
    {
      name: "PlayStation 5",
      ip: "192.168.1.112",
      link: "Wi-Fi 6",
      latency: 11,
      priority: "HIGH",
    },
    {
      name: "Xbox",
      ip: "192.168.1.118",
      link: "Wi-Fi 6",
      latency: 14,
      priority: "NORMAL",
    },
    {
      name: "Gaming Laptop",
      ip: "192.168.1.119",
      link: "Wi-Fi 6",
      latency: 17,
      priority: "NORMAL",
    },
  ]);

  const [dragIndex, setDragIndex] = useState<number | null>(null);

  const [telemetry, setTelemetry] = useState<number[]>(
    Array.from({ length: 42 }, (_, i) =>
      9 +
      Math.sin(i / 2.8) * 3 +
      Math.sin(i / 5.4) * 2,
    ),
  );

  useEffect(() => {
    const timer = window.setInterval(() => {
      setLatency((value) =>
        Math.max(
          5,
          Math.min(
            18,
            value + (Math.random() - 0.5) * (autoOptimize ? 1.5 : 3),
          ),
        ),
      );

      setJitter((value) =>
        Math.max(
          0.3,
          Math.min(
            3.8,
            value + (Math.random() - 0.5) * (autoOptimize ? 0.2 : 0.45),
          ),
        ),
      );

      setPacketLoss((value) =>
        Math.max(
          0,
          Math.min(0.8, value + (Math.random() - 0.5) * 0.08),
        ),
      );

      setScore((value) =>
        Math.max(
          91,
          Math.min(
            100,
            value + (Math.random() - 0.5) * (autoOptimize ? 1.1 : 2),
          ),
        ),
      );

      setTelemetry((values) => [
        ...values.slice(1),
        8 +
          Math.random() * 4 +
          Math.sin(Date.now() / 1100) * 2,
      ]);
    }, 1800);

    return () => window.clearInterval(timer);
  }, [autoOptimize]);

  function optimize() {
    if (optimizing) return;

    setOptimizing(true);

    setEngine(true);
    setSmartQueue(true);
    setGamingPriority(true);
    setAutoOptimize(true);

    setMode("latency");
    setDownloadLimit("950");
    setUploadLimit("45");

    setLatency(7);
    setJitter(0.9);
    setPacketLoss(0);
    setScore(99);

    window.setTimeout(() => {
      setOptimizing(false);
    }, 2200);
  }

  function moveClient(from: number, to: number) {
    if (
      from === to ||
      from < 0 ||
      to < 0 ||
      from >= clients.length ||
      to >= clients.length
    ) {
      return;
    }

    setClients((current) => {
      const next = [...current];
      const [item] = next.splice(from, 1);
      next.splice(to, 0, item);
      return next;
    });
  }

  return (
    <div className="gaming-page">
      {optimizing && (
        <div className="optimization-overlay">
          <div className="optimization-orbit">
            <Zap size={27} />
          </div>

          <strong>Optimizing QuantumGrid</strong>

          <span>
            Rebalancing latency, queues and client priorities...
          </span>

          <div className="optimization-progress">
            <span />
          </div>
        </div>
      )}

      <section className="gaming-hero premium-hero">
        <div className="gaming-hero-copy">
          <div className="setup-kicker">GAMING ENGINE • LIVE</div>

          <h1>
            Maximum
            <span> gaming performance.</span>
          </h1>

          <p>
            QuantumGrid continuously monitors latency, jitter, packet loss,
            bufferbloat and client traffic to keep gaming traffic responsive.
          </p>

          <div className="gaming-engine-controls">
            <ToggleButton
              label="Gaming Engine"
              enabled={engine}
              onClick={() => setEngine(!engine)}
            />

            <ToggleButton
              label="Auto Optimize"
              enabled={autoOptimize}
              onClick={() => setAutoOptimize(!autoOptimize)}
            />

            <Status>
              {engine ? "LATENCY OPTIMIZED" : "STANDARD ROUTING"}
            </Status>
          </div>
        </div>

        <div className="gaming-score-card premium-score">
          <div className="gaming-score-ring large">
            <strong>{Math.round(score)}</strong>
            <span>/100</span>
          </div>

          <div className="gaming-score-label">GAMING SCORE</div>

          <p>
            {optimizing
              ? "Optimization in progress"
              : "Excellent connection quality"}
          </p>
        </div>
      </section>

      <div className="gaming-metrics premium-metrics">
        <MetricTile
          label="LATENCY"
          value={latency.toFixed(0)}
          unit="ms"
          detail="Excellent"
          good
        />
        <MetricTile
          label="JITTER"
          value={jitter.toFixed(1)}
          unit="ms"
          detail="Stable"
          good
        />
        <MetricTile
          label="PACKET LOSS"
          value={packetLoss.toFixed(1)}
          unit="%"
          detail="Perfect"
          good
        />
        <MetricTile
          label="BUFFERBLOAT"
          value="A"
          detail="Excellent"
          good
        />
      </div>

      <div className="gaming-main-grid">
        <Panel title="Gaming Mode" eyebrow="TRAFFIC POLICY">
          <div className="gaming-mode-grid">
            {[
              [
                "latency",
                "Latency First",
                "Minimum delay",
                "Best for competitive gaming",
              ],
              [
                "balanced",
                "Balanced",
                "Latency + throughput",
                "General gaming",
              ],
              [
                "throughput",
                "Throughput",
                "Maximum bandwidth",
                "Large downloads",
              ],
            ].map(([id, title, description, detail]) => (
              <button
                key={id}
                className={
                  mode === id ? "gaming-mode selected" : "gaming-mode"
                }
                onClick={() =>
                  setMode(
                    id as "latency" | "balanced" | "throughput",
                  )
                }
              >
                <div className="gaming-mode-icon">
                  <Zap size={18} />
                </div>

                <strong>{title}</strong>
                <span>{description}</span>
                <small>{detail}</small>

                {mode === id && (
                  <div className="gaming-mode-check">
                    <Check size={14} />
                  </div>
                )}
              </button>
            ))}
          </div>
        </Panel>

        <Panel title="Smart Queue Control" eyebrow="BUFFERBLOAT">
          <div className="advanced-toggle-stack">
            <AdvancedToggle
              icon={Gamepad2}
              title="Smart Queue Management"
              description="Shape WAN traffic dynamically to reduce latency under load."
              enabled={smartQueue}
              setEnabled={setSmartQueue}
            />

            <AdvancedToggle
              icon={Gamepad2}
              title="Gaming Priority"
              description="Prioritize gaming traffic above normal network traffic."
              enabled={gamingPriority}
              setEnabled={setGamingPriority}
            />

            <AdvancedToggle
              icon={Sparkles}
              title="Auto Optimization"
              description="Continuously adjust queue behaviour using live network conditions."
              enabled={autoOptimize}
              setEnabled={setAutoOptimize}
            />
          </div>
        </Panel>
      </div>

      <div className="gaming-policy-grid">
        <Panel title="Bandwidth Policy" eyebrow="WAN CONTROL">
          <div className="bandwidth-policy premium-bandwidth">
            <label>
              <span>DOWNLOAD LIMIT</span>

              <div>
                <input
                  type="number"
                  value={downloadLimit}
                  onChange={(e) => setDownloadLimit(e.target.value)}
                />
                <b>Mbps</b>
              </div>
            </label>

            <label>
              <span>UPLOAD LIMIT</span>

              <div>
                <input
                  type="number"
                  value={uploadLimit}
                  onChange={(e) => setUploadLimit(e.target.value)}
                />
                <b>Mbps</b>
              </div>
            </label>
          </div>

          <div className="policy-summary">
            <div>
              <span>MODE</span>
              <strong>
                {mode === "latency" ? "LATENCY FIRST" : mode.toUpperCase()}
              </strong>
            </div>

            <div>
              <span>AUTO ADJUST</span>
              <strong>{autoOptimize ? "ENABLED" : "DISABLED"}</strong>
            </div>
          </div>
        </Panel>

        <Panel title="Gaming Client Priority" eyebrow="DRAG TO REORDER">
          <div className="priority-help">
            <GripVertical size={14} />
            Drag clients to change their priority order.
          </div>

          <div className="gaming-priority-list">
            {clients.map((client, index) => (
              <div
                key={client.name}
                className={
                  dragIndex === index
                    ? "gaming-priority-row dragging"
                    : "gaming-priority-row"
                }
                draggable
                onDragStart={() => setDragIndex(index)}
                onDragOver={(event) => event.preventDefault()}
                onDrop={() => {
                  if (dragIndex !== null) {
                    moveClient(dragIndex, index);
                  }
                  setDragIndex(null);
                }}
                onDragEnd={() => setDragIndex(null)}
              >
                <div className="drag-handle">
                  <GripVertical size={17} />
                </div>

                <div className="priority-number">{index + 1}</div>

                <div className="priority-device">
                  <div className="device-icon">
                    <Gamepad2 size={16} />
                  </div>

                  <div>
                    <strong>{client.name}</strong>
                    <span>
                      {client.ip} • {client.link}
                    </span>
                  </div>
                </div>

                <div className="priority-latency">
                  <span>LATENCY</span>
                  <strong>{client.latency} ms</strong>
                </div>

                <span
                  className={
                    index < 2
                      ? "priority-pill high"
                      : "priority-pill normal"
                  }
                >
                  {index < 2 ? "HIGH" : client.priority}
                </span>
              </div>
            ))}
          </div>
        </Panel>
      </div>

      <Panel title="Live Gaming Telemetry" eyebrow="REAL-TIME">
        <div className="gaming-live-chart">
          {telemetry.map((value, index) => (
            <span
              key={`${index}-${value}`}
              style={{
                height: `${Math.max(8, Math.min(92, value * 5))}%`,
              }}
            />
          ))}
        </div>

        <div className="telemetry-labels">
          <span>LATENCY</span>
          <span>LIVE</span>
        </div>
      </Panel>

      <div className="gaming-schedule-bar">
        <AdvancedToggle
          icon={Sparkles}
          title="Scheduled Optimization"
          description="Run a network optimization pass automatically."
          enabled={scheduled}
          setEnabled={setScheduled}
        />

        <div className="schedule-select-wrap">
          <span>RUN EVERY</span>

          <select className="premium-select">
            <option>15 minutes</option>
            <option>30 minutes</option>
            <option>1 hour</option>
            <option>3 hours</option>
            <option>6 hours</option>
          </select>
        </div>

        <button
          className="hero-button"
          onClick={optimize}
          disabled={optimizing}
        >
          <Zap size={16} />
          {optimizing ? "Optimizing..." : "Optimize Gaming"}
        </button>
      </div>
    </div>
  );
}

function ToggleButton({
  label,
  enabled,
  onClick,
}: {
  label: string;
  enabled: boolean;
  onClick: () => void;
}) {
  return (
    <button
      className={enabled ? "engine-toggle active" : "engine-toggle"}
      onClick={onClick}
    >
      <span />
      {label}
    </button>
  );
}

function MetricTile({
  label,
  value,
  unit,
  detail,
  good,
}: {
  label: string;
  value: string;
  unit?: string;
  detail: string;
  good?: boolean;
}) {
  return (
    <div className="gaming-metric-tile">
      <span>{label}</span>

      <strong>
        {value}
        {unit && <small>{unit}</small>}
      </strong>

      <em className={good ? "metric-good" : ""}>
        {detail}
      </em>
    </div>
  );
}

function AdvancedToggle({
  icon: Icon,
  title,
  description,
  enabled,
  setEnabled,
}: {
  icon: React.ElementType;
  title: string;
  description: string;
  enabled: boolean;
  setEnabled: (value: boolean) => void;
}) {
  return (
    <div className="advanced-toggle">
      <div className="advanced-toggle-icon">
        <Icon size={17} />
      </div>

      <div className="advanced-toggle-copy">
        <strong>{title}</strong>
        <span>{description}</span>
      </div>

      <button
        className={enabled ? "qg-switch enabled" : "qg-switch"}
        onClick={() => setEnabled(!enabled)}
        aria-label={`Toggle ${title}`}
      >
        <span />
      </button>
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
        <div className="module-icon">
          <Icon size={25} />
        </div>

        <div>
          <div className="setup-kicker">{eyebrow.toUpperCase()}</div>
          <h1>{title}</h1>
          <p>
            QuantumGrid management module. Real hardware telemetry and
            controls will be connected to this service.
          </p>
        </div>
      </section>

      <div className="module-grid">
        <Panel title="Service Status" eyebrow="QUANTUMGRID">
          <Status>MODULE ONLINE</Status>

          <div className="module-message">
            This service is ready for QuantumGrid backend integration.
          </div>
        </Panel>

        <Panel title="Controls" eyebrow="MANAGEMENT">
          <div className="control-grid">
            {["Optimize", "Diagnostics", "Configure", "Inspect"].map(
              (item) => (
                <button key={item} className="control-tile">
                  <Sparkles size={17} />
                  {item}
                </button>
              ),
            )}
          </div>
        </Panel>
      </div>
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

  // Setup username must always start blank.
  // The saved username is loaded separately for the login screen.
  const [username, setUsername] = useState("");

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
    latency: 8,
    jitter: 1.1,
    download: 942,
    upload: 41,
    loss: 0,
    cpu: 21,
    ram: 34,
    temp: 51,
  });

  function refresh() {
    setSecondsUntilRefresh(3);

    setStats((s) => ({
      latency: clamp(s.latency + (Math.random() - 0.5) * 4, 5, 18),
      jitter: clamp(s.jitter + (Math.random() - 0.5) * 0.5, 0.3, 4),
      download: clamp(s.download + (Math.random() - 0.5) * 80, 700, 1120),
      upload: clamp(s.upload + (Math.random() - 0.5) * 12, 25, 80),
      loss: clamp(s.loss + (Math.random() - 0.5) * 0.1, 0, 0.8),
      cpu: clamp(s.cpu + (Math.random() - 0.5) * 8, 7, 58),
      ram: clamp(s.ram + (Math.random() - 0.5) * 4, 22, 60),
      temp: clamp(s.temp + (Math.random() - 0.5) * 1.5, 43, 68),
    }));
  }

  useEffect(() => {
    if (!setupComplete || !loggedIn) return;

    setSecondsUntilRefresh(3);

    const refreshTimer = window.setInterval(() => {
      refresh();
      setSecondsUntilRefresh(3);
    }, 3000);

    const countdownTimer = window.setInterval(() => {
      setSecondsUntilRefresh((value) =>
        value <= 1 ? 3 : value - 1,
      );
    }, 1000);

    return () => {
      window.clearInterval(refreshTimer);
      window.clearInterval(countdownTimer);
    };
  }, [setupComplete, loggedIn]);

  function finishSetup() {
    localStorage.setItem("quantumgrid-setup-complete", "1");
    localStorage.setItem("quantumgrid-username", username);
    localStorage.setItem("quantumgrid-wifi-ssid", ssid);
    localStorage.setItem("quantumgrid-wan-type", wanType);

    setSetupComplete(true);
    setSetupStep("welcome");
  }

  function logout() {
    setLoggedIn(false);
    setLoginPassword("");
    setLoginError("");
    setPage("dashboard");
    setCollapsed(false);
  }

  function login() {
    const saved = localStorage.getItem("quantumgrid-username") || "";

    /*
     * Development-only credential handling.
     * Production firmware will authenticate against the router backend.
     */
    if (saved.length > 0 && loginPassword === password) {
      setLoggedIn(true);
      setLoginError("");
      return;
    }

    setLoginError("Incorrect username or password.");
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
        username={localStorage.getItem("quantumgrid-username") || ""}
        password={loginPassword}
        setPassword={setLoginPassword}
        login={login}
        error={loginError}
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
    />
  );
}

export default App;
