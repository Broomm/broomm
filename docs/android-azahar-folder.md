# Azahar scoped storage on Android

Broomm’s installer uses the official
[Azahar 2126.2 scoped-storage APK](https://github.com/azahar-emu/azahar/releases/tag/2126.2).
Its package is `io.github.lime3ds.android` and its version code is 33989152.
Broomm checks SHA-256
`83cf9c612c0729059f278333ebc20c0cd277826bcf799394acd7c2da5927a3c6`
before handing the download to Android. Existing configured Vanilla installs
keep their package and shared-folder connection.

On Android 11 or newer, user 0 and ARM64, the root check requires the reviewed
standalone APK and signer
`5ba2563e0d13fae2aba067d1c230cd1c863a93005c10d648ce5b331792aa0af1`.
It reads Azahar’s
[user-data preference](https://github.com/azahar-emu/azahar/blob/2126.2/src/android/app/src/main/java/org/citra/citra_emu/utils/CitraDirectoryUtils.kt)
to verify that the selected primary storage tree matches the emulator’s
configuration. It refuses a running Azahar process or ambiguous Lime3DS
migration. Save reads and writes use Android’s persisted folder grant. The
existing journal preserves standalone files and retains recovery if capture
or restoration fails.

## Setup and play

1. Open **Emulator Settings → Nintendo 3DS → Azahar → Set up**. Install Azahar
   if it is missing and accept Android’s installer prompt.
2. Open Azahar once and select a dedicated folder under internal **Documents**
   as its user-data folder. Exit Azahar and select that same folder in Broomm.
   Allow Magisk when prompted. If Android keeps Azahar running after exit,
   stop Azahar in Android’s app settings and retry.
3. Play an installed 3DS game from Broomm. Create an in-game save or a native
   state. Quit emulation before finishing sync. Ordinary 3DS title data and
   verified extdata use the existing cloud format. State compatibility is
   scoped to the exact emulator APK.
4. On devices without root or with other Azahar builds, use **Use shared
   folder** if root verification fails and confirm the folder yourself.
   Broomm keeps the existing save and recovery flow for that folder.

Keep the chosen Documents folder if you want to keep standalone progress.
Broomm’s Remove action uninstalls the selected APK and clears its Broomm
connection. Android’s shared folder and Broomm’s private cloud history are
separate.

## Thor verification

Build 1141 set up the scoped APK through Broomm and launched Mario Kart 7
(title `0004000000030800`). Azahar loaded the three files from the primary
account’s existing RomM save and wrote an 18,033,801-byte Slot 1 state. The
Android bridge rejected the private capture path and retained both recovery
journals and all four native files.

Build 1146 corrected the bridge to use Broomm’s app data directory for shared
captures and legacy MMJ recovery. An in-place update preserved both journals
and all four file hashes. **Finish previous game session** captured the state
and restored the standalone folder. On the next Play, **Use device progress**
published and read back RomM version 275. The original three save files and
Slot 1 restored byte for byte, and Azahar loaded the saved menu selection.

The second RomM account started with no title save or state, then created
its own ordinary save and a 14,671,691-byte Slot 2. RomM read back version
276. The cumulative build 1148 restored the second account’s save and
Slot 2 byte for byte, with Slot 1 absent. Azahar loaded Slot 2. Both
accounts completed with no pending transfer or recovery journal.

Native path regressions cover an allowed capture target and legacy recovery
source, and refuse sibling paths, traversal, and links. All checks and five
packages passed for [build 1146](https://github.com/Broomm/broomm/actions/runs/42574216171)
and [build 1148](https://github.com/Broomm/broomm/actions/runs/42574255749).
