# macOS build notes

2.x has no Flash plugin, so the mac build is the same code as Windows/Linux.
It is still built and uploaded manually (the release workflow builds Windows
and Linux only), and it is unsigned:

    npm install
    npm run dist:mac          # zip, x64 + arm64 (on a Mac)
    npm run dist:mac:dmg      # plus a dmg (scripts/createMacDmg.js)

Unsigned consequences: Gatekeeper warns on first open (right-click > Open),
and auto-update is off on macOS (Squirrel.Mac only updates signed apps).
Signing + notarisation need an Apple Developer ID (set `APPLE_IDENTITY`,
plus notarisation credentials) - not configured.

Older (Flash) mac builds live on the `mac-support*` branches.
