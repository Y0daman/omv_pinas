const vscode = require("vscode")
const fs = require("fs")
const path = require("path")

function activate(context) {
  const openPreview = vscode.commands.registerCommand("omvPinasScreen.openPreview", () => {
    const cfg = vscode.workspace.getConfiguration("omvPinasScreen")
    const novncUrl = cfg.get("novncUrl", "http://127.0.0.1:6080/vnc.html")
    openPanel(context, novncUrl, false)
  })

  const openLive = vscode.commands.registerCommand("omvPinasScreen.openLivePreview", () => {
    const cfg = vscode.workspace.getConfiguration("omvPinasScreen")
    const novncUrl = cfg.get("novncUrl", "http://127.0.0.1:6080/vnc.html")
    openPanel(context, novncUrl, true)
  })

  const viewProvider = new SidebarViewProvider()
  const treeDisposable = vscode.window.registerTreeDataProvider("omvPinasScreen.sidebar", viewProvider)

  context.subscriptions.push(openPreview, openLive, treeDisposable)
}

function deactivate() {}

class SidebarViewProvider {
  constructor() {
    this._onDidChangeTreeData = new vscode.EventEmitter()
    this.onDidChangeTreeData = this._onDidChangeTreeData.event
  }

  getTreeItem(element) {
    return element
  }

  getChildren() {
    return [
      new ActionItem("Open Local Mock Preview", "omvPinasScreen.openPreview", "Open mock dashboard view"),
      new ActionItem("Open Live noVNC Preview", "omvPinasScreen.openLivePreview", "Open live screen from noVNC URL"),
    ]
  }
}

class ActionItem extends vscode.TreeItem {
  constructor(label, commandId, tooltip) {
    super(label, vscode.TreeItemCollapsibleState.None)
    this.tooltip = tooltip
    this.command = {
      command: commandId,
      title: label,
    }
    this.contextValue = "action"
  }
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/\"/g, "&quot;")
    .replace(/'/g, "&#039;")
}

function openPanel(context, novncUrl, startLive) {
  const workspaceRoots = (vscode.workspace.workspaceFolders || []).map((f) => f.uri)
  const cfg = vscode.workspace.getConfiguration("omvPinasScreen")
  const iconsPathSetting = cfg.get("iconsPath", "scripts/freenove/picture/icons")

  const panel = vscode.window.createWebviewPanel(
    "omvPinasScreenPreview",
    "OMV PiNAS Screen Preview",
    vscode.ViewColumn.One,
    {
      enableScripts: true,
      localResourceRoots: [context.extensionUri, ...workspaceRoots],
    }
  )

  const iconUris = buildIconUris(panel.webview, workspaceRoots, iconsPathSetting)

  panel.webview.html = getHtml(
    escapeHtml(novncUrl),
    startLive,
    {
      wifiGreen: escapeHtml(iconUris.wifiGreen),
      wifiYellow: escapeHtml(iconUris.wifiYellow),
      lanGreen: escapeHtml(iconUris.lanGreen),
      lanYellow: escapeHtml(iconUris.lanYellow),
      source: escapeHtml(iconUris.source || "unknown"),
    }
  )
}

function buildIconUris(webview, workspaceRoots, iconsPathSetting) {
  if (workspaceRoots.length === 0) {
    return { wifiGreen: "", wifiYellow: "", lanGreen: "", lanYellow: "", source: "fallback (no workspace)" }
  }

  function resolveIconsDir() {
    const roots = workspaceRoots.map((u) => u.fsPath)
    const configured = String(iconsPathSetting || "").trim()

    if (configured && path.isAbsolute(configured) && fs.existsSync(configured)) {
      return configured
    }

    for (const root of roots) {
      if (configured) {
        const p = path.resolve(root, configured)
        if (fs.existsSync(p)) return p
      }
    }

    for (const root of roots) {
      let cur = root
      for (let i = 0; i < 6; i++) {
        const p = path.join(cur, "scripts", "freenove", "picture", "icons")
        if (fs.existsSync(p)) return p
        const parent = path.dirname(cur)
        if (parent === cur) break
        cur = parent
      }
    }

    return ""
  }

  const iconBasePath = resolveIconsDir()
  if (!iconBasePath) {
    return { wifiGreen: "", wifiYellow: "", lanGreen: "", lanYellow: "", source: "fallback (icons dir not found)" }
  }

  function pickIconFile(candidates, matcher) {
    for (const filename of candidates) {
      const full = path.join(iconBasePath, filename)
      if (fs.existsSync(full)) return full
    }

    if (fs.existsSync(iconBasePath)) {
      const files = fs.readdirSync(iconBasePath)
      const match = files.find((f) => matcher.test(f))
      if (match) return path.join(iconBasePath, match)
    }

    return ""
  }

  function toWebviewUriWithVersion(filePath) {
    if (!filePath) return ""
    const stat = fs.statSync(filePath)
    const base = webview.asWebviewUri(vscode.Uri.file(filePath)).toString()
    return `${base}?v=${stat.mtimeMs}`
  }

  const wifiGreenIcon = pickIconFile(
    ["wifi_green.png", "wlan_green.png", "wifi.png", "wlan.png"],
    /^(wifi|wlan).*\.(png|jpg|jpeg|svg)$/i
  )

  const wifiYellowIcon = pickIconFile(
    ["wifi_yellow.png", "wlan_yellow.png", "wifi.png", "wlan.png"],
    /^(wifi|wlan).*\.(png|jpg|jpeg|svg)$/i
  )

  const lanGreenIcon = pickIconFile(
    ["lan_green.png", "ethernet_green.png", "lan.png", "ethernet.png"],
    /^(lan|ethernet).*\.(png|jpg|jpeg|svg)$/i
  )

  const lanYellowIcon = pickIconFile(
    ["lan_yellow.png", "ethernet_yellow.png", "lan.png", "ethernet.png"],
    /^(lan|ethernet).*\.(png|jpg|jpeg|svg)$/i
  )

  return {
    wifiGreen: toWebviewUriWithVersion(wifiGreenIcon),
    wifiYellow: toWebviewUriWithVersion(wifiYellowIcon),
    lanGreen: toWebviewUriWithVersion(lanGreenIcon),
    lanYellow: toWebviewUriWithVersion(lanYellowIcon),
    source: iconBasePath,
  }
}

function getHtml(novncUrl, startLive, iconUris) {
  const mode = startLive ? "live" : "mock"
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>OMV PiNAS Screen Preview</title>
  <style>
    :root { --bg:#2f2f2f; --panel:#1f1f1f; --text:#f0f0f0; --muted:#bdbdbd; --wifi:#47d16a; --lan:#f1c84c; }
    body { margin:0; font-family:"Segoe UI",sans-serif; background:var(--bg); color:var(--text); }
    .wrap { max-width:1100px; margin:0 auto; padding:16px; }
    .toolbar { display:flex; gap:8px; flex-wrap:wrap; margin-bottom:12px; align-items:center; }
    button { border:1px solid #4d4d4d; background:#242424; color:var(--text); border-radius:6px; padding:6px 10px; cursor:pointer; }
    input[type="text"] { min-width:420px; border:1px solid #4d4d4d; background:#1b1b1b; color:var(--text); border-radius:6px; padding:6px 8px; }
    .screen { background:#333; border:1px solid #454545; border-radius:10px; padding:8px; }
    .status { display:flex; align-items:center; justify-content:center; gap:8px; font-weight:700; margin-bottom:8px; min-height:24px; }
    .status .icon { width:14px; height:14px; display:inline-flex; align-items:center; justify-content:center; line-height:1; }
    .status .icon img { width:14px; height:14px; display:block; }
    .grid { display:grid; grid-template-columns:repeat(4,minmax(120px,1fr)); gap:8px; }
    .portrait .grid { grid-template-columns:repeat(2,minmax(120px,1fr)); }
    .gauge { background:var(--panel); border-radius:8px; display:grid; place-items:center; padding:8px; min-height:140px; }
    svg { overflow:visible; }
    .ring-bg { stroke:#4a4a4a; }
    .value { font-size:20px; font-weight:700; }
    .label { font-size:12px; fill:var(--muted); }
    .note { margin-top:10px; color:var(--muted); font-size:12px; }
    #liveWrap { display:none; }
    iframe { width:100%; min-height:720px; border:0; border-radius:8px; background:#111; }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="toolbar">
      <button id="modeMock">Mock Mode</button>
      <button id="modeLive">Live noVNC Mode</button>
      <button id="toggleOrientation">Toggle Portrait/Landscape</button>
      <button id="toggleLink">Cycle Link Icon</button>
      <button id="pause">Pause</button>
    </div>

    <div class="toolbar" id="liveToolbar" style="display:none;">
      <label for="novncUrl">noVNC URL</label>
      <input id="novncUrl" type="text" value="${novncUrl}" />
      <button id="openLive">Open Live Stream</button>
    </div>

    <div id="mockWrap">
      <div id="screen" class="screen portrait">
        <div id="status" class="status">
          <span id="statusIcon" class="icon"></span>
          <span id="statusText">WiFi 192.168.100.205</span>
        </div>
        <div id="grid" class="grid"></div>
      </div>
      <div class="note">Local preview with sample values. Uses PNG icons from scripts/freenove/picture/icons when available.</div>
      <div class="note" id="iconSource"></div>
    </div>

    <div id="liveWrap" class="screen">
      <iframe id="liveFrame" src="about:blank" title="Live noVNC"></iframe>
      <div class="note">Live mode embeds your noVNC URL directly.</div>
    </div>
  </div>

  <script>
    const initialMode = "${mode}";
    const wifiIconUrl = "${iconUris.wifiGreen}";
    const wifiIconYellowUrl = "${iconUris.wifiYellow}";
    const lanIconGreenUrl = "${iconUris.lanGreen}";
    const lanIconUrl = "${iconUris.lanYellow}";
    const iconSource = "${iconUris.source}";

    const metrics = [
      { key: "cpu", label: "CPU Usage", color: "#ff6b6b", value: 22, unit: "%" },
      { key: "ram", label: "RAM Usage", color: "#4ecdc4", value: 31, unit: "%" },
      { key: "cpuTemp", label: "CPU Temp", color: "#45b7d1", value: 54, unit: "°C", max: 80 },
      { key: "caseTemp", label: "Case Temp", color: "#f7dc6f", value: 36, unit: "°C", max: 80 },
      { key: "disk", label: "Storage Usage", color: "#dda0dd", value: 48, unit: "%" },
      { key: "rpiPwm", label: "RPi PWM", color: "#ffa500", value: 39, unit: "%" },
      { key: "case1", label: "Case PWM1", color: "#4eceb4", value: 55, unit: "%" },
      { key: "case2", label: "Case PWM2", color: "#eaea77", value: 55, unit: "%" }
    ];

    const wifiIconSvg = '<svg viewBox="0 0 24 24" width="14" height="14" xmlns="http://www.w3.org/2000/svg" aria-hidden="true"><path fill="currentColor" d="M2.3 8.9A15.1 15.1 0 0 1 12 5.3c3.7 0 7.1 1.3 9.7 3.6l-1.8 2A12.4 12.4 0 0 0 12 8.1c-3 0-5.7 1-7.9 2.8zm3.6 3.9A9.6 9.6 0 0 1 12 10.6c2.4 0 4.6.8 6.2 2.2l-1.8 2A6.9 6.9 0 0 0 12 13.1c-1.7 0-3.3.6-4.5 1.7zm3.6 3.9A4.1 4.1 0 0 1 12 15.8c1 0 1.9.3 2.6.9l-1.8 2a1.5 1.5 0 0 0-1.7 0z"/></svg>';
    const lanIconSvg = '<svg viewBox="0 0 24 24" width="14" height="14" xmlns="http://www.w3.org/2000/svg" aria-hidden="true"><path fill="currentColor" d="M4 3h16v10H4zm2 2v6h12V5zM9 15h2v2H8v2h3v2h2v-2h3v-2h-3v-2h-2v2H9z"/></svg>';

    const screen = document.getElementById("screen");
    const grid = document.getElementById("grid");
    const statusIcon = document.getElementById("statusIcon");
    const statusText = document.getElementById("statusText");
    const mockWrap = document.getElementById("mockWrap");
    const liveWrap = document.getElementById("liveWrap");
    const liveToolbar = document.getElementById("liveToolbar");
    const liveFrame = document.getElementById("liveFrame");
    const novncUrlInput = document.getElementById("novncUrl");

    let paused = false;
    let linkIndex = 0;

    const linkStates = [
      { key: 'wifi_green', text: 'WiFi 192.168.100.205', color: 'var(--wifi)', url: wifiIconUrl },
      { key: 'wifi_yellow', text: 'WiFi (degraded) 192.168.100.205', color: 'var(--lan)', url: wifiIconYellowUrl || wifiIconUrl },
      { key: 'lan_green', text: 'LAN 192.168.100.205', color: 'var(--wifi)', url: lanIconGreenUrl || lanIconUrl },
      { key: 'lan_yellow', text: 'LAN (degraded) 192.168.100.205', color: 'var(--lan)', url: lanIconUrl || lanIconGreenUrl },
    ];

    function clamp(v, min, max) { return Math.max(min, Math.min(max, v)); }

    function setMode(mode) {
      const isLive = mode === "live";
      mockWrap.style.display = isLive ? "none" : "block";
      liveWrap.style.display = isLive ? "block" : "none";
      liveToolbar.style.display = isLive ? "flex" : "none";
      if (isLive) {
        liveFrame.src = novncUrlInput.value || "about:blank";
      }
    }

    function makeGauge(metric) {
      const host = document.createElement("div");
      host.className = "gauge";
      host.innerHTML = '<svg width="120" height="120" viewBox="0 0 120 120" data-key="' + metric.key + '">' +
        '<circle class="ring-bg" cx="60" cy="60" r="42" stroke-width="10" fill="none"></circle>' +
        '<circle class="ring" cx="60" cy="60" r="42" stroke="' + metric.color + '" stroke-width="10" fill="none" stroke-linecap="round" transform="rotate(-90 60 60)"></circle>' +
        '<text class="value" x="60" y="62" text-anchor="middle" fill="#fff"></text>' +
        '<text class="label" x="60" y="90" text-anchor="middle">' + metric.label + '</text>' +
      '</svg>';
      grid.appendChild(host);
    }

    function renderMetric(metric) {
      const svg = grid.querySelector('svg[data-key="' + metric.key + '"]');
      if (!svg) return;
      const ring = svg.querySelector('.ring');
      const valueEl = svg.querySelector('.value');
      const max = metric.max || 100;
      const pct = clamp((metric.value / max) * 100, 0, 100);
      const r = 42;
      const c = 2 * Math.PI * r;
      ring.style.strokeDasharray = String(c);
      ring.style.strokeDashoffset = String(c * (1 - pct / 100));
      valueEl.textContent = metric.value.toFixed(0) + metric.unit;
    }

    function setIconFromUrl(url, fallbackSvg, color) {
      statusIcon.style.color = color;
      if (!url) {
        statusIcon.innerHTML = fallbackSvg;
        return;
      }
      statusIcon.innerHTML = '<img src="' + url + '" alt="" />';
      const img = statusIcon.querySelector('img');
      if (img) {
        img.onerror = () => {
          statusIcon.innerHTML = fallbackSvg;
        };
      }
    }

    function updateStatus() {
      const state = linkStates[linkIndex % linkStates.length];
      const fallback = state.key.startsWith('wifi') ? wifiIconSvg : lanIconSvg;
      setIconFromUrl(state.url, fallback, state.color);
      statusText.textContent = state.text;
    }

    function tick() {
      if (paused) return;
      for (const m of metrics) {
        const drift = (Math.random() - 0.5) * (m.max ? 2.2 : 4.0);
        m.value = clamp(m.value + drift, m.max ? 20 : 5, m.max || 100);
        renderMetric(m);
      }
    }

    function init() {
      metrics.forEach(makeGauge);
      metrics.forEach(renderMetric);
      updateStatus();
      document.getElementById('iconSource').textContent = 'Icons source: ' + iconSource;
      setInterval(tick, 1000);
      setMode(initialMode);
    }

    document.getElementById('modeMock').addEventListener('click', () => setMode('mock'));
    document.getElementById('modeLive').addEventListener('click', () => setMode('live'));
    document.getElementById('openLive').addEventListener('click', () => setMode('live'));
    document.getElementById('toggleOrientation').addEventListener('click', () => screen.classList.toggle('portrait'));
    document.getElementById('toggleLink').addEventListener('click', () => {
      linkIndex = (linkIndex + 1) % linkStates.length;
      updateStatus();
    });
    document.getElementById('pause').addEventListener('click', (e) => {
      paused = !paused;
      e.target.textContent = paused ? 'Resume' : 'Pause';
    });

    init();
  </script>
</body>
</html>`
}

module.exports = { activate, deactivate }
