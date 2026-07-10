const { spawn, execFile } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
const logger = require("./logger");

// Per-application OS volume control for the 0-100% sound slider.
//
// Chromium (and therefore Electron 8) only exposes a boolean setAudioMuted()
// per webContents, and the game's audio comes from the PPAPI Flash plugin, so
// scripting HTML5 media volume into the page does nothing either. The only
// lever that actually attenuates Flash audio is the OS mixer's per-application
// volume:
//   - Windows: WASAPI audio sessions (ISimpleAudioVolume), driven through a
//     small persistent PowerShell helper so we don't have to ship a native
//     Node module rebuilt against Electron 8.
//   - Linux: PulseAudio/PipeWire sink-inputs via pactl.
//   - macOS: no public per-app volume API; set() is a no-op there. The 0%
//     position still hard-mutes via setAudioMuted() in index.js.

const DEBOUNCE_MS = 150;
const REAPPLY_MS = 5000;

let lastVolume = 1;
let debounceTimer = null;
let reapplyTimer = null;

function exeBaseName() {
  return path.basename(process.execPath).replace(/\.exe$/i, "");
}

const WINDOWS_HELPER_PS1 = `
$src = @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
class MMDeviceEnumeratorComObject { }

[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator {
  int NotImpl1();
  [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice);
}

[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice {
  [PreserveSig] int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
}

[Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioSessionManager2 {
  int NotImpl1();
  int NotImpl2();
  [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator SessionEnum);
}

[Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioSessionEnumerator {
  [PreserveSig] int GetCount(out int SessionCount);
  [PreserveSig] int GetSession(int SessionCount, out IAudioSessionControl2 Session);
}

[Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioSessionControl2 {
  int NotImpl1();
  int NotImpl2();
  int NotImpl3();
  int NotImpl4();
  int NotImpl5();
  int NotImpl6();
  int NotImpl7();
  int NotImpl8();
  int NotImpl9();
  int NotImpl10();
  int NotImpl11();
  [PreserveSig] int GetProcessId(out uint pRetVal);
  int NotImpl12();
  int NotImpl13();
}

[Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface ISimpleAudioVolume {
  [PreserveSig] int SetMasterVolume(float fLevel, ref Guid EventContext);
  [PreserveSig] int GetMasterVolume(out float pfLevel);
  [PreserveSig] int SetMute(bool bMute, ref Guid EventContext);
  [PreserveSig] int GetMute(out bool pbMute);
}

public static class EkolokoAppVolume {
  public static int SetByProcessName(string name, float level) {
    int hits = 0;
    IMMDeviceEnumerator devEnum = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
    IMMDevice speakers;
    if (devEnum.GetDefaultAudioEndpoint(0, 1, out speakers) != 0) return 0;
    Guid iidMgr = typeof(IAudioSessionManager2).GUID;
    object o;
    if (speakers.Activate(ref iidMgr, 0x17, IntPtr.Zero, out o) != 0) return 0;
    IAudioSessionManager2 mgr = (IAudioSessionManager2)o;
    IAudioSessionEnumerator sessions;
    if (mgr.GetSessionEnumerator(out sessions) != 0) return 0;
    int count;
    sessions.GetCount(out count);
    for (int i = 0; i < count; i++) {
      IAudioSessionControl2 ctl;
      if (sessions.GetSession(i, out ctl) != 0 || ctl == null) continue;
      uint pid;
      ctl.GetProcessId(out pid);
      bool match = false;
      if (pid != 0) {
        try { match = string.Equals(Process.GetProcessById((int)pid).ProcessName, name, StringComparison.OrdinalIgnoreCase); }
        catch (Exception) { }
      }
      if (match) {
        ISimpleAudioVolume vol = ctl as ISimpleAudioVolume;
        if (vol != null) {
          Guid ctx = Guid.Empty;
          if (vol.SetMasterVolume(level, ref ctx) == 0) hits++;
        }
      }
      Marshal.ReleaseComObject(ctl);
    }
    Marshal.ReleaseComObject(sessions);
    Marshal.ReleaseComObject(mgr);
    Marshal.ReleaseComObject(speakers);
    Marshal.ReleaseComObject(devEnum);
    return hits;
  }
}
'@
Add-Type -TypeDefinition $src
$target = $args[0]
$culture = [System.Globalization.CultureInfo]::InvariantCulture
while ($true) {
  $line = [Console]::In.ReadLine()
  if ($null -eq $line) { break }
  $v = [single]0
  if ([single]::TryParse($line, [System.Globalization.NumberStyles]::Float, $culture, [ref]$v)) {
    try { [void][EkolokoAppVolume]::SetByProcessName($target, $v) } catch { }
  }
}
`;

let psProc = null;
let psSpawnFailures = 0;

function windowsHelper() {
  if (psProc) return psProc;
  if (psSpawnFailures >= 3) return null;
  try {
    const scriptPath = path.join(os.tmpdir(), "ekoloko-app-volume.ps1");
    fs.writeFileSync(scriptPath, WINDOWS_HELPER_PS1, "utf8");
    psProc = spawn(
      "powershell.exe",
      ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", scriptPath, exeBaseName()],
      { windowsHide: true, stdio: ["pipe", "ignore", "pipe"] }
    );
  } catch (e) {
    psSpawnFailures++;
    logger.error("app-volume", `failed to spawn helper: ${(e && e.message) || e}`);
    psProc = null;
    return null;
  }
  psProc.stderr.on("data", (d) => logger.warn("app-volume", `helper stderr: ${String(d).trim()}`));
  psProc.on("error", (err) => {
    psSpawnFailures++;
    logger.error("app-volume", `helper error: ${(err && err.message) || err}`);
    psProc = null;
  });
  psProc.on("exit", (code) => {
    if (code !== 0 && code !== null) {
      psSpawnFailures++;
      logger.warn("app-volume", `helper exited with code ${code}`);
    }
    psProc = null;
  });
  return psProc;
}

function applyWindows(volume) {
  const proc = windowsHelper();
  if (!proc) return;
  try {
    proc.stdin.write(volume.toFixed(3) + "\n");
  } catch (e) {
    logger.warn("app-volume", `helper write failed: ${(e && e.message) || e}`);
    psProc = null;
  }
}

function applyLinux(volume) {
  execFile("pactl", ["list", "sink-inputs"], (err, stdout) => {
    if (err) {
      logger.warn("app-volume", `pactl list failed: ${(err && err.message) || err}`);
      return;
    }
    const ids = [];
    let current = null;
    for (const raw of String(stdout).split("\n")) {
      const line = raw.trim();
      const header = line.match(/^Sink Input #(\d+)$/);
      if (header) {
        current = header[1];
        continue;
      }
      if (!current) continue;
      const pid = line.match(/^application\.process\.id = "(\d+)"$/);
      const bin = line.match(/^application\.process\.binary = "(.+)"$/);
      if ((pid && Number(pid[1]) === process.pid) || (bin && bin[1] === exeBaseName())) {
        ids.push(current);
        current = null;
      }
    }
    const pct = Math.max(0, Math.min(100, Math.round(volume * 100)));
    for (const id of ids) {
      execFile("pactl", ["set-sink-input-volume", id, `${pct}%`], (setErr) => {
        if (setErr) logger.warn("app-volume", `pactl set failed: ${setErr.message}`);
      });
    }
  });
}

function apply(volume) {
  switch (process.platform) {
    case "win32":
      applyWindows(volume);
      break;
    case "linux":
      applyLinux(volume);
      break;
    default:
      break;
  }
}

function set(volume) {
  lastVolume = Math.max(0, Math.min(1, Number(volume) || 0));
  if (debounceTimer) clearTimeout(debounceTimer);
  debounceTimer = setTimeout(() => {
    debounceTimer = null;
    apply(lastVolume);
  }, DEBOUNCE_MS);

  if (!reapplyTimer && (process.platform === "win32" || process.platform === "linux")) {
    reapplyTimer = setInterval(() => {
      if (lastVolume < 1) apply(lastVolume);
    }, REAPPLY_MS);
  }
}

function dispose() {
  if (debounceTimer) clearTimeout(debounceTimer);
  if (reapplyTimer) clearInterval(reapplyTimer);
  debounceTimer = null;
  reapplyTimer = null;
  if (psProc) {
    try {
      psProc.stdin.end();
      psProc.kill();
    } catch (e) {
      // Already gone.
    }
    psProc = null;
  }
}

module.exports = { set, dispose };
