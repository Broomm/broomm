# Keyboard/controller navigation and motion

The current UI uses a shared 3.5-point mint-to-teal stroke with a 3-point gap
around focused buttons, text fields, scrollable descriptions and pairing
controls. Home's shortcuts, game rail, actions and footer form separate
directional rows. The two labeled settings shortcuts start above the
selected tile, with the first button aligned to its left edge. Home reserves
space at both ends of the rail so selections settle near the left edge of the
window. Tile size and scroll offset ease over 340 ms, or settle immediately
with reduced motion.
Titles wrap within the space beside the selection or move below the rail.
Very short layouts can shorten the visual caption while preserving the
full accessible title. Home has horizontal navigation and fits vertically
above the footer. The artwork and stacked Play/Options rows share the
selected tile’s left edge, as do the Game Store title and Open button.
When there is insufficient height for the stacked layout, Play and Options
move to the right of the logo, align to its bottom edge, and retain focus.
Logo spacing defaults to
72 logical pixels from the tile's bottom edge when the caption is beside
the tile and there is room. Each preset adds or subtracts 20 logical pixels.
A cached RomM platform
illustration, when available, appears inside Play to the left of the label.
Logo scale and UI scale combine to size the logo while preserving its
aspect ratio and fitting the available space. See the [current Home walkthrough](../README.md#home-and-save-sync-preview).
Earlier observations below describe their tested builds.

## Ortholinear keyboard and Home artwork movement — 2026-11-19

The keyboard uses one 14-column grid across all five rows. Character keys are
one column wide; both Shift keys and Enter span two columns. Wider footer
controls occupy whole columns. All key edges use the same grid at desktop and
compact widths. Directional navigation uses explicit row/column positions:
Up/Down retains the entry column through wide controls, while Left/Right moves
to an adjacent key and chooses its center column. Row edges stop. The preferred
column survives repeated directions, Shift/Caps relabeling and window resize;
Tab retains ordinary reading order. Existing text, Unicode, clipboard and
controller shortcuts continue to use the original editor.

Horizontally overflowing Home heroes start at the left crop, pause for three
seconds, ease across to the right over 20 seconds, pause for three seconds,
then return over 20 seconds. Top alignment, aspect-preserving cover, the bottom
fade and the underlying atmosphere are retained. Fitting images stay still.
A new image starts from the left. Reduced motion holds the left crop; hidden
applications and muted rendering pause/resume the current position.

The dedicated background widget owns a 50 ms on-demand clock and repaints its
image boundary. It does not rebuild the surrounding page. A one-frame metadata
listener measures decoded aspect ratio and releases its reference/listener;
Image retains its existing cache and animation lifecycle. Image failure keeps
the atmosphere available and stops panning. No game, save or emulator state is
changed. The [walkthrough](../README.md#verify-keyboardcontroller-navigation-and-motion)
covers navigation, pauses, artwork changes and accessibility.

## Circle focus outline and living gradient — 2026-11-19

The application shell paints one foreground outline across screens, dialogs,
notifications and the controller keyboard. The newest visible focused control
owns it. An editing field does not keep a second outline while its controller
dock has focus. Standalone controls retain their root-overlay outline.

The renderer uses one native rounded rectangle throughout. Movement and size
have independent clocks. The ring moves toward the destination center while
shrinking over 160 ms toward a 16-point hollow circle. Stroke width stays
constant and the circle scales with UI scale. Arrival starts a 140 ms expansion
from the current size, even if shrinking has not finished. A new target captures
the current rounded rectangle, redirects its center and starts shrinking again;
rapid navigation therefore keeps the traveling shape compact. Coincident
centers only resize. A delayed frame catches up both clocks rather than
postponing expansion until its next paint.

Center travel eases out over 90–360 ms, with bounded incoming-speed carry on a
retarget. Nearby portrait-card moves have proportional duration in either
axis. Long jumps accelerate within the upper bound. First focus is immediate.
Both source and destination geometry are sampled after layout. Scroll and tile
growth update their geometry without restarting clocks. An interrupted pose
follows its source control's origin and UI scale; attached offscreen sources
remain anchors, and removal retains the last valid source geometry. Once
arrived, expansion stays centered on the live destination.

Point sampling, Bezier contour interpolation, center-line ordering, split
paths and pinch heuristics are no longer in the runtime or current tests.
[Historical experiment notes and fingerprints](research/focus-motion-history.md)
remain separate from the current implementation.

The unchanged 3.5-point mint-to-teal stroke and 3-point gap now have an eight
second rotating gradient, including at rest. A 33 ms timer requests only the
foreground repaint; the page's cached layer is retained. Finite navigation
animations can settle while this slow decoration continues. The timer stops
when focus is removed, hidden or offscreen, or when the application is hidden.
Saved reduced motion and platform disabled animations stop both travel and
rotation. The outline remains transparent to input. Removing the shell disposes
its motion ticker, geometry callback and timer.

The [README walkthrough](../README.md#verify-keyboardcontroller-navigation-and-motion)
includes keyboard, Home, dialog, interruption, scaling, resting color and
reduced-motion checks, plus the offscreen renderer. Physical input feel and
other-host native execution remain owner/platform verification steps. Earlier
observations below describe their tested builds.

### Scrolling and portrait-card correction

Owner testing of build 1211 found faster upward Store motion and broken flow
during Home rail movement. The source perimeter was captured in screen
coordinates while only the destination followed layout. A stationary
170×265-card fixture also measured initial vertical stroke speed about 12%
above horizontal speed with the former square-root duration rule. This was
a contributing pacing difference, not proof of a separate Up-only timing bug.

Build 1212 introduced live anchors and proportional nearby-route timing for
those issues. The owner confirmed the correction worked. The circle renderer
retains the live anchors and directional pacing checks.
Regressions compare portrait pacing in all four directions, translate both
perimeters and interrupted strokes at fixed progress, resize both ends, and
exercise horizontal/vertical viewports with offscreen/removed sources. The
offscreen renderer now includes the actual Home rail's simultaneous growth
and scroll, a mid-scroll reversal, and upward Store reveal. Those checks are
retained for circle motion. These are fixture and raster checks; final
physical-input feel remains owner verification.
The earlier commands, source hashes and frames are retained under
`.tool-cache/research/focus-scroll/`. Current circle checks and frames are under
`.tool-cache/research/focus-circle/`; see the
[implementation status](../IMPLEMENTATION.md) for current counts and build.

Updated 2026-10-18. This review covered the product, implementation, decisions, architecture, profile/authentication, download/setup and controller research Markdown documents, then every implemented Flutter screen: server/profile selection and login, Home/header, Store/search/filters/details/download feedback, preferences, emulator setup/removal, game loading/pairing/paused/playing states and the local controller lab. Save conflict and Android emulator handoff screens are still future work, not reviewed implemented features.

## Changes

Shared traversal requests focus without Flutter's default immediate scroll, then reveals the containing visual unit in each enclosing viewport. Cards include their name/status/padding and fields include their label. A 12-pixel margin is used when space permits. First/last visual rows also reveal the scroll view's heading/footer; visibility of the selected unit takes precedence if these cannot fit together. Already visible interior controls leave scrolling still, and a newer selection stops an obsolete scroll animation. Focus outlines retain a constant border width, with a short eased color/shadow transition. The implementation uses the pinned Flutter SDK, including its [focus traversal callback](https://api.flutter.dev/flutter/widgets/FocusTraversalPolicy/requestFocusCallback.html) and viewport geometry; no package, native dependency or reference-project code was added.

Home uses explicit neighbors along its rail, Down to its primary action and Up back to the selected tile. Header left/right stays in the header and Down returns to the remembered content scope. Saved-server startup selects the remembered server. The local controller lab uses an up/down list with bounded ends and scroll reveal. Hover continues to leave keyboard/controller focus alone.

Store recent picks are a bounded ten-item eager rail. The main catalogue remains a lazy sliver grid. Its geometry determines row/column neighbors and scroll offsets, including destinations not mounted yet. Focused/remembered cards stay alive during fast scrolling and modal/header excursions. New directional requests supersede pending scroll destinations; completion checks the current game identity, focus owner and route. Row edges stop, a short final row clamps to its last game, and Load more hands focus to the first appended game. Loading the final page cannot strand focus on a removed footer. The search field declares the true top and the final grid row/footer declares the true bottom, independently of which lazy children are currently mounted. Emulator Settings uses spatial arrows/controller directions, ordered Tab traversal and a bounded final row; expanded setup animates its height and rechecks visibility when expansion/collapse finishes.

Long game descriptions have a focusable reading region: arrows or controller directions scroll text, then leave for the surrounding actions at a boundary. Platform dialogs reveal the current selection, including deep in a long list. Existing setup-removal confirmations and loading/paused/playing bodies scroll in short windows. Pairing switches to an outer scroll layout when its fixed header/help/actions would leave too little height; its normal desktop tester layout remains.

Async buttons suppress duplicate activation while working. Completion restores temporarily disabled focus only when no newer control/modal owns it; it cannot reclaim focus after navigation. Native controller activation also works with standard Flutter controls such as password visibility. Native Back first leaves inline editing. Held Enter/accept/back/search events are consumed without falling through to ancestor default activation shortcuts; directional repeats remain available. Text editing still owns its caret keys.

Screen changes use a short eased fade/slide with only the current screen mounted. Dialogs and session routes use matching entrance/return motion, and Home's atmospheric color blends between selections. Saved reduced motion and platform disabled animations make these transitions, focus/reading scrolls, setup expansion and active-player reveal immediate. Physical controller D-pad/buttons in pairing remain tester input; join/type/layout/gyro/hold gestures and native gameplay gating are unchanged. Keyboard Enter now respects the selected pairing action, including Cancel, instead of the parent shortcut starting a game.

## Initial verification, before owner testing

The initial [machine-readable record](navigation-and-motion.json) identifies that workspace snapshot, host, commands and logs. Its fingerprints and 130-test count are historical. The owner's subsequent screenshots exposed missing coverage of headings, whole-card bounds and spatial action rows. The [correction record](focus-scroll-corrections.json) identifies the follow-up source and checks. The [README walkthrough](../README.md#verify-keyboardcontroller-navigation-and-motion) provides prerequisites, actions, outputs, effects and cleanup.

On macOS 27.0.1 arm64 with Flutter 3.47.0 / Dart 3.13.0 and Xcode 27.1, analysis and **130 Flutter tests pass**. Both fixture renderers pass, the final macOS app builds, and **three native XCTest checks pass** (the existing Keychain and two window regressions). The actual managed RetroArch/Snes9x Home smoke also passes download-to-Home, loading, pairing, play, normal shutdown and return with the supplied SNES ROM and opt-in synthetic sources. It retains isolated fixture progress, not owner account/game data. This is one real emulator session, not a new six-ROM or physical-input acceptance run.

Regression coverage includes both scroll edges and intermediate animated positions; visible-control stability; disabled/busy retry versus moved or modal focus; Home/header/action return and row boundaries; offscreen grid rows and rapid held input; final-page focus; recent-rail/details return; saved-server startup and mixed-device editing; standard password visibility activation; a 60-platform picker; long-description reading boundaries; reduced motion; and Enter on both pairing Cancel and Apply in a 640×480 window. Existing installation, authentication, locking, recovery and emulator-session tests remain enabled.

During development, rapid scrolling reproduced disposal of the focused grid card; retaining the input owner and scheduling destination focus fixed that failure. Final-page loading required retaining its footer until the appended card could take focus. A 640×480 pairing check exposed a 35-pixel fixed-footer overflow; the compact scroll layout fixed it. Test harness mistakes (tapping clipped controls, waiting on real filesystem I/O inside fake widget time, and sampling before an animation ticker's first frame) were corrected without relaxing the behavior assertions. An initial sandbox attempt could not bind Flutter's loopback test socket; the same tests ran with the required local access. Failed investigation logs are retained under `.tool-cache/research/navigation/`.

PNG inspection covers Home, Store, preferences, expanded/configured/compact emulator cards, removal confirmation and Wii pairing at desktop/phone widths. Those are offscreen Flutter artifacts, not desktop computer-control or physical-controller observations. The changes are shared Dart UI code; successful macOS compilation and synthetic action/channel tests do not establish Linux/Windows/Android native input, Steam/gamescope handoff, final motion feel or owner-server acceptance. Emulator bridges and synchronization are outside this change; earlier six-ROM native records remain historical evidence.

## Scroll and direction corrections after owner testing

The owner supplied three screenshots: returning to Store search left its heading/label clipped, entering an emulator card from above cut its bottom padding, and returning from below left only its action buttons visible. Down also moved sideways through Refresh/Import and Verify/Remove. These are owner-observed failures of the initial implementation. The earlier tests asserted button visibility and the mistaken sequential Down order, which did not establish the intended behavior.

Eager scroll views now identify their first/last enabled visual rows independently for each viewport. Store's lazy grid declares its actual endpoints from catalogue data, so an unbuilt row cannot be mistaken for the end. Focusing Search returns the Store to its minimum offset; focusing the final row/footer reveals the maximum offset. Full emulator/account cards, field labels and the Store featured panel are reveal regions. A unit that barely fits uses less margin; an oversized expanded card keeps the active action visible. A long unsupported-platform tail cannot scroll the selected card out of sight just to reach the page end. If a narrow window cannot fit both its explanatory header and first button, button visibility takes precedence.

Emulator arrows/controller directions use rendered geometry, including compact Wrap rows. Numeric order remains for Tab. The final action row stops Down. Expanding/collapsing setup rechecks the current selection after its size animation. New focus cancels an old reveal immediately, including when the destination already fits and would otherwise start no new animation. Reduced motion still applies.

Analysis and **131 Flutter tests pass**. The rewritten emulator regression checks wide horizontal actions, wrapped vertical actions, full card bounds on down/up movement, oversized setup, cancellation and a long noninteractive tail. Store coverage now checks exact minimum/maximum offsets, heading/label/footer visibility and the final row after loading. The shared regression checks intermediate motion, stationary visible controls and interruption of an old animation. These use real widgets and keyboard/native controller messages with fixture data.

Three offscreen renderer tests pass. The new renderer exercises the reported Store and emulator directions using the application shell and loaded macOS fonts, asserts full card bounds and writes `store-search-top`, `emulator-down-full-card`, `emulator-up-full-card` and `emulator-wrapped-full-card` PNGs. All four were inspected. The two existing renderers cover the other unchanged layouts. The macOS app also builds successfully. Logs and previews are in `.tool-cache/research/navigation-followup/`; [source/log/build fingerprints](focus-scroll-corrections.json) identify this correction. No physical-controller or owner acceptance of the correction, other-host runtime, or new emulator/gameplay run is claimed.

The first compact fixture attempt expected Remove to survive real setup re-inspection of an empty synthetic installation; the test now follows the observed unconfigured state. Another short-window check established that its header exceeded the viewport, then verified focus visibility before resizing to check the exact top. The interrupted-animation regression reproduced a continuing obsolete scroll and drove its cancellation fix. Those investigation logs remain alongside the final passing checks.
