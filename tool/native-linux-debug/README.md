# Native Linux debugger

This is a development-only GNU GDB 15.1 environment approved for investigating
Eden's native pause/shutdown hang. Its recipe uses the same immutable Nixpkgs
revision as the project's Linux native tools. It adds no application runtime
dependency and installs nothing through the OS package manager.

On a native Linux development host, from the repository root:

```sh
devbox --config tool/native-linux-debug run -- gdb --version
```

Use only disposable, private emulator profiles for native reproductions. Turn
off auto-loaded debugger scripts and debuginfod, suppress frame arguments and
locals, and disable core dumps. A debugger may stop the inferior's threads;
compare observations with the undebugged failure. Keep captures bounded and
confirm process identity and actual exit before removing its copied data.

See [the approved plan](../../docs/eden-native-debugging.md) and the
[Thor investigation](../../docs/thor-gameplay-investigation.md) for scope and
evidence. Native ARM64 provisioning is verified; this is not an x64 debugger
execution or game compatibility acceptance claim. GDB is GPL-3.0-or-later and
is not bundled into a Broomm release.

The owner declined a custom Eden build and additional Qt SDK on November 5,
then deferred further Linux ARM64 work. The uncompiled source experiment is
archived in ignored local investigation storage, outside committed product/tool
sources. Do not resume or deploy it without a new owner request. The approved
GDB recipe and lock remain reproducible development tooling; the linked
investigation records its findings and limits.
