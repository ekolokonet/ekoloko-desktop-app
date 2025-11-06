const { app, BrowserWindow } = require("electron");
const path = require("path");
const fs = require("fs");

let win;
let pluginName;
let os;
switch (process.platform) {
  case "win32":
    pluginName = process.arch == 'x64' ? 'x64/pepflashplayer.dll' : 'x32/pepflashplayer32.dll';
    os = "windows";
    break;
  default:
    pluginName = 'x64/pepflashplayer.dll';
    break;
}

app.commandLine.appendSwitch(
  "ppapi-flash-path",
  path.join(__dirname + "/../plugins/", pluginName)
);
 

app.commandLine.appendSwitch("ppapi-flash-version", "32.0.0.371");


function createWindow() {
  win = new BrowserWindow({
    autoHideMenuBar: true,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: false,
      devTools: false,
      plugins: true,
    },
  });

  win.maximize();
  win.loadURL("http://beta.ekoloko.org/ekoloko/login.html");
}

app.whenReady().then(() => {
  createWindow();

  app.on("activate", function () {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", function () {
  if (process.platform !== "darwin") app.quit();
});
