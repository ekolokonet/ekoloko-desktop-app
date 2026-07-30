# Discord Rich Presence

Shows a playing-ekoloko activity on the player's Discord profile while the
desktop app is running, optionally including their username and current
in-game location.

## Data flow

```text
SWF (login / room change)
  └─ ExternalInterface.call("ekolokoPresence", username, room)
       └─ login.html: window.ekolokoPresence(username, room)
            └─ window.electronPresence.update({ username, room })
                 └─ isolated BrowserView preload
                      └─ validated IPC message to the main process
                           └─ privacy filter and 15-second rate limit
                                └─ local Discord IPC socket
                                   └─ SET_ACTIVITY
```

- `src/main/discordPresence.js` is a dependency-free Discord RPC client,
  compatible with Electron 8 / Node 12. It connects to `discord-ipc-0..9`
  (a named pipe on Windows and a Unix socket on macOS/Linux) and retries if
  Discord starts after ekoloko.
- The game BrowserView receives one narrow, isolated preload bridge. Popup
  windows and the remote game page do not receive Node.js access.
- The activity also includes download/community buttons from release 1.0.27.

## Privacy switch

The control bar contains a Discord privacy toggle:

- **🔒 דיסקורד: אנונימי** (default) — shows only that ekoloko is being played.
- **🎮 דיסקורד: שם ומיקום** — may show the username and mapped room name.

The setting is stored in `userData/settings.json`. A fresh installation always
starts in anonymous mode.

## Discord application setup

The application ID is configured in `src/main/index.js` as
`DISCORD_CLIENT_ID`. The Discord Developer Portal application should contain a
Rich Presence image asset named `cover`.

## macOS notes

Discord's desktop app exposes the same local RPC protocol on macOS through a
Unix socket under the runtime temporary directory. No additional npm package
or native module is required, so the feature remains compatible with the
existing Intel Electron 8 build.
