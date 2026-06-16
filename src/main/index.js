const { app, BrowserWindow, BrowserView, Menu, dialog, ipcMain, shell } = require("electron");
const { execFile } = require("child_process");
const path = require("path");
const fs = require("fs");

const LOGIN_URL = "https://prod.ekoloko.org/ekoloko/login.html";
const DISCORD_URL = "https://discord.gg/5uBSQx4yWa";
const CONTROL_BAR_HEIGHT = 100;

let win;
let siteView;
let pluginName;
let os;
let isDarkMode = false;
let darkModeCSSKey = null;

switch (process.platform) {
  case "win32":
    pluginName = process.arch == "x64" ? "x64/pepflashplayer.dll" : "x32/pepflashplayer32.dll";
    os = "windows";
    break;
  default:
    pluginName = "x64/pepflashplayer.dll";
    break;
}

app.commandLine.appendSwitch(
  "ppapi-flash-path",
  path.join(__dirname + "/../plugins/", pluginName)
);

app.commandLine.appendSwitch("ppapi-flash-version", "32.0.0.371");

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

function createWindow() {
  win = new BrowserWindow({
    autoHideMenuBar: true,
    backgroundColor: "#6aaa1e",
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,
      devTools: false,
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
      devTools: false,
      plugins: true,
      allowRunningInsecureContent: true,
    },
  });

  win.setBrowserView(siteView);
  setViewBounds();
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

app.whenReady().then(() => {
  createAppMenu();
  createWindow();

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
      await siteView.webContents.session.clearCache();
    }
  });

  app.on("activate", function () {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", function () {
  if (process.platform !== "darwin") app.quit();
});
