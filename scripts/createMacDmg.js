"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFileSync } = require("child_process");

if (process.platform !== "darwin") {
  console.error("createMacDmg.js can only run on macOS.");
  process.exit(1);
}

const rootDir = path.resolve(__dirname, "..");
const pkg = require(path.join(rootDir, "package.json"));
const appName = pkg.build && pkg.build.productName ? pkg.build.productName : pkg.name;
const version = pkg.version;
const distDir = path.join(rootDir, "dist");
const appPath = path.join(distDir, "mac", `${appName}.app`);
const backgroundPath = path.join(rootDir, "build", "dmg-background.png");
const stageDir = path.join(os.tmpdir(), `${appName}-dmg-stage-${process.pid}`);
const rwDmg = path.join(os.tmpdir(), `${appName}-${version}-mac-rw-${process.pid}.dmg`);
const finalDmg = path.join(distDir, `${appName}-${version}-mac.dmg`);

function run(command, args, options = {}) {
  return execFileSync(command, args, {
    encoding: "utf8",
    stdio: options.capture ? ["ignore", "pipe", "pipe"] : "inherit",
  });
}

function cleanPath(target) {
  fs.rmSync(target, { force: true, recursive: true });
}

function escapeAppleScriptString(value) {
  return value.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

function detachExistingVolumes() {
  const volumesDir = "/Volumes";
  if (!fs.existsSync(volumesDir)) return;
  for (const name of fs.readdirSync(volumesDir)) {
    if (name === appName || name.startsWith(`${appName} `)) {
      try {
        run("hdiutil", ["detach", path.join(volumesDir, name), "-quiet"]);
      } catch (error) {
        // Finder may briefly hold the mounted image. The later attach will fail
        // loudly if the volume cannot be released.
      }
    }
  }
}

function mountReadWriteDmg() {
  const output = run("hdiutil", ["attach", rwDmg, "-readwrite", "-noverify", "-noautoopen"], {
    capture: true,
  });
  const mountLine = output
    .split(/\r?\n/)
    .map((line) => line.match(/(\/Volumes\/.+)$/))
    .find(Boolean);

  if (!mountLine) {
    throw new Error(`Could not find mounted volume path in hdiutil output:\n${output}`);
  }

  return mountLine[1].trim();
}

function styleMountedVolume(mountDir) {
  const background = escapeAppleScriptString(
    path.join(mountDir, ".background", "dmg-background.png")
  );

  const script = `
    tell application "Finder"
      tell disk "${escapeAppleScriptString(appName)}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {120, 90, 880, 570}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 96
        set background picture of theViewOptions to POSIX file "${background}"
        set position of item "${escapeAppleScriptString(`${appName}.app`)}" of container window to {190, 292}
        set position of item "Applications" of container window to {570, 292}
        close
        open
        update without registering applications
        delay 2
      end tell
    end tell
  `;

  run("osascript", ["-e", script]);
}

if (!fs.existsSync(appPath)) {
  console.error(`Missing packaged app: ${appPath}`);
  console.error("Run `npm run dist:mac` before creating the styled DMG.");
  process.exit(1);
}

if (!fs.existsSync(backgroundPath)) {
  console.error(`Missing DMG background: ${backgroundPath}`);
  process.exit(1);
}

cleanPath(stageDir);
cleanPath(rwDmg);
cleanPath(finalDmg);

fs.mkdirSync(path.join(stageDir, ".background"), { recursive: true });
run("ditto", [appPath, path.join(stageDir, `${appName}.app`)]);
fs.symlinkSync("/Applications", path.join(stageDir, "Applications"));
fs.copyFileSync(backgroundPath, path.join(stageDir, ".background", "dmg-background.png"));

detachExistingVolumes();
run("hdiutil", [
  "create",
  "-volname",
  appName,
  "-srcfolder",
  stageDir,
  "-fs",
  "HFS+",
  "-format",
  "UDRW",
  "-ov",
  rwDmg,
]);

let mountDir = null;
try {
  mountDir = mountReadWriteDmg();
  styleMountedVolume(mountDir);
  run("sync", []);
} finally {
  if (mountDir) {
    try {
      run("hdiutil", ["detach", mountDir, "-quiet"]);
    } catch (error) {
      run("hdiutil", ["detach", mountDir, "-force", "-quiet"]);
    }
  }
}

run("hdiutil", [
  "convert",
  rwDmg,
  "-format",
  "UDZO",
  "-imagekey",
  "zlib-level=9",
  "-ov",
  "-o",
  finalDmg,
]);

cleanPath(stageDir);
cleanPath(rwDmg);

console.log(`Created ${finalDmg}`);
