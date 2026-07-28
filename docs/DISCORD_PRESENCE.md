# Discord Rich Presence

Shows an "playing ekoloko" activity on the player's Discord profile while the
app is running, optionally with their username and current in-game location.

## Data flow

```
SWF (login-OK / room change)                     [pending SWF patch, see below]
  └─ ExternalInterface.call("ekolokoPresence", username, room)
       └─ login.html: window.ekolokoPresence(username, room)   [server repo]
            └─ window.electronPresence.update({username, room})
                 └─ presence preload (contextBridge, game BrowserView only)
                      └─ ipcRenderer.send("presence-update")
                           └─ main: validates sender + payload, applies the
                              privacy switch, throttles to 1 update / 15s
                                └─ discordPresence.js → local Discord IPC
                                   socket → SET_ACTIVITY
```

- `src/main/discordPresence.js` — dependency-free Discord RPC client
  (Electron 8 = Node 12, current npm RPC packages need Node 14+). Connects to
  `discord-ipc-0..9` (named pipe on Windows, unix socket elsewhere), retries
  with backoff forever, so it works if Discord starts after the game and stays
  silent if Discord isn't installed.
- The preload is generated in `getPresencePreloadJs()` (src/main/index.js) and
  written to a temp file at startup, same pattern as the control-bar HTML,
  because electron-webpack bundles the main process into a single file.
- Until the SWF patch ships, the presence shows the generic activity only
  (plus the username when the page was opened with `?username=...`), which is
  enough to test the Discord side end to end.

## Privacy switch

The control bar gets a toggle (only rendered when `DISCORD_CLIENT_ID` is set):

- **🔒 דיסקורד: אנונימי** (default) — presence is just "משחק באקולוקו";
  username and room are never sent to Discord.
- **🎮 דיסקורד: שם ומיקום** — presence shows "משחק בתור `<username>`" /
  "נמצא ב-`<room>`".

Defaults to anonymous on a fresh install (the players are kids); persisted in
`userData/settings.json` as `presenceShowDetails`.

## Setup (one-time, before testing)

1. Create an application at <https://discord.com/developers/applications>
   (name it `ekoloko` — the name is what "Playing ..." shows).
2. Copy its **Application ID** into `DISCORD_CLIENT_ID` in `src/main/index.js`.
3. Under **Rich Presence → Art Assets**, upload the game logo with asset key
   `cover` (that key is referenced by `buildPresenceActivity()` — if you name
   the asset differently, update `large_image` there to match).
4. Run the app (`npm run dev`) with the Discord desktop client running on the
   same machine. Within a few seconds the profile should show
   "Playing ekoloko". Toggle the control-bar switch and watch the details
   line change (updates are rate-limited to one per 15 seconds).

## Server-side / SWF counterpart

The web page hook (`window.ekolokoPresence` in `login.html`) and the spec for
the ActionScript ExternalInterface calls live in the server repo:
`docs/findings/2026-07-23-discord-presence-web-bridge-and-swf-hook.md`.
