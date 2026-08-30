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
  Globe2,
  HardDrive,
  Lock,
  Menu,
  Monitor,
  Network,
  RefreshCw,
  Router,
  Settings,
  Shield,
  Signal,
  Sparkles,
  Thermometer,
  Upload,
  User,
  Users,
  Wifi,
  X,
  Zap,
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

      <div className="welcome-kicker">WELCOME</div>

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
  const [show, setShow] = useState(false);
  const good = ssid.trim().length >= 2 && password.length >= 8;

  return (
    <SetupFrame progress={70} step={2}>
      <div className="wifi-setup">
        <div className="wifi-heading">
          <div className="setup-kicker">STEP 2 OF 3 • WIRELESS</div>

          <div className="wifi-icon">
            <Wifi size={27} />
          </div>

          <h1>
            Make your network
            <span> yours.</span>
          </h1>

          <p>
            Configure both wireless radios from one place.
            QuantumGrid will optimize channels automatically.
          </p>
        </div>

        <div className="wifi-grid">
          <section className="wifi-card">
            <div className="card-heading">
              <span>PRIMARY WI-FI</span>
              <Status>WI-FI 6 READY</Status>
            </div>

            <Field
              label="NETWORK NAME • 2.4 GHz + 5 GHz"
              icon={Wifi}
              value={ssid}
              placeholder="QuantumGrid"
              onChange={setSsid}
              valid={ssid.trim().length >= 2}
            />

            <label className="setup-field">
              <span>NETWORK PASSWORD</span>

              <div className={password.length >= 8 ? "input-shell valid" : "input-shell"}>
                <div className="input-icon">
                  <Lock size={17} />
                </div>

                <input
                  type={show ? "text" : "password"}
                  value={password}
                  placeholder="Create a secure Wi-Fi password"
                  onChange={(e) => setPassword(e.target.value)}
                />

                <button
                  type="button"
                  className="show-password"
                  onClick={() => setShow(!show)}
                >
                  {show ? "HIDE" : "SHOW"}
                </button>
              </div>
            </label>

            <div className="rules">
              <Rule text="2.4 GHz network" valid={ssid.trim().length >= 2} />
              <Rule text="5 GHz network" valid={ssid.trim().length >= 2} />
              <Rule text="8+ character password" valid={password.length >= 8} />
            </div>
          </section>

          <section className="wifi-card wifi-preview-card">
            <div className="wifi-halo" />

            <div className="router-visual">
              <Wifi size={31} />
            </div>

            <div className="preview-label">NETWORK PREVIEW</div>

            <strong>{ssid.trim() || "QuantumGrid"}</strong>

            <span className="secured">
              <Lock size={12} />
              WPA2 / WPA3 protected
            </span>

            <div className="radio-preview">
              <div>
                <span>2.4 GHz</span>
                <b>AX</b>
              </div>

              <div>
                <span>5 GHz</span>
                <b>AX</b>
              </div>
            </div>

            <div className="preview-message">
              <Sparkles size={14} />
              Smart channel selection and band steering ready.
            </div>
          </section>
        </div>
      </div>

      <div className="wizard-nav">
        <button className="ghost-button" onClick={back}>
          <ArrowLeft size={17} />
          Back
        </button>

        <button
          className="hero-button"
          disabled={!good}
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
  return (
    <SetupFrame progress={91} step={3}>
      <div className="wan-setup">
        <div className="wan-heading">
          <div className="setup-kicker">STEP 3 OF 3 • INTERNET</div>

          <div className="wan-icon">
            <Globe2 size={27} />
          </div>

          <h1>
            Connect QuantumGrid
            <span> to the Internet.</span>
          </h1>

          <p>
            Choose how your WAN connection receives its address.
          </p>
        </div>

        <div className="wan-options">
          {[
            ["dhcp", "Automatic DHCP", "Recommended for most connections", Globe2],
            ["pppoe", "PPPoE", "ISP username and password", Network],
            ["static", "Static IP", "Manually configured WAN", Settings],
          ].map(([id, title, description, Icon]) => (
            <button
              key={id as string}
              className={type === id ? "wan-option selected" : "wan-option"}
              onClick={() => setType(id as "dhcp" | "pppoe" | "static")}
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

        <div className="wan-ready">
          <Sparkles size={16} />
          <span>
            QuantumGrid will automatically run diagnostics after setup.
          </span>
        </div>
      </div>

      <div className="wizard-nav">
        <button className="ghost-button" onClick={back}>
          <ArrowLeft size={17} />
          Back
        </button>

        <button className="hero-button" onClick={next}>
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
    <div className="login-screen">
      <div className="atmosphere atmosphere-red" />
      <div className="atmosphere atmosphere-blue" />
      <div className="atmosphere atmosphere-purple" />
      <div className="grid-overlay" />

      <div className="login-content">
        <div className="login-logo-shell">
          <div className="login-logo-q">Q</div>
        </div>

        <div className="login-wordmark">QUANTUMGRID</div>
        <div className="login-subtitle">NETWORK OPERATING SYSTEM</div>

        <div className="login-kicker">SECURE ACCESS</div>

        <h1>
          Welcome
          <span> back.</span>
        </h1>

        <p className="login-copy">
          Sign in to your QuantumGrid command center.
        </p>

        <div className="login-fields">
          <div className="login-field">
            <div className="input-icon">
              <User size={17} />
            </div>

            <div className="login-field-inner">
              <span>USERNAME</span>
              <input value={username} readOnly />
            </div>

            <Check size={16} className="input-success" />
          </div>

          <div className="login-field">
            <div className="input-icon">
              <Lock size={17} />
            </div>

            <div className="login-field-inner">
              <span>PASSWORD</span>
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
          </div>
        </div>

        {error && showError && (
          <div className="login-error">
            <div>
              <AlertIcon />
            </div>

            <span>{error}</span>

            <button onClick={() => setShowError(false)}>
              <X size={15} />
            </button>
          </div>
        )}

        <button className="login-button" onClick={login}>
          Enter QuantumGrid
          <ArrowRight size={18} />
        </button>

        <div className="login-security">
          <Lock size={12} />
          Protected management session
        </div>
      </div>
    </div>
  );
}

function AlertIcon() {
  return (
    <span className="alert-icon">
      !
    </span>
  );
}

function Dashboard({
  stats,
  refresh,
  collapsed,
  setCollapsed,
  page,
  setPage,
}: {
  stats: Stats;
  refresh: () => void;
  collapsed: boolean;
  setCollapsed: (v: boolean) => void;
  page: Page;
  setPage: (v: Page) => void;
}) {
  const [mobile, setMobile] = useState(false);

  return (
    <div className="app-shell">
      <aside className={mobile ? "sidebar mobile-open" : "sidebar"}>
        <div className="sidebar-brand">
          <div className="brand-q">Q</div>
          {!collapsed && (
            <div>
              <strong>QUANTUMGRID</strong>
              <span>NETWORK OS</span>
            </div>
          )}

          {mobile && (
            <button className="mobile-close" onClick={() => setMobile(false)}>
              <X size={18} />
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

            <button
              className="collapse-toggle"
              onClick={() => setCollapsed(!collapsed)}
            >
              <Menu size={18} />
            </button>

            <span>QUANTUMGRID</span>
            <ChevronRight size={14} />
            <strong>{page.toUpperCase()}</strong>
          </div>

          <div className="header-right">
            <Status>SYSTEM OPTIMAL</Status>

            <button className="refresh-button" onClick={refresh}>
              <RefreshCw size={16} />
            </button>

            <div className="header-security">
              <Lock size={15} />
            </div>
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

  const [title, eyebrow, Icon] = titles[page as Exclude<Page, "dashboard">];

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
            QuantumGrid management module. Real device telemetry and
            controls will connect here through the QuantumGrid API.
          </p>
        </div>
      </section>

      <div className="module-grid">
        <Panel title="Live Status" eyebrow="QUANTUMGRID">
          <Status>MODULE ONLINE</Status>
          <div className="module-message">
            This interface is ready for the corresponding QuantumGrid
            backend service.
          </div>
        </Panel>

        <Panel title="Controls" eyebrow="MANAGEMENT">
          <div className="control-grid">
            {["Optimize", "Diagnostics", "Configure", "Inspect"].map((item) => (
              <button key={item} className="control-tile">
                <Sparkles size={17} />
                {item}
              </button>
            ))}
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

  const [username, setUsername] = useState(
    () => localStorage.getItem("quantumgrid-username") || "",
  );

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

    const timer = window.setInterval(refresh, 3000);
    return () => window.clearInterval(timer);
  }, [setupComplete, loggedIn]);

  function finishSetup() {
    localStorage.setItem("quantumgrid-setup-complete", "1");
    localStorage.setItem("quantumgrid-username", username);
    localStorage.setItem("quantumgrid-wifi-ssid", ssid);
    localStorage.setItem("quantumgrid-wan-type", wanType);

    setSetupComplete(true);
    setSetupStep("welcome");
  }

  function login() {
    const saved = localStorage.getItem("quantumgrid-username") || "";

    /*
     * Development-only credential handling.
     * Production firmware will authenticate against the router backend.
     */
    if (username === saved && loginPassword === password) {
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
        username={username}
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
      collapsed={collapsed}
      setCollapsed={setCollapsed}
      page={page}
      setPage={setPage}
    />
  );
}

export default App;
