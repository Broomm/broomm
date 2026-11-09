# Rooted melonDS on Android

This increment uses the official [melonDS 2.0.1 release](https://github.com/rafaelvcaetano/melonDS-android/releases/tag/2.0.1),
the GitHub APK with version code 40 on Android user 0 and ARM64. The pinned
APK hash is `646eb4564c71b0817ace6474e92c169da16630d58826c43e0fe648896311ec94`.
The signer is `0493bb8749289f0304cc868489dd68b930c19ccc4dce2da876bfe6b9bdbabebc`.

The native reader checks the effective save locations and DS mode in
`me.magnum.melonds_preferences.xml` without changing them. The [reviewed source](https://github.com/rafaelvcaetano/melonDS-android/blob/5ec3648d68382dea9c17d6fbf02544e5c2c0afed/app/src/main/java/me/magnum/melonds/impl/SharedPreferencesSettingsRepository.kt)
uses its Android media save directory for launcher games with no writable ROM
parent. Its numbered states go in the save directory or its separate native
state directory. Both locations use the same raw DS save and exact APK state
identity as the existing connected-folder path. The reviewed launcher
hands melonDS an exact read-only Android game document. A native ROM library
can substitute an already scanned file with the same name and size, so the
root route requires an empty native library. Custom folders use the shared
setup route.

The root service verifies ownership, the Android mount, the installed build,
and process absence before each file operation. It derives the exact
`.sav` and `.ml0` through `.ml8` names from the installed raw `.nds` file.
Broomm keeps standalone bytes and metadata in its existing journal, installs
only the selected profile's progress, and restores the originals after
capture. The Dart cloud transaction keeps interrupted and offline work
recoverable. File payloads use bounded descriptors through the existing libsu
service. The disposable Thor fixture verified real native publication,
listing, exact readback, cleanup and refusal of a foreign save filename.
The fixture also published with the app's effective media label while the
package directory still had Android's initial generic label.

## Thor verification

On AYN Thor with Android 13 and Magisk 31.1, build 1131 completed normal
Setup and launched Mario Kart DS (USA, Australia) on both screens. Creating
the game's license changed its 262,144-byte cartridge save. Native slot 1
produced a 19,498,151-byte state, which exceeded the original 16 MiB bound.
The refused sync left both files and the recovery journals intact.

Build 1132 at `488f896` accepts states up to 32 MiB per slot. The native
fixture published and captured a copy of the actual state with verified
ownership and cleaned up the fixture. The in-place APK upgrade preserved
both files, the journals and both saved accounts. Broomm recovered the
interrupted session and required review before uploading its progress. After
**Use device progress**, RomM readback succeeded and Broomm restored the
cartridge save and state byte-for-byte before Play. Loading slot 1 returned
the emulator to the captured game menu. A normal second finish cleared
the journals and removed both temporary native copies.

The other saved RomM account started with a fresh cartridge save and no
state in slot 1. It created a different cartridge save and used slot 2.
Both accounts finished with separate RomM versions and state hashes, no
pending transfer and no remaining session journal. Input was sent over ADB.
CI run [42561379858](https://github.com/Broomm/broomm/actions/runs/42561379858)
passed the checks and all five packages for the tested code revision.

## Setup and play

On a rooted Android 11 or newer ARM64 device, install the official APK through
**Emulator Settings → Nintendo DS → melonDS → Set up**. Open melonDS once to
initialize it. Use its default save location and set **Save state location** to
**Save directory** or **Internal directory**. Close the app and continue setup.
Play an installed `.nds` cartridge. Save in the game, choose the native Exit
action, return to Broomm and finish the session. If Android retains the
melonDS process, stop it through Android's app settings after saving and
exiting the game, then retry sync. Broomm requires process absence and keeps
the journal if it cannot prove that. On the Thor, Android retained the
process after the normal native Exit, so this step was needed.
