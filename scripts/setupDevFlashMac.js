"use strict";

// Dev-only (macOS): copy plugins/mac (the Flash PPAPI player) into the
// prebuilt Electron.app inside node_modules so `npm run dev` can load Flash.
//
// Chromium's PPAPI helper runs under a seatbelt sandbox that can read files
// inside the app bundle but not the repo checkout, so pointing
// ppapi-flash-path at the repo-root plugins/ folder makes the helper's
// CFBundle load fail silently ("No PPP_GetInterface in plugin library") and
// the page shows "Couldn't load plugin." Copying the plugin into
// Electron.app/Contents/Resources/plugins lets getPluginPath()'s
// process.resourcesPath candidate resolve it — the same code path a packaged
// build uses, with the sandbox left on.
//
// Runs from postinstall, so a reinstall or Electron version bump re-copies it.
// Exits quietly on other platforms and when plugins/mac or the Electron
// binary is absent (Windows/Linux checkouts, CI, ELECTRON_SKIP_BINARY_DOWNLOAD).

const fs = require("fs");
const path = require("path");

if (process.platform !== "darwin") {
  process.exit(0);
}

const rootDir = path.resolve(__dirname, "..");
const srcDir = path.join(rootDir, "plugins", "mac");
const resourcesDir = path.join(
  rootDir,
  "node_modules",
  "electron",
  "dist",
  "Electron.app",
  "Contents",
  "Resources"
);
const destDir = path.join(resourcesDir, "plugins", "mac");

if (!fs.existsSync(srcDir) || !fs.existsSync(resourcesDir)) {
  process.exit(0);
}

fs.rmSync(destDir, { recursive: true, force: true });
fs.mkdirSync(destDir, { recursive: true });
fs.cpSync(srcDir, destDir, { recursive: true });
console.log(`Copied plugins/mac into dev Electron.app for sandboxed Flash loading.`);
