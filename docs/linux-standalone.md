# Linux standalone emulator integration — 2026-11-02

**Eden reconnect, 2026-11-03:** [native Smash comparison](linux-eden-reconnect.md)
reproduces the owner's Wayland exit 255 after disconnect/resume. Eden's child
now selects XWayland when an X11 display exists. Three native reconnects,
replacement IDs, one/two/one player changes and normal exit pass; actual Qt
backend is confirmed. Physical/Bazzite and Wayland-only acceptance remain.

**Owner follow-up, 2026-11-03:** most systems have now been tested on Linux and
are reported to work well. The owner did not enumerate individual cases;
retain the exact automated evidence below separately. Bazzite/Steam Big Picture
acceptance is planned for 2026-11-04, not yet completed. Subsequent native Eden
Smash loading/virtual-port/pause verification and setup-performance corrections
are recorded in [the follow-up](setup-throughput.md).

This milestone follows the owner's completed Linux x64 RetroArch milestone.
Linux x64 selects its own bundled recipe automatically. It adds Dolphin,
RPCS3, Azahar, Ryubing, melonDS, DuckStation, PCSX2, PPSSPP and Eden. There is
no setup pack to import. Existing macOS recipes and Android external-app
handoff remain separate. ARMSX2's Linux build is ARM64, Astris is macOS-only,
and RPCS3 Intel is a macOS variant; none is advertised as a Linux x64 choice.
Linux ARM64 has a separate bundled RetroArch recipe with the same 15 core
choices. Its frontend and core payloads were checked as AArch64 ELF files.
The Armada-specific variants below are now in the ARM64 setup recipes. Other
standalone packages need separate review. Upstream ARM64 assets exist for
melonDS, DuckStation, PPSSPP and ARMSX2. The standalone bridges depend on
build-specific native symbols, and the SDL dispatch decoder used by some
adapters currently recognizes x64 instructions. ARMSX2 also offers distinct
4 KiB and 16 KiB packages. Select that package using the running kernel's
page size when its standalone integration is reviewed.


## AYN Thor dual-screen feasibility

Armada introduced experimental Gaming Mode dual-screen emulation in
[20260907](https://github.com/armada-os/armada/releases/tag/20260907).
The [Armada Store catalog](https://github.com/armada-os/armada/blob/main/decky/armada-store/catalog.json)
points to AArch64 [melonDS](https://github.com/virtudude/melonDS/releases/tag/drm-leasing)
and [Azahar Enhanced](https://github.com/virtudude/Azahar-AppImage-Enhanced/releases/tag/drm-leasing)
builds. The emulator presents its top view to Gamescope and leases the bottom
DRM connector for direct scanout. The lease does not appear as a second Steam
game window. Armada's
[Gamescope session patch](https://github.com/armada-os/armada/blob/main/packages/gamescope-session/patches/0005-add-drm-lease-functions.patch)
sets aside the secondary panel and its touch device. The bottom Plasma
companion can yield the panel through the
[lease broker](https://github.com/armada-os/armada/blob/main/packages/gamescope/patches/0016-drm-let-a-socket-lease-holder-yield-to-protocol-clients.patch).

The [melonDS fork](https://github.com/virtudude/melonDS/compare/master...drm-leasing)
requires its OpenGL display path with EGL for the lease. The
[Azahar fork](https://github.com/virtudude/azahar/compare/master...drm-leasing)
requires Vulkan with direct-display support. Both can negotiate the lease over
the main Gamescope Wayland socket even when their Qt windows use XWayland.
They read the bottom touch device through evdev. The forks can fall back to
the normal single-window layout when no lease is available. Desktop Mode
exposes both panels as desktop outputs and is a separate window-placement path.
Cemu already has a separate GamePad view. The Armada Store's Cemu entry does
not identify a Gaming Mode lease-capable build.

Broomm lists **melonDS (Armada)** under Nintendo DS and **Azahar (Armada)**
under Nintendo 3DS on Linux ARM64 with `ID=armada` in os-release. They have
separate recipe IDs and installation directories. Each variant uses the
corresponding Broomm-owned DS or 3DS profile and save format. Stock host
recipes retain their own identities and download sources. Broomm enables
the relevant renderer for the variants when launched through Gamescope.
Normal setup downloads the reviewed AppImages and uses their private
extraction roots (`squashfs-root` for melonDS and `AppDir` for Azahar).

Both downloaded archives matched the provider SHA-256. Their extracted trees,
AArch64 executables and SDL dispatch metadata were inspected. Both extracted
payloads passed Broomm’s normal inventory verification, installation and
private-profile resolution in disposable storage. The native
Linux sanitizer fixture checks the captured ARM64 melonDS SDL stub. The
stripped Azahar ELF uses a build-pinned SDL 2.32.10 dispatch table, identified
from its relocation array and initializer stubs. The top-panel Settings and
Controller pairing retain the existing Gamescope handoff. The forks read
bottom touch through evdev, so verify touch during pause independently on
the Thor. Lease loss, single-window fallback, suspend/resume, display return
on exit, per-profile save/state behavior and CIA installation also require
native device verification.

## Implemented boundaries

All nine official source archives, complete file/link inventories, native SDL
versions and required local symbols are pinned in `assets/setup/linux-x64/`.
Application packaging includes original Broomm SDL2/SDL3 bridges, the native
installer guard and a small process supervisor. No emulator, core, BIOS, key,
ROM, Qt, extra SDL copy or compiler is bundled inside Broomm's release archive.
Emulator downloads retain upstream licenses/notices; executable updates require
explicit Setup/Verify, as before. Launch checks the setup-bound file metadata
and ELF architecture without hashing the full installation again.

Dart owns archive validation, preparation, settings, firmware/content publication,
profiles, save/state synchronization and recovery. C provides OS/native SDK
interop only. AppImage extraction runs without FUSE, inside a kernel-confined
private stage; ZIP/tar staging retains path/link/collision/size limits. The
supervisor drains its process group and adopted daemon children before releasing
an inherited writer lock. Installer networking is denied except local Unix IPC.
Linux needs Landlock ABI 3 (normally kernel 6.2+); unsupported kernels fail with
existing data preserved. No OS packages or global settings are installed.

Game sessions discover physical controllers through the emulator's own SDL.
Stable logical ports receive Broomm's pairing/mapping/motion output; native
pause/readiness is acknowledged before pairing. Qt operations run on a native
Qt timer, not inside arbitrary `poll` calls holding graphics/X11 locks. Both
reviewed SDL x64 dispatch forms are recognized without scanning into the next
export. Controller menus, disconnect gating and normal stop share the existing
Dart supervision/progress lifecycle. Native pauses retain explicit ownership. A native pause regression also corrected shared Wii command ordering: active route re-publication cannot manufacture Resume; the correction applies on macOS as well.

Profile-local XDG aliases bind each emulator's actual data path to the existing
cloud adapter. Azahar launches from its private HOME to avoid its cwd/user
precedence. PCSX2 named shared memory is redirected into its own profile.
DuckStation uses its bundled RUNPATH without a redundant LD_LIBRARY_PATH that
would trigger a blocking native warning. PPSSPP/Eden use their reviewed Sharun
loader with its preload opt-in; the underlying ELF cannot use Ubuntu's loader.
Open emulator is detached and independent: Broomm stays visible and does not
watch/wait for it; native private configuration retains its writer exclusion.

Ryubing's existing GDB stub and PPSSPP's existing WebSocket debugger provide
acknowledged CPU pause from inside the emulator process. The endpoint is forced
to loopback and verified against a listening descriptor in that same process;
a port collision never authorizes an unrelated service. Requests, frames,
responses and operation deadlines are bounded. PPSSPP discovery advertisement
is disabled. The connection remains inside the emulator after Broomm exits,
preserving the orphan pause. Ryubing's debugger enables upstream JIT debugging
and may affect performance; no zero-overhead claim is made.

Eden applies player sockets through its own scoped configuration action and
native checkboxes while paused. This is in-process Qt interop; it does not
control another OS window. User-opened native dialogs retain normal behavior.
Switch NCA header inspection retains Apple's AES on macOS and uses a bounded
original Dart AES-128 primitive on other hosts. The latter follows FIPS 197,
with NIST multi-block vectors, independent Apple comparison and XTS sector
checks. It is limited to media headers, not credentials/general encryption.

## Verification and remaining acceptance

Native host: the owner's CachyOS x86_64 machine, AMD Radeon RX 6600 XT, over the
authorized SSH/desktop-session connection. The owner's running Broomm PID and
production data were preserved. Tests use project-contained disposable profiles,
original guest loops, public PSP2048/Basic Water homebrew, and narrowly copied test BIOS images.
No production saves or RomM assets were changed by these tests.

| Emulator | Pinned Linux build | Native evidence |
| --- | --- | --- |
| Dolphin | 2609-166 / d182533d363e | 🟢 GameCube/Wii guest launch, pairing/remap/menu/disconnect/reconnect/normal exit; all four Wii layouts read back |
| Azahar | 2126.1.2 | 🟢 3DSX launch/controller lifecycle and normal exit; CIA import/title-content readback |
| melonDS | 1.1 | 🟢 Original DS loop and native controller lifecycle/normal exit |
| DuckStation | v0.1-12083 / 00e299795 | 🟢 Original PS-X EXE, test BIOS and native controller lifecycle/normal exit |
| PCSX2 | 2.8.2 / fd9d310 | 🟢 Original PS2 ELF, test BIOS and native controller lifecycle/normal exit |
| PPSSPP | 1.20.4 / 3a31057 | 🟢 Public PSP2048 PBP and native controller/debugger pause lifecycle/normal exit |
| RPCS3 | 0.0.42-20031 / d08d568d | 🟢 Native PUP install/liblv2 readback; Basic Water homebrew controller lifecycle/normal exit with fixture-local interpreters |
| Ryubing | 1.3.3 | 🟡 Installation/private profiles verified; native Switch runtime/physical input pending |
| Eden | 0.2.1 | 🟢 Smash launch/pause, three native reconnects and player-count changes through XWayland; physical/Bazzite acceptance pending |

All nine production installations and two independent profiles per installation
were exercised, including full archive verification/extraction/publication.
Linux native kernel/process regressions and independent ASan/UBSan runs cover
write confinement, stable locks, cancellation/adopted descendants, protocol
framing/checksums/root acknowledgements, endpoint identity and SDL stub forms.
The native host recovery fixture and existing RetroArch fixture remain separate. The first bare PS3 loop remained in native Starting because it lacked an ordinary initialized program environment; it is not shipped as a successful test fixture. Basic Water v2.0.0 supplies the valid PS3 test. Interpreter selection is test-local and makes no performance claim for production LLVM.

The Qt comparison used child-only X11/XWayland and verified `xcb` actually loaded;
earlier Wayland runs exposed the reentrant poll problem. This does not establish
that Wayland is generally broken or authorize a global backend preference.
The final default-backend check is recorded in the JSON evidence.
Devbox's test environment hid host Vulkan driver directories; test-only
XDG_DATA_DIRS restored them. Production/Steam driver paths were not overridden.

Firmware and content workflows use the shared adapters: PS3 PUP/PKG/RAP, 3DS
CIA, Switch firmware/keys/updates/DLC, and existing PSP folders. Wii updates
remain unnecessary for the owner's catalogue. The pinned Azahar package lacks
an offscreen Qt plugin: its --install command uses the existing desktop
connection but exits before showing a main window. RPCS3 needs a 32 GiB sparse
VM backing file even in installer mode; native installer limits allow that,
while archive extraction stays capped at 8 GiB. Content limits still apply.

Runtime checks do not establish completed commercial gameplay, new native
save/state creation on every standalone, physical controller/gyro behavior,
Steam Input or gamescope stacking. These remain owner acceptance. In particular,
automatic approval review rejected exporting private Switch prod/title keys to
the Linux host; no alternative export was attempted. Switch runtime testing
needs explicit authorization or keys already configured by the owner there.
Windows, Android and ARM64 native execution are not inferred from this host.

## Owner walkthrough

1. Install the official Linux x64 CI release, keeping its `lib/` and `data/`
   beside `broomm`. Normal `~/.config/broomm` storage remains unchanged.
2. Open Emulator Settings, expand a supported platform and review/confirm Setup.
   Confirm the configured/default card. Open emulator should leave Broomm usable.
3. Play an installed game. Missing BIOS/firmware comes from that platform's RomM
   catalogue using its normal provisioning flow. Pair with L1+R1, test buttons,
   hold Start, then open the menu with R3+Select. Test face swapping, disconnect,
   reconnect, normal native pause and normal exit. Wii supports all four layouts.
4. Confirm cloud status on return, test a second profile and inspect a saved
   timestamp in the BROOMM slot. Preserve pending/conflicting progress until
   explicit resolution. Switch has ordinary saves but no save states.
5. For a failed native launch, keep the profile's `broomm.log`/`bridge.log` and
   application logs; use the displayed recovery/close flow. Do not delete stable
   lock files or clean a profile while its native writer may still be alive.

Opt-in checks (after explicitly acquiring the pinned inputs) are
`tool/check_linux_standalone_test.dart`, `tool/check_linux_gameplay_test.dart`,
`tool/check_linux_import_test.dart` and `tool/check_linux_retroarch_test.dart`.
The original program generator is `tool/fixtures/standalone_programs.py`.
`tool/linux_desktop_test.py <authorized-pid> <literal-command...>` keeps approved
desktop connection values in memory. Evidence stays in ignored
`.tool-cache/research/linux-standalone/`. Cleanup may remove only those disposable
fixtures after their verified native writers exit; never production storage.

## Source and implementation choices

- [Qt QTimer](https://doc.qt.io/qt-6/qtimer.html) and [Qt 6 source](https://code.qt.io/cgit/qt/qtbase.git/): existing application runtime, no new Qt dependency. The reviewed object/vtable ABI is guarded; arbitrary emulator upgrades are rejected.
- [SDL DynAPI](https://wiki.libsdl.org/SDL3/README-dynapi): use the actual runtime table, not a second library/device enumeration.
- [Linux Landlock](https://docs.kernel.org/userspace-api/landlock.html): native private write policy, with no bubblewrap/container daemon dependency.
- [Sharun](https://github.com/VHSgunzo/sharun): retain the reviewed upstream loader; bypassing it requires a newer host glibc.
- [RPCS3 d08d568d](https://github.com/RPCS3/rpcs3/tree/d08d568d5edf4f21508d9b8e471197e6d6f499ad), [Azahar 2126.1.2](https://github.com/azahar-emu/azahar/tree/2126.1.2), [Dolphin d182533d363e](https://github.com/dolphin-emu/dolphin/tree/d182533d363e): source contracts and independent pinned ELF symbols, not copied emulator implementations.
- [Ryubing 1.3.3](https://git.ryujinx.app/projects/Ryubing/src/tag/1.3.3), [PPSSPP v1.20.4](https://github.com/hrydgard/ppsspp/tree/v1.20.4), [Eden v0.2.1](https://git.eden-emu.dev/eden-emu/eden/src/tag/v0.2.1): native input/configuration/debugger contracts. The direct official Ryubing archive is pinned; no Anubis challenge bypass was used.
- [FIPS 197](https://csrc.nist.gov/pubs/fips/197/final), [SP 800-38A](https://csrc.nist.gov/pubs/sp/800/38/a/final): bounded Dart AES for header inspection avoids another runtime dependency. OpenSSL/PointyCastle would add distribution/maintenance dependencies; the kernel [AF_ALG interface](https://docs.kernel.org/crypto/userspace-if.html) is deprecated and unavailable on the host, so is not used. Original scalar Dart is slower than hardware crypto but works across target architectures; the API caps each operation at 64 KiB and retains native Apple crypto on macOS. No upstream crypto code is copied.

Final validation: **483 macOS Flutter tests** and **414 Linux tests** pass, with
22 native/platform comparison skips stated in the [evidence](linux-standalone.json).
All eight lifecycle cases pass with the default backend and child-only X11;
Qt logs confirm the actual backend. Analysis, formatting, workflow lint, native
kernel/process/protocol tests, independent sanitizers and host recovery pass.
The current macOS ZIP is **21,196,410 bytes**, SHA-256
`16c8c9f4af464fea08c350a1f0d738ba802093d7c6f7525867015e0ecac151a4`.
Its source and freshly extracted deep/strict/all-architecture signatures and
archive/readback checks pass. It is universal and ad-hoc signed, not notarized.
The native Linux app builds and its complete ELF dependency audit passes.
Official Ubuntu/Windows/Android/ARM64 CI execution remains distinct.
