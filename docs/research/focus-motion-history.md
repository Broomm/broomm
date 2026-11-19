# Earlier focus-motion experiments

These are historical implementation notes and verification records for builds
1208–1213. The runtime now uses native rounded rectangles and a traveling hollow
circle; none of the point, Bezier, slime, pinch or split-path engines is retained.
See the [current design](../navigation-and-motion.md#circle-focus-outline-and-living-gradient--2026-11-19)
and [implementation status](../../IMPLEMENTATION.md) for current behavior.
Earlier archives/fingerprints remain useful evidence, not current acceptance.

## Delayed contour morph with a soft waist — 2026-11-19

The owner confirmed build 1212's scrolling correction works, then replaced
the visual direction with a closed outline whose points leave gradually and
pinch toward the travel line. Shared Dart rendering now uses 96 corresponding
edge/corner points joined by bounded cubic Beziers. The center line orders
departure around both halves: the facing intersection moves first and the
opposite intersection last. Smooth delays span 40% of the transfer; each point
then eases over a 60% interval. Temporary transverse contraction creates the
waist and releases smoothly at arrival. Thin controls and large changes of
breadth receive less contraction to avoid corner folds. The settled shape is
the exact destination rounded rectangle. Coincident controls morph in place.

Retargets capture the current contour with a fixed point count. Both live
anchors, UI scaling, offscreen/removal handling, bounded timing, directional
portrait pacing, foreground layering, rotating mint gradient and reduced
motion remain in place. No package, native adapter, emulator configuration
or save workflow changed. See the [current geometry](#delayed-contour-morph-with-a-soft-waist--2026-11-19)
and [owner walkthrough](../../README.md#verify-keyboardcontroller-navigation-and-motion).

Static analysis, **837 macOS-hosted Flutter tests** and **three offscreen
renderer fixtures** passed, with the existing Linux-only launcher case skipped.
Geometry checks cover staggered departure in both directions, a narrow middle
with full ends, exact arrival, closed/noncrossing contours for diagonal,
portrait, circle, overlapping, wide-field and extreme aspect-ratio changes,
snapshot continuity, both live anchors, scale and directional timing. An
isolated fixed-seed sweep of 160 shape pairs at 19 intermediate poses found
no polygon crossings after contraction limits. Earlier probes reproduced
folds with stronger contraction; their failing logs are retained. This finite
sweep does not establish every possible contour or physical animation feel.

Inspected frames include the actual Home rail's growth/scroll and reversal,
upward Store reveal, controller keyboard, and tile-to-settings morph. The
previously accepted scrolling behavior has fixture coverage; owner acceptance
of this new visual effect and other-host native execution remain pending.
Commands, diagnostics and frames are under
`.tool-cache/research/focus-point-morph/`.

The [universal macOS preview](../../build/releases/Broomm-macOS-delayed-goo.zip)
is `0.1.29-dev` (1213), **24,474,321 bytes**, with SHA-256
`033e575259805d82fe9fc45e00341dc50428bb083009e4218d6bdb1d6f377c2f`.
ZIP integrity, source/extracted signatures, both architectures, setup assets
and bundled bridges passed verification. The [verification record](../focus-delayed-contour.json)
identifies the checked workspace sources and logs.

## Focus flow during scrolling and portrait navigation — 2026-11-19

Owner testing of build 1211 accepted the effect but found faster upward Store
movement and broken flow during Home scrolling. The departing perimeter was
frozen in screen coordinates. A stationary portrait fixture also measured
vertical initial stroke speed about 12% above horizontal speed; this was a
contributing difference, not evidence of an independent Up-only clock bug.

Both controls now supply geometry after layout. The source and destination
perimeters follow scrolling and growth/shrinkage, with stable join fractions
and split direction. Interrupted snapshots follow their departing control's
origin and UI scale. Attached offscreen sources remain anchors; removed sources
retain their last valid geometry until arrival. Layout updates do not restart
the distance clock. Nearby routes have proportional duration and consistent
stroke speed in all four directions, bounded to 260–520 ms before incoming
velocity adjustment. Very long jumps still start faster. No dependency,
native adapter or save workflow changed.

Static analysis, **836 macOS-hosted Flutter tests** and **three offscreen
renderer fixtures** passed, with the existing Linux-only launcher case skipped.
Four new regression cases cover cardinal portrait pacing, both live ends,
interrupted snapshots, simultaneous resize, viewport translation at fixed
animation time, offscreen sources and source removal. Actual Home growth/rail
scroll, mid-scroll reversal and upward Store reveal frames were inspected.
The renderer asserts that the real Home/Store scroll offsets change.
Other-host native execution and owner acceptance of the correction remain
pending. See the [behavior and reproduction](../navigation-and-motion.md#scrolling-and-portrait-card-correction)
and [walkthrough](../../README.md#verify-keyboardcontroller-navigation-and-motion).
Logs and frames are under `.tool-cache/research/focus-scroll/`.

The [universal macOS preview](../../build/releases/Broomm-macOS-focus-scroll.zip)
is `0.1.29-dev` (1212), **24,496,551 bytes**, with SHA-256
`17d2523daa8a5a9eb7887447bc22c7c6d9c7d57501805e4fcac66caf4437305d`.
ZIP integrity, source/extracted signatures, both architectures, setup assets
and bundled bridges passed verification. The [verification record](../focus-flow-scrolling.json)
identifies the checked workspace sources and logs.

## Perimeter flow, soft joins and rotating focus color — 2026-11-19

The owner accepted the perimeter-flow preview and requested softer bridge
connections plus a continuously rotating gradient. Shared Dart geometry now
splits the source/destination perimeters using their center line and slides
two strokes along native paths. Joins open farther around the corners until
their tangents point toward the destination, avoiding the preview's tight
backward turn. Retargeting retains the actual painted paths and a bounded
incoming speed. Moving destinations stay live, including Home returning a
tile to its fixed position; coincident controls use an in-place resize.

The mint/teal gradient rotates once every eight seconds, including at rest.
Its 33 ms clock repaints only the foreground layer, retaining page content.
Hidden/removed focus and hidden applications stop it. Reduced motion snaps
to the target and freezes the color cycle. No package or native adapter was
added. The [walkthrough](../../README.md#verify-keyboardcontroller-navigation-and-motion)
includes the keyboard, tile-to-settings, resting color and accessibility checks.

Static analysis and **832 macOS-hosted Flutter tests** passed, with the existing
Linux-only launcher case skipped. Two offscreen renderer fixtures passed and
their keyboard, soft tile-to-settings and resting-color frames were inspected.
Regressions cover route following and soft turns, very wide fields, repeated
retargets, live/coincident destinations, incoming speed, rotation at rest,
unchanged content build/paint counts, immediate hidden-app shutdown before a
new frame, reduced motion, scaling, removal, layering and click-through.

An isolated 50-iteration native geometry probe measured the final preparation
at roughly 0.55–1.08 ms per route across 156/4000/8000 logical-pixel fields.
Earlier stepwise corner searches took about 6.77 ms for the 8000-pixel case;
the final search uses bounded tangent-angle refinement. These are headless
debug geometry timings, not native input or end-to-end rendering acceptance.
Logs, source fingerprints and frames are retained under
`.tool-cache/research/focus-flow-native/`. Other-host execution and physical
controller/visual acceptance remain pending.

The [universal macOS preview](../../build/releases/Broomm-macOS-outline-flow.zip)
is `0.1.29-dev` (1211), **24,490,709 bytes**, with SHA-256
`11faaa0419859d37f60d893017d22316c2f5a01e98d417cb457e24a7bbbafb49`.
ZIP integrity, source and extracted signatures, both architectures, setup
assets and bundled bridges passed verification.

## Directional slime focus shape — 2026-11-18

The owner liked build 1209's motion but found its centered pinch too symmetric.
The moving contour now swells and reaches forward while narrowing behind it.
The bulge and neck follow the travel direction, including diagonals. Reversals
retain the entire previously painted contour before it turns toward the new
target. The 360 ms timing, global foreground layer, mint/teal gradient,
reduced-motion behavior and final control geometry are retained.

Static analysis, **48 focused widget tests** and the keyframe renderer passed
on macOS. Four new pixel cases compare the fuller front with the narrow rear
in both horizontal directions, vertically and diagonally. They also check
pixel-identical reversal and symmetric settled geometry. Existing checks cover
moving targets, reduced motion, layering, scaling, click-through, keyboard,
Home, settings and dialogs. Horizontal, vertical and reversed keyboard frames
were visually inspected. Physical-input feel and other-host native execution
remain unverified. Logs and previews are under
`.tool-cache/research/focus-slime/`.

The [universal macOS preview](../../build/releases/Broomm-macOS-directional-slime.zip)
is `0.1.29-dev` (1210), **24,453,348 bytes**, with SHA-256
`847c9426a6513be730b4298751635932a9a2e6ec96919c1ceee1982718053ca8`.
ZIP integrity, source and extracted signatures, both architectures, setup
assets and bundled bridges passed verification.

## Fluid focus transitions — 2026-11-18

The shell now paints one foreground focus ring across screens, dialogs and
the controller keyboard. Focus changes stretch its leading edge ahead of its
trailing edge, with a small inward bow before settling over 360 ms. Direction
changes continue from the currently painted shape. Destination geometry stays
live while controls scroll or grow. First focus is immediate; saved or platform
reduced motion stops an active transition and snaps to its destination. Hidden,
removed or unfocused controls clear the ring, and it never handles input.

The full macOS-hosted Flutter suite passed **827 tests** with its existing
Linux-only launcher test skipped. Five focus pixel regressions and the new
offscreen keyframe renderer passed after the final geometry change. These cover
fluid travel, interrupted direction changes, a moving/resizing destination,
reduced motion during travel, hidden/removal cleanup, idle scheduling, 50% and
150% transforms, elevated neighbors, click-through and keyboard/dialog focus.
Static analysis passed. Horizontal, vertical and settled keyboard frames were
visually inspected. No physical-input motion or other-host native acceptance
is claimed. See the [walkthrough](../../README.md#verify-keyboardcontroller-navigation-and-motion)
and [rendering design](../navigation-and-motion.md).

The [universal macOS preview](../../build/releases/Broomm-macOS-fluid-focus.zip)
is `0.1.29-dev` (1209), **24,447,464 bytes**, with SHA-256
`763f66a780911d62b324ee5b784c33ef4bc1406e9818aa453057ad06dff96d69`.
ZIP integrity, source and extracted signatures, both architectures, setup
assets, and bundled bridges passed verification. Logs and rendered keyframes
are retained under `.tool-cache/research/focus-motion/`.

## Focus outlines above the interface — 2026-11-18

The shared focus ring renders in the outer Flutter overlay. That overlay
contains the screen, dialogs, notifications, and controller keyboard, so
adjacent or elevated controls cannot cover the active ring. The outline uses
the control's current size and transform, follows scrolling and scaling,
ignores pointer input, and disappears with the control or focus.

Static analysis, 42 focused widget tests, and the desktop/compact fixture
renderer passed. The three pixel regressions cover elevated neighbors and
clipping, transformed scrolling controls, and keyboard-to-dialog focus.
The reduced-motion regression checks frame scheduling because Flutter's
overlay layout builder retains a passive geometry callback even while idle.
Both keyboard renders were visually inspected. Physical-device testing of the
focus rendering is pending.

The [universal macOS preview](../../build/releases/Broomm-macOS-focus-outline.zip)
is `0.1.29-dev` (1208), **24,430,279 bytes**, with SHA-256
`e2ed11f2b3e52c5218b90c8feea0b038fecdd210517fa3d7ddb8f7c39f3b3de7`.
ZIP integrity, source and extracted signatures, both architectures, setup
assets, and bundled bridges passed verification.

## Earlier browser perimeter-flow proposal

The following proposal and browser evidence preceded the retired application
experiments above. It does not describe the current renderer.

## Geometry

Capture the line joining the controls' centers. Its facing intersections with
their rounded outlines identify the two inner junctions. Open a small section
of each perimeter around those junctions and connect the matching sides with
two cubic Beziers. Match the curve handles to the outgoing source and incoming
destination tangents. Keep handles bounded, including where a small opening
would otherwise let the two bridges cross the center line.

Each route starts at the back of the source, follows one source perimeter half,
passes through its bridge, then follows the corresponding destination half to
the far side. A moving interval of that route is the visible stroke. Advance
its head and tail by arc length; do not interpolate the border vertices between
the two controls. Its length can adapt to a larger or smaller destination while
the stroke width stays constant. Briefly ease the source openings at departure
and close the destination openings at arrival so the resting outlines are
complete. The main routes stay fixed during the middle of a transfer.

Preserve the application's mint/teal palette, gap, foreground layering and
reduced-motion preference. Freeze the split direction for each transfer while
following live destination geometry. When centers coincide, the production
version should use the navigation direction or perform a local resize rather
than select an arbitrary travel direction.

## Timing and interruption

Use a bounded duration that grows more slowly than travel distance, so long
moves have higher initial speed. Ease out along arc length for a fast start and
a gentle stop. The preview uses a 240–520 ms base interval with a slower demo
time scale; these are tuning choices, not accepted product requirements.

On a new destination, retain the actual two visible strokes as prefixes of the
new routes. Append new bridges from their tips, preserving their outgoing
tangents, and attach the destination halves. The first frame must retain the
current curves, even after repeated reversals. The preview implements that
position/shape continuity. Carrying velocity continuously across retargets,
tracking Home's moving tiles, overlap/zero-distance cases, and lifecycle cleanup
still need production implementation and native verification.

The existing shared Flutter renderer owns the needed geometry, layering,
timing, reduced motion and pointer transparency. Path measurement/extraction
and cubic Beziers require no new dependency or native adapter. Fixed-width
stroke windows are a simpler approach than further contour deformation.

## Preview evidence

The revised conversation preview has Play/pause, a travel scrubber, selectable
controls and **Show route**, which reveals the combined paths and two inner
junctions. It is separate from the application and uses no accounts or games.

An isolated headless-browser check sampled 41 points on each visible stroke at
20%, 45% and 75% travel; all were on their route. Two immediate retarget checks
preserved the exact visible path coordinates. Longer travel had a higher initial
speed, and the final halves formed the complete destination outline. Layouts at
736 and 320 logical pixels fit without overflow, and no JavaScript exceptions
occurred. The wide, late-transition and compact frames were inspected.

Repeated browser path queries initially cost about 135 ms per update. Measuring
cached geometric perimeters instead reduced the same synchronous update check
to about 1.3–1.4 ms. Those timings exclude browser painting and do not establish
Flutter or native-host performance. Logs and frames are retained under
`.tool-cache/research/focus-path-flow/`. No application change, new native build,
or native acceptance of this effect was established by the browser preview.
