# Ekoloko mobile layout lab

A local AIR prototype for adapting the existing Ekoloko interface to iPhone and
iPad. Landscape is the default; portrait and runtime rotation are supported.
`run.py` is the offline lab. `run_connected.py` and `launch-connected.command`
open a separate local review with real login, Shell/Main, menus and chat.

## Run

From the `ekoloko-air-client` checkout, with one lab instance at a time:

```sh
/opt/homebrew/bin/python3 air/mobile/run.py --device phone
/opt/homebrew/bin/python3 air/mobile/run.py --orientation portrait
/opt/homebrew/bin/python3 air/mobile/run.py --device tablet
/opt/homebrew/bin/python3 air/mobile/run.py --test
/opt/homebrew/bin/python3 air/mobile/run.py --orientation portrait --test
/opt/homebrew/bin/python3 air/mobile/run.py --device phone-small --render
```

`AIR_SDK_HOME` overrides the SDK location. Build output is in
`air/build/mobile-lab`; `--render` writes actual AIR display-tree rasterizations
and native StageText pixels to application storage, printing absolute paths.
These are AIR desktop mobile-profile checks, not Apple Simulator/device results.

## Existing game artwork, not a replacement design

- `prepare_assets.py` checks hashes while extracting the original room, walk mask,
  NPC and 13 avatar layers from the existing local AIR asset pack.
- UI symbols come from the checked-out game's `ekoloko/main.swf`. Override that
  source with `EKOLOKO_UI_SWF` when comparing a different verified client version.
  `assets/provenance.json` records the exact source path and SHA-256. This does
  not establish that the checked-out SWF is the currently deployed release.
- `OriginalUI` uses `MainMenuMCStatic`'s original buttons and states, `TextBox`
  and its send arrow, `PlainBaloon`, and the `Questmenu` background. Resizable backgrounds use nine slices rasterized from the original
  vectors at 2x; buttons retain their original vector artwork. Arial text follows the original Hebrew `TextFormats.init()`; player names use
  the original Arial/white-glow treatment. The desktop host's Gan font is not
  used for the game HUD.
- The nine regular dock controls are settings, home, animal, emoticons, my player,
  quests, buddies, map and cards. Help, newspaper and pioneer-store buttons stay
  at the side. Landscape puts chat between the two button groups; portrait uses
  two rows of 48-unit button targets and a full-width chat field on narrow phones.
  The dock overlays the room, with no separate opaque footer. Wide tablets keep
  a single dock row even in portrait.
- The map button retains a distinct map action; it is never a shortcut for camera
  zoom-out. Game menu clicks currently open explicitly offline placeholders,
  not functional replacements for the original menus. Role/level/event-gated
  actions must use real controller visibility and authorization on integration.
- Camera, rotation and recent-message controls use new matching blue vector icons
  from `assets/icons/MobileActionIcons.swf`. They are adaptation/lab controls,
  not original game actions. All action labels were replaced by icons; Hebrew
  accessibility names remain attached to each 48-unit touch target.

## Camera and input

The follow camera has a dead zone, room bounds and a stable scale while the
keyboard opens. An explicit overview shows the whole room; pinch/wheel and the
landscape +/- controls adjust zoom. The world and HUD have separate transforms.
Movement uses the real local walk mask, with a floating joystick that appears at
55% opacity while held and disappears on release. Modal menus, chat and app
backgrounding cancel movement. The local movement implementation is not the real
server/pathfinding controller.

Native StageText supports Hebrew, selection and a preserved draft across close,
reopen and rotation. Sending a local echo keeps the composer open. The gray area
on Mac is labeled keyboard-space simulation; it is not Apple's keyboard.
`stage.softKeyboardRect` takes precedence when the runtime supplies a rectangle.
The 160-character fixture limit is not a verified game chat contract.

## Recent messages

An optional floating window uses the original quest-panel artwork. Its default
background opacity is 38%, with 22%/72% alternatives; text remains opaque.
Drag its header to move it, drag the body or use wheel/previous/new controls to
read older messages, and use the matching cross icon to close it. It is bounded
to the available viewport after rotation/keyboard changes and does not block
movement elsewhere. Opening it does not dismiss the composer or replace the room.
The session retains the last 200 local messages, including off-camera speakers.
Incoming messages preserve the scroll position while reading earlier messages.
No chat is persisted to disk.

## Validation

`--test` exercises eight phone/tablet layouts, original-menu hit targets and map
semantics, camera bounds/dead zone, unchanged zoom on keyboard activation,
joystick ownership/cancellation, synthetic two-finger pinch, native ADL rotation
in both directions, draft retention, and history drag bounds/scroll anchoring.
`--render` covers follow, overview, history, inventory placeholder, keyboard,
keyboard overview and active joystick. Visual inspection remains necessary for
Hebrew/RTL, clipping and original-art fidelity after UI changes.

## Connected review

Launch `launch-connected.command`, or run
`/opt/homebrew/bin/python3 air/mobile/run_connected.py --snapshot`.
`--portrait` starts the narrow window; the rotation icon switches orientation.
This separate app uses the existing native AIR host and real login/Shell/Main.
Authenticated joins and transitions through rooms 101, 102 and 107 have been
observed. Desktop release files and production services are unchanged.

The adapter reflows actual menu instances and their existing handlers. Movement
uses the original room controller; chat submission uses the original validation
and cooldown; history observes accepted chat balloons. The mute button is fixed
beside the original-view control, alongside the mobile controls. The right auxiliary column keeps only the native
rare-items store action.

The quest adapter retains native selection handlers, art, descriptions and
navigation. Narrow screens show group, task and detail steps; wide screens have
a scrollable list beside scrollable details. Reflowed text uses the original
field's font family, color and weight through Flash Text Engine for explicit
Hebrew direction, avoiding authored TextField clipping rectangles. Native fields
remain controller-owned and unchanged.

Build prerequisites: local AIR SDK, Java 11 and the pinned CORE checkout named
in `run_connected.py`. The local pack is hash-verified; the deployed public
version map must match the reviewed receipt. Content was reconstructed from the
authenticated Git source plus the previously verified pack. Direct deployed SWF
hash equivalence is not claimed. See `current-content/content-receipt.json` in
the build output. A changed live version map fails closed and requires review.

Checks: `--test` covers 11 navigation contracts and 481 camera updates;
it also checks ten dock layouts for consistent touch targets, available chat
width, hidden controls and overlapping bounds. `--entry-test` renders native
login and selector artwork in eleven states, including five curtain-reveal frames.
`--composer-test` verifies readable Hebrew ink and bounded glyph height in four
SHOW_ALL viewport cases after correcting stage-coordinate conversion. Desktop
review uses the original game TextField; real iOS validation remains pending. `--test` checks 36 original
white-skin bounds and long-text clipping cases. The NO_SCALE lab renders readable
Hebrew with the same bounded input geometry.
`--panel-test` renders 17 original profile/pet states and verifies fixed positioning, expanded-subpanel containment and absence of
redundant external controls. `--cleanup-test` additionally checks original menu motion/lifecycle
and the packed selector page getters.
`--chat-test` runs 123 checks on the real ChatInput and ScrollPane with isolated event
sinks (no sent chat), including full-component pixel clipping, native Hebrew logical
order, caret retention and swipe-versus-tap behavior. Native chat skin end caps stay
fixed while the center stretches; own accepted history messages have an author
marker and translucent highlight. The far-right cards button is removed.
`--chat-test` never sends a real message;
`--quest-test` renders six local fixture states with original art and verifies
restoration of native parents/text. Fixture renders do not establish live quest
state correctness, audible mute behavior, or elimination of visual flicker.

The local compatibility patch fixes re-entrant display-list cleanup in both
Shell and Main, plus the SmartFox socket callback's access to a retired socket.
`--cleanup-test` runs the utility resolved from the actual packed application
domains against remove/reparent callbacks. The original pack reproduced error
2025; the patched pack passes six checks. The reported error 1009 was secondary
to runtime shutdown. Long authenticated play is still required to validate
the full reported disconnect sequence. See `connected-qa.md` for evidence.

The live adapter also clips the room layer to its original 960x600 boundary,
eases camera zoom changes over 320 ms, and hides the native menu during chat
composition. Entry screens use the original fields, buttons and handlers, with
the leaf and form scaled as one unit and a server list bounded by the parchment.
Player/pet menus attach to the screen top, retain native menu motion and grow
without popup or tab geometry changing the outer scale. Opening a card closes the composer. The card cannot be dragged; finger/mouse
swipes scroll the original inventory ScrollPane inside it. Native scrollbar
thumb/track gestures remain separate from content swipes; empty pane areas also
receive wheel and drag input. Expanded subpanels fit
inside the frame, and only the native handle remains for closing. No authentication or server
availability checks are bypassed.

iOS still needs packaging of executable ActionScript, native safe-area/density
measurements, real Apple keyboard and rotation testing, authentication, device
performance and accessibility checks. Insets in this lab are fixtures. A signed IPA and an authenticated iOS session
have not been produced here.
Desktop release files and production services are not changed by this lab.

## Connected phone host

`run_phone.py --emulate` compiles the same pinned real client for the AIR
`mobileDevice` profile. This is macOS ADL emulation, not Apple Simulator.
The phone host avoids desktop windows/ANE initialization and uses native mobile
keyboard events. It preserves the pinned pack, bootstrap, authentication and
release-map contracts. No saved desktop login credentials are copied.

Phone builds use AIR 51.4.1, installed separately from the desktop SDK. The older
51.3.4 simulator build crashed under iOS 27 at
`_UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption`; its plist-only
compatibility setting did not resolve the simulator's linked SDK requirement.
See the [AIR scene-lifecycle release](https://airsdk.dev/news/2026/09/23/release-51.4.1.1).
`package_phone_simulator.py` packages an interpreter-mode test app with ephemeral
simulator signing. It is not signed for a physical iPhone or App Store release.
Run `run_phone_simulator.py` after packaging to install it into the named
`Ekoloko — iPhone 14 Pro Max` iOS 27 simulator, displayed in Xcode Device Hub.
Normal simulator and ADL phone runs disable automatic screenshots. Add
`--snapshots` only for visual capture sessions: that mode draws and PNG-encodes
the stage after interactions and is unsuitable for assessing responsiveness.
The package embeds an isolated simulator application identifier in the Mach-O
`__TEXT,__entitlements` section for EncryptedLocalStore; iOS entitlements must
not be placed in the host macOS ad-hoc code signature. The Swift runtime rpath
is added only when absent. No Keychain access groups are shared with other apps.

On 2026-10-11 the AIR 51.4.1.1 build reached the real landing and login screens
in Apple's simulator with no recorded runtime/asset failure. The host maps the
Retina display to responsive UI units (932x430 on this simulator), and landscape
login keeps the leaf/form's original local matrices instead of moving them at
frame 90. Eleven native entry/selector fixture renders passed, including a
regression assertion for that end-frame jump. Subsequently the user logged in
using the simulator's on-screen keyboard, and the real room and pet drawer were
visually observed. Portrait keyboard behavior and physical-device support remain
unverified.

Mac-keyboard entry remains suspect: the user reported that on-screen keyboard
entry and authentication work. The exact Mac input failure is not yet isolated.
`MobileLoginInput` blurs the iOS native editor before the original submit handler
and records only allowlisted login-result event codes. It never reads, changes,
logs or hashes credential values and does not replace server authentication.

For the reported slow room interaction, a live sample observed about 97% CPU
and 524 MB footprint, with software GL rendering in the call graph. The launcher
had also enabled synchronous stage capture/PNG output after each of its first
96 clicks. Automatic capture is now opt-in; the simulator was relaunched without
it. The user subsequently confirmed a significant improvement in responsiveness.
Sustained-session performance and measured FPS/latency remain unverified.

## New Flash vector icons

`assets/icons/MobileActionIcons.swf` exports ten timeline symbols: Overview,
Follow, Rotate, Opacity, ZoomIn, ZoomOut, Older, Newer, Close, Messages.
Use `[Embed(source="MobileActionIcons.swf",symbol="Close")]` in AIR/AS3.
The lab embeds these symbols directly. No PNG is embedded in this library.

The approved artwork was generated with the built-in Image Gen tool following
the Product Design reference workflow. Original PNGs, exact prompts and source
references remain in `assets/icons/`; see `prompts.json`. At the user's request,
VTracer converted that artwork into paths, preserving its silhouette/palette
while simplifying smooth tonal shading into solid fills. Editable SVG and
Adobe FXG paths plus SHA-256 provenance are in `assets/icons/vector/`.
These are true Flash shapes; no original FLA authoring document is claimed.

To regenerate (isolated Python requires vtracer 0.6.15 and Pillow 12.3.0):

```sh
air/build/vector-tools/bin/python air/mobile/vectorize_icons.py
/opt/homebrew/bin/python3 air/mobile/compile_icons.py
/opt/homebrew/bin/python3 air/mobile/run.py --render
```

`compile_icons.py` uses the installed AIR SDK's own FXG-to-SWF transcoder and
rejects bitmap-containing output. Normal lab builds consume the saved SWF and
do not need VTracer. `--render` also writes a native 136/44-unit icon contact
sheet. See `design-qa.md` and `qa/` for before/after and raster/vector comparisons.
