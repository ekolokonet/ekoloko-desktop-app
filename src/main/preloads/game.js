"use strict";

// Preload of the game view (the remote site). Sandboxed, context-isolated. It
// gives the page exactly one narrow bridge, window.electronPresence, for the
// Discord presence ({username, room}); values are cleaned here and again in
// the main process, which also only accepts them from the game view itself.
// window.ekolokoDesktop tells the page it runs in the desktop app (version).
const { contextBridge, ipcRenderer } = require("electron");

function cleanString(value, maxLength) {
  if (typeof value !== "string") return "";
  return value.replace(/[\u0000-\u001f\u007f]/g, "").replace(/\s+/g, " ").trim().slice(0, maxLength);
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

const version = cleanString((process.argv.find((a) => a.startsWith("--ekoloko-app-version=")) || "").slice(22), 32);
contextBridge.exposeInMainWorld("ekolokoDesktop", Object.freeze({ app: "ekoloko-desktop", version }));
