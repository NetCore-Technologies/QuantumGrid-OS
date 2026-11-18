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
}

export interface RouterWirelessRadio {
  name: string;
  up: boolean;
  interfaces: RouterWirelessInterface[];
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
  wireless: RouterWirelessRadio[];
  cellular: { modem_present: boolean };
  phone: {
    service_installed: boolean;
    enabled: boolean;
    patch_installed: boolean;
  };
}

const API_URL = "/cgi-bin/luci/admin/services/quantumgrid/api";

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

export async function loginToRouter(
  username: string,
  password: string,
): Promise<RouterOverview> {
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

export async function fetchRouterOverview(): Promise<RouterOverview> {
  const response = await fetch(API_URL, {
    method: "GET",
    credentials: "same-origin",
    cache: "no-store",
    headers: { Accept: "application/json" },
  });

  return decodeOverview(response);
}
