"use strict";

// Windows graphics preference for the app's own exe, so a laptop with two GPUs
// (Intel + NVIDIA / AMD) runs the game on the strong one. This is the same
// per-app switch as Settings > System > Display > Graphics; Chromium's GPU
// process then gets that adapter first from DXGI. (WebGL's powerPreference
// does not switch adapters on Windows Chromium, and the game asks "default".)
//
//   HKCU\Software\Microsoft\DirectX\UserGpuPreferences  "<exe path>" = "GpuPreference=2;"
//   (0 = let Windows decide, 1 = power saving, 2 = high performance)
//
// Rules: a choice the player made in Windows' settings is never overwritten;
// only a value this app wrote itself is updated or removed. The app setting
// ("gpuPreference" in settings.json: "high" default, "low", "system" = leave it
// to Windows) can be changed with --gpu-preference=high|low|system.
// On a desktop whose screen is on the dedicated card this changes nothing.

const { execFileSync } = require("child_process");

const KEY = "HKCU\\Software\\Microsoft\\DirectX\\UserGpuPreferences";
const VALUES = { high: "GpuPreference=2;", low: "GpuPreference=1;" };

function reg(args) {
  return execFileSync("reg.exe", args, { encoding: "utf8", windowsHide: true, timeout: 3000, stdio: ["ignore", "pipe", "ignore"] });
}

function readValue(name) {
  try {
    const out = reg(["query", KEY, "/v", name]);
    const m = out.match(/REG_SZ\s+(.*)$/m);
    return m ? m[1].trim() : null;
  } catch (e) {
    return null; // no such value (or no key)
  }
}

function apply(settings, saveSetting, logger) {
  try {
    const arg = process.argv.find((a) => a.startsWith("--gpu-preference="));
    let mode = (arg ? arg.slice(17) : settings.gpuPreference || "high").toLowerCase();
    if (!["high", "low", "system"].includes(mode)) mode = "high";
    if (arg) saveSetting("gpuPreference", mode);

    const exe = process.execPath;
    const current = readValue(exe);
    const ours = settings.gpuPreferenceWritten || null;

    // (an explicit --gpu-preference is the player's own choice too: it wins)
    if (current !== null && current !== ours && !arg) {
      logger.info("gpu-pref", `kept the player's own Windows graphics setting (${current})`);
      return;
    }
    if (mode === "system") {
      if (current !== null) {
        reg(["delete", KEY, "/v", exe, "/f"]);
        logger.info("gpu-pref", "removed the app's graphics preference (Windows decides)");
      }
      saveSetting("gpuPreferenceWritten", null);
      return;
    }
    const want = VALUES[mode];
    if (current !== want) {
      reg(["add", KEY, "/v", exe, "/t", "REG_SZ", "/d", want, "/f"]);
      saveSetting("gpuPreferenceWritten", want);
      logger.info("gpu-pref", `set ${want} for ${exe}`);
    }
  } catch (e) {
    logger.warn("gpu-pref", `could not set the graphics preference: ${(e && e.message) || e}`);
  }
}

module.exports = { apply };
