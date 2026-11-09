# Rooted melonDS on Android

This increment uses the official [melonDS 2.0.1 release](https://github.com/rafaelvcaetano/melonDS-android/releases/tag/2.0.1),
the GitHub APK with version code 40 on Android user 0 and ARM64. The pinned
APK hash is `646eb4564c71b0817ace6474e92c169da16630d58826c43e0fe648896311ec94`.
The signer is `0493bb8749289f0304cc868489dd68b930c19ccc4dce2da876bfe6b9bdbabebc`.

The native reader checks the three save-location preferences in
`me.magnum.melonds_preferences.xml` without changing them. The [reviewed source](https://github.com/rafaelvcaetano/melonDS-android/blob/5ec3648d68382dea9c17d6fbf02544e5c2c0afed/app/src/main/java/me/magnum/melonds/impl/SharedPreferencesSettingsRepository.kt)
uses its Android media save directory for launcher games with no writable ROM
parent. Its numbered states go in the save directory or its separate native
state directory. Both modes use the same raw DS save and exact APK state
identity as the existing connected-folder path. Custom folders use the shared
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

On a rooted Android 11 or newer ARM64 device, install the official APK through
**Emulator Settings → Nintendo DS → melonDS → Set up**. Open melonDS once to
initialize it. Use its default save location and set **Save state location** to
**Save directory** or **Internal directory**. Close the app and continue setup.
Play an installed `.nds` cartridge. Save in the game, choose the native Exit
action, return to Broomm and finish the session. If Android retains the
melonDS process, stop it through Android's app settings after saving and
exiting the game, then retry sync. Broomm requires process absence and keeps
the journal if it cannot prove that. No physical input, full packaged launch
or real RomM save round trip is claimed by the file fixture.
