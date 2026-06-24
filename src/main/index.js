const { app, BrowserWindow, BrowserView, Menu, dialog, ipcMain, shell } = require("electron");
const { execFile } = require("child_process");
const { autoUpdater } = require("electron-updater");
const path = require("path");
const fs = require("fs");
const os = require("os");
const logger = require("./logger");

const LOGIN_URL = "https://play.ekoloko.org/ekoloko/login.html";
const DISCORD_URL = "https://discord.gg/5uBSQx4yWa";
const CONTROL_BAR_HEIGHT = 100;
// Must match the bundled plugins/ DLLs. We ship CleanFlash 34.0.0.301
// (kill-switch-free) PPAPI players: the plain release build in plugins/x64
// (used by normal launches) and the content-debugger build in plugins/x64-debug
// (used only with --devtools; it writes trace()/error output to flashlog.txt
// when mm.cfg enables it — see DEBUG_MODE and ensureFlashDebugConfig).
const FLASH_VERSION = "34.0.0.301";

// DevTools is gated behind a launch flag so support can open live Chrome
// DevTools during a call (`ekoloko.exe --devtools`) without exposing it to
// normal users. Logging happens regardless of this flag.
const DEBUG_MODE =
  process.argv.includes("--devtools") || process.argv.includes("--debug");

let win;
let siteView;
let pluginName;
let osName;
let isDarkMode = false;
let darkModeCSSKey = null;

switch (process.platform) {
  case "win32":
    pluginName = process.arch == "x64" ? "x64/pepflashplayer.dll" : "x32/pepflashplayer32.dll";
    osName = "windows";
    break;
  default:
    pluginName = "x64/pepflashplayer.dll";
    break;
}

// Normal launches use the release Flash player; only --devtools/--debug loads
// the content-debugger build from the parallel "-debug" folder
// (e.g. "x64/pepflashplayer.dll" -> "x64-debug/pepflashplayer.dll").
if (DEBUG_MODE) {
  pluginName = pluginName.replace(/^(x\d+)\//, "$1-debug/");
}

// Resolve the bundled Flash plugin in both development and the packaged app.
// Packaged: electron-builder copies plugins/ via extraResources to
// <process.resourcesPath>/plugins (outside the asar). Dev: it lives at the
// repo-root plugins/ folder, relative to the compiled main in dist/main.
// (Mirrors getAssetPath() below.) The previous `__dirname + "/../plugins/"`
// resolved to a non-existent path inside the asar, so Flash failed to load.
function getPluginPath(rel) {
  const candidates = [
    path.join(process.resourcesPath || "", "plugins", rel),
    path.join(__dirname, "..", "..", "plugins", rel),
    path.join(__dirname, "..", "..", "..", "plugins", rel),
    path.join(__dirname, "..", "plugins", rel),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

const flashPluginPath = getPluginPath(pluginName);
app.commandLine.appendSwitch("ppapi-flash-path", flashPluginPath);

app.commandLine.appendSwitch("ppapi-flash-version", FLASH_VERSION);

function getAssetPath(filename) {
  const candidates = [
    path.join(process.resourcesPath || "", "assets", filename),
    path.join(__dirname, "..", "..", "assets", filename),
    path.join(__dirname, "..", "..", "..", "assets", filename),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return null;
}

function getAssetDataUrl(filename) {
  const p = getAssetPath(filename);
  if (!p) return "";
  try {
    return `data:image/png;base64,${fs.readFileSync(p).toString("base64")}`;
  } catch (e) {
    return "";
  }
}

function getAssetFontUrl(filename) {
  const p = getAssetPath(filename);
  if (!p) return "";
  try {
    return `data:font/truetype;base64,${fs.readFileSync(p).toString("base64")}`;
  } catch (e) {
    return "";
  }
}

function getControlPageHtml() {
  const logoSrc = getAssetDataUrl("3.png");
  const discordSrc = getAssetDataUrl("d-1.png");
  const fontSrc = getAssetFontUrl("Gan CLM Bold.ttf");
  return `
    <!doctype html>
    <html>
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <title>ekoloko</title>
        <style>
          ${fontSrc ? `@font-face { font-family: 'GanCLM'; src: url('${fontSrc}') format('truetype'); font-weight: bold; }` : ""}

          * { box-sizing: border-box; margin: 0; padding: 0; }

          body {
            font-family: 'GanCLM', 'Arial Rounded MT Bold', Arial, sans-serif;
            overflow: hidden;
            height: ${CONTROL_BAR_HEIGHT}px;
            background: linear-gradient(180deg, #8fd42e 0%, #6aaa1e 100%);
            border-bottom: 4px solid #4e8810;
          }

          .bar {
            height: ${CONTROL_BAR_HEIGHT}px;
            position: relative;
            display: flex;
            align-items: center;
            padding: 0 28px;
            gap: 20px;
          }

          .logo-img {
            flex-shrink: 0;
            height: 96px;
          }

          .sep {
            flex-shrink: 0;
            width: 2px;
            height: 68px;
            background: rgba(255, 255, 255, 0.3);
            border-radius: 2px;
          }

          .panel {
            flex-shrink: 0;
            background: #3a6fd8;
            border-radius: 14px;
            border: 3px solid #2a55c0;
            padding: 10px 16px 12px;
            display: flex;
            flex-direction: column;
            gap: 6px;
            min-width: 180px;
          }

          .panel-label {
            font-size: 12px;
            color: #b8cdff;
            letter-spacing: 0.08em;
            text-transform: uppercase;
          }

          .slider-row {
            display: flex;
            align-items: center;
            gap: 10px;
          }

          input[type="range"] {
            flex: 1;
            cursor: pointer;
            -webkit-appearance: none;
            appearance: none;
            height: 6px;
            border-radius: 4px;
            outline: none;
            background: linear-gradient(to right, #fb7d07 var(--fill, 100%), rgba(255,255,255,0.3) var(--fill, 100%));
          }

          input[type="range"]::-webkit-slider-thumb {
            -webkit-appearance: none;
            appearance: none;
            width: 18px;
            height: 18px;
            border-radius: 50%;
            background: #fff;
            box-shadow: 0 1px 4px rgba(0,0,0,0.4);
            cursor: pointer;
            transition: transform 0.1s;
          }

          input[type="range"]::-webkit-slider-thumb:hover { transform: scale(1.2); }
          input[type="range"]:active::-webkit-slider-thumb { transform: scale(1.3); }

          .val {
            font-size: 14px;
            color: #fff;
            min-width: 42px;
            text-align: right;
            font-variant-numeric: tabular-nums;
          }

          .btn {
            flex-shrink: 0;
            border: none;
            border-radius: 14px;
            padding: 0 26px;
            height: 52px;
            background: linear-gradient(180deg, #ff9a2a 0%, #fb7d07 100%);
            border-bottom: 4px solid #c05800;
            color: #fff;
            font-family: inherit;
            font-size: 17px;
            cursor: pointer;
            text-shadow: 1px 1px 2px rgba(0,0,0,0.3);
            transition: transform 0.1s, border-bottom-width 0.1s, filter 0.1s;
            white-space: nowrap;
          }

          .btn:hover { filter: brightness(1.08); }
          .btn:active { transform: translateY(3px); border-bottom-width: 1px; }

          .spacer { width: 10px; flex-shrink: 0; }

          .btn-icon {
            position: absolute;
            top: 6px;
            right: 10px;
            background: none;
            border: none;
            padding: 0;
            cursor: pointer;
            border-radius: 50%;
            width: 72px;
            height: 72px;
            overflow: hidden;
            display: flex;
            align-items: center;
            justify-content: center;
            transition: transform 0.1s, filter 0.1s;
          }

          .btn-icon img { width: 100%; height: 100%; object-fit: cover; border-radius: 50%; }
          .btn-icon:hover { transform: scale(1.06); filter: brightness(1.08); }
          .btn-icon:active { transform: scale(0.95); }

          body.dark {
            background: linear-gradient(180deg, #1a2744 0%, #0d1728 100%);
            border-bottom-color: #060e1c;
          }
          body.dark .panel {
            background: #0f1e3a;
            border-color: #071228;
          }
          body.dark .panel-label { color: #5a80c0; }
          body.dark .btn {
            background: linear-gradient(180deg, #1e2d50 0%, #131d38 100%);
            border-bottom-color: #060e1c;
          }
          body.dark .btn#darkModeBtn {
            background: linear-gradient(180deg, #2a3d6a 0%, #1a2848 100%);
            border-bottom-color: #060e1c;
          }
        </style>
      </head>
      <body>
        <div class="bar">
          ${logoSrc ? `<img class="logo-img" src="${logoSrc}" alt="ekoloko" />` : ""}

          <div class="panel">
            <div class="panel-label">זום</div>
            <div class="slider-row">
              <input id="zoom" type="range" min="0.5" max="2" step="0.05" value="1" />
              <div class="val" id="zoomValue">100%</div>
            </div>
          </div>

          <div class="spacer"></div>

          <button class="btn" id="muteBtn" type="button">🔊 קול</button>

          <div class="spacer"></div>

          <button class="btn" id="clearCache" type="button">🗑️ נקה מטמון</button>

          <div class="spacer"></div>

          <button class="btn" id="restartBtn" type="button">🔄 הפעל מחדש</button>

          <div class="spacer"></div>

          <button class="btn" id="saveLogsBtn" type="button">💾 שמירת לוגים</button>

          <div class="spacer"></div>

          <button class="btn" id="darkModeBtn" type="button">🌙 מצב לילה</button>

          ${discordSrc
            ? `<button class="btn-icon" id="openDiscord" type="button" title="דיסקורד"><img src="${discordSrc}" alt="דיסקורד" /></button>`
            : `<button class="btn" id="openDiscord" type="button">דיסקורד</button>`
          }
        </div>
        <script>
          const { ipcRenderer } = require("electron");

          const zoom = document.getElementById("zoom");
          const zoomValue = document.getElementById("zoomValue");
          const muteBtn = document.getElementById("muteBtn");
          const clearCache = document.getElementById("clearCache");
          const restartBtn = document.getElementById("restartBtn");
          const saveLogsBtn = document.getElementById("saveLogsBtn");
          const darkModeBtn = document.getElementById("darkModeBtn");
          const openDiscord = document.getElementById("openDiscord");
          let muted = false;
          let dark = false;

          function formatPercent(value) {
            return Math.round(Number(value) * 100) + "%";
          }

          function setSliderFill(input) {
            const min = parseFloat(input.min) || 0;
            const max = parseFloat(input.max) || 1;
            const pct = ((parseFloat(input.value) - min) / (max - min)) * 100;
            input.style.setProperty("--fill", pct + "%");
          }

          zoom.addEventListener("input", () => {
            zoomValue.textContent = formatPercent(zoom.value);
            setSliderFill(zoom);
            ipcRenderer.send("zoom-change", Number(zoom.value));
          });

          muteBtn.addEventListener("click", () => {
            muted = !muted;
            muteBtn.textContent = muted ? "🔇 מושתק" : "🔊 קול";
            muteBtn.style.background = muted ? "linear-gradient(180deg,#e05050 0%,#c03030 100%)" : "";
            muteBtn.style.borderBottomColor = muted ? "#8b0000" : "";
            ipcRenderer.send("mute-toggle", muted);
          });

          clearCache.addEventListener("click", () => {
            ipcRenderer.send("clear-cache");
            clearCache.textContent = "✓ נוקה!";
            setTimeout(() => { clearCache.textContent = "🗑️ נקה מטמון"; }, 2000);
          });

          darkModeBtn.addEventListener("click", () => {
            dark = !dark;
            document.body.classList.toggle("dark", dark);
            darkModeBtn.textContent = dark ? "☀️ מצב יום" : "🌙 מצב לילה";
            ipcRenderer.send("dark-mode-toggle", dark);
          });

          restartBtn.addEventListener("click", () => {
            ipcRenderer.send("restart");
          });

          let savingLogs = false;
          saveLogsBtn.addEventListener("click", () => {
            if (savingLogs) return;
            savingLogs = true;
            saveLogsBtn.textContent = "⏳ שומר...";
            ipcRenderer.send("save-logs");
          });

          ipcRenderer.on("save-logs-done", (_event, ok) => {
            savingLogs = false;
            saveLogsBtn.textContent = ok ? "✓ נשמר!" : "✗ שגיאה";
            setTimeout(() => { saveLogsBtn.textContent = "💾 שמירת לוגים"; }, 2500);
          });

          openDiscord.addEventListener("click", () => {
            ipcRenderer.send("open-discord");
          });

          zoomValue.textContent = formatPercent(zoom.value);
          setSliderFill(zoom);
        </script>
      </body>
    </html>
  `;
}

function setViewBounds() {
  if (!win || !siteView) {
    return;
  }

  const bounds = win.getContentBounds();
  siteView.setBounds({
    x: 0,
    y: CONTROL_BAR_HEIGHT,
    width: bounds.width,
    height: Math.max(0, bounds.height - CONTROL_BAR_HEIGHT),
  });

  siteView.setAutoResize({ width: true, height: true });
}

async function applyZoom(zoomFactor) {
  if (!siteView) return;
  await siteView.webContents.setZoomFactor(zoomFactor);
}

async function applyDarkModeCSS(isDark) {
  if (!siteView) return;
  if (darkModeCSSKey) {
    await siteView.webContents.removeInsertedCSS(darkModeCSSKey);
    darkModeCSSKey = null;
  }
  if (isDark) {
    darkModeCSSKey = await siteView.webContents.insertCSS(
      "html, body { background-color: #1c2d4a !important; }"
    );
  }
}

function applyMute(muted) {
  if (!siteView) return;
  siteView.webContents.setAudioMuted(muted);
}

function openDiscordLink() {
  shell.openExternal(DISCORD_URL);
}

// Path the debug Flash player writes trace()/ActionScript error output to.
function getFlashLogPath() {
  switch (process.platform) {
    case "win32":
      return path.join(app.getPath("appData"), "Macromedia", "Flash Player", "Logs", "flashlog.txt");
    case "darwin":
      return path.join(os.homedir(), "Library", "Preferences", "Macromedia", "Flash Player", "Logs", "flashlog.txt");
    default:
      return path.join(os.homedir(), ".macromedia", "Flash_Player", "Logs", "flashlog.txt");
  }
}

// Flash Player reads mm.cfg from the user's home directory at startup. These
// flags make the *debug* player write trace()/error output to flashlog.txt.
// SuppressDebuggerExceptionDialogs stops the debug player from popping
// ActionScript-error dialogs at end users while still logging them.
function ensureFlashDebugConfig() {
  const mmCfgPath = path.join(os.homedir(), "mm.cfg");
  const contents = [
    "ErrorReportingEnable=1",
    "TraceOutputFileEnable=1",
    "MaxWarnings=0",
    "SuppressDebuggerExceptionDialogs=1",
    "",
  ].join("\r\n");
  try {
    fs.writeFileSync(mmCfgPath, contents, "utf8");
    logger.info("flash", `wrote mm.cfg at ${mmCfgPath}`);
  } catch (e) {
    logger.warn("flash", `could not write mm.cfg: ${(e && e.message) || e}`);
  }

  // The sandboxed PPAPI Flash process can write to an existing flashlog.txt but
  // usually cannot CREATE the Logs directory tree itself. Pre-create the dir and
  // an empty, world-writable flashlog.txt so the debug player's trace()/error
  // output actually lands on disk.
  try {
    const flashLogPath = getFlashLogPath();
    fs.mkdirSync(path.dirname(flashLogPath), { recursive: true });
    if (!fs.existsSync(flashLogPath)) fs.writeFileSync(flashLogPath, "");
    logger.info("flash", `flashlog ready at ${flashLogPath}`);
  } catch (e) {
    logger.warn("flash", `could not prepare flashlog dir: ${(e && e.message) || e}`);
  }
}

// Assemble one shareable .txt (app log + flashlog) and let the user save it
// wherever they like (defaulting to the Desktop) so they can send it to us.
async function saveLogsBundle() {
  const parts = [
    logger.metadataHeader(),
    "\n\n========== APP LOG ==========\n",
    logger.getExportText(),
    "\n\n========== FLASH LOG (flashlog.txt) ==========\n",
  ];
  const flashLogPath = getFlashLogPath();
  try {
    if (fs.existsSync(flashLogPath)) {
      parts.push(fs.readFileSync(flashLogPath, "utf8"));
    } else {
      parts.push("(flashlog.txt not found — only produced by the debug Flash player)\n");
    }
  } catch (e) {
    parts.push(`(could not read flashlog.txt: ${(e && e.message) || e})\n`);
  }

  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const { canceled, filePath } = await dialog.showSaveDialog(win, {
    title: "שמירת לוגים",
    defaultPath: path.join(app.getPath("desktop"), `ekoloko-logs-${stamp}.txt`),
    filters: [{ name: "Log", extensions: ["txt"] }],
  });
  if (canceled || !filePath) {
    logger.info("save-logs", "user cancelled the save dialog");
    return false;
  }

  fs.writeFileSync(filePath, parts.join(""), "utf8");
  logger.info("save-logs", `saved logs to ${filePath}`);
  shell.showItemInFolder(filePath);
  return true;
}

// Mirror a webContents' console + lifecycle/crash events into the log file so
// the saved bundle reflects what actually happened in the game.
function attachWebContentsLogging(wc, source) {
  const levelName = (level) => ["INFO", "WARN", "ERROR", "INFO"][level] || "INFO";

  wc.on("console-message", (_e, level, message, line, sourceId) => {
    const where = sourceId ? ` (${sourceId}:${line})` : "";
    logger.info(source, `console[${levelName(level)}]: ${message}${where}`);
  });
  wc.on("did-fail-load", (_e, code, desc, url) => {
    logger.error(source, `did-fail-load ${code} ${desc} ${url || ""}`);
  });
  wc.on("did-fail-provisional-load", (_e, code, desc, url) => {
    logger.error(source, `did-fail-provisional-load ${code} ${desc} ${url || ""}`);
  });
  wc.on("dom-ready", () => logger.info(source, "dom-ready"));
  wc.on("did-finish-load", () => logger.info(source, "did-finish-load"));
  wc.on("did-navigate", (_e, url) => logger.info(source, `did-navigate ${url}`));
  // Electron 8 has no `render-process-gone` — use `crashed`.
  wc.on("crashed", (_e, killed) => logger.error(source, `renderer crashed (killed=${killed})`));
  wc.on("unresponsive", () => logger.warn(source, "unresponsive"));
  wc.on("responsive", () => logger.info(source, "responsive"));
  wc.on("plugin-crashed", (_e, name, version) =>
    logger.error(source, `plugin-crashed: ${name} ${version}`)
  );
  wc.on("certificate-error", (_e, url, error) =>
    logger.warn(source, `certificate-error ${error} ${url}`)
  );
}

// When launched with --devtools, F12 / Ctrl+Shift+I toggle the game's DevTools.
function attachDevtoolsShortcut(wc, targetWc) {
  wc.on("before-input-event", (event, input) => {
    if (input.type !== "keyDown") return;
    const isF12 = input.key === "F12";
    const isCtrlShiftI =
      input.control && input.shift && String(input.key).toLowerCase() === "i";
    if (isF12 || isCtrlShiftI) {
      if (targetWc.isDevToolsOpened()) targetWc.closeDevTools();
      else targetWc.openDevTools({ mode: "detach" });
      event.preventDefault();
    }
  });
}

function createWindow() {
  win = new BrowserWindow({
    autoHideMenuBar: true,
    backgroundColor: "#6aaa1e",
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,
      devTools: DEBUG_MODE,
      plugins: true,
    },
  });

  win.maximize();

  const controlHtmlPath = path.join(app.getPath("temp"), `ekoloko-control-${Date.now()}.html`);
  fs.writeFileSync(controlHtmlPath, getControlPageHtml(), "utf8");
  win.loadFile(controlHtmlPath);

  siteView = new BrowserView({
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      devTools: DEBUG_MODE,
      plugins: true,
      allowRunningInsecureContent: true,
    },
  });

  win.setBrowserView(siteView);
  // Paint the game view solid ekoloko green. Without this the BrowserView is
  // transparent, so while a page is navigating it briefly reveals the control
  // bar's gradient body underneath (propagated across the whole viewport),
  // which reads as a "broken" stretched gradient. Matches the window bg and
  // the light-mode value used by the dark-mode toggle below.
  siteView.setBackgroundColor("#6aaa1e");
  setViewBounds();

  attachWebContentsLogging(siteView.webContents, "game");
  attachWebContentsLogging(win.webContents, "control-bar");

  if (DEBUG_MODE) {
    logger.info("devtools", "launched with --devtools; DevTools enabled");
    attachDevtoolsShortcut(siteView.webContents, siteView.webContents);
    attachDevtoolsShortcut(win.webContents, siteView.webContents);
    siteView.webContents.once("dom-ready", () => {
      siteView.webContents.openDevTools({ mode: "detach" });
    });
  }

  siteView.webContents.loadURL(LOGIN_URL);
  siteView.webContents.setAudioMuted(false);

  siteView.webContents.on("new-window", (event, url) => {
    event.preventDefault();
    if (url === DISCORD_URL) {
      openDiscordLink();
      return;
    }
    const popup = new BrowserWindow({
      width: 1024,
      height: 768,
      autoHideMenuBar: true,
      webPreferences: {
        nodeIntegration: false,
        contextIsolation: true,
        plugins: true,
        allowRunningInsecureContent: true,
      },
    });
    popup.loadURL(url);
  });

  siteView.webContents.on("did-finish-load", () => {
    if (isDarkMode) applyDarkModeCSS(true);
  });

  win.on("resize", setViewBounds);
  win.on("closed", () => {
    win = null;
    siteView = null;
  });
}

function getUninstallerPath() {
  return path.join(path.dirname(process.execPath), `Uninstall ${app.getName()}.exe`);
}

function uninstallApp() {
  const uninstallerPath = getUninstallerPath();

  if (!fs.existsSync(uninstallerPath)) {
    dialog.showErrorBox("Uninstaller not found", `Could not find ${path.basename(uninstallerPath)}.`);
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

  if (response !== 1) {
    return;
  }

  execFile(uninstallerPath, [], {
    detached: true,
    stdio: "ignore",
  }).unref();

  app.quit();
}

function createAppMenu() {
  if (process.platform !== "win32") {
    return;
  }

  Menu.setApplicationMenu(
    Menu.buildFromTemplate([
      {
        label: "File",
        submenu: [
          {
            label: "Uninstall ekoloko",
            click: uninstallApp,
          },
          { type: "separator" },
          { role: "quit" },
          ],
      },
    ])
  );
}

function initAutoUpdater() {
  // Auto-update pulls each new GitHub Release from the public repo (see the
  // `publish` provider in package.json). Only meaningful in packaged builds.
  // macOS is skipped: the app is unsigned, and Squirrel.Mac refuses to apply
  // updates to an unsigned bundle. Windows + Linux update silently.
  if (!app.isPackaged || process.platform === "darwin") return;

  autoUpdater.autoDownload = true;
  autoUpdater.on("error", (err) => {
    // never let a failed update check disrupt the game, but record it
    logger.error("updater", (err && err.message) || String(err));
  });
  autoUpdater.on("checking-for-update", () => logger.info("updater", "checking for update"));
  autoUpdater.on("update-available", (info) =>
    logger.info("updater", `update available: ${(info && info.version) || "?"}`)
  );
  autoUpdater.on("update-not-available", () => logger.info("updater", "no update available"));

  autoUpdater.on("update-downloaded", (info) => {
    logger.info("updater", `update downloaded: ${(info && info.version) || "?"}`);
    const response = dialog.showMessageBoxSync(win, {
      type: "info",
      buttons: ["Later", "Restart now"],
      defaultId: 1,
      cancelId: 0,
      title: "Update ready",
      message: "A new version of ekoloko is ready to install.",
      detail: `Version ${info && info.version ? info.version : ""} will be applied after restart.`,
    });
    if (response === 1) {
      autoUpdater.quitAndInstall();
    }
  });

  autoUpdater.checkForUpdates().catch(() => {});
  // Re-check periodically for long-running sessions.
  setInterval(() => autoUpdater.checkForUpdates().catch(() => {}), 6 * 60 * 60 * 1000);
}

app.whenReady().then(() => {
  logger.init({ flashVersion: FLASH_VERSION });
  logger.info("app", `ekoloko starting (debugMode=${DEBUG_MODE})`);
  logger.info(
    "flash",
    `ppapi-flash v${FLASH_VERSION} path=${flashPluginPath} exists=${fs.existsSync(flashPluginPath)}`
  );

  process.on("uncaughtException", (err) => {
    logger.error("uncaughtException", (err && err.stack) || String(err));
  });
  process.on("unhandledRejection", (reason) => {
    logger.error("unhandledRejection", (reason && reason.stack) || String(reason));
  });

  // Only configure Flash trace/error logging when launched in debug mode; normal
  // users run the plain release player with no mm.cfg / flashlog side effects.
  if (DEBUG_MODE) ensureFlashDebugConfig();

  createAppMenu();
  createWindow();
  initAutoUpdater();

  ipcMain.on("zoom-change", async (_event, zoomFactor) => {
    await applyZoom(zoomFactor);
  });

  ipcMain.on("mute-toggle", (_event, muted) => {
    applyMute(muted);
  });

  ipcMain.on("restart", () => {
    app.relaunch();
    app.exit(0);
  });

  ipcMain.on("dark-mode-toggle", async (_event, isDark) => {
    isDarkMode = isDark;
    const bg = isDark ? "#1c2d4a" : "#6aaa1e";
    if (win) win.setBackgroundColor(bg);
    if (siteView) {
      siteView.setBackgroundColor(bg);
      await applyDarkModeCSS(isDark);
    }
  });

  ipcMain.on("open-discord", () => {
    openDiscordLink();
  });

  ipcMain.on("clear-cache", async () => {
    if (siteView) {
      // clearCache() only drops the HTTP cache. The game's preload_assets.js
      // stashes the SWFs in localStorage for 24h offline use, and a corrupt or
      // over-quota entry there renders a blank screen that survives restarts and
      // the old cache-only clear. Wipe the persistent stores too, then reload so
      // the page re-fetches everything fresh.
      await siteView.webContents.session.clearCache();
      await siteView.webContents.session.clearStorageData({
        storages: ["localstorage", "indexdb", "serviceworkers", "cachestorage"],
      });
      siteView.webContents.reload();
    }
  });

  ipcMain.on("save-logs", async () => {
    let ok = false;
    try {
      ok = await saveLogsBundle();
    } catch (e) {
      logger.error("save-logs", (e && e.stack) || String(e));
    }
    if (win && !win.isDestroyed()) {
      win.webContents.send("save-logs-done", ok);
    }
  });

  app.on("activate", function () {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", function () {
  if (process.platform !== "darwin") app.quit();
});
