"use strict";

// ekoloko desktop app, 2.x: a current Electron around the Phaser game.
//
// 1.x was an Electron 8 (Chrome 80) shell built for the Flash game (PPAPI Flash
// plugin). The game is HTML5 now (Phaser, cut over 2026-11-15), so this version
// drops Flash and runs a current Chromium: the game's modern code paths, a
// current GPU blocklist, current WebGL/ANGLE, security fixes.
//
// Layout (as 1.x): one window, the control bar is the window's own page
// (src/control, local, sandboxed) and the game is a WebContentsView under it.

const {
  app,
  BrowserWindow,
  WebContentsView,
  Menu,
  dialog,
  ipcMain,
  shell,
  screen,
  session,
} = require("electron");
const { execFile } = require("child_process");
const path = require("path");
const fs = require("fs");
const logger = require("./logger");
const appVolume = require("./appVolume");
const discordPresence = require("./discordPresence");
const roomNames = require("./roomNames");
const gpuPreference = require("./gpuPreference");
const cookieMigration = require("./cookieMigration");

// ---------------------------------------------------------------------------
// Where the game is
// ---------------------------------------------------------------------------

const TARGETS = {
  prod: "https://play.ekoloko.org/",
  beta: "https://playtesting.ekoloko.org/",
};

function argValue(name) {
  const prefix = `--${name}=`;
  const hit = process.argv.find((a) => a.startsWith(prefix));
  return hit ? hit.slice(prefix.length) : null;
}

const ALLOW_LOCAL = !app.isPackaged && process.env.EKOLOKO_ALLOW_LOCAL === "1";

// Only ekoloko.org (and its subdomains) over https may load inside the app.
// Everything else opens in the system browser.
function isAllowedUrl(raw) {
  let u;
  try {
    u = new URL(raw);
  } catch (e) {
    return false;
  }
  const host = u.hostname.toLowerCase();
  // Development runs only (never a packaged build): a local game build for testing.
  if (ALLOW_LOCAL && u.protocol === "http:" && (host === "127.0.0.1" || host === "localhost")) return true;
  if (u.protocol !== "https:") return false;
  return host === "ekoloko.org" || host.endsWith(".ekoloko.org");
}

// Production by default. For testing:
//   ekoloko.exe --beta                (or EKOLOKO_TARGET=beta)
//   ekoloko.exe --url=https://<x>.ekoloko.org/...   (or EKOLOKO_URL=...)
// A non-ekoloko URL is ignored (falls back to production).
function resolveGameUrl() {
  const explicit = argValue("url") || process.env.EKOLOKO_URL;
  if (explicit) {
    if (isAllowedUrl(explicit)) return { url: explicit, target: "custom" };
    console.warn(`ignoring --url ${explicit}: only https://*.ekoloko.org is allowed`);
  }
  const t = (argValue("target") || process.env.EKOLOKO_TARGET || "").toLowerCase();
  if (process.argv.includes("--beta") || t === "beta") return { url: TARGETS.beta, target: "beta" };
  return { url: TARGETS.prod, target: "prod" };
}

const GAME = resolveGameUrl();
const DISCORD_URL = "https://discord.gg/5uBSQx4yWa";

// A test target gets its own profile, so beta cookies/storage never mix with
// the production login. EKOLOKO_USER_DATA / --user-data=<dir> override it
// (used by tests so a run never touches a real profile). Before "ready".
(function chooseUserData() {
  const override = argValue("user-data") || process.env.EKOLOKO_USER_DATA;
  if (override) {
    app.setPath("userData", path.resolve(override));
  } else if (GAME.target !== "prod") {
    app.setPath("userData", path.join(app.getPath("appData"), `${app.getName()}-${GAME.target}`));
  }
})();

// Discord Rich Presence (see docs/DISCORD_PRESENCE.md). Empty = disabled.
const DISCORD_CLIENT_ID = "1529879266370523206";
const PRESENCE_BUTTON_LABEL = "להורדת המשחק";
const PRESENCE_BUTTON_DISCORD_LABEL = "הצטרפו לקהילה";
const PRESENCE_BUTTON_URL = "https://ekoloko.org/";

const CONTROL_BAR_HEIGHT = 100;
const GAME_DEFAULT_WIDTH = 960;
const GAME_DEFAULT_HEIGHT = 600;
const ZOOM_MIN = 0.5;
const ZOOM_MAX = 3;
const GREEN = "#6aaa1e";
const NIGHT = "#1c2d4a";

// DevTools: only in development runs (npm start), never in a packaged release.
const DEVTOOLS_ENABLED = !app.isPackaged;

// ---------------------------------------------------------------------------
// Settings (userData/settings.json; same file and keys as 1.x)
// ---------------------------------------------------------------------------

function getSettingsPath() {
  return path.join(app.getPath("userData"), "settings.json");
}

function readSettings() {
  try {
    return JSON.parse(fs.readFileSync(getSettingsPath(), "utf8")) || {};
  } catch (e) {
    return {};
  }
}

function saveSetting(key, value) {
  const settings = readSettings();
  settings[key] = value;
  try {
    fs.mkdirSync(path.dirname(getSettingsPath()), { recursive: true });
    fs.writeFileSync(getSettingsPath(), JSON.stringify(settings, null, 2), "utf8");
  } catch (e) {
    logger.warn("settings", `could not save settings: ${(e && e.message) || e}`);
  }
}

// ---------------------------------------------------------------------------
// Chromium switches (before "ready")
// ---------------------------------------------------------------------------

// Every renderer sandboxed (control bar, game, popups).
app.enableSandbox();

// No remote DevTools in a release: drop the Chromium debugging switches if
// someone starts the installed app with them.
if (app.isPackaged) {
  for (const s of ["remote-debugging-port", "remote-debugging-pipe", "remote-debugging-address", "remote-allow-origins"]) {
    if (app.commandLine.hasSwitch(s)) app.commandLine.removeSwitch(s);
  }
}

// Keep timers alive while minimised: Chrome's "intensive" throttling (a hidden
// page gets one timer wake-up per minute after 5 minutes) would stretch the
// game's 10 s socket heartbeat to 60 s. The normal hidden-page throttling
// (timers at most once per second, no animation frames) stays, so a minimised
// game costs almost no CPU.
app.commandLine.appendSwitch("disable-features", "IntensiveWakeUpThrottling");

// No --ignore-gpu-blocklist: 1.x forced it because Electron 8's 2020 blocklist
// was stale; this Chromium's list is current (the same as Chrome's), so the
// app gets the same GPU decisions as Chrome on that machine. Support can still
// pass Chromium switches on the command line (ekoloko.exe --ignore-gpu-blocklist).

// Windows: run on the high-performance GPU on laptops with two (Intel + NVIDIA
// / AMD), unless the player chose otherwise in Windows' graphics settings.
// See gpuPreference.js; must run before the GPU process starts.
if (process.platform === "win32") {
  gpuPreference.apply(readSettings(), saveSetting, logger);
}

// ---------------------------------------------------------------------------
// Single instance: a second launch focuses the running game
// ---------------------------------------------------------------------------

if (!app.requestSingleInstanceLock()) {
  app.quit();
  process.exit(0);
}
// The 1.x login cookies, read before Chromium opens (and empties) the old
// cookie database; put back once the session exists (cookieMigration.js).
const legacyCookies = cookieMigration.readLegacyCookies(app.getPath("userData"), logger);

app.on("second-instance", () => {
  if (!win || win.isDestroyed()) return;
  if (win.isMinimized()) win.restore();
  win.show();
  win.focus();
});

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

let win = null;
let gameView = null;
let controlBarHeight = CONTROL_BAR_HEIGHT;
let isDarkMode = false;
let darkModeCSSKey = null;

let zoomFitEnabled = true;
let manualZoom = 1;
let zoomResizeTimer = null;
let zoomSaveTimer = null;
let windowStateTimer = null;

let presenceShowDetails = false;
let presenceUsername = "";
let presenceRoom = "";
let presenceSessionStart = null;

function gameContents() {
  return gameView && !gameView.webContents.isDestroyed() ? gameView.webContents : null;
}

// ---------------------------------------------------------------------------
// Window state (position, size, maximised, fullscreen)
// ---------------------------------------------------------------------------

function boundsVisible(b) {
  if (!b || !(b.width > 200) || !(b.height > 150)) return false;
  return screen.getAllDisplays().some((d) => {
    const a = d.workArea;
    const ix = Math.min(b.x + b.width, a.x + a.width) - Math.max(b.x, a.x);
    const iy = Math.min(b.y + b.height, a.y + a.height) - Math.max(b.y, a.y);
    return ix >= 200 && iy >= 100;
  });
}

function saveWindowState() {
  if (!win || win.isDestroyed()) return;
  saveSetting("window", {
    bounds: win.getNormalBounds(),
    maximized: win.isMaximized(),
    fullscreen: win.isFullScreen(),
  });
}

function scheduleWindowStateSave() {
  if (windowStateTimer) clearTimeout(windowStateTimer);
  windowStateTimer = setTimeout(() => {
    windowStateTimer = null;
    saveWindowState();
  }, 500);
}

// ---------------------------------------------------------------------------
// Discord presence
// ---------------------------------------------------------------------------

function buildPresenceActivity() {
  const activity = {
    assets: { large_image: "cover", large_text: "ekoloko" },
    timestamps: { start: presenceSessionStart || Date.now() },
  };
  if (presenceShowDetails && presenceUsername) {
    activity.details = `משחק בתור ${presenceUsername}`;
    if (presenceRoom) {
      const friendly = roomNames[presenceRoom];
      activity.state = friendly ? `נמצא ב${friendly}` : "מסייר במפה";
    }
  } else {
    activity.details = "משחק באקולוקו";
  }
  if (PRESENCE_BUTTON_URL) {
    const url =
      presenceShowDetails && presenceUsername
        ? `${PRESENCE_BUTTON_URL}?ref=${encodeURIComponent(presenceUsername)}`
        : PRESENCE_BUTTON_URL;
    // (Discord hides the whole activity when a button names its own brand;
    // see docs/DISCORD_PRESENCE.md.)
    activity.buttons = [
      { label: PRESENCE_BUTTON_LABEL, url },
      { label: PRESENCE_BUTTON_DISCORD_LABEL, url: DISCORD_URL },
    ];
  }
  return activity;
}

function updatePresenceActivity() {
  if (!DISCORD_CLIENT_ID) return;
  if (!presenceSessionStart) presenceSessionStart = Date.now();
  discordPresence.setActivity(buildPresenceActivity());
}

// ---------------------------------------------------------------------------
// Layout and zoom (as 1.x: the game page is scaled with Chromium page zoom;
// the ekolokoGameZoom bridge is used if a page provides one)
// ---------------------------------------------------------------------------

function setViewBounds() {
  if (!win || win.isDestroyed() || !gameView) return;
  const [width, height] = win.getContentSize();
  gameView.setBounds({
    x: 0,
    y: controlBarHeight,
    width,
    height: Math.max(0, height - controlBarHeight),
  });
}

function roundZoom(zoomFactor) {
  const value = Number(zoomFactor);
  if (!isFinite(value) || value <= 0) return 1;
  return Math.round(value * 20) / 20;
}

function clampZoom(zoomFactor) {
  return Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, roundZoom(zoomFactor)));
}

async function measureGameSize() {
  const fallback = { width: GAME_DEFAULT_WIDTH, height: GAME_DEFAULT_HEIGHT, top: 0 };
  const wc = gameContents();
  if (!wc) return fallback;
  try {
    const size = await wc.executeJavaScript(`(function () {
      var el = document.getElementById("shell") || document.querySelector("object, embed");
      if (!el) return null;
      var width = el.offsetWidth || parseInt(el.getAttribute("width"), 10) || 0;
      var height = el.offsetHeight || parseInt(el.getAttribute("height"), 10) || 0;
      if (!(width > 0 && height > 0)) return null;
      var rect = el.getBoundingClientRect();
      return { width: width, height: height, top: Math.max(0, rect.top + window.pageYOffset) };
    })();`);
    if (size && size.width > 0 && size.height > 0) return size;
  } catch (e) {
    // navigating / no page yet
  }
  return fallback;
}

async function computeFitZoom() {
  if (!win || win.isDestroyed()) return clampZoom(manualZoom);
  const size = await measureGameSize();
  const [width, height] = win.getContentSize();
  const availableWidth = Math.max(1, width - 56);
  const availableHeight = Math.max(1, height - controlBarHeight - 12);
  return clampZoom(Math.min(availableWidth / size.width, availableHeight / (size.height + size.top)));
}

function sendToControl(channel, value) {
  if (win && !win.isDestroyed() && !win.webContents.isDestroyed()) win.webContents.send(channel, value);
}

function sendZoomState(zoomFactor) {
  sendToControl("zoom-changed", { zoom: zoomFactor, fit: zoomFitEnabled });
}

async function applyPageScale(fit, scale) {
  const wc = gameContents();
  if (!wc) return null;
  const js = `(function () {
    if (!window.ekolokoGameZoom) return null;
    return window.ekolokoGameZoom.apply(${fit ? "true" : "false"}, ${Number(scale) || 0});
  })();`;
  try {
    const state = await wc.executeJavaScript(js);
    if (state && Number(state.scale) > 0) return Number(state.scale);
  } catch (e) {
    // navigating / no page yet
  }
  return null;
}

async function refreshZoom() {
  if (!gameContents()) return;
  const applied = await applyPageScale(zoomFitEnabled, manualZoom);
  if (applied !== null) {
    const wc = gameContents();
    if (wc) wc.setZoomFactor(1);
    sendZoomState(roundZoom(applied));
    return;
  }
  const zoomFactor = zoomFitEnabled ? await computeFitZoom() : clampZoom(manualZoom);
  const wc = gameContents();
  if (wc) wc.setZoomFactor(zoomFactor);
  sendZoomState(zoomFactor);
}

function saveZoomPreference() {
  if (zoomSaveTimer) clearTimeout(zoomSaveTimer);
  zoomSaveTimer = setTimeout(() => {
    zoomSaveTimer = null;
    saveSetting("zoomFit", zoomFitEnabled);
    saveSetting("zoomLevel", manualZoom);
  }, 400);
}

function scheduleZoomRefresh() {
  if (!zoomFitEnabled) return;
  if (zoomResizeTimer) clearTimeout(zoomResizeTimer);
  zoomResizeTimer = setTimeout(() => {
    zoomResizeTimer = null;
    refreshZoom();
  }, 150);
}

// Night mode: only the page's own background around the game changes.
async function applyDarkModeCSS(isDark) {
  const wc = gameContents();
  if (!wc) return;
  if (darkModeCSSKey) {
    try {
      await wc.removeInsertedCSS(darkModeCSSKey);
    } catch (e) {
      /* page changed */
    }
    darkModeCSSKey = null;
  }
  if (isDark) {
    darkModeCSSKey = await wc.insertCSS(`
      html, body { background-color: ${NIGHT} !important; background-image: none !important; }
      .page-container, .game-viewport, #mainSWFDIV, .game-footer { background-color: ${NIGHT} !important; }
    `);
  }
}

// Chromium has only a boolean mute per webContents; the in-between levels are
// set on the OS mixer by appVolume (Windows WASAPI session / PulseAudio).
function applyVolume(volume) {
  const wc = gameContents();
  if (wc) wc.setAudioMuted(volume <= 0);
  appVolume.set(volume);
}

function openExternal(url) {
  try {
    const u = new URL(url);
    if (u.protocol === "https:" || u.protocol === "http:" || u.protocol === "mailto:") {
      logger.info("nav", `opening in the browser: ${u.href.slice(0, 200)}`);
      // (development test runs: log only, open nothing)
      if (!app.isPackaged && process.env.EKOLOKO_NO_EXTERNAL === "1") return;
      shell.openExternal(u.href);
      return;
    }
  } catch (e) {
    /* not a URL */
  }
  logger.warn("nav", `blocked opening ${String(url).slice(0, 200)}`);
}

// ---------------------------------------------------------------------------
// Logs
// ---------------------------------------------------------------------------

async function saveLogsBundle() {
  const text = [logger.metadataHeader(), "\n\n========== APP LOG ==========\n", logger.getExportText()].join("");
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const { canceled, filePath } = await dialog.showSaveDialog(win, {
    title: "שמירת לוגים",
    defaultPath: path.join(app.getPath("desktop"), `ekoloko-logs-${stamp}.txt`),
    filters: [{ name: "Log", extensions: ["txt"] }],
  });
  if (canceled || !filePath) return false;
  fs.writeFileSync(filePath, text, "utf8");
  logger.info("save-logs", `saved logs to ${filePath}`);
  shell.showItemInFolder(filePath);
  return true;
}

function attachWebContentsLogging(wc, source) {
  wc.on("console-message", (event) => {
    // (Electron 35+: one details object)
    const level = event.level || "info";
    if (level === "debug" || level === "verbose") return;
    const where = event.sourceId ? ` (${event.sourceId}:${event.lineNumber})` : "";
    logger.info(source, `console[${String(level).toUpperCase()}]: ${String(event.message).slice(0, 2000)}${where}`);
  });
  wc.on("did-fail-load", (_e, code, desc, url, isMainFrame) => {
    if (isMainFrame) logger.error(source, `did-fail-load ${code} ${desc} ${url || ""}`);
  });
  wc.on("did-finish-load", () => logger.info(source, "did-finish-load"));
  wc.on("did-navigate", (_e, url) => logger.info(source, `did-navigate ${url}`));
  wc.on("unresponsive", () => logger.warn(source, "unresponsive"));
  wc.on("responsive", () => logger.info(source, "responsive"));
}

function attachDevtoolsShortcut(wc, targetWc) {
  wc.on("before-input-event", (event, input) => {
    if (input.type !== "keyDown") return;
    const isF12 = input.key === "F12";
    const isCtrlShiftI = (input.control || input.meta) && input.shift && String(input.key).toLowerCase() === "i";
    if (isF12 || isCtrlShiftI) {
      if (targetWc.isDevToolsOpened()) targetWc.closeDevTools();
      else targetWc.openDevTools({ mode: "detach" });
      event.preventDefault();
    }
  });
}

// F11 toggles fullscreen from either view (the control bar's button does too).
function attachFullscreenShortcut(wc) {
  wc.on("before-input-event", (event, input) => {
    if (input.type === "keyDown" && input.key === "F11" && !input.isAutoRepeat) {
      if (win && !win.isDestroyed()) win.setFullScreen(!win.isFullScreen());
      event.preventDefault();
    }
  });
}

// ---------------------------------------------------------------------------
// Navigation policy for every webContents the app creates
// ---------------------------------------------------------------------------

const CONTROL_PAGE = path.join(__dirname, "..", "control", "index.html");

function isControlContents(wc) {
  return !!(win && !win.isDestroyed() && wc === win.webContents);
}

app.on("web-contents-created", (_event, wc) => {
  // Top-level navigation: ekoloko.org stays in the app, anything else goes to
  // the system browser. The control bar never navigates.
  const guard = (event, url) => {
    if (isControlContents(wc)) {
      event.preventDefault();
      return;
    }
    if (isAllowedUrl(url)) return;
    event.preventDefault();
    openExternal(url);
  };
  wc.on("will-navigate", (event) => {
    if (event.isMainFrame === false) return;
    guard(event, event.url);
  });
  wc.on("will-redirect", (event) => {
    if (event.isMainFrame === false) return;
    guard(event, event.url);
  });

  // window.open / target=_blank: ekoloko.org pages open in a small in-app
  // window (the game's info pages, as 1.x), everything else in the browser.
  wc.setWindowOpenHandler(({ url }) => {
    if (url === DISCORD_URL || !isAllowedUrl(url) || isControlContents(wc)) {
      openExternal(url);
      return { action: "deny" };
    }
    return {
      action: "allow",
      overrideBrowserWindowOptions: {
        width: 1024,
        height: 768,
        autoHideMenuBar: true,
        backgroundColor: "#ffffff",
        webPreferences: {
          sandbox: true,
          contextIsolation: true,
          nodeIntegration: false,
          devTools: DEVTOOLS_ENABLED,
          spellcheck: false,
        },
      },
    };
  });

  wc.on("will-attach-webview", (event) => event.preventDefault());
});

// Permissions: the game needs none of camera / mic / location / notifications.
function setupPermissions(ses) {
  const allowed = new Set(["fullscreen", "clipboard-sanitized-write", "pointerLock", "keyboardLock"]);
  ses.setPermissionRequestHandler((wc, permission, callback, details) => {
    const origin = (details && details.requestingUrl) || (wc && wc.getURL()) || "";
    callback(allowed.has(permission) && isAllowedUrl(origin));
  });
  ses.setPermissionCheckHandler((_wc, permission, requestingOrigin) => {
    return allowed.has(permission) && isAllowedUrl(requestingOrigin);
  });
}

// ---------------------------------------------------------------------------
// Window
// ---------------------------------------------------------------------------

function createWindow() {
  const saved = readSettings().window || {};
  const bounds = boundsVisible(saved.bounds) ? saved.bounds : null;

  win = new BrowserWindow({
    ...(bounds || { width: 1280, height: 800 }),
    minWidth: 640,
    minHeight: 480,
    autoHideMenuBar: true,
    backgroundColor: GREEN,
    show: false,
    title: "ekoloko",
    icon: process.platform === "linux" ? path.join(__dirname, "..", "..", "build", "icon.png") : undefined,
    webPreferences: {
      preload: path.join(__dirname, "preloads", "control.js"),
      sandbox: true,
      contextIsolation: true,
      nodeIntegration: false,
      devTools: DEVTOOLS_ENABLED,
      spellcheck: false,
    },
  });

  // First run (no saved state) opens maximised, as 1.x always did.
  win.once("ready-to-show", () => {
    if (!bounds || saved.maximized !== false) win.maximize();
    win.show();
    if (saved.fullscreen) win.setFullScreen(true);
  });

  win.loadFile(CONTROL_PAGE);

  gameView = new WebContentsView({
    webPreferences: {
      preload: path.join(__dirname, "preloads", "game.js"),
      sandbox: true,
      contextIsolation: true,
      nodeIntegration: false,
      devTools: DEVTOOLS_ENABLED,
      spellcheck: false,
      // Default (true): a minimised or fully covered window stops drawing and
      // its timers slow to once a second, as in a browser tab; the socket's
      // 10 s heartbeat survives that (intensive throttling is off, above).
      backgroundThrottling: true,
      additionalArguments: [`--ekoloko-app-version=${app.getVersion()}`],
    },
  });
  gameView.setBackgroundColor(GREEN);
  win.contentView.addChildView(gameView);
  setViewBounds();

  const wc = gameView.webContents;
  attachWebContentsLogging(wc, "game");
  attachWebContentsLogging(win.webContents, "control-bar");
  attachFullscreenShortcut(wc);
  attachFullscreenShortcut(win.webContents);
  if (DEVTOOLS_ENABLED) {
    attachDevtoolsShortcut(wc, wc);
    attachDevtoolsShortcut(win.webContents, wc);
  }

  wc.on("render-process-gone", (_e, details) => {
    logger.error("game", `renderer gone: ${details.reason} (exit ${details.exitCode})`);
    // A crash / out-of-memory: bring the game back instead of a dead view.
    if (details.reason !== "clean-exit" && details.reason !== "killed") {
      setTimeout(() => {
        const g = gameContents();
        if (g) g.loadURL(GAME.url);
      }, 1000);
    }
  });

  wc.on("did-finish-load", () => {
    // Chromium remembers the zoom per origin; set it after every load.
    refreshZoom();
    if (isDarkMode) applyDarkModeCSS(true);
  });

  wc.loadURL(GAME.url);

  win.on("resize", () => {
    setViewBounds();
    scheduleZoomRefresh();
    scheduleWindowStateSave();
  });
  win.on("move", scheduleWindowStateSave);
  win.on("maximize", () => {
    setViewBounds();
    refreshZoom();
    scheduleWindowStateSave();
  });
  win.on("unmaximize", scheduleWindowStateSave);
  win.on("enter-full-screen", () => {
    sendToControl("fullscreen-changed", true);
    setViewBounds();
    scheduleZoomRefresh();
    scheduleWindowStateSave();
  });
  win.on("leave-full-screen", () => {
    sendToControl("fullscreen-changed", false);
    setViewBounds();
    scheduleZoomRefresh();
    scheduleWindowStateSave();
  });
  win.on("close", () => {
    if (windowStateTimer) clearTimeout(windowStateTimer);
    windowStateTimer = null;
    saveWindowState();
  });
  win.on("closed", () => {
    win = null;
    gameView = null;
    if (zoomResizeTimer) clearTimeout(zoomResizeTimer);
    zoomResizeTimer = null;
    if (zoomSaveTimer) {
      clearTimeout(zoomSaveTimer);
      zoomSaveTimer = null;
      saveSetting("zoomFit", zoomFitEnabled);
      saveSetting("zoomLevel", manualZoom);
    }
  });
}

// ---------------------------------------------------------------------------
// Menu (Windows: File > Uninstall, as 1.x)
// ---------------------------------------------------------------------------

function uninstallApp() {
  const dir = path.dirname(process.execPath);
  const target = [`Uninstall ${app.getName()}.exe`, "Uninstall ekoloko.exe"]
    .map((f) => path.join(dir, f))
    .find((p) => fs.existsSync(p));
  if (!target) {
    dialog.showErrorBox("Uninstaller not found", "Could not find the ekoloko uninstaller.");
    return;
  }
  const response = dialog.showMessageBoxSync(win, {
    type: "warning",
    buttons: ["Cancel", "Uninstall"],
    defaultId: 1,
    cancelId: 0,
    title: "Uninstall ekoloko",
    message: "This will remove ekoloko from your computer.",
    detail: "The app will close and launch the Windows uninstaller.",
  });
  if (response !== 1) return;
  execFile(target, [], { detached: true, stdio: "ignore" }).unref();
  app.quit();
}

function createAppMenu() {
  if (process.platform === "darwin") {
    // macOS needs an app menu for Cmd+Q / copy / paste.
    Menu.setApplicationMenu(Menu.buildFromTemplate([{ role: "appMenu" }, { role: "editMenu" }, { role: "windowMenu" }]));
    return;
  }
  if (process.platform !== "win32") {
    Menu.setApplicationMenu(null);
    return;
  }
  Menu.setApplicationMenu(
    Menu.buildFromTemplate([
      {
        label: "File",
        submenu: [{ label: "Uninstall ekoloko", click: uninstallApp }, { type: "separator" }, { role: "quit" }],
      },
    ])
  );
}

// ---------------------------------------------------------------------------
// Auto-update (electron-updater, GitHub Releases of ekolokonet/ekoloko-desktop-app)
// ---------------------------------------------------------------------------

function initAutoUpdater() {
  // Packaged Windows / Linux builds only. macOS: Squirrel.Mac only applies
  // updates to a signed app, and the mac build is unsigned.
  if (!app.isPackaged || process.platform === "darwin") return;
  if (GAME.target !== "prod" || process.env.EKOLOKO_NO_UPDATE === "1") {
    logger.info("updater", "skipped (test target or EKOLOKO_NO_UPDATE=1)");
    return;
  }
  let autoUpdater;
  try {
    ({ autoUpdater } = require("electron-updater"));
  } catch (e) {
    logger.error("updater", `electron-updater missing: ${(e && e.message) || e}`);
    return;
  }
  autoUpdater.logger = {
    info: (m) => logger.info("updater", String(m)),
    warn: (m) => logger.warn("updater", String(m)),
    error: (m) => logger.error("updater", String(m)),
    debug: () => {},
  };
  autoUpdater.autoDownload = true;
  // A downloaded update also installs by itself when the player closes the app.
  autoUpdater.autoInstallOnAppQuit = true;
  autoUpdater.on("error", (err) => logger.error("updater", (err && err.message) || String(err)));
  autoUpdater.on("update-downloaded", (info) => {
    const version = (info && info.version) || "";
    logger.info("updater", `update downloaded: ${version}`);
    if (!win || win.isDestroyed()) return;
    dialog
      .showMessageBox(win, {
        type: "info",
        buttons: ["אחר כך", "הפעלה מחדש עכשיו"],
        defaultId: 1,
        cancelId: 0,
        title: "עדכון מוכן",
        message: "גרסה חדשה של אקולוקו מוכנה להתקנה.",
        detail: `גרסה ${version} תותקן בהפעלה מחדש (או כשסוגרים את המשחק).`,
      })
      .then(({ response }) => {
        if (response === 1) autoUpdater.quitAndInstall(true, true);
      })
      .catch(() => {});
  });
  autoUpdater.checkForUpdates().catch(() => {});
  setInterval(() => autoUpdater.checkForUpdates().catch(() => {}), 6 * 60 * 60 * 1000);
}

// ---------------------------------------------------------------------------
// IPC (control bar and game view; every handler checks who is asking)
// ---------------------------------------------------------------------------

function fromControl(event) {
  return isControlContents(event.sender);
}

function fromGame(event) {
  return !!(gameView && event.sender === gameView.webContents);
}

function registerIpc() {
  const onControl = (channel, handler) =>
    ipcMain.on(channel, (event, value) => {
      if (!fromControl(event)) return;
      handler(value);
    });

  ipcMain.handle("control-init", (event) => {
    if (!fromControl(event)) return null;
    return {
      zoom: manualZoom,
      zoomFit: zoomFitEnabled,
      presenceEnabled: !!DISCORD_CLIENT_ID,
      presenceShowDetails,
      isFullScreen: !!(win && win.isFullScreen()),
      target: GAME.target,
    };
  });

  onControl("toggle-fullscreen", () => {
    if (win) win.setFullScreen(!win.isFullScreen());
  });

  onControl("control-bar-height", (height) => {
    const h = Math.round(Number(height));
    if (!isFinite(h) || h <= 0 || h > 400 || h === controlBarHeight) return;
    controlBarHeight = h;
    setViewBounds();
    scheduleZoomRefresh();
  });

  onControl("zoom-change", (zoomFactor) => {
    zoomFitEnabled = false;
    manualZoom = clampZoom(zoomFactor);
    saveZoomPreference();
    refreshZoom();
  });

  onControl("zoom-fit", () => {
    zoomFitEnabled = true;
    saveZoomPreference();
    refreshZoom();
  });

  onControl("zoom-request", () => refreshZoom());

  onControl("volume-change", (volume) => {
    const v = Number(volume);
    if (isFinite(v)) applyVolume(Math.min(1, Math.max(0, v)));
  });

  onControl("restart", () => {
    app.relaunch();
    app.exit(0);
  });

  onControl("dark-mode-toggle", async (isDark) => {
    isDarkMode = isDark === true;
    const bg = isDarkMode ? NIGHT : GREEN;
    if (win) win.setBackgroundColor(bg);
    if (gameView) {
      gameView.setBackgroundColor(bg);
      await applyDarkModeCSS(isDarkMode);
    }
  });

  onControl("open-discord", () => openExternal(DISCORD_URL));

  onControl("presence-details-toggle", (show) => {
    presenceShowDetails = show === true;
    saveSetting("presenceShowDetails", presenceShowDetails);
    updatePresenceActivity();
  });

  onControl("clear-cache", async () => {
    const wc = gameContents();
    if (!wc) return;
    // HTTP cache plus the page's own stores; cookies (the login) stay.
    await wc.session.clearCache();
    await wc.session.clearStorageData({
      storages: ["localstorage", "indexdb", "serviceworkers", "cachestorage", "shadercache"],
    });
    wc.reload();
  });

  onControl("save-logs", async () => {
    let ok = false;
    try {
      ok = await saveLogsBundle();
    } catch (e) {
      logger.error("save-logs", (e && e.stack) || String(e));
    }
    sendToControl("save-logs-done", ok);
  });

  ipcMain.on("presence-update", (event, data) => {
    if (!fromGame(event) || !data || typeof data !== "object") return;
    const reportedUsername = typeof data.username === "string" ? data.username.slice(0, 64) : "";
    if (reportedUsername) presenceUsername = reportedUsername;
    presenceRoom = typeof data.room === "string" ? data.room.slice(0, 100) : "";
    updatePresenceActivity();
  });

  ipcMain.on("presence-clear", (event) => {
    if (!fromGame(event)) return;
    presenceUsername = "";
    presenceRoom = "";
    updatePresenceActivity();
  });
}

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

app.whenReady().then(async () => {
  logger.init();
  logger.info("app", `ekoloko ${app.getVersion()} starting: target=${GAME.target} url=${GAME.url} packaged=${app.isPackaged} userData=${app.getPath("userData")}`);

  process.on("uncaughtException", (err) => logger.error("uncaughtException", (err && err.stack) || String(err)));
  process.on("unhandledRejection", (reason) => logger.error("unhandledRejection", (reason && reason.stack) || String(reason)));

  const settings = readSettings();
  presenceShowDetails = settings.presenceShowDetails === true;
  zoomFitEnabled = settings.zoomFit !== false;
  manualZoom = clampZoom(settings.zoomLevel !== undefined ? settings.zoomLevel : 1);

  setupPermissions(session.defaultSession);
  await cookieMigration.restoreCookies(session.defaultSession, legacyCookies, logger);
  registerIpc();
  createAppMenu();
  createWindow();
  initAutoUpdater();

  if (DISCORD_CLIENT_ID) {
    discordPresence.init(DISCORD_CLIENT_ID, logger);
    updatePresenceActivity();
  }

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });

  // Which GPU Chromium really uses (and whether it is hardware accelerated).
  try {
    const info = await app.getGPUInfo("complete");
    const devices = info.gpuDevice || [];
    const active = devices.find((d) => d.active) || devices[0] || {};
    logger.info(
      "gpu",
      `active vendor=0x${Number(active.vendorId || 0).toString(16)} device=0x${Number(active.deviceId || 0).toString(16)} ` +
        `driver=${active.driverVersion || "?"} adapters=${devices.length} ` +
        `renderer=${(info.auxAttributes && info.auxAttributes.glRenderer) || "?"}`
    );
    const status = app.getGPUFeatureStatus();
    logger.info("gpu", `features ${JSON.stringify(status)}`);
  } catch (e) {
    logger.warn("gpu", `could not read GPU info: ${(e && e.message) || e}`);
  }
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});

app.on("will-quit", () => {
  appVolume.dispose();
  discordPresence.dispose();
});
