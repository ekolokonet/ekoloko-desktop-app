const { app, BrowserWindow, BrowserView, Menu, dialog, ipcMain, shell } = require("electron");
const { execFile } = require("child_process");
const { autoUpdater } = require("electron-updater");
const path = require("path");
const fs = require("fs");
const os = require("os");
const logger = require("./logger");
const discordPresence = require("./discordPresence");
const roomNames = require("./roomNames");

// macOS has no supported per-application volume API for the Flash plugin.
// Keep the desktop volume control on platforms where it can actually change
// the level; Mac users can use the sound control inside the Flash game.
const HAS_APP_VOLUME_CONTROL = process.platform !== "darwin";
const appVolume = HAS_APP_VOLUME_CONTROL ? require("./appVolume") : null;

const LOGIN_URL = "https://play.ekoloko.org/ekoloko/login.html";
const DISCORD_URL = "https://discord.gg/5uBSQx4yWa";
const DISCORD_CLIENT_ID = "1529879266370523206";
const PRESENCE_BUTTON_LABEL = "להורדת המשחק";
const PRESENCE_BUTTON_COMMUNITY_LABEL = "הצטרפו לקהילה";
const PRESENCE_BUTTON_URL = "https://ekoloko.org/";
const CONTROL_BAR_HEIGHT = 100;
const FLASH_VERSION = process.platform === "darwin" ? "32.0.0.371" : "34.0.0.301";
const APP_BUNDLE_ID = "org.ekoloko";
const GAME_ORIGIN = new URL(LOGIN_URL).origin;
const NETWORK_URL_FILTER = {
  urls: ["*://ekoloko.org/*", "*://*.ekoloko.org/*"],
};
const PAGE_DIAGNOSTIC_PREFIX = "__EKOLOKO_DIAGNOSTIC__";
const PAGE_NETWORK_PREFIX = "__EKOLOKO_NETWORK__";
const LEGACY_ASSET_PRELOADER_PATH = "/ekoloko/preload_assets.js";

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
let isGameFullscreen = false;
let darkModeCSSKey = null;
let sessionNetworkLoggingAttached = false;
const suppressedPreloadRequestIds = new Set();

// Rich Presence starts anonymous so a fresh installation never broadcasts a
// player's username or location. The player can opt in from the control bar.
let presenceShowDetails = false;
let presenceUsername = "";
let presenceRoom = "";
let presenceSessionStart = null;

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
    pluginName = null;
    break;
}

// Normal launches use the release Flash player; only --devtools/--debug loads
// the content-debugger build from the parallel "-debug" folder
// (e.g. "x64/pepflashplayer.dll" -> "x64-debug/pepflashplayer.dll").
if (DEBUG_MODE && process.platform === "win32") {
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

const flashPluginPath = pluginName ? getPluginPath(pluginName) : null;
if (flashPluginPath) {
  app.commandLine.appendSwitch("ppapi-flash-path", flashPluginPath);
  app.commandLine.appendSwitch("ppapi-flash-version", FLASH_VERSION);
} else {
  console.warn(`Pepper Flash plugin not configured for ${process.platform}`);
}

// Flash (PPAPI) renders into a texture composited by Chromium's GPU process.
// Electron 8 ships an older GPU blocklist, so newer driver/OS combinations can
// fall back to software compositing. Keep Flash playback on hardware paths.
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

// The remote game page receives only this narrow bridge. Node integration
// stays disabled and every value is validated again in the main process.
function getPresencePreloadJs() {
  return `
    const { contextBridge, ipcRenderer } = require("electron");

    function cleanString(value, maxLength) {
      if (typeof value !== "string") return "";
      return value
        .replace(/[\\u0000-\\u001f\\u007f]/g, "")
        .replace(/\\s+/g, " ")
        .trim()
        .slice(0, maxLength);
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

function buildPresenceActivity() {
  const activity = {
    assets: { large_image: "cover", large_text: "ekoloko" },
    timestamps: { start: presenceSessionStart || Date.now() },
  };

  if (presenceShowDetails && presenceUsername) {
    activity.details = `משחק בתור ${presenceUsername}`;
    if (presenceRoom) {
      const friendlyRoom = roomNames[presenceRoom];
      activity.state = friendlyRoom ? `נמצא ב${friendlyRoom}` : "מסייר במפה";
    }
  } else {
    activity.details = "משחק באקולוקו";
  }

  const downloadUrl =
    presenceShowDetails && presenceUsername
      ? `${PRESENCE_BUTTON_URL}?ref=${encodeURIComponent(presenceUsername)}`
      : PRESENCE_BUTTON_URL;
  activity.buttons = [
    { label: PRESENCE_BUTTON_LABEL, url: downloadUrl },
    { label: PRESENCE_BUTTON_COMMUNITY_LABEL, url: DISCORD_URL },
  ];
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
  const appVersion = app.getVersion();
  return `
    <!doctype html>
    <html>
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <title>ekoloko v${appVersion}</title>
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

          .version-badge {
            position: absolute;
            left: 8px;
            bottom: 5px;
            z-index: 5;
            padding: 3px 8px;
            border-radius: 8px;
            background: rgba(15, 30, 58, 0.92);
            border: 1px solid rgba(255, 255, 255, 0.45);
            color: #fff;
            font-family: Arial, sans-serif;
            font-size: 13px;
            font-weight: 700;
            letter-spacing: 0.02em;
            direction: ltr;
            user-select: text;
          }

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

          <button class="btn" id="fullscreenBtn" type="button">⛶ מסך מלא</button>

          <div class="spacer"></div>

          ${HAS_APP_VOLUME_CONTROL
            ? `<div class="panel">
                <div class="panel-label" id="volumeLabel">🔊 עוצמת קול</div>
                <div class="slider-row">
                  <input id="volume" type="range" min="0" max="1" step="0.01" value="1" />
                  <div class="val" id="volumeValue">100%</div>
                </div>
              </div>

              <div class="spacer"></div>`
            : ""
          }

          <button class="btn" id="clearCache" type="button" title="מנקה cookies, מטמון ונתוני Flash ומחזיר למסך הכניסה">🩹 תקן התחברות</button>

          <div class="spacer"></div>

          <button class="btn" id="restartBtn" type="button">🔄 הפעל מחדש</button>

          <div class="spacer"></div>

          <button class="btn" id="saveLogsBtn" type="button">💾 שמירת לוגים</button>

          <div class="spacer"></div>

          <button class="btn" id="darkModeBtn" type="button">🌙 מצב לילה</button>

          ${DISCORD_CLIENT_ID
            ? `<div class="spacer"></div>

          <button class="btn" id="presenceBtn" type="button" title="בחירת המידע שמופיע לחברים בפעילות Discord">${presenceShowDetails ? "🎮 דיסקורד: שם ומיקום" : "🔒 דיסקורד: אנונימי"}</button>`
            : ""}

          ${discordSrc
            ? `<button class="btn-icon" id="openDiscord" type="button" title="דיסקורד"><img src="${discordSrc}" alt="דיסקורד" /></button>`
            : `<button class="btn" id="openDiscord" type="button">דיסקורד</button>`
          }
          <div class="version-badge" title="גרסת האפליקציה">v${appVersion}</div>
        </div>
        <script>
          const { ipcRenderer } = require("electron");

          const volume = document.getElementById("volume");
          const volumeValue = document.getElementById("volumeValue");
          const volumeLabel = document.getElementById("volumeLabel");
          const fullscreenBtn = document.getElementById("fullscreenBtn");
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

          ipcRenderer.on("fullscreen-changed", (_event, fullscreen) => {
            fullscreenBtn.textContent = fullscreen ? "Esc יציאה ממסך מלא" : "⛶ מסך מלא";
          });

          function updateVolumeUI() {
            if (!volume) return;
            const v = Number(volume.value);
            volumeValue.textContent = formatPercent(volume.value);
            setSliderFill(volume);
            volumeLabel.textContent = (v === 0 ? "🔇" : v < 0.5 ? "🔉" : "🔊") + " עוצמת קול";
          }

          if (volume) {
            volume.addEventListener("input", () => {
              updateVolumeUI();
              ipcRenderer.send("volume-change", Number(volume.value));
            });
          }

          clearCache.addEventListener("click", () => {
            clearCache.disabled = true;
            ipcRenderer.send("clear-cache");
            clearCache.textContent = "⏳ מאפס...";
          });

          ipcRenderer.on("clear-cache-done", (_event, status) => {
            clearCache.disabled = false;
            if (status === "ok") clearCache.textContent = "✓ החיבור אופס";
            else if (status === "partial") clearCache.textContent = "⚠ אופס חלקית";
            else if (status === "cancelled") clearCache.textContent = "לא בוצע";
            else clearCache.textContent = "✗ שגיאה";
            setTimeout(() => { clearCache.textContent = "🩹 תקן התחברות"; }, 2500);
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
              presenceBtn.textContent = presenceDetails
                ? "🎮 דיסקורד: שם ומיקום"
                : "🔒 דיסקורד: אנונימי";
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
  const topOffset = isGameFullscreen ? 0 : CONTROL_BAR_HEIGHT;
  siteView.setBounds({
    x: 0,
    y: topOffset,
    width: bounds.width,
    height: Math.max(0, bounds.height - topOffset),
  });

  siteView.setAutoResize({ width: true, height: true });
}

function setGameFullscreen(fullscreen) {
  if (!win || win.isDestroyed()) return;
  isGameFullscreen = Boolean(fullscreen);
  win.setFullScreen(isGameFullscreen);
  setViewBounds();
  if (siteView && !siteView.webContents.isDestroyed()) {
    siteView.webContents.focus();
  }
}

function syncFullscreenState() {
  if (!win || win.isDestroyed()) return;
  isGameFullscreen = win.isFullScreen();
  setViewBounds();
  if (!win.webContents.isDestroyed()) {
    win.webContents.send("fullscreen-changed", isGameFullscreen);
  }
  logger.info("fullscreen", `game fullscreen=${isGameFullscreen}`);
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

// Chromium exposes only a boolean mute per webContents, and the game's sound
// comes from the Flash plugin. appVolume handles OS mixer attenuation where the
// platform supports it; 0% always hard-mutes the game view.
function applyVolume(volume) {
  if (!appVolume) return;
  if (siteView) siteView.webContents.setAudioMuted(volume <= 0);
  appVolume.set(volume);
}

// Support logs must identify the failing resource without leaking usernames,
// login correlation ids, tokens or other values carried in a query string.
function redactUrl(rawUrl) {
  if (!rawUrl) return "";
  try {
    const parsed = new URL(String(rawUrl));
    if (parsed.protocol === "http:" || parsed.protocol === "https:") {
      return `${parsed.origin}${parsed.pathname}`;
    }
    if (parsed.protocol === "file:") {
      return `file:///${path.basename(parsed.pathname)}`;
    }
    return `${parsed.protocol}//${parsed.host || ""}${parsed.pathname || ""}`;
  } catch (e) {
    return String(rawUrl).replace(/[?#].*$/, "");
  }
}

function getResponseHeader(headers, name) {
  if (!headers) return "";
  const wanted = String(name).toLowerCase();
  for (const key of Object.keys(headers)) {
    if (key.toLowerCase() !== wanted) continue;
    const value = headers[key];
    return Array.isArray(value) ? value.join(",") : String(value || "");
  }
  return "";
}

function isDiagnosticAsset(url, resourceType) {
  const cleanUrl = redactUrl(url).toLowerCase();
  return (
    resourceType === "object" ||
    resourceType === "xhr" ||
    resourceType === "xmlhttprequest" ||
    /\.(swf|xml|json|bin|dat|mp3|mp4|png|jpe?g|gif)$/.test(cleanUrl) ||
    /\/(shell|login|main)$/.test(cleanUrl)
  );
}

// Capture the result Chromium/Flash actually observed on the affected Mac.
// Successful diagnostic assets and every HTTP/network failure are logged.
// Response bodies, request headers, cookies and query strings are never logged.
function attachSessionNetworkLogging(gameSession) {
  if (sessionNetworkLoggingAttached) return;
  sessionNetworkLoggingAttached = true;

  const startedAt = new Map();
  gameSession.webRequest.onBeforeRequest(NETWORK_URL_FILTER, (details, callback) => {
    startedAt.set(details.id, Date.now());
    if (startedAt.size > 5000) startedAt.clear();
    try {
      const requestUrl = new URL(details.url);
      if (
        requestUrl.hostname === "play.ekoloko.org" &&
        requestUrl.pathname === LEGACY_ASSET_PRELOADER_PATH
      ) {
        suppressedPreloadRequestIds.add(details.id);
        logger.info(
          "network",
          `disabled duplicate legacy asset preloader url=${redactUrl(details.url)}`
        );
        callback({ cancel: true });
        return;
      }
    } catch (e) {
      // Let Chromium handle malformed or non-HTTP URLs normally.
    }
    callback({});
  });

  gameSession.webRequest.onCompleted(NETWORK_URL_FILTER, (details) => {
    const start = startedAt.get(details.id);
    startedAt.delete(details.id);
    if (suppressedPreloadRequestIds.delete(details.id)) return;
    const durationMs = start ? Date.now() - start : -1;
    const requestError =
      details.error && details.error !== "net::OK" ? details.error : "";
    const shouldLog =
      details.statusCode >= 400 ||
      Boolean(requestError) ||
      isDiagnosticAsset(details.url, details.resourceType);
    if (!shouldLog) return;

    const metadata = [
      `status=${details.statusCode}`,
      `type=${details.resourceType || "?"}`,
      `cache=${Boolean(details.fromCache)}`,
      `durationMs=${durationMs}`,
      `bytes=${getResponseHeader(details.responseHeaders, "content-length") || "?"}`,
      `contentType=${getResponseHeader(details.responseHeaders, "content-type") || "?"}`,
      `etag=${getResponseHeader(details.responseHeaders, "etag") || "?"}`,
      `cfCache=${getResponseHeader(details.responseHeaders, "cf-cache-status") || "?"}`,
      `url=${redactUrl(details.url)}`,
    ].join(" ");

    if (details.statusCode >= 400 || requestError) {
      logger.error("network", `${metadata} error=${requestError || "HTTP error"}`);
    } else {
      logger.info("network", metadata);
    }
  });

  gameSession.webRequest.onErrorOccurred(NETWORK_URL_FILTER, (details) => {
    const start = startedAt.get(details.id);
    startedAt.delete(details.id);
    if (suppressedPreloadRequestIds.delete(details.id)) return;
    const durationMs = start ? Date.now() - start : -1;
    logger.error(
      "network",
      [
        `request failed`,
        `error=${details.error || "unknown"}`,
        `type=${details.resourceType || "?"}`,
        `cache=${Boolean(details.fromCache)}`,
        `durationMs=${durationMs}`,
        `url=${redactUrl(details.url)}`,
      ].join(" ")
    );
  });
}

// The live login page exposes structured, redacted diagnostic events for the
// Flash login flow. Mirror future events and online/offline transitions into the
// desktop log, so support receives them through the existing "save logs" flow.
async function installPageDiagnosticsBridge(gameContents) {
  if (!gameContents || gameContents.isDestroyed()) return;
  const visibleVersion = JSON.stringify(`ekoloko v${app.getVersion()}`);
  const script = `
    (() => {
      if (window.__ekolokoDesktopDiagnosticsInstalled) return "already-installed";
      window.__ekolokoDesktopDiagnosticsInstalled = true;

      const versionBadge = document.createElement("div");
      versionBadge.id = "__ekolokoDesktopVersion";
      versionBadge.textContent = ${visibleVersion};
      versionBadge.style.cssText =
        "position:fixed;right:8px;bottom:8px;z-index:2147483647;" +
        "padding:4px 8px;border-radius:7px;background:rgba(15,30,58,.88);" +
        "border:1px solid rgba(255,255,255,.55);color:#fff;" +
        "font:700 12px Arial,sans-serif;direction:ltr;pointer-events:none;";
      document.documentElement.appendChild(versionBadge);

      const report = window.ekolokoBrowserReportEvent;
      if (typeof report === "function") {
        window.ekolokoBrowserReportEvent = function (event) {
          try { console.info("${PAGE_DIAGNOSTIC_PREFIX}" + JSON.stringify(event)); } catch (_) {}
          return report.apply(this, arguments);
        };
      }

      const reportNetwork = function (state) {
        console.info("${PAGE_NETWORK_PREFIX}" + state);
      };
      window.addEventListener("online", function () { reportNetwork("online"); });
      window.addEventListener("offline", function () { reportNetwork("offline"); });
      reportNetwork(navigator.onLine ? "online-at-load" : "offline-at-load");
      return "installed";
    })()
  `;
  try {
    const result = await gameContents.executeJavaScript(script);
    logger.info("diagnostics", `page bridge ${result}`);
  } catch (e) {
    logger.warn("diagnostics", `page bridge failed: ${(e && e.message) || e}`);
  }
}

function withTimeout(promise, timeoutMs, message) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(message)), timeoutMs);
    Promise.resolve(promise).then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (error) => {
        clearTimeout(timer);
        reject(error);
      }
    );
  });
}

async function getSessionSnapshot(gameSession) {
  const snapshot = {
    cacheBytes: null,
    ekolokoCookieCount: null,
    proxy: null,
  };

  try {
    snapshot.cacheBytes = await gameSession.getCacheSize();
  } catch (e) {
    snapshot.cacheError = (e && e.message) || String(e);
  }
  try {
    const cookies = await gameSession.cookies.get({ url: `${GAME_ORIGIN}/` });
    snapshot.ekolokoCookieCount = cookies.length;
  } catch (e) {
    snapshot.cookieError = (e && e.message) || String(e);
  }
  try {
    snapshot.proxy = await withTimeout(
      gameSession.resolveProxy(LOGIN_URL),
      5000,
      "proxy resolution timed out after 5s"
    );
  } catch (e) {
    snapshot.proxyError = (e && e.message) || String(e);
  }
  return snapshot;
}

async function collectRuntimeDiagnostics() {
  const result = {
    appVersion: app.getVersion(),
    platform: `${process.platform} ${process.arch}`,
    userDataFolder: path.basename(app.getPath("userData")),
    loginUrl: redactUrl(LOGIN_URL),
    flash: {
      declaredVersion: FLASH_VERSION,
      pluginConfigured: Boolean(flashPluginPath),
      pluginExists: Boolean(flashPluginPath && fs.existsSync(flashPluginPath)),
    },
  };

  if (result.flash.pluginExists) {
    try {
      result.flash.pluginBytes = fs.statSync(flashPluginPath).size;
    } catch (e) {
      result.flash.pluginStatError = (e && e.message) || String(e);
    }
  }

  if (!siteView || siteView.webContents.isDestroyed()) return result;
  result.session = await getSessionSnapshot(siteView.webContents.session);

  try {
    const pageJson = await siteView.webContents.executeJavaScript(`
      JSON.stringify({
        url: location.origin + location.pathname,
        online: navigator.onLine,
        readyState: document.readyState,
        userAgent: navigator.userAgent,
        flashElementPresent: Boolean(document.querySelector('embed[type="application/x-shockwave-flash"], object')),
        flashPluginPresent: Array.prototype.some.call(navigator.plugins || [], function (plugin) {
          return /shockwave flash/i.test(String(plugin && plugin.name || ""));
        }),
        browserDiagnosticFailure: String(window.ekolokoBrowserDiagnosticFailure || ""),
        storage: {
          localKeyCount: window.localStorage ? localStorage.length : null,
          sessionKeyCount: window.sessionStorage ? sessionStorage.length : null,
          hasPreloadMarker: Boolean(window.localStorage && localStorage.getItem("ekoloko_assets_preloaded")),
          hasBrowserIdentity: Boolean(window.localStorage && localStorage.getItem("ekolokoBrowserIdentity")),
          hasLoginFlow: Boolean(window.sessionStorage && sessionStorage.getItem("ekolokoLoginFlowId"))
        }
      })
    `);
    result.page = JSON.parse(pageJson);
  } catch (e) {
    result.pageError = (e && e.message) || String(e);
  }

  return result;
}

function removeDirectoryTree(directory) {
  if (!fs.existsSync(directory)) return;
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory() && !entry.isSymbolicLink()) {
      removeDirectoryTree(entryPath);
    } else {
      fs.unlinkSync(entryPath);
    }
  }
  fs.rmdirSync(directory);
}

function clearBundledFlashData() {
  // PPAPI Flash keeps its own cache, Local Shared Objects and settings outside
  // Chromium's HTTP cache. Limit deletion to this application's userData so we
  // never touch Flash/Animate data belonging to other applications.
  const flashDataPath = path.join(
    app.getPath("userData"),
    "Pepper Data",
    "Shockwave Flash"
  );
  if (!fs.existsSync(flashDataPath)) {
    logger.info("clear-cache", `Flash data directory not found: ${flashDataPath}`);
    return;
  }
  removeDirectoryTree(flashDataPath);
  logger.info("clear-cache", `cleared bundled Flash data: ${flashDataPath}`);
}

async function runResetStep(name, action, failures) {
  try {
    await action();
    logger.info("login-repair", `${name}: done`);
  } catch (e) {
    const message = (e && e.message) || String(e);
    failures.push(`${name}: ${message}`);
    logger.error("login-repair", `${name}: ${message}`);
  }
}

// This is intentionally stronger than clearCache(): App Cleaner appeared to
// help because it removed Chromium cookies/storage AND Pepper Flash LSOs/cache.
// The repair performs those same session-level resets without deleting the app.
async function repairLoginSession() {
  if (!siteView || siteView.webContents.isDestroyed()) return "error";

  const gameContents = siteView.webContents;
  const gameSession = gameContents.session;
  const failures = [];
  const before = await getSessionSnapshot(gameSession);
  logger.info("login-repair", `starting; before=${JSON.stringify(before)}`);

  await runResetStep(
    "clear page session storage",
    () => gameContents.executeJavaScript("sessionStorage.clear(); localStorage.clear();"),
    failures
  );
  await runResetStep("unload game", () => gameContents.loadURL("about:blank"), failures);
  await runResetStep("clear HTTP cache", () => gameSession.clearCache(), failures);
  await runResetStep("clear cookies and web storage", () => gameSession.clearStorageData(), failures);
  await runResetStep(
    "clear HTTP authentication cache",
    () => gameSession.clearAuthCache({ type: "password" }),
    failures
  );
  await runResetStep("clear DNS cache", () => gameSession.clearHostResolverCache(), failures);
  await runResetStep("clear Pepper Flash data", async () => clearBundledFlashData(), failures);
  await runResetStep("reload login", () => gameContents.loadURL(LOGIN_URL), failures);

  const after = await getSessionSnapshot(gameSession);
  logger.info(
    "login-repair",
    `finished failures=${failures.length} after=${JSON.stringify(after)}`
  );
  if (failures.length === 0) return "ok";
  return gameContents.getURL() === "about:blank" ? "error" : "partial";
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
  const runtimeDiagnostics = await collectRuntimeDiagnostics();
  const parts = [
    logger.metadataHeader(),
    "\n\n========== RUNTIME DIAGNOSTICS ==========\n",
    JSON.stringify(runtimeDiagnostics, null, 2),
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
  const levelName = (level) =>
    ["VERBOSE", "INFO", "WARN", "ERROR"][level] || "INFO";

  wc.on("console-message", (_e, level, message, line, sourceId) => {
    if (String(message).startsWith(PAGE_DIAGNOSTIC_PREFIX)) {
      logger.info("login-flow", String(message).slice(PAGE_DIAGNOSTIC_PREFIX.length));
      return;
    }
    if (String(message).startsWith(PAGE_NETWORK_PREFIX)) {
      logger.info("network-state", String(message).slice(PAGE_NETWORK_PREFIX.length));
      return;
    }
    const where = sourceId ? ` (${redactUrl(sourceId)}:${line})` : "";
    const formatted = `console[${levelName(level)}]: ${message}${where}`;
    if (level >= 3) logger.error(source, formatted);
    else if (level === 2) logger.warn(source, formatted);
    else logger.info(source, formatted);
  });
  wc.on("did-fail-load", (_e, code, desc, url) => {
    logger.error(source, `did-fail-load ${code} ${desc} ${redactUrl(url)}`);
  });
  wc.on("did-fail-provisional-load", (_e, code, desc, url) => {
    logger.error(source, `did-fail-provisional-load ${code} ${desc} ${redactUrl(url)}`);
  });
  wc.on("dom-ready", () => logger.info(source, "dom-ready"));
  wc.on("did-finish-load", () => logger.info(source, "did-finish-load"));
  wc.on("did-navigate", (_e, url) => logger.info(source, `did-navigate ${redactUrl(url)}`));
  // Electron 8 has no `render-process-gone` — use `crashed`.
  wc.on("crashed", (_e, killed) => logger.error(source, `renderer crashed (killed=${killed})`));
  wc.on("unresponsive", () => logger.warn(source, "unresponsive"));
  wc.on("responsive", () => logger.info(source, "responsive"));
  wc.on("plugin-crashed", (_e, name, version) =>
    logger.error(source, `plugin-crashed: ${name} ${version}`)
  );
  wc.on("certificate-error", (_e, url, error, _certificate, callback) => {
    logger.warn(source, `certificate-error ${error} ${redactUrl(url)}`);
    // Never bypass TLS failures. Calling the callback explicitly also prevents
    // an unresolved certificate challenge from looking like a network hang.
    callback(false);
  });
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
    title: `ekoloko v${app.getVersion()}`,
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
  win.setTitle(`ekoloko v${app.getVersion()}`);
  win.on("page-title-updated", (event) => {
    event.preventDefault();
    win.setTitle(`ekoloko v${app.getVersion()}`);
  });

  const controlHtmlPath = path.join(app.getPath("temp"), `ekoloko-control-${Date.now()}.html`);
  fs.writeFileSync(controlHtmlPath, getControlPageHtml(), "utf8");
  win.loadFile(controlHtmlPath);

  const presencePreloadPath = path.join(
    app.getPath("temp"),
    `ekoloko-presence-preload-${Date.now()}.js`
  );
  fs.writeFileSync(presencePreloadPath, getPresencePreloadJs(), "utf8");

  siteView = new BrowserView({
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      devTools: DEBUG_MODE,
      plugins: true,
      preload: presencePreloadPath,
      allowRunningInsecureContent: true,
      // The control bar is a separate view, so the game view can lose focus
      // while the user is playing. Without this, Chromium throttles the blurred
      // webContents to about 1fps and Flash visibly stutters.
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

  // The game BrowserView covers the control bar in fullscreen mode. Escape is
  // handled before the page/Flash plugin so users can always restore the bar.
  siteView.webContents.on("before-input-event", (event, input) => {
    if (isGameFullscreen && input.type === "keyDown" && input.key === "Escape") {
      event.preventDefault();
      setGameFullscreen(false);
    }
  });

  win.on("enter-full-screen", syncFullscreenState);
  win.on("leave-full-screen", syncFullscreenState);

  attachWebContentsLogging(siteView.webContents, "game");
  attachWebContentsLogging(win.webContents, "control-bar");
  attachSessionNetworkLogging(siteView.webContents.session);

  siteView.webContents.on("dom-ready", () => {
    installPageDiagnosticsBridge(siteView.webContents);
  });

  if (DEBUG_MODE) {
    logger.info("devtools", "launched with --devtools; DevTools enabled");
    attachDevtoolsShortcut(siteView.webContents, siteView.webContents);
    attachDevtoolsShortcut(win.webContents, siteView.webContents);
    siteView.webContents.once("dom-ready", () => {
      siteView.webContents.openDevTools({ mode: "detach" });
    });
  }

  siteView.webContents.loadURL(LOGIN_URL).catch((e) => {
    logger.error("game", `initial login load failed: ${(e && e.message) || e}`);
  });
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
    isGameFullscreen = false;
    win = null;
    siteView = null;
  });
}

function sendLoginRepairStatus(status) {
  if (win && !win.isDestroyed() && !win.webContents.isDestroyed()) {
    win.webContents.send("clear-cache-done", status);
  }
}

async function requestLoginRepair() {
  const { response } = await dialog.showMessageBox(win, {
    type: "warning",
    buttons: ["ביטול", "תקן והתחבר מחדש"],
    defaultId: 1,
    cancelId: 0,
    title: "תיקון התחברות",
    message: "לנקות את נתוני ההתחברות ולטעון את המשחק מחדש?",
    detail:
      "הפעולה תנקה cookies, מטמון, אחסון מקומי ונתוני Flash של ekoloko. " +
      "החשבון וההתקדמות שעל השרת לא יימחקו, אבל יהיה צורך להתחבר שוב.",
  });
  if (response !== 1) {
    sendLoginRepairStatus("cancelled");
    return;
  }

  let status = "error";
  try {
    status = await repairLoginSession();
  } catch (e) {
    logger.error("login-repair", (e && e.stack) || String(e));
  }
  sendLoginRepairStatus(status);
}

function getSafeMacCleanupTargets() {
  const homeDirectory = os.homedir();
  const applicationSupport = path.join(homeDirectory, "Library", "Application Support");
  const caches = path.join(homeDirectory, "Library", "Caches");
  const preferences = path.join(homeDirectory, "Library", "Preferences");
  const savedState = path.join(homeDirectory, "Library", "Saved Application State");
  const httpStorages = path.join(homeDirectory, "Library", "HTTPStorages");
  const webKit = path.join(homeDirectory, "Library", "WebKit");

  const allowedTargets = [
    path.join(applicationSupport, "ekoloko-rewritten"),
    path.join(applicationSupport, "ekoloko"),
    path.join(caches, APP_BUNDLE_ID),
    path.join(caches, "ekoloko"),
    path.join(caches, "ekoloko-rewritten"),
    path.join(preferences, `${APP_BUNDLE_ID}.plist`),
    path.join(savedState, `${APP_BUNDLE_ID}.savedState`),
    path.join(httpStorages, APP_BUNDLE_ID),
    path.join(webKit, APP_BUNDLE_ID),
  ].map((target) => path.resolve(target));

  const currentUserData = path.resolve(app.getPath("userData"));
  if (!allowedTargets.includes(currentUserData)) {
    throw new Error(`Refusing unexpected userData cleanup target: ${currentUserData}`);
  }
  return Array.from(new Set(allowedTargets));
}

// macOS does not run an uninstall hook when a user drags an app to the Trash.
// Schedule deletion after this process exits, while the exact paths are no
// longer held open by Chromium. The helper accepts only pre-validated targets.
function scheduleMacDataCleanup(targets) {
  const helperPath = path.join(app.getPath("temp"), `ekoloko-cleanup-${process.pid}.sh`);
  const helper = `#!/bin/sh
parent_pid="$1"
shift
attempt=0
while /bin/kill -0 "$parent_pid" 2>/dev/null; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 150 ]; then
    /bin/rm -f -- "$0"
    exit 1
  fi
  /bin/sleep 0.2
done
for cleanup_target in "$@"; do
  /bin/rm -rf -- "$cleanup_target"
done
/bin/rm -f -- "$0"
`;
  fs.writeFileSync(helperPath, helper, { encoding: "utf8", mode: 0o700 });
  const child = execFile("/bin/sh", [helperPath, String(process.pid), ...targets], {
    detached: true,
    stdio: "ignore",
  });
  child.unref();
}

async function resetAllMacAppData() {
  if (process.platform !== "darwin") return;
  const { response } = await dialog.showMessageBox(win, {
    type: "warning",
    buttons: ["ביטול", "מחק נתונים וצא"],
    defaultId: 0,
    cancelId: 0,
    title: "איפוס מלא לפני הסרה",
    message: "למחוק את כל הנתונים המקומיים של ekoloko?",
    detail:
      "האפליקציה תיסגר. Cookies, מטמון, נתוני Flash, לוגים והעדפות מקומיות יימחקו. " +
      "החשבון וההתקדמות שעל השרת לא יימחקו. לאחר מכן ניתן להעביר את האפליקציה לפח בלי App Cleaner.",
  });
  if (response !== 1) return;

  try {
    const targets = getSafeMacCleanupTargets();
    logger.info("factory-reset", `scheduled cleanup of ${targets.length} validated macOS paths`);
    scheduleMacDataCleanup(targets);
    app.quit();
  } catch (e) {
    logger.error("factory-reset", (e && e.stack) || String(e));
    dialog.showErrorBox(
      "האיפוס לא בוצע",
      "לא ניתן היה להכין מחיקה בטוחה של נתוני האפליקציה. הנתונים לא נמחקו."
    );
  }
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
  if (process.platform === "darwin") {
    app.setAboutPanelOptions({
      applicationName: "ekoloko",
      applicationVersion: app.getVersion(),
      version: app.getVersion(),
      copyright: "Virtual Tweens Ltd.",
    });
    Menu.setApplicationMenu(
      Menu.buildFromTemplate([
        {
          label: "ekoloko",
          submenu: [
            { role: "about", label: `אודות ekoloko — גרסה ${app.getVersion()}` },
            { type: "separator" },
            {
              label: "איפוס מלא לפני הסרה…",
              click: resetAllMacAppData,
            },
            { type: "separator" },
            { role: "hide", label: "הסתר ekoloko" },
            { role: "hideOthers", label: "הסתר אחרים" },
            { role: "unhide", label: "הצג הכול" },
            { type: "separator" },
            { role: "quit", label: "יציאה מ-ekoloko" },
          ],
        },
        {
          label: "עריכה",
          submenu: [
            { role: "undo", label: "בטל" },
            { role: "redo", label: "בצע שוב" },
            { type: "separator" },
            { role: "cut", label: "גזור" },
            { role: "copy", label: "העתק" },
            { role: "paste", label: "הדבק" },
            { role: "selectAll", label: "בחר הכול" },
          ],
        },
        {
          label: "חלון",
          submenu: [
            { role: "minimize", label: "מזער" },
            { role: "zoom", label: "הגדל" },
            { role: "front", label: "הבא הכול לחזית" },
          ],
        },
        {
          label: "עזרה",
          submenu: [
            { label: "תיקון התחברות…", click: requestLoginRepair },
            { label: "שמירת לוגים…", click: () => saveLogsBundle().catch(() => {}) },
            { label: "Discord", click: openDiscordLink },
          ],
        },
      ])
    );
    return;
  }

  if (process.platform !== "win32") return;

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
    `ppapi-flash v${FLASH_VERSION} path=${flashPluginPath || "(not configured)"} exists=${Boolean(
      flashPluginPath && fs.existsSync(flashPluginPath)
    )}`
  );

  // Surface whether Chromium is hardware-accelerated or fell back to software
  // compositing. Software compositing is a prime suspect for Flash FPS lag.
  try {
    const gpu = app.getGPUFeatureStatus();
    logger.info(
      "gpu",
      `gpu_compositing=${gpu.gpu_compositing} 2d_canvas=${gpu["2d_canvas"]} webgl=${gpu.webgl} rasterization=${gpu.rasterization}`
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

  presenceShowDetails = readSettings().presenceShowDetails === true;

  createAppMenu();
  createWindow();
  initAutoUpdater();
  getSessionSnapshot(siteView.webContents.session)
    .then((snapshot) => logger.info("network", `startup session=${JSON.stringify(snapshot)}`))
    .catch((e) => logger.warn("network", `startup snapshot failed: ${(e && e.message) || e}`));

  if (DISCORD_CLIENT_ID) {
    discordPresence.init(DISCORD_CLIENT_ID, logger);
    updatePresenceActivity();
  }

  ipcMain.on("toggle-fullscreen", () => {
    setGameFullscreen(!isGameFullscreen);
  });

  if (HAS_APP_VOLUME_CONTROL) {
    ipcMain.on("volume-change", (_event, volume) => {
      applyVolume(Number(volume));
    });
  }

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

  ipcMain.on("presence-update", (event, data) => {
    if (!siteView || event.sender !== siteView.webContents) return;
    if (!data || typeof data !== "object") return;

    const reportedUsername =
      typeof data.username === "string" ? data.username.slice(0, 64) : "";
    if (reportedUsername) presenceUsername = reportedUsername;
    presenceRoom = typeof data.room === "string" ? data.room.slice(0, 100) : "";
    logger.info(
      "presence",
      `game reported username=${presenceUsername ? "<set>" : "<empty>"} room=${
        presenceRoom || "<empty>"
      }`
    );
    updatePresenceActivity();
  });

  ipcMain.on("presence-clear", (event) => {
    if (!siteView || event.sender !== siteView.webContents) return;
    presenceUsername = "";
    presenceRoom = "";
    updatePresenceActivity();
  });

  ipcMain.on("presence-details-toggle", (event, show) => {
    if (!win || event.sender !== win.webContents) return;
    presenceShowDetails = show === true;
    saveSetting("presenceShowDetails", presenceShowDetails);
    logger.info(
      "presence",
      `details switch -> ${presenceShowDetails ? "show name+room" : "anonymous"}`
    );
    updatePresenceActivity();
  });

  ipcMain.on("clear-cache", () => {
    requestLoginRepair();
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
  if (appVolume) appVolume.dispose();
  discordPresence.dispose();
});
