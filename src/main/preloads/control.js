"use strict";

// Preload of the control bar (a local page). Sandboxed: only "electron" can be
// required here. The page gets a fixed list of message names, nothing else.
const { contextBridge, ipcRenderer } = require("electron");

const SEND = new Set([
  "control-bar-height",
  "toggle-fullscreen",
  "zoom-change",
  "zoom-fit",
  "zoom-request",
  "volume-change",
  "clear-cache",
  "restart",
  "save-logs",
  "dark-mode-toggle",
  "open-discord",
  "presence-details-toggle",
]);
const RECEIVE = new Set(["zoom-changed", "fullscreen-changed", "save-logs-done"]);

contextBridge.exposeInMainWorld("ekolokoControl", {
  send(channel, value) {
    if (!SEND.has(channel)) return;
    if (value !== undefined && typeof value !== "number" && typeof value !== "boolean") return;
    ipcRenderer.send(channel, value);
  },
  on(channel, listener) {
    if (!RECEIVE.has(channel) || typeof listener !== "function") return;
    ipcRenderer.on(channel, (_event, value) => listener(value));
  },
  init() {
    return ipcRenderer.invoke("control-init");
  },
});
