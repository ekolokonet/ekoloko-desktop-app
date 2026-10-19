# Ekoloko native AIR preview — macOS

A native macOS game host with a bundled HARMAN AIR runtime. Electron and a
separate player-installed AIR runtime are not used. The content candidate now
matches production source `cb43ab9cff50faffff5afc23fbbee2f1af3bde0e`, verified in
the running web container on2026-09-14 (main107, house14, text2440). The thin host
and installer are unchanged; generation2 updates Shell and the holiday module.

The new delivery mode is a thin host: game SWFs are fetched on demand from a
signed server release and cached by content digest. This mode is implemented and
locally tested, but its production publication endpoint is **not active yet**.
The earlier bundled preview remains separate; do not distribute the thin preview
until the server publication and real HTTPS smoke have passed.

Coolify access recovered on2026-09-14. The scoped Apache draft passed a syntax
check in the running web container, without being enabled or reloaded. The
current content archive is ready locally and passed41 actual AIR release/cache
checks. Transfer authentication, persistent release storage and live activation
remain pending; see [the production preflight receipt](server/live-releases/production-preflight-20260914.json).
The final browser observation was again denied because the administrative policy
could not be verified. The earlier syntax result remains valid evidence, but
administrative access is not currently established.

This is a local preview under active gameplay validation. The complete game
has not yet passed an authenticated room/server-transition and sustained-memory
test. Windows and Linux are outside the current macOS milestone.

## Build and install

Prerequisites: macOS, HARMAN AIR SDK51.3.4, Java11, Python3.12 and FFDec26.
The SDK and FFDec come from their official distributions. Set the paths to your
installed tools, then run from the desktop repository/worktree root:

```sh
export AIR_SDK_HOME=/Volumes/T9/AIR/sdks/AIRSDK_51.3.4
export JAVA_HOME=/Library/Java/JavaVirtualMachines/amazon-corretto-11.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:$PATH"

python3 air/scripts/air.py build --live \
  --public-key air/config/release-public-key.json
python3 air/scripts/air.py verify
python3 air/scripts/air.py package-preview
python3 -m pip install --target air/local/dmgtools -r air/macos/requirements.txt
python3 air/scripts/air.py dmg
```

Use the interpreter actually installed on your machine. This workspace uses
`/Users/ransaymour/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3`.
This build does not require a game pack. The installer contains the host, runtime,
branding and pinned public key. The private release-signing key stays outside both
the repository and public release tree. Preserve it securely: ordinary content
updates reuse the same trusted key.

For a game-content update, use `prepare --ref <immutable-commit> --assets-only`
and `publish_release.py publish`, as documented in
[the release runbook](server/live-releases/README.md). This prepares server
artifacts without rebuilding the host or issuing an installer. It preserves the
source checkout's uncommitted work. `prepare` without `--assets-only` and `build`
without `--live` retain the older bundled mode for compatibility probes only.

`package-preview` writes a new `.app` to the Mac's APFS cache and records its
location in `air/build/mac-preview.json`. ExFAT cannot preserve all framework
symlinks/signature metadata; distribute the single DMG, not an app copied loose
to ExFAT. The DMG uses the existing Ekoloko installer background, app icon and
drag-to-Applications layout. It refuses to package stale host/manifest/descriptor
bytes or overwrite an earlier image; move the earlier task-owned image aside.

The preview uses a local AIR certificate and an ad-hoc macOS signature. This
does not provide Developer ID signing or notarization. HARMAN's free-tier splash
remains. Distribution requires review of the applicable
[HARMAN license](https://airsdk.harman.com/faq) and
[Apple signing/notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
No Gatekeeper, Keychain or certificate-validation setting is disabled.

An updated ad-hoc preview may trigger macOS Keychain authorization when reading
the existing encrypted install identity. Complete that system prompt locally.
The synchronous system call can hold startup while authorization is pending;
do not delete the identity, clear cookies or substitute a new ID to avoid it.

## Native host and original game

- The original960×600 game area stays clipped and centered beneath a92-point
  toolbar. High-resolution rendering is enabled for Retina. Original Gan CLM
  typography, wordmark, jungle artwork and a round emblem are reused.
- Fullscreen, restart, remembered-login repair, redacted diagnostic export,
  day/night appearance, motion setting, volume/mute and the community link are
  implemented in AIR. Compact widths use an overflow menu. Discord Rich Presence
  is not implemented; the community link opens Discord's public invitation.
- The pinned shipped Shell receives only a deferred Stage initialization and
  a native persistent-install lookup. Its login/admission, encryption and device
  observation code stays in the current shipped implementation.
- Original SWF runtime references resolve to narrowly scoped AIR adapters in
  each loaded movie's application domain, covering both QName imports and
  Multiname namespace-set imports. The latter previously left recycle-bin
  Security calls unadapted and raised AIR Error3207. `WorldPlayer.isPlaying()` and its game
  call sites are renamed to avoid the AIR MovieClip getter collision that caused
  VerifyError1053. Original method bytecode and game literals are preserved.
- AIR document-class cloning lost `ItemMC` and `NpcMC` artwork: constructors returned an
  empty one-frame clip. At build time its original timeline is moved, byte for
  byte, into a library sprite, and a wrapper preserves `content.constructor`.
  Both `content.constructor` and `content.getMC()` return the original class;
  NPC collision and speech/quest/helper locations are forwarded to that content.
  Torso, hair and clothing retain their original444/444/386-frame timelines, and
  the tested NPC retains199 frames and26 children after unload and cloning.
- A failed or restarted game invalidates its asset generation, closes requests,
  stops sounds and unloads the old tree. Delayed callbacks from the prior tree
  cannot resume loading after a new launch. Reentrant unload callbacks cannot
  dereference a cleared game loader; diagnostics retain the first asset/runtime
  failure instead of replacing it with a cleanup error.

## Cookies and security boundaries

AIR uses its own managed HTTPS cookie jar. Repeated accounts on the same AIR
installation retain the existing browser-identity cookie and a32-byte random
install identity stored through EncryptedLocalStore. “Repair login” clears only
the original `shellData` remembered-login settings; it preserves those identities.

The AIR cookie jar is separate from Electron and browsers. No historical identity
migration or automatic cross-runtime account correlation has been implemented.
The native traits report the actual AIR/OS identity; browser-only canvas/WebGL
traits are empty. Live account switching and server-side correlation still need
end-to-end validation. A successful cookie roundtrip is not proof of every
anti-abuse rule.

Only executable bytes covered by the release's signed manifest may run in the
application sandbox. RSA2048/SHA256 verification uses the public key pinned in
the host. Every requested SWF is checked against its exact length and SHA256,
including cache hits. The current server publication maps21434 logical paths
to7710 objects; its295.8MiB of game objects is not bundled with the thin client.
Requests stay within the compiled HTTPS game origin and existing allowlisted
directories. Same-host legacy HTTP URLs are upgraded. Redirect following is
disabled and HTTPS validation remains enabled. No request Referer is forged.

Installed assets receive the fixed logical game-document URL for the exact legacy
bridge read `eval("window.location.href")`. No JavaScript is evaluated; every
other eval expression, cookie read and extra argument is rejected. Some shipped
wearables otherwise classify `app:/` as an unauthorized domain and enter a delayed
resource-consuming branch. A native sampler identified that branch dominating
the stalled process after about one minute. The existing asset domain check,
manifest verification and authentication code are preserved.

Dynamic transition, quest artwork and community-event responses must match an
original or adapted asset hash in the signed release; the corresponding native
object is then fetched on demand. Newly uploaded/generated assets must enter the
approved server publication pipeline. That integration is still pending: a
snapshot of Git assets alone does not cover the Dashboard's stored/design SWFs.
Unknown server uploads are not imported as privileged AIR code.

On startup and reconnect the host fetches `current.json`, verifies the selected
manifest/signature, and pins one release for that session. The exact live version
map must match it before starting. A changed file gets a new content digest even
if its logical filename or query version is unchanged; old cached bytes cannot
satisfy the new entry. Unchanged objects are reused. Downloads coalesce by digest
and use at most four concurrent requests. The disk cache is bounded to256MiB;
corrupt entries and interrupted partial writes are removed, and old objects are
evicted. Game process memory is separate and still requires gameplay profiling.

Every60 seconds the host checks for a newer signed release and offers the toolbar
action “עדכון משחק”. Accepting it reconnects with the new release; classes are not
swapped in the middle of a running session. Lower generations are rejected, so
an operational rollback must republish the old content under a newer generation.
An already running client is not forcibly disconnected by this mechanism; a
mandatory emergency cutoff must also use the server's existing admission/version
policy. Runtime, host protocol or trust-key changes may still need a new installer.

Client update/caching tests and local publication are complete. Automatic
publication on game deployment, the scoped HTTPS endpoint and a real two-version
client update are not activated/verified. Editing a production SWF alone will
not update the new client until publication is connected to that deployment.

The server's active public-transition opt-in and deployment hook are described in
[server/COOLIFY-ACTIVATION.md](server/COOLIFY-ACTIVATION.md). That Referer predicate
is an anti-hotlink compatibility rule, not authentication. Login, cookies, EK2,
client admission, SmartFox authority and database permissions are not relaxed.
The additional community-module/asset opt-in is in
`server/community-scope-review/`; it was activated and saved in production at
23:08 UTC after normal browser access recovered.
The client now follows the same seasonal module selection as the web rewrite,
instead of loading the old static `communityGroupsChallenge.swf` unconditionally.

Native diagnostics retain at most128 fixed stage/reason events, runtime version,
source commit and sanitized error frames. They exclude credentials, cookies,
player identifiers and raw game logs. Preview signing material and generated
files are ignored by Git.

## Verification and remaining work

Run native tests sequentially; keep only one complete game process open.

```sh
python3 air/tests/native_tests.py
python3 air/tests/release_tests.py
python3 air/tests/on_demand_loader_tests.py
python3 -m unittest discover -s air/tests -p test_publish_release.py
python3 air/tests/adaptation_audit.py /Volumes/T9/ekoloko-rewritten-new
```

The older real-asset probes below read the prepared pack and use a bundled test
BuildInfo. After preparing content, deliberately compile that test host first;
restore the live build afterward. Do not package the bundled probe host for users.

```sh
python3 air/scripts/air.py build
python3 air/tests/main_load_probe.py
python3 air/tests/avatar_asset_probe.py
python3 air/tests/sandbox_probe.py
python3 air/tests/live_probe.py
python3 air/tests/live_nested_probe.py
python3 air/tests/live_startup.py
python3 air/scripts/air.py build --live --public-key air/config/release-public-key.json
```

Observed on 2026-09-13–14 UTC:

| Check | Evidence |
|---|---|
| Native bridge, origins, entropy, cache isolation and stale-loader cancellation |63 checks pass on two successive AIR runs, including actual navigateToURL adaptation, native optional-thumbnail IOErrors and stale-loader cancellation |
| Signed release and disk cache |41 actual AIR checks passed, including the independent publisher fixtures and all21434 paths of the real signed manifest; HTTP transport was injected for lifecycle tests, not a production update |
| Nested on-demand SWF execution |7 actual AIR checks passed: the adapted parent requests its child asynchronously, the unused movie is not fetched, a second signed release changes Main and reuses the child from disk; transport uses local fixtures |
| Release publisher |14 tests and the complete7710-object publication/check passed; detached signatures independently verified by AIR |
| Main107 and house14 load contract | Installed Shell/Main class domains, live public configuration/texts, then three successive house loads/unloads pass with the exact `house.swf?14` request |
| Asset cloning | Twelve native/adapter cases cover body, hair, shirt, recycle item/bin and NPC; getMC, metadata, reuse after unload and the next Stage frame pass |
| Executable/artwork preservation | Eleven representative real SWFs preserve method/trait bytes and original literals; item timeline records match byte for byte |
| Entire release pack |7710 unique digests verified over21434 paths |
| Cookie behavior | Local HttpOnly/account-switch fixture and real AIR two-request browser identity roundtrip passed; no live account-switch claim |
| Production transport after user redeploy | New web healthy; post-deployment hook applied; actual nested AIR request200 with15144 bytes matching the installed bongo asset |
| Authenticated progression | Shell/Main and application-login response completed; after the scoped v2 activation the community module loaded. Optional-thumbnail and unknown dynamic-asset failures remained; no world entry or room movement passed |
| Community route activation follow-up | v2 applied to current web and persisted; actual nested AIR received HTTP200 with the installed 4,273,892-byte module, then Main loaded it successfully. Authenticated follow-up remains pending |
| Window focus | Production Main's legacy javascript navigation was intercepted locally; focused=true at both layout calls, followed by the user's explicit confirmation that the window no longer jumps |
| Fullscreen host | F11 entered and Escape exited fullscreen in the failure screen. SHOW_ALL, centered alignment and null fullScreenSourceRect were retained; repeated in-world fullscreen transitions remain unverified |
| Packaging | Earlier bundled DMGs passed strict local signature and pack comparisons. The new thin preview has separate mode metadata and packaging rejects any embedded game pack |

The initial long-running idle profile reached about1.1GiB RSS and became
unresponsive; the sampler identified the wearable domain-check branch as the
CPU consumer. After supplying the fixed logical origin, a126-second live startup
check passed with no frame gap over92ms. RSS peaked at1093MiB and the AIR heap
reclaimed memory during collection, but memory use remains high. This is an idle
responsiveness result, not proof of leak-free gameplay or an Electron comparison.
The startup regression now runs for120 seconds after construction and enforces
a2-second frame-gap ceiling; the previous45-second check missed the delayed fault.

An earlier packaged run passed server selection, proxy connection and the
application-login response, then reported an asset failure2ms after requesting
card data. Main immediately loads `main_components/house.swf?14` at that point.
The exact request reproduced AIR Error2101: URLVariables rejected the bare
version token. The host then removed the game when handling that load failure;
the recorded application exit happened later. The native query adapter now
ignores cache-only tokens and preserves named FlashVars and existing decoding.
No server, authentication or cookie change is involved in this correction.

The subsequent authenticated attempt passed that point and exposed a separate
seasonal-content mismatch. The static base module requested a nonexistent
`gauge/4/gauge_4_iw.swf`, while the live web rewrite selects the installed
Rosh Hashanah module. The updated client requests `communityModule.php` and
verifies the selected bytes against the installed release. In the latest packaged
run at 22:43 UTC, that request still received HTTP 403: the active server opt-in
covers `roomTransition.php` only. Browser policy verification initially blocked
v2 activation. After access recovered, v2 was applied to the current container
and saved as the next post-deployment hook; a real nested AIR request and actual
Main-module load passed. Authenticated world entry is still pending, so this
transport result does not establish successful gameplay.

The original Shell's hidden FLV player could take over the global Stage on a
fullscreen event; Main also set a 960x600 hardware-scaled fullscreen rectangle.
The adapted Shell disables FLV fullscreen takeover, and the native host restores
its centered Stage policy and clears that rectangle. The real Shell probe checks
the disabled property. Repeated authenticated transitions in fullscreen remain
pending. During repeated failed login/retry attempts the latest process reached
about 1.7 GiB RSS; sustained gameplay memory and leak behavior remain unresolved.

`last-native-failure.json` retains one sanitized failure snapshot across Retry
and app restarts, including the public asset path without its query. Regular
diagnostics also capture native-window and viewport state to distinguish a movie
failure from fullscreen/minimization. The older per-run report lost its first
error when the user restarted. Repeated authenticated room transitions still
require verification in the updated app; the Main/house probe does not sign in.
Keep only one complete game process running during that check.

Nine pre-existing malformed/non-SWF files are excluded with reasons in
`air/build/asset-audit.json`, including truncated English/Hebrew tutorial SWFs.
New-player onboarding therefore remains unvalidated and may require repairing
those source assets. No malformed asset is silently admitted.

Authenticated server selection, repeated room transitions, complete character
appearance, UI resizing/fullscreen and sustained memory remain the release gate.
An unsigned local preview is not a production-ready player release.

Use `air/build/mac-preview.json` for the latest packaged app and its delivery
mode. Bundled and live-preview DMGs have distinct filenames; an old bundled DMG
does not contain the new on-demand update mechanism.

The live-preview DMG built on2026-09-14 is20,652,134 bytes (19.7MiB), SHA256
`726793876c19ca0cd6291d0a047d7d0bb2c3f390cb9c8a7187fad6dbe1b65079`.
Read-only mount, strict local app signature, current host digest and absence of
the game pack passed. It is prepared for endpoint activation, not for player
distribution or a currently functional production login.
