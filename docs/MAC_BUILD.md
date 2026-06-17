# macOS build notes

This repository keeps the macOS work isolated from the Windows build path.

## Shared code

- `src/main/index.js` is shared by all platforms.
- Flash plugin loading is platform-aware:
  - Windows loads `plugins/x64/pepflashplayer.dll` or `plugins/x32/pepflashplayer32.dll`.
  - macOS loads `plugins/mac/PepperFlashPlayer.plugin`.
  - Linux loads `plugins/linux/libpepflashplayer.so`.
- The login URL is platform-aware:
  - macOS uses `https://play.ekoloko.org/ekoloko/login.html`.
  - Windows and Linux keep the default `https://prod.ekoloko.org/ekoloko/login.html`.

## macOS-only files

- `plugins/mac/**`
- `build/icon.icns`
- `build/icon-1024.png`
- `build/dmg-background.png`
- `build/entitlements.mac.plist`
- `scripts/createMacDmg.js`

These files are used only by the macOS packaging scripts and the `build.mac`
section in `package.json`.

## Windows files

- `plugins/x64/**`
- `plugins/x32/**`
- `icon.ico`
- `build.win` and `build.nsis` in `package.json`

The macOS plugin and DMG assets are not included in the Windows installer.

## Build commands

Build the macOS zip:

```sh
npm run dist:mac
```

Build the macOS zip and styled DMG:

```sh
npm run dist:mac:dmg
```

Build Windows from Windows as before:

```sh
npm run dist
```

## What to commit

Commit source, packaging config, and platform resources:

```sh
git add .gitignore package.json src/main/index.js scripts/withLegacyOpenSSL.js scripts/createMacDmg.js docs/MAC_BUILD.md
git add build/entitlements.mac.plist build/icon.icns build/icon-1024.png build/dmg-background.png
git add plugins/mac
```

Do not commit generated release output:

- `dist/`
- `node_modules/`
- `*.dmg`
- `*.blockmap`
- macOS AppleDouble files such as `._package.json`

Upload the generated `.dmg` and `.zip` as GitHub Release assets instead of
committing them to the repository.
