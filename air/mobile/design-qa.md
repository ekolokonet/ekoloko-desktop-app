# Mobile Flash action icons — design QA

Scope: replace the lab's text action buttons, including all recent-message
controls, with the accepted Ekoloko-style artwork and real Flash vectors.
This is an offline AIR/ADL lab, not authenticated gameplay or Apple Simulator.

## Visual evidence

- Source visual truth: `assets/icons/source-landscape-history.png` (the original
  game assets and the prior text-button layout), plus the ten original PNGs in
  `assets/icons/` (approved six icons and four matching message-window additions).
- Implementation: `qa/landscape-history.png`, rendered by the actual AIR display
  tree; viewport and output 844 x 390, density 1:1. CSS size is not applicable.
- Same state: follow camera, local room, open recent messages, keyboard closed.
- Combined full-view comparison: `qa/history-before-after.png`, source above,
  implementation below; each frame is 844 x 390 with no density scaling.
- Combined focused comparison: `qa/history-controls-before-after.png`, source
  left and implementation right, same 352 x 248 crop at (32,70).
- Artwork comparison: `qa/raster-vector-comparison.png`, original PNG artwork
  above and actual SWF rendering below, normalized to 136 and 44 units. This
  is a deterministic comparison sheet, not a generated screenshot.
- Additional actual AIR renders: `qa/portrait-history.png` and
  `qa/portrait-keyboard-history.png` (390 x 844),
  `qa/landscape-keyboard-history.png` (844 x 390),
  `qa/small-phone-keyboard-history.png` (667 x 375), and
  `qa/tablet-keyboard-history.png` (1024 x 768).

## Findings and fixes

1. [P1, fixed] Previous/new/transparency text buttons and the purple collapse bar
   did not match the accepted icon family. Replaced them with up arrow, latest
   arrow, overlapping cards and cross; screenshot comparisons above verify all
   four in the final window. Camera/rotation/chat actions use the same family.
2. [P2, fixed] Generated PNGs had inconsistent transparent margins. The trace
   pipeline removes low-alpha noise and normalizes visible bounds; controls have
   48 x 48 touch targets with proportional artwork and no stretched glyphs.
3. [P2, fixed] Raster-only assets did not meet the user's Flash-vector request.
   VTracer paths are converted to Adobe FXG and compiled with the installed AIR
   SDK's own vector transcoder. `qa/swf-verification.json` confirms 155 shape
   tags and zero bitmap tags in both deliverable SWFs. The lab embeds the vector
   symbols, and `qa/vector-icons.png` is their native AIR rendering.
4. [P3, accepted conversion difference] Smooth raster shading becomes solid
   color regions in the trace. The paired 136/44-unit render retains the accepted
   silhouettes, cream/gold/blue palette, outlines and highlights. No substitute
   icon set or hand-drawn replacement was used.

## Required fidelity surfaces

- Fonts/typography: no font glyphs are used as icons. Scene names, window title,
  message text and chat retain the existing Arial treatment; title width was
  reduced to clear the 48-unit opacity control. Action names remain in Hebrew
  accessibility properties. The narrow portrait StageText bitmap capture has a
  text-rendering artifact; native keyboard/RTL presentation still needs a real
  Apple runtime check and is outside this icon pass. No iOS text fidelity claim.
- Spacing/layout: same room/camera/dock layout and translucent history rectangle.
  The centered close target is now 48 units; footer controls fit the short
  landscape keyboard viewport, portrait and tablet. No buttons are clipped.
- Colors/tokens: blue/cream/gold action family; original room, dock, quest-panel
  artwork and 38% default history background retained. Opacity changes affect
  panel background only. Native text content remains opaque.
- Image quality: real room/avatar/menu art retained; new image-generated artwork
  converted from those exact source pixels to editable paths at user request.
  The full and focused paired comparisons show no material silhouette drift.
- Copy/content: removed visible action words, retained title and conversation.
  Accessibility names describe actual actions; the original map action is still
  separate from camera overview. Demo message content is explicitly local.

## Interaction and runtime evidence

AIR compilation and both orientation test runs completed with
`MOBILE_TESTS_PASS`. Checks include eight phone/tablet layouts; original menu
actions and 44+ unit hit targets; camera overview/follow icon actions; message
window toggle; each of the four history icon actions; opacity changes; scroll
anchoring on incoming messages; drag bounds; draft preservation; pinch/NPC input;
and native ADL rotation in both directions. No runtime errors appeared in these
runs or the four render runs. Apple touch/VoiceOver/keyboard are not verified.

Comparison history: prior text-button screenshot -> replacement with real
vector icon family -> final paired screenshots and successful action checks.
No remaining P0/P1/P2 finding in the requested icon conversion/replacement scope.

## Implementation checklist

- [x] All adaptation and history actions use matching icons without text labels.
- [x] Original menu actions and artwork remain in place.
- [x] Real vector SWF plus editable SVG/FXG and generation prompts saved.
- [x] Combined full-view, focused and raster/vector comparisons inspected.
- [x] Functional actions, rotation and viewport cases checked in AIR.
- [ ] Separate integration work: real game controllers and Apple device testing.

final result: passed
