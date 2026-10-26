# Nintendo 3DS updates and DLC

Implemented 2026-10-22. Initial native delivery is the existing **macOS ARM64 Azahar 2126.1.2** managed pack. Linux, Windows and Android remain product targets; this change does not claim native add-on support on them.

## Behavior

- After a 3DS base download commits, discover update/DLC packages in the authenticated RomM game manifest and import them automatically. Folder names `updates`, `update` and `dlc` are recognized, as are API categories `update`/`dlc`.
- Home Select/Back, Options, right-click or long-press opens **Download Updates and DLC**. It refreshes that game's detail/permission check, compares file identity, size and valid remote hashes, and fetches changed packages only. Missing/blank hashes require revalidation; a timestamp or unchanged size is not proof of equality. Metadata-only timestamps do not force an import when content hashes are unchanged.
- Existing verified CIA payloads in a prior game download are reused. The base ROM is never downloaded by this action. Repeated checks verify deployed files and repair missing/changed tracked content from the shared cache without another native import. Unknown extra files block destructive replacement/removal.
- Packages must be unpacked decrypted `.cia` files, at most 16 GiB each. Archives, compressed CIA variants, encrypted packages, foreign title/region IDs and base/system CIAs fail visibly. NCSD/NCCH base headers and CIA TMD identities establish correspondence. Filename similarity is not identity.
- Native import runs in private staging. Only expected update/DLC title `content/` directories and exact tickets are copied into account-local emulator data. Configuration, logs, NAND system data, base title saves, title `data/`, extdata and save states never enter a publication/removal transaction.
- The active profile receives its copy immediately. Other profiles receive private copies at launch after their normal catalogue permission check. Newer tracked content shared by installed ROM variants is not downgraded. Content retains an owner reference for every installed variant that uses it.
- Delete uninstalls the game's owned native content in every Broomm profile, then removes shared packages/ROM/artwork. A title still used by another installed version is retained. Saves/states and RomM content remain untouched. Failed cleanup keeps a retryable deletion entry.
- A session lease excludes gameplay/setup/deletion while add-ons are installed. Home Play displays **Installing…** for the current installation; direct launch requests also wait for it to finish. Download/verification/import phases and cancellation use the existing transfer UI and timed notices. Artwork pickers wait until installation work ends.
- A failed import retains the completed base game, reports the reason and points to the menu action for retry. Failure to fetch a manifest does not imply that remote add-ons were removed. Previously installed content is retained when a successful listing no longer contains an old package; automatic remote-driven removal is not part of this milestone.

## Storage and interruption

`<data>/addons/<server>/<rom>/current.json` selects a self-contained immutable generation with CIA sources, a SHA-256 payload inventory and title versions. Downloads and native output stage under that game, never in an emulator profile. A fully verified generation is published before private deployment. A checkpoint outside an old generation allows interrupted cache retirement to finish without losing ownership evidence. A change temporarily needs room for old/new CIA and extracted content copies; superseded generations are retired after publication.

Each `<data>/profiles/<profile>/emulators/azahar/addons.json` records exact native units and their server/ROM owners. `.addon-transaction/` stages replacements and preserves old content; `addons-pending.json` stays outside recursive cleanup. Recovery checks the original registry, observed file inventory, allowed destinations and prepared replacement hashes before moving anything. An explicit commit checkpoint distinguishes a completed transaction from a repair whose before/after registry is identical. Recovery runs before another apply/uninstall or gameplay. Untracked native content is never silently adopted.

Game deletion first publishes the library's existing external deletion intent, then removes native claims under the same session/library locks. Shared add-on cleanup has its own external checkpoint. Losing an inner receipt/manifest during cleanup does not make pending data unidentified or authorize unrelated deletion. Neither session nor writer lock files are removed.

CRC verification uses a Dart worker isolate; SHA tools and the native importer run asynchronously with bounded operations. Network/CRC/native import can be cancelled. Once a private publication starts, its short transaction finishes or retains recovery evidence. Existing profile configuration, the bridge protocol and system installations are preserved. No new application dependency, helper service or PGCS code was introduced.

## Native contract and source evidence

The existing tested Azahar Qt executable accepts `--install <CIA>` and exits with a status plus `Installed CIA successfully.` on macOS. A bounded child process runs with a fresh HOME/XDG/temp environment and macOS write confinement to staging; network is denied and no input bridge is injected. Azahar prefers an adjacent portable `user/` directory over HOME, so that unexpected configuration is rejected before import. The isolated initial probe confirmed this distinction without allowing writes to the owner profile.

The official tagged implementation is the authority for [CLI behavior](https://github.com/azahar-emu/azahar/blob/2126.1.2/src/citra_qt/citra_qt.cpp), [CIA installation and content-only cleanup](https://github.com/azahar-emu/azahar/blob/2126.1.2/src/core/hle/service/am/am.cpp), [CIA structure](https://github.com/azahar-emu/azahar/blob/2126.1.2/src/core/file_sys/cia_container.h), [TMD structure](https://github.com/azahar-emu/azahar/blob/2126.1.2/src/core/file_sys/title_metadata.h), [NCSD/NCCH identity](https://github.com/azahar-emu/azahar/blob/2126.1.2/src/core/file_sys/ncch_container.h) and [portable/data lookup](https://github.com/azahar-emu/azahar/blob/2126.1.2/src/common/file_util.cpp). The local [RomM 5.4.0 schema](reference/romm-5.4.0-openapi.json) defines per-file categories and fingerprints. [RomM's folder documentation](https://docs.romm.app/4.8.1/Getting-Started/Folder-Structure/) also uses singular `update`; the owner's plural `updates` is supported alongside it.

The same Qt CLI uses a blocking message box on Windows, so unattended Windows import cannot be inferred from macOS success. Linux still needs its managed pack, native execution and storage/backend validation. Android needs an external emulator import contract; it does not inherit desktop injection or filesystem access.

## Verification and owner acceptance

Run serially through Devbox:

```sh
devbox run -- flutter --suppress-analytics analyze
devbox run -- flutter --suppress-analytics test
devbox run -- flutter --suppress-analytics test tool/check_3ds_addons_test.dart --reporter expanded
devbox run -- bash tool/build_app.sh --release
```

The native check requires the already downloaded supplied Smash Bros. CCI/DLC and existing managed Azahar. It clones those **read-only sources** into a unique `.tool-cache/research/3ds-addons/native-workflow-*` directory. It reconstructs a remote manifest from the copied receipt, uses the production manager/import/deployment/removal paths, checks a second private profile and preserves test save sentinels. It never authenticates to RomM or writes to the owner's installed game/progress. This establishes real native import and filesystem behavior, not live server transfer or in-game DLC visibility.

Native evidence: Azahar **2126.1.2**, executable SHA-256 `3dfdfbed147cfb420f224385e832191833d07b0951d4b86326ab193e2deb3b21`; Smash base title `00040000000edf00`, DLC title `0004008c000edf00`. One actual CIA produced **118 imported files**, zero remote transfers, zero repeat imports, successful second-profile application and all-profile uninstall with three progress sentinels retained. Timings and the exact isolated root are saved in `.tool-cache/research/3ds-addons/native-workflow.json`. Unit tests cover update packages, folder/API discovery, identity/category rejection, remote/copy/import failure, cancellation, missing hashes, repair, shared ownership, OS lease exclusion, interrupted publication/deletion and untracked/linked data. Widget tests activate the menu by controller actions. A supplied real update CIA, physical-controller acceptance and non-macOS native execution remain unverified.

Final validation: analysis is clean, all **175 Flutter tests** pass, the native workflow passes, and the release app plus an extracted copy pass strict/deep signature verification. ZIP integrity also passes. The archive is `build/releases/Broomm-macOS-arm64-3ds-addons.zip`, SHA-256 `acd11cdf076245cb7b92fbd5e554d9c15f1a32d8354e4ddd85f9113ae626ef66`. It is the existing checkout-based development distribution, not a notarized standalone emulator installer. [Machine-readable evidence](3ds-updates-and-dlc.json) includes source fingerprints, complete check-log fingerprints, native timings and artifact size.

For owner testing, open the new build, select the existing **Super Smash Bros. for Nintendo 3DS** tile, press **Select/Back → Download Updates and DLC**, wait for completion and Play. No base download is needed. Repeat the action to see the up-to-date result. For a fresh game, choose **Download game** in the Store and let its automatic add-on phase complete before Play. Verify DLC within the game. Delete a disposable test installation, redownload and confirm progress survives. Full directions and build location are in [README](../README.md).

After all fixture processes have exited, only `native-workflow-*` test directories under this research folder may be removed to reclaim cloned binaries/fixture data. Never use normal `broomm-data/profiles` for manual cleanup. Preserve `native-workflow.json` and check logs if retaining evidence.
