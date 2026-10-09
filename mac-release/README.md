# macOS 1.1.1 / Flash 34 manual release

This directory is the macOS-only source supplement for the existing `v1.1.1`
release. The historical tag stays on `6a09ae534858f9674c6aa9cd29139ab25eb4a72e`.
Windows/Linux source, configuration, installers and update manifests are unchanged.

The Mac app uses this standalone CommonJS entry point and the existing Electron
8.2.0 Intel x64 runtime. It is manually assembled and unsigned, following the
unsigned x64 DMG/ZIP policy documented on the `v1.0.28` release. macOS automatic
updates remain disabled; `latest-mac.yml` is distribution metadata only.

Runtime entry: `runtime-source/index.js`, copied to `src/main/index.js` in app.asar.
The app ID is `org.ekoloko` and normal userData is the historical
`~/Library/Application Support/ekoloko-rewritten`. Review/fixture modes use separate
directories outside the app bundle. The published packages contain no profiles,
logs, credentials or user configuration.

Changes: Mac LaunchServices process restart, opt-in native recovery after renderer
failure, default Flash 34.0.0.372 with `--legacy-flash` fallback, game-only native
fullscreen using page auto-fit (960:600), Escape/native-menu exit, mute/unmute,
manual zoom/night UI removal. A direct relaunch after LaunchServices startup
reproduced GPU/renderer termination; the internal OS cause is not claimed proven.

Review fixes: debug overlay/DevTools require an explicit debug flag even when
Electron reports `isPackaged=false`; a per-profile single-instance lock prevents
duplicate launches; late callbacks cannot recreate a window during quit or clear
the current window state after an older window closes.

The user reported that visible gameplay/fullscreen worked in the first candidate.
Hidden automated checks cover Flash runtime, mute, cold launch, repeated macOS
relaunch and explicit renderer recovery. Visible plugin-focused Escape and all
fullscreen/recovery combinations are not independently exhaustively verified.

Flash binary SHA-256:
`e412191a202ddf3627f433509353cc90fd94713950c55072b493a4dcb851d4d7`.
This is the exact locally verified Flash34 Test plugin. Upstream community build:
https://github.com/darktohka/clean-flash-builds/releases/tag/v1.53
Patch project: https://github.com/darktohka/FlashPatch

No AIR client is included. Mac DMG/ZIP assets are added to the existing release,
with the source commit recorded in release notes and build metadata.
