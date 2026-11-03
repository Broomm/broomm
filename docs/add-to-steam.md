# Add to Steam

## Product and implementation

**Broomm settings → Application → Add to Steam** adds the running desktop copy
to the currently signed-in Steam library. It is a controller-navigable action on
Linux, macOS and Windows; Android omits it. Put the full application bundle in
its final location first. Steam must be running, signed in and fully loaded,
with local CEF debugging enabled. No SteamGridDB key is needed for Broomm's own
artwork.

The Dart SDK supplies direct HTTP/WebSocket transport; no extra shipped service,
Node/Puppeteer runtime or library dependency is introduced. Browser automation
packages would add a runtime and dependencies without improving these few fixed
CEF calls. Direct shortcuts.vdf editing would race Steam's in-memory library and
does not satisfy the selected CEF workflow. The integration uses an original
Broomm JavaScript bridge, bundled with the approved artwork. PGCS is reference
material for API contracts; no Go or PGCS code is imported.

The application discovers one `SharedJSContext` page with the Steam loopback
origin on local port 8080 or 8081, including Big Picture `/routes/` URLs. It
rejects remote/ambiguous contexts, proxies and discovery/handshake redirects.
Responses, payload sizes and deadlines are bounded. Unsupported native API
shapes fail visibly instead of editing Steam files as a fallback. Steam APIs are
unofficial and may change with client updates.

Use the current Steam account's identity and all shortcut overviews, including
hidden entries. Inspect native shortcut settings with short-lived
`RegisterForAppDetails` subscriptions; always unregister them. On the tested
Linux client, `RequestAppDetails` returned unsubscribed stale cached settings,
and the overview map was an observable map rather than JavaScript's native Map.
`AddShortcut` also resolved before the overview appeared. Fresh native readback
and a bounded publication wait handle those actual behaviors. Read back the
name from the overview, executable, working directory and empty launch options
before reporting configuration success.

Linux/Windows target the resolved executable. macOS targets the complete `.app`
bundle. Steam receives an explicitly quoted executable and literal start
directory; no command shell is used. Paths with control characters or quotes
are rejected with move/retry guidance. Keep the full bundle in place. Running
Add to Steam after moving the app updates a recorded owned shortcut rather than
claiming another application with the same display name.

Both **Install to Launcher** and **Add to Steam** refresh their existing Broomm
entries when run again, including their managed icon/artwork. Steam refreshes
the current account's matching shortcut and retains its app ID. Updates that
replace the executable or bundle at the same path do not require reinstalling
either shortcut: neither is tied to the executable's file hash or inode. Keep
Broomm's normal data directory so Steam's persistent icon cache remains present.

An app-owned OS lock coordinates Broomm processes. A durable per-Steam-account
receipt records intent before creating the shortcut and its returned unsigned
32-bit app ID before configuration. A namespaced job in Steam's shared context
retains/join an in-flight creation after a lost reply. Unknown/unpublished
results are not treated as absence. Retry after Steam finishes loading; if a
pending result remains unavailable, exit Steam normally and restart it before
retrying. A fresh shared context permits a complete rescan after the previous
Steam process has exited. Multiple exact-path entries produce an actionable
conflict rather than choosing arbitrarily. Closing/updating Broomm drains its
bounded active Steam operation before closing logs or handing off replacement.

The approved artwork is embedded:

| Steam asset | Bundled file | Dimensions |
| --- | --- | --- |
| Cover / capsule | `assets/steam/cover.png` | 600 × 900 |
| Horizontal grid / header | `assets/steam/horizontal.png` | 920 × 430 |
| Hero | `assets/steam/hero.png` | 1920 × 600 |
| Logo | `assets/steam/logo.png` | 1536 × 384, transparent |

Steam's native custom-artwork API receives PNG bytes. Read back each asset via
Steam's same-origin custom-image endpoint and compare its SHA-256. Existing
identical PNGs are reused. Clear older PNG/JPG artwork through Steam before
replacing it, so a prior JPG cannot shadow the new PNG. A partial artwork failure
keeps the valid shortcut and receipt; press Add to Steam again to finish it.
The logo uses a left-aligned position over the hero's quiet area. The ordinary
Broomm icon is copied to stable app-owned storage and passed to Steam's icon API.
Its decoded/sidebar cache can remain stale until a normal Steam exit/reopen;
the application does not force that restart.

## Walkthrough and external effects

1. Enable CEF debugging in Steam yourself and restart Steam normally. The action
   does not create debugging flags or alter Steam startup. On the owner's Linux
   test host only, explicit permission was given to create
   `~/.local/share/Steam/.cef-enable-remote-debugging` and reopen Steam; the live
   shared context was confirmed on port 8080. Steam paths vary with installation.
2. Open Broomm from its final folder. Select **Broomm settings → Application →
   Add to Steam** with keyboard, controller or pointer.
3. Wait for per-phase feedback, then confirmed completion. Steam should list one
   **Broomm** entry with cover, horizontal grid, hero and transparent logo.
4. Repeat the action: it must retain the same app ID. Close Broomm normally,
   then launch it through Steam and test Desktop/Big Picture navigation and
   game/overlay focus on the actual compositor. These visual/input checks are
   separate from API readback.

The action changes only the matching shortcut's name/target/start directory/
launch options/icon/artwork and Broomm's `steam/` coordination/cache files under
its normal data root. It does not change games, saves, emulator settings, other
Steam shortcuts, Steam Input preferences, compatibility-tool selection or
global launcher installation. When refreshing an existing matching shortcut,
the user explicitly refreshes its Broomm artwork and empty launch options too.

To remove the shortcut, use Steam's normal **Remove non-Steam game** action.
Its library artwork is managed by Steam. Broomm's receipt/cache can remain for
safe rediscovery; after both apps have exited, removing only the Broomm data
root's `steam/` directory discards those receipts and icon cache. It does not
remove the Steam shortcut itself. Do not delete receipts while an installation
is pending. To disable debugging on the configured Linux test installation,
exit Steam normally, remove only the `.cef-enable-remote-debugging` flag, and
reopen Steam. CEF debugging grants local client control; avoid exposing its
port to the network.

## Sources and verification

References inspected on 2026-11-03:

- PGCS `internal/steam/{client.go,endpoint.go,probe.js,managed.js,apply.js,artwork.js}`
  for the owner's requested sister-project API audit, without copying code or
  adopting its instructions.
- The test host's installed Valve Steam `steamui/sp.js`: current-user identity,
  observable shortcut map, native detail registration/cache and artwork URL/API
  behavior.
- [Steam client API type definitions](https://github.com/SteamDeckHomebrew/decky-frontend-lib/blob/main/src/globals/steam-client/App.ts),
  including shortcut mutation, detail registrations and library asset enums.
- [Chrome DevTools Runtime protocol](https://chromedevtools.github.io/devtools-protocol/tot/Runtime/)
  for promise-aware, by-value evaluation and exception responses.
- [Artwork provenance and prompts](../design/steam-artwork/v1/README.md). Existing
  Material icon attribution remains bundled; no font files are redistributed.

The Linux host is CachyOS x64, using its installed Steam desktop shared context
on port 8080. Native CEF execution created Broomm app ID **3861238242**, read back
its settings and all four artwork hashes, then repeated installation with the
same ID and matching bytes. A follow-up moved that same shortcut from the older
Linux preview to `~/Downloads/Broomm-Linux-steam-preview/bundle/broomm`, loading
the bridge/artwork from the actual release bundle and repeating successfully.
This is real Steam integration evidence, not a mock.
The owner subsequently reported the feature working on 2026-11-03; no further
device/compositor details were supplied with that confirmation.
Physical controller behavior, visual artwork composition, launch from Steam/
Big Picture/gamescope, native macOS Steam and native Windows Steam remain owner/
native acceptance. No computer-control tools were used.

Automated checks exercise real loopback HTTP/WebSocket framing, promise results,
out-of-order IDs, disconnected/exception responses, remote/ambiguous targets,
both redirect boundaries, literal paths, macOS bundle resolution, durable retry,
unpublished creation, partial artwork, relocation, account-scoped receipts,
held cross-process locks, and keyboard/controller navigation. Workflow fakes
verify orchestration and recovery; they do not establish Steam API behavior.

Current local logs and package evidence are under the ignored
`.tool-cache/research/steam-integration/` directory. The unrelated documented
Linux immediate-close Mesa/Flutter raster crash remains unresolved; this feature
does not claim to fix it.

All **539 macOS** and **470 Linux** applicable Flutter tests pass (one and 22
existing host-specific skips respectively), with clean analysis and Linux
release/dependency audit. The macOS release build succeeds; source and freshly
extracted ZIP pass deep/strict/all-architecture code-signature verification.
Both archives contain the exact current bridge, four approved images and icon.
The macOS preview is ad-hoc signed, not notarized. These development previews
use `0.1.7-dev (1013)`, production user storage and disabled automatic application
updates; a subsequent official CI release remains the production update path.

| Package | Bytes | SHA-256 |
| --- | ---: | --- |
| [macOS universal preview](../build/releases/Broomm-macOS-steam-preview.zip) | 23,660,255 | `b042018d6fc758d76c7cf5088098b2b00285e6f2bead9f9bbcc80238b0abc94b` |
| [Linux x64 preview](../build/releases/Broomm-Linux-x64-steam-preview.tar.gz) | 14,297,677 | `43bd6dd683a87083720ee61e69412bd4883056f169de1433f4471a3dc1b2411d` |
