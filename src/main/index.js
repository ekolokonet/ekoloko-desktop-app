const { app, BrowserWindow, BrowserView, Menu, dialog, ipcMain, shell } = require("electron");
const { execFile } = require("child_process");
const { autoUpdater } = require("electron-updater");
const path = require("path");
const fs = require("fs");
const os = require("os");
const logger = require("./logger");
const appVolume = require("./appVolume");
const discordPresence = require("./discordPresence");
const roomNames = require("./roomNames");

// const LOGIN_URL = "https://ekobeta.arnon001.com/ekoloko/login.html";
const LOGIN_URL = "https://play.ekoloko.org/ekoloko/login.html";
const DISCORD_URL = "https://discord.gg/5uBSQx4yWa";

// Discord application id for Rich Presence, from the Discord Developer Portal
// (https://discord.com/developers/applications -> New Application -> copy the
// "Application ID"). Empty string keeps the whole presence feature disabled.
// See docs/DISCORD_PRESENCE.md for setup + the art asset keys.
const DISCORD_CLIENT_ID = "1529879266370523206";
const CONTROL_BAR_HEIGHT = 100;

// Must match the bundled plugins/ DLLs. We ship CleanFlash 34.0.0.301
// (kill-switch-free) PPAPI players: the plain release build in plugins/x64
// (used by normal launches) and the content-debugger build in plugins/x64-debug
// (used only with --devtools; it writes trace()/error output to flashlog.txt
// when mm.cfg enables it — see DEBUG_MODE and ensureFlashDebugConfig).
const FLASH_VERSION =
  process.platform === "darwin"
    ? "32.0.0.371"
    : process.platform === "linux"
    ? "34.0.0.137"
    : "34.0.0.301";



// DevTools is gated behind a launch flag so support can open live Chrome
// DevTools during a call (`ekoloko.exe --devtools`) without exposing it to
// normal users. Logging happens regardless of this flag.
const DEBUG_MODE =
  process.argv.includes("--devtools") || process.argv.includes("--debug");

// DevTools itself (plus the F12 / Ctrl+Shift+I toggle) is also always
// available in dev runs, without the flag's other side effects (debug Flash
// player, mm.cfg, auto-open).
const DEVTOOLS_ENABLED = DEBUG_MODE || !app.isPackaged;

let win;
let siteView;
let pluginName;
let osName;
let isDarkMode = false;
let darkModeCSSKey = null;

// Discord Rich Presence state. The privacy switch defaults to OFF so a fresh
// install never broadcasts a kid's username/in-game location — with it off the
// presence is just "playing ekoloko". The game page reports username/room via
// the presence preload bridge (see getPresencePreloadJs).
let presenceShowDetails = false;
let presenceUsername = "";
let presenceRoom = "";
let presenceSessionStart = null;

// Tiny persisted settings file (userData/settings.json). Only the presence
// privacy switch lives here for now; unknown keys are preserved.
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
    fs.writeFileSync(getSettingsPath(), JSON.stringify(settings, null, 2), "utf8");
  } catch (e) {
    logger.warn("settings", `could not save settings: ${(e && e.message) || e}`);
  }
}

switch (process.platform) {
  case "win32":
    pluginName = process.arch == "x64" ? "x64/pepflashplayer.dll" : "x32/pepflashplayer32.dll";
    osName = "windows";
    break;
  case "darwin":
    pluginName = "mac/PepperFlashPlayer.plugin";
    osName = "mac";
    break;
  case "linux":
    pluginName = "linux/libpepflashplayer.so";
    osName = "linux";
    break;
  default:
    pluginName = "linux/libpepflashplayer.so";
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

// Flash (PPAPI) renders into a texture composited by Chromium's GPU process.
// Electron 8 ships a 2020-era GPU blocklist; on newer Windows builds/drivers it
// readily blacklists the GPU and falls back to software (SwiftShader)
// compositing, which makes Flash playable but FPS-laggy — while standalone
// Chrome on the same machine keeps hardware acceleration and runs smooth.
// Force GPU acceleration on regardless of the stale blocklist. (Both spellings:
// Chrome renamed "blacklist" -> "blocklist"; harmless to pass the unused one.)
app.commandLine.appendSwitch("ignore-gpu-blocklist");
app.commandLine.appendSwitch("ignore-gpu-blacklist");
app.commandLine.appendSwitch("enable-gpu-rasterization");

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

// Preload for the game BrowserView. The site is remote and untrusted, so it
// only gets a single, narrow, validated bridge: window.electronPresence. The
// game page (login.html defines window.ekolokoPresence, which the SWF calls
// via ExternalInterface on login/room changes) pushes {username, room} here.
// Like the control page, this is written to a temp file at startup because
// electron-webpack bundles src/main into one file and a preload must be a
// real file on disk.
function getPresencePreloadJs() {
  return `
    const { contextBridge, ipcRenderer } = require("electron");

    function cleanString(value, maxLength) {
      if (typeof value !== "string") return "";
      // strip control characters, collapse whitespace, cap length
      return value.replace(/[\\u0000-\\u001f\\u007f]/g, "").replace(/\\s+/g, " ").trim().slice(0, maxLength);
    }

    contextBridge.exposeInMainWorld("electronPresence", {
      update(data) {
        if (!data || typeof data !== "object") return;
        ipcRenderer.send("presence-update", {
          username: cleanString(data.username, 64),
          room: cleanString(data.room, 100),
        });
      },
      clear() {
        ipcRenderer.send("presence-clear");
      },
    });
  `;
}

// Discord activity text is Hebrew to match the game. "details" is the top
// line, "state" the second. Discord caps both at 128 chars — the preload
// already caps the inputs well below that.
function buildPresenceActivity() {
  const activity = {
    assets: { large_image: "cover", large_text: "ekoloko" },
    timestamps: { start: presenceSessionStart || Date.now() },
  };
  if (presenceShowDetails && presenceUsername) {
    activity.details = `משחק בתור ${presenceUsername}`;
    if (presenceRoom) {
      // The game reports the SFS room name (usually a numeric id); map it to the
      // Hebrew display name where known. Unmapped rooms (house instances,
      // minigames) show a generic "exploring the map" line instead of a raw id.
      const friendly = roomNames[presenceRoom];
      activity.state = friendly ? `נמצא ב${friendly}` : "מסייר במפה";
    }
  } else {
    activity.details = "משחק באקולוקו";
  }
  return activity;
}

function updatePresenceActivity() {
  if (!DISCORD_CLIENT_ID) return;
  if (!presenceSessionStart) presenceSessionStart = Date.now();
  discordPresence.setActivity(buildPresenceActivity());
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
            /* Panels give up width first (buttons are flex-shrink: 0) so the
               bar still fits everything on 1366px-wide laptop screens. */
            flex-shrink: 1;
            background: #3a6fd8;
            border-radius: 14px;
            border: 3px solid #2a55c0;
            padding: 10px 16px 12px;
            display: flex;
            flex-direction: column;
            gap: 6px;
            min-width: 140px;
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
            /* Allow the track to compress below its ~129px intrinsic width,
               otherwise a shrunk panel overflows instead of narrowing. */
            min-width: 56px;
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

          /* Push the fullscreen button to the far right of the bar. The reserved
             right margin clears the absolutely-positioned Discord icon. */
          .btn-fullscreen { margin-left: auto; margin-right: ${discordSrc ? "84px" : "0"}; }

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
            <div class="panel-label" id="volumeLabel">🔊 עוצמת קול</div>
            <div class="slider-row">
              <input id="volume" type="range" min="0" max="1" step="0.01" value="1" />
              <div class="val" id="volumeValue">100%</div>
            </div>
          </div>

          <div class="spacer"></div>

          <button class="btn" id="clearCache" type="button">🗑️ נקה מטמון</button>

          <div class="spacer"></div>

          <button class="btn" id="restartBtn" type="button">🔄 הפעל מחדש</button>

          <div class="spacer"></div>

          <button class="btn" id="saveLogsBtn" type="button">💾 שמירת לוגים</button>

          <div class="spacer"></div>

          <button class="btn" id="darkModeBtn" type="button">🌙 מצב לילה</button>

          ${DISCORD_CLIENT_ID
            ? `<div class="spacer"></div>

          <button class="btn" id="presenceBtn" type="button" title="מה חברים רואים בדיסקורד: שם ומיקום במשחק, או אנונימי">${presenceShowDetails ? "🎮 דיסקורד: שם ומיקום" : "🔒 דיסקורד: אנונימי"}</button>`
            : ""}

          <button class="btn btn-fullscreen" id="fullscreenBtn" type="button">⛶ מסך מלא</button>

          ${discordSrc
            ? `<button class="btn-icon" id="openDiscord" type="button" title="דיסקורד"><img src="${discordSrc}" alt="דיסקורד" /></button>`
            : `<button class="btn" id="openDiscord" type="button">דיסקורד</button>`
          }
        </div>
        <script>
          const { ipcRenderer } = require("electron");

          const fullscreenBtn = document.getElementById("fullscreenBtn");
          const volume = document.getElementById("volume");
          const volumeValue = document.getElementById("volumeValue");
          const volumeLabel = document.getElementById("volumeLabel");
          const clearCache = document.getElementById("clearCache");
          const restartBtn = document.getElementById("restartBtn");
          const saveLogsBtn = document.getElementById("saveLogsBtn");
          const darkModeBtn = document.getElementById("darkModeBtn");
          const openDiscord = document.getElementById("openDiscord");
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

          fullscreenBtn.addEventListener("click", () => {
            ipcRenderer.send("toggle-fullscreen");
          });

          ipcRenderer.on("fullscreen-changed", (_event, isFull) => {
            fullscreenBtn.textContent = isFull ? "🗗 יציאה ממסך מלא" : "⛶ מסך מלא";
          });

          function updateVolumeUI() {
            const v = Number(volume.value);
            volumeValue.textContent = formatPercent(volume.value);
            setSliderFill(volume);
            volumeLabel.textContent = (v === 0 ? "🔇" : v < 0.5 ? "🔉" : "🔊") + " עוצמת קול";
          }

          volume.addEventListener("input", () => {
            updateVolumeUI();
            ipcRenderer.send("volume-change", Number(volume.value));
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

          const presenceBtn = document.getElementById("presenceBtn");
          if (presenceBtn) {
            let presenceDetails = ${presenceShowDetails ? "true" : "false"};
            presenceBtn.addEventListener("click", () => {
              presenceDetails = !presenceDetails;
              presenceBtn.textContent = presenceDetails ? "🎮 דיסקורד: שם ומיקום" : "🔒 דיסקורד: אנונימי";
              ipcRenderer.send("presence-details-toggle", presenceDetails);
            });
          }

          updateVolumeUI();
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

// Chromium only exposes a boolean mute per webContents and the game's sound
// comes from the Flash plugin (no HTML5 media to script a volume onto), so
// the in-between range is applied at the OS mixer level by appVolume. The
// hard mute here guarantees 0% is silent on every platform, including macOS
// where no per-app OS volume API exists.
function applyVolume(volume) {
  if (siteView) siteView.webContents.setAudioMuted(volume <= 0);
  appVolume.set(volume);
}

function openDiscordLink() {
  shell.openExternal(DISCORD_URL);
}

// ---- TEMP dev-only debug overlay -------------------------------------------
// Draws a small live log box over the game view so presence flow can be watched
// without DevTools: game console lines, presence IPC arrivals, Discord RPC
// state, and each SET_ACTIVITY actually sent. Active only when DevTools are
// enabled (dev runs / --devtools); packaged release builds never show it.
// Remove once the Discord presence feature is verified.
function getDebugOverlayJs() {
  return `
    (function () {
      if (window.__ekoDebugLog) return;
      var box = document.createElement("div");
      box.style.cssText = "position:fixed;top:8px;left:8px;z-index:2147483647;" +
        "background:rgba(0,0,0,0.78);color:#8f8;font:11px/1.5 Menlo,Consolas,monospace;" +
        "padding:6px 10px;border-radius:6px;max-width:62vw;pointer-events:none;" +
        "white-space:pre-wrap;word-break:break-all;direction:ltr;text-align:left";
      (document.body || document.documentElement).appendChild(box);
      var lines = [];
      window.__ekoDebugLog = function (line) {
        lines.push(new Date().toISOString().slice(11, 19) + " " + line);
        if (lines.length > 14) lines.shift();
        box.textContent = lines.join("\\n");
      };
      window.__ekoDebugLog("debug overlay ready");
    })();
  `;
}

function pushDebug(line) {
  if (!DEVTOOLS_ENABLED || !siteView) return;
  try {
    siteView.webContents
      .executeJavaScript(`window.__ekoDebugLog && window.__ekoDebugLog(${JSON.stringify(String(line))})`)
      .catch(() => {});
  } catch (e) {
    /* ignore */
  }
}

// Logger passthrough that also mirrors lines onto the overlay; handed to
// discordPresence so its connect/SET_ACTIVITY lines show up on screen.
const overlayLogger = {
  info(tag, msg) {
    logger.info(tag, msg);
    pushDebug(`[${tag}] ${msg}`);
  },
  warn(tag, msg) {
    logger.warn(tag, msg);
    pushDebug(`[${tag}] WARN ${msg}`);
  },
  error(tag, msg) {
    logger.error(tag, msg);
    pushDebug(`[${tag}] ERROR ${msg}`);
  },
};
// ---- end TEMP debug overlay ------------------------------------------------

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
    // TEMP debug overlay: echo the game's console onto the on-screen box.
    if (source === "game") pushDebug(`console: ${String(message).slice(0, 160)}`);
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

// F12 / Ctrl+Shift+I / Cmd+Shift+I (macOS) toggle the game's DevTools.
// (Cmd+Shift+I, not Cmd+Alt+I: macOS's default menu already owns Alt+Cmd+I and
// menu accelerators win over before-input-event, but they target the focused
// window — usually the control bar — instead of the game view.)
function attachDevtoolsShortcut(wc, targetWc) {
  wc.on("before-input-event", (event, input) => {
    if (input.type !== "keyDown") return;
    const isF12 = input.key === "F12";
    const isCtrlShiftI =
      (input.control || input.meta) && input.shift && String(input.key).toLowerCase() === "i";
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
      devTools: DEVTOOLS_ENABLED,
      plugins: true,
    },
  });

  win.maximize();

  const controlHtmlPath = path.join(app.getPath("temp"), `ekoloko-control-${Date.now()}.html`);
  fs.writeFileSync(controlHtmlPath, getControlPageHtml(), "utf8");
  win.loadFile(controlHtmlPath);

  const presencePreloadPath = path.join(app.getPath("temp"), `ekoloko-presence-preload-${Date.now()}.js`);
  fs.writeFileSync(presencePreloadPath, getPresencePreloadJs(), "utf8");

  siteView = new BrowserView({
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      devTools: DEVTOOLS_ENABLED,
      plugins: true,
      preload: presencePreloadPath,
      allowRunningInsecureContent: true,
      // The control bar is a separate view, so the game view can lose focus
      // while the user is playing. Without this, Chromium throttles the blurred
      // webContents to ~1fps and Flash visibly stutters.
      backgroundThrottling: false,
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

  if (DEVTOOLS_ENABLED) {
    attachDevtoolsShortcut(siteView.webContents, siteView.webContents);
    attachDevtoolsShortcut(win.webContents, siteView.webContents);
  }

  if (DEBUG_MODE) {
    logger.info("devtools", "launched with --devtools; DevTools enabled");
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
    // Keep the game at a fixed 100% zoom; Chromium otherwise persists the
    // per-origin zoom factor across loads.
    siteView.webContents.setZoomFactor(1);
    if (isDarkMode) applyDarkModeCSS(true);
    // TEMP debug overlay (dev only) — re-inject after every navigation.
    if (DEVTOOLS_ENABLED) {
      siteView.webContents.executeJavaScript(getDebugOverlayJs()).catch(() => {});
    }
  });

  win.on("resize", setViewBounds);
  win.on("enter-full-screen", () => {
    if (win) win.webContents.send("fullscreen-changed", true);
  });
  win.on("leave-full-screen", () => {
    if (win) win.webContents.send("fullscreen-changed", false);
  });
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

  // Surface whether Chromium is hardware-accelerated or fell back to software
  // (SwiftShader) compositing. Software compositing is the prime suspect for
  // Flash FPS lag that only shows up in the app and not in standalone Chrome.
  try {
    const gpu = app.getGPUFeatureStatus();
    logger.info(
      "gpu",
      `gpu_compositing=${gpu.gpu_compositing} 2d_canvas=${gpu.gpu_compositing && gpu["2d_canvas"]} webgl=${gpu.webgl} rasterization=${gpu.rasterization}`
    );
  } catch (e) {
    logger.warn("gpu", `could not read GPU feature status: ${(e && e.message) || e}`);
  }

  process.on("uncaughtException", (err) => {
    logger.error("uncaughtException", (err && err.stack) || String(err));
  });
  process.on("unhandledRejection", (reason) => {
    logger.error("unhandledRejection", (reason && reason.stack) || String(reason));
  });

  // Only configure Flash trace/error logging when launched in debug mode; normal
  // users run the plain release player with no mm.cfg / flashlog side effects.
  if (DEBUG_MODE) ensureFlashDebugConfig();

  // Load the persisted privacy switch before the control bar HTML is generated
  // so the button renders in the right state.
  presenceShowDetails = readSettings().presenceShowDetails === true;

  createAppMenu();
  createWindow();
  initAutoUpdater();

  // Rich presence starts as the generic "playing ekoloko" activity right away;
  // username/room only ever show after the game reports them AND the privacy
  // switch is on.
  if (DISCORD_CLIENT_ID) {
    discordPresence.init(DISCORD_CLIENT_ID, overlayLogger);
    updatePresenceActivity();
  }

  ipcMain.on("toggle-fullscreen", () => {
    if (!win) return;
    win.setFullScreen(!win.isFullScreen());
  });

  ipcMain.on("volume-change", (_event, volume) => {
    applyVolume(Number(volume));
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

  // From the game BrowserView's presence preload. Only trust the game view —
  // popup windows load arbitrary external URLs and have no business setting
  // the presence.
  ipcMain.on("presence-update", (event, data) => {
    if (!siteView || event.sender !== siteView.webContents) return;
    if (!data || typeof data !== "object") return;
    // Keep the last known username: the game reliably reports the room on every
    // join, but the username only where the client knows it, so an empty
    // username field must never wipe a previously reported one.
    const reportedUsername = typeof data.username === "string" ? data.username.slice(0, 64) : "";
    if (reportedUsername) presenceUsername = reportedUsername;
    presenceRoom = typeof data.room === "string" ? data.room.slice(0, 100) : "";
    overlayLogger.info(
      "presence",
      `game reported username=${presenceUsername ? "<set>" : "<empty>"} room=${presenceRoom || "<empty>"}`
    );
    updatePresenceActivity();
  });

  ipcMain.on("presence-clear", (event) => {
    if (!siteView || event.sender !== siteView.webContents) return;
    presenceUsername = "";
    presenceRoom = "";
    updatePresenceActivity();
  });

  // Privacy switch from the control bar.
  ipcMain.on("presence-details-toggle", (_event, show) => {
    presenceShowDetails = show === true;
    saveSetting("presenceShowDetails", presenceShowDetails);
    overlayLogger.info("presence", `details switch -> ${presenceShowDetails ? "show name+room" : "anonymous"}`);
    updatePresenceActivity();
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

app.on("will-quit", () => {
  appVolume.dispose();
  discordPresence.dispose();
});
