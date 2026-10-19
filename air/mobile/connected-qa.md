# Connected mobile AIR review — 2026-10-11

The desktop connected review and Apple Simulator builds are separate local apps.
No production release was changed. The authenticated user previously entered
rooms 101, 102 and 107 in the desktop review using the original login/Shell/Main.
The new iOS 27 simulator reached the original landing/login screens; authenticated
simulator entry is not yet confirmed. See the simulator evidence below.

## Apple Simulator evidence — 2026-10-11

- AIR 51.3.4 crashed before startup on iOS 27's scene-lifecycle requirement.
  AIR 51.4.1.1 now starts and loads the pinned real game content.
- Initial EncryptedLocalStore startup failure was traced to missing simulator
  application identity. Embedding its own identifier at link time resolved it,
  retaining the original manifest/pack checks and encrypted installation store.
- Visually observed the original landing and login screens in iPhone 14 Pro Max
  Simulator. Current diagnostics report 932x430 UI units and no runtime failure.
- Removed the landscape frame-90 leaf/form relocation. Native entry fixtures
  pass eleven renders plus the unchanged-local-matrix regression assertion.
- The user reported password rejection using the Mac keyboard. Blurring the
  native editor before submission did not resolve it. The user subsequently
  confirmed successful entry with the on-screen iPhone keyboard; diagnostics
  recorded application login processed and UI ready. No password content is
  recorded. The exact Mac input failure remains unisolated.
- Visually observed an authenticated room and a pet drawer opening after a click.
  User reports progressive slowdown/poor click response. Process sample: about
  97% CPU, 524 MB footprint, software GL rendering. Removed the default launcher
  `--mobile-snapshot` argument: synchronous draw/PNG/file output on each click
  is now opt-in with `--snapshots`. After relaunching without it, the user confirmed
  that responsiveness improved significantly. This is user-observed improvement,
  not a measured FPS/latency result or a long-session acceptance pass.
- Physical signing/installation is paused at the user's request. Simulator
  sustained room responsiveness, chat keyboard and portrait acceptance remain
  pending; a launched process alone is not a passed gameplay test.

## Implemented

### Chat draft delivery — 2026-10-11

- `NativeChatDelivery` wraps the original Enter/click submit path. Dispatching
  `send_message` keeps the draft in both editors until a matching own-player
  bubble appears. Cooldown/validation rejection also preserves the draft.
- A pending attempt blocks repeated submits without sending automatic retries.
  After eight seconds without a matching bubble, the original popup UI reports
  that display was not confirmed and leaves the draft available for retry.
  A confirmed bubble cannot clear a newer edit; own bubbles with original server
  masking can acknowledge the pending attempt. Other players never acknowledge it.
- iOS/Flash synchronization ignores display-only direction marks and does not
  manufacture edit events on every sync. No chat content is written to logs.
- `--delivery-test`: 17 isolated checks passed (duplicate submits, rejection,
  timeout, synchronous/late confirmation, new drafts, masking and cleanup).
  `--chat-test`: 185 checks passed against the shipped components, including
  Hebrew payload, original cooldown, max length, rejection retention and RTL
  synchronization. No real chat was sent by these tests.
- The intermittent original failure has not been reproduced in an authenticated
  session; connected iOS keyboard/send/bubble behavior remains a live smoke check.

### World map sizing — 2026-10-11

- `NativeMapLayout` fits the original 850x555 map artwork, frame and shutter
  handle within the safe area. Hidden region/tooltip bounds above the artwork
  no longer reduce its size or shift it when map contents change.
- While the native `MapPanelMC` is open, the HUD/chat and mobile actions are
  hidden; they return after it closes. The original map stays in its parent
  with its controls, listeners and normalized shutter animation intact.
- `run_connected.py --map-test` passed five viewport sizes, bounds of the
  original close/filter controls, uniform scale, region/tooltip stability,
  and shutter travel. Original Hebrew artwork was inspected at 932x430 and
  375x812. Portrait remains limited by the original map's width/aspect ratio.
- These are component checks; connected navigation, HUD restoration and the
  perceived map size still require a live simulator check after installation.

### Inventory scrolling and vault popup — 2026-10-11

- `NativeInventorySwipe` excludes both native scrollbars and their descendants
  from content swipes. The native thumb/track/arrows retain their own direction
  and handlers. Transparent hit surfaces behind pane contents let empty spaces
  receive wheel and drag input; swipe clicks are suppressed only for that pane.
- `ConnectedMobileUI` now lays out the native security popup even while a profile
  drawer is open. `NativeSecurityPopupLayout` fits the authored vault card bounds
  independently of its oversized decorative scrim/glow. No security state,
  message content, or confirmation callback is replaced.
- `chat-scroll-vault-test.log`: 182 checks passed against the actual shipped
  components, including wheel over empty space, mouse/touch scrollbar isolation,
  content swipe and item taps, and all vault message/button bounds at five sizes.
  Vault renders at 932x430 and 375x812 were visually reviewed. The original
  continue callback was verified with an isolated test sink, without a session.
- `panel-scroll-test.log`: 17 original profile/pet/storage renders passed.
  Phone host compiled, packaged, installed and launched with automatic captures
  disabled; the updated connected
  simulator gestures and popup still need live user verification after relaunch.

- Original HUD instances retain their original click handlers. Stable authored
  button bounds and a final EXIT_FRAME presentation pass prevent the adapter
  from repeatedly resizing controls around their animation bounds.
- Camera uses the avatar's world anchor, a dead zone, time-based easing and
  device-pixel translation. Focus/overview/zoom changes interpolate over 320 ms.
  The room layer is clipped to the original 960x600 canvas.
- The dock uses uniform 48-unit targets, eight-unit gaps, releases hidden slots,
  and gives chat its own row when the available inline width is below 260.
  The native menu is hidden and noninteractive while composing chat.
- Login leaf and the actual native form move as one uniformly scaled group,
  retaining their original matrices/rotation at the completed opening frame.
  The earlier individual-field reflow was removed after it broke the leaf.
- Selector cards and scroll controls stay within the parchment's inner bounds.
  Read-only native getters expose page count/index. One page hides navigation;
  multiple pages retain the original native navigation and availability logic.
- The right-side auxiliary HUD keeps only the original pioStore button, wired
  by UILayer to CreditsStorePane.onShow. The home icon ignores its hidden wide
  edit-mode label. Send artwork is centered at 36 units inside the 48-unit bar.
- The room fills behind the composer; only an actual OS keyboard reduces the
  available world height. Desktop review edits the original ChatInput TextField;
  StageText is reserved for IOS/AND runtimes; its viewport converts adapter points
  to stage coordinates while its 18px font stays unscaled. Both inputs are measured
  from the original white skin, inset and rounded inward before the send icon.
  Flash fields disable auto-size/wrapping and clip text/caret to that rectangle.
  The isolated lab uses the same white-opening measurement.
- Own/other-player and animal panels use their actual outer frame, anchored at
  the top edge. Opening a card closes the composer. Tabs and expanded
  subpanels never resize/recenter the outer frame, and the card cannot be dragged.
  Expanded native subpanels fit inside the frame; the original inventory ScrollPane
  accepts mouse/touch swipes. Swipes suppress item clicks; ordinary taps still work.
  The native close handle remains; added external arrows and the extra X are gone.
  The dock hides while these panels are open.
- The far-right cards/album control is hidden and its dock space is reclaimed.
- Native chat uses fixed original skin end caps, a separate clipped field holder
  and explicit right paragraph alignment. The adapter uses a 1024-unit transform
  basis to avoid Flash point-rounding scale errors; field dimensions and clipping
  are only reassigned when changed. Repeated reflow preserves the caret.
- Own accepted chat messages are marked with an "אני" author prefix, a cream tint
  and a translucent highlight; other messages retain white text.
- MenuDisplayOps exposes separate presentation progress with the original duration
  and a monotonic cubic ease. This removes the overshoot/clamp pause at the top
  edge while counter-transforms no longer erase menu motion. Existing original
  animation and close/lifecycle callbacks remain native. Reversing direction starts
  at the current normalized position, without a second competing tween. Drawer
  clipping is only reassigned when its bounds change.
- Original muteBut is permanently visible beside the original-view control.
  Its existing UILayer handler switches on/off artwork and calls the original
  BGSoundManager.Mute/Unmute methods.
- Quest menu keeps original selection controllers, tabs, slots, NPC and helper
  controls. Portrait uses group/task/detail steps; landscape shows a list and
  independently scrollable details. Original field strings are read into Flash
  Text Engine using the same font family, weight, color and filters, with
  explicit Hebrew bidi layout. Native fields remain unchanged.

## Evidence

- `chat-hit-before.log` reproduced an invisible native chat-skin hit outside
  the chat rectangle, over adjacent toolbar controls. `chat-hit-after.log`
  passes 123 checks, including native hit tests 2/8/20/44 units beyond all four
  edges at widths 260/343/796/1640. The native skin is hidden after capture and
  a sibling mask bounds both painting and input; disposal restores native state.
- Profile framing includes the original help/storage handles rather than
  clipping the whole root. Storage keeps its original x tween while an outer
  wrapper keeps the expanded pane on screen. Portrait and landscape renders
  show both handles; the frame stays fixed when storage opens. The two reported
  Hebrew captions use an original-style FTE presentation without changing their
  controller-owned source values. Their restored values/visibility are checked.
- `air/build/mobile-connected/input-test.log`: 11 original navigation contract
  checks and 481 camera updates passed, including idle jitter, monotonic motion,
  reverse motion, bounds and a second update at the same timestamp. Ten dock
  cases cover 375/390/667/844/1024 widths and both hidden/shown home controls.
- `air/build/mobile-connected/chat-test.log`: 58 checks on the actual
  ChatInput and ScrollPane passed with isolated event sinks. Pixel comparisons at
  260/343/796/1640 widths verify ink remains in the white skin with a fixed send gap.
  Hebrew/Latin logical order, caret retention, native limits/cooldown, swipe in both
  directions, fixed card position and swipe-versus-tap behavior passed. No real chat
  message was sent. Native Hebrew rendering was visually compared with an FTE
  reference; character-bound APIs alone do not prove visual bidi order.
- `air/build/mobile-connected/quest-test.log`: six renders passed, with native
  parent restoration and unchanged source text after disposal.
- Quest fixtures were visually inspected at 796x334, 366x798, 619x319 and
  1000x740. Portrait group/task/detail, long wrapped descriptions and scroll
  controls render in original purple/yellow art. Initial legacy TextField
  clipping and embedded subset-font corruption were found during inspection
  and corrected by explicit RTL text layout. Fixture content is synthetic.
- Latest host compiled successfully, passed the deployed version-map and cookie
  checks. A prior connected build joined room 107 and showed the native mute
  icon. The newly reopened build's landing capture fills the available width.
- `entry-test.log`: eleven native-art renders passed. Original timeline depths
  and clipDepth mask are preserved. A temporary test marker verifies zero card
  pixels in frames 1/28, partial pixels at 40 and full reveal at 46/54. Selector tests use the
  complete code-stripped timeline at frame 54, with source art hashes recorded
  by `prepare_entry_assets.py`. Login renders instantiate the actual packed
  Login class in an isolated domain, including native checkbox initialization;
  the complete original leaf/form composition is rendered in both orientations.
  No authentication request is submitted by this fixture.

- `composer-test.log`: four SHOW_ALL native-input fixtures now show complete
  Hebrew glyphs after converting viewport coordinates to stage space and keeping
  font size in pixels. Tests reject clipped/too-short ink bounds; portrait and
  landscape captures were visually inspected. NO_SCALE mobile-lab keyboard and
  placeholder renders also stay within the white opening. These are local AIR
  emulation checks; actual iOS StageText behavior still requires a device check.
- `input-test.log`: 36 skin cases (160 through 3200 wide, 44/48 high, authored
  stretch and nine-slice) check every permitted text-area pixel lies in the white
  opening and long Hebrew/Latin input cannot paint outside its clip.
- `air/build/mobile-lab/latest-test.log`: rotation/draft/menu/gesture checks pass;
  local room and keyboard renders were visually inspected after the bounds fix.
- `panel-test.log`: 17 native-art renders cover own/other-player/animal panels,
  landscape, portrait, tablet, keyboard states and expanded subpanel containment. Drag/wheel do not move the
  frame. Redundant external controls are absent; the original close handle remains.
  Art fixtures do not initialize live avatars, inventory or account values.
- `input-test.log`: 55 additional cases check drawer anchoring/keyboard scale,
  server card bounds/touch sizes and full world height while typing.
- `cleanup-test.log`: native cleanup still passes; the actual packed MenuDisplayOps
  tween survives repeated display counter-transforms and invokes its native hide
  completion. Thirty timed samples also cover monotonic opening/closing, continuous
  reversal and native hide completion. The actual packed selector exposes valid page getters.

## Disconnect investigation

The captured runtime failure was error 2025 in
`DisplayObjectContainerUtils.stopAndRemoveHierarchy`, called during
`WorldPlayer.deactivate` / `WorldRoom.removePlayer` / `Main.onUserLeaveRoom`.
Error 1009 in `SmartFoxClient.handleSocketData` followed after the host retired
the socket. The patch snapshots children and checks their current parent before
and after removal callbacks. Both Shell and Main copies are patched because
the parent application-domain definition wins. The socket loop uses its event
source and exits when that source is disconnected or replaced.

- `cleanup-before.log`: original packed runtime reproduces error 2025.
- `cleanup-after.log`: six checks pass against the actual patched packed domain,
  covering re-entrant removal, sibling removal, reparenting, ordinary cleanup,
  repeated cleanup and null. No SmartFox session or live chat is created.
- Fatal-error handling, authentication, EK2 processing and release-map checks
  retain their existing policy. No production asset has been published.

## Still requiring live verification

Previous live builds showed visible typing but overflow and motion defects were
reported. The latest combined fixes were compiled and reopened in Connected Mobile Review;
the native startup capture reached server-selection artwork. A fresh authenticated
review of typing, native menus and motion remains pending. Also pending: animated menu
opening/closing, own/other profile actions,
animal actions, full quest selection/scrolling/close/reopen across actual states, native
login field/checkbox behavior, selector selection, mute audibility, movement
flicker, overview clipping, composer hiding and prolonged authenticated play.
Real iOS keyboard/touch behavior has not been tested.
Numerical camera tests and fixture renders are not substitutes for these checks.
