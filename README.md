# ekoloko desktop app

The ekoloko game (https://play.ekoloko.org/) in its own window. More info at
https://play.ekoloko.org/ or https://discord.gg/ekoloko

2.x runs a current Electron (no Flash; the game is HTML5 since 2026-11-15).

## Develop

    npm install
    npm start                 # production game
    npm run start:beta        # https://playtesting.ekoloko.org (own profile)
    npm run check             # syntax check
    npm run dist              # Windows installer -> dist/ekoloko-Setup-<version>.exe

## Command-line switches (also in the installed app)

| switch | |
| --- | --- |
| `--beta` (or env `EKOLOKO_TARGET=beta`) | load the beta game; separate profile, no auto-update |
| `--url=https://<x>.ekoloko.org/...` (or `EKOLOKO_URL`) | any ekoloko.org page; other hosts are ignored |
| `--user-data=<dir>` (or `EKOLOKO_USER_DATA`) | use another profile folder (tests) |
| `--gpu-preference=high\|low\|system` | Windows graphics preference for the app (default high = the strong GPU on two-GPU laptops; system = Windows decides) |
| env `EKOLOKO_NO_UPDATE=1` | no update check |

Development runs only: `EKOLOKO_ALLOW_LOCAL=1` lets `--url=http://127.0.0.1:<port>/`
load (a local game build), `EKOLOKO_NO_EXTERNAL=1` logs instead of opening the browser.
DevTools exist only in development runs (F12).

## Releases and updates

A push to `main` builds Windows + Linux and publishes GitHub release
`v<package.json version>` (only if that version has no release yet). Installed
apps, 1.1.x included, download it with electron-updater and install it on the
next restart. Bump `version` to ship; merging to main is shipping.
