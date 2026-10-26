# RPCS3 unattended installer exit correction

Implemented 2026-10-23 alongside the [live RomM support matrix](platform-support-matrix.md). The matrix is planning/documentation; this correction is the only emulator runtime behavior changed in this follow-up.

The owner's macOS crash report after GT6 package installation records SIGABRT in `report_fatal_error` during `__cxa_finalize_ranges`. The matching retained installer log confirms successful package installation followed by the pinned RPCS3 0.0.42-20031 / d08d568d uninitialized emulation-object destructor failure. The earlier adapter accepted that exact completed-install failure after verification, but macOS still showed its system crash notification. Source and package data were not the cause of that notification.

The existing precompiled universal `broomm-installer-guard.dylib` now interposes `abort()` only when its writer lock was acquired and this child explicitly receives `BROOMM_INSTALLER_ABORT_MODE=rpcs3-cli-v1`. It writes the fixed `BROOMM_RPCS3_CLI_ABORT_V1` marker and exits with **non-success status 86**, retaining writer ownership until OS process exit. It neither resumes execution after a fatal error nor turns that error into success. Gameplay and no-game configuration do not set the opt-in; their ordinary crash behavior is preserved. No OS crash-report preference, emulator binary or user configuration is modified, and no new library dependency was introduced.

Dart accepts status 86 only with the guard marker, the exact native package/firmware completion checkpoint and the known process-teardown diagnostic. The add-on/firmware caller still independently verifies imported content before publication. An arbitrary failure, missing completion, or exit 86 without the marker remains an installation error with retained diagnostics and existing progress kept. Signal failures other than the opted-in `abort()` path are unchanged. A process identifier is included in the bounded installer log for correspondence with crash reports; no environment/credential values are logged.

## Verification

- **257 Flutter tests pass**, with separate static analysis/build results in the JSON.
- **Five native guard checks pass:** writer exclusion through exit, orphan retention, held/linked lock rejection, opted-in abort producing status 86 rather than SIGABRT, and non-opted-in abort still reaching the original SIGABRT handler. The last uses a fixture-only handler that exits before a system crash notification is generated; real app crash handling is unchanged.
- **Three native adapter regressions pass:** verified completed teardown accepted; genuine failed installation rejected; forged exit 86 without a bridge marker rejected.
- **Two real GT6 package imports pass**, using existing Broomm-managed ARM and Intel/Rosetta executables in separate disposable profiles. Each produces the exact canonical eleven-file inventory; measured durations were 1,460 ms and 1,785 ms. Both emit the bridge marker and have no corresponding macOS crash report for their PID.
- **One real firmware workflow passes** through the changed installer path, privately installing the already supplied PUP and reusing the verified result across two disposable profiles. No server upload or owner profile write occurs.

The first native test mistakenly used an old prototype ARM executable with adjacent portable data. Its attempted write outside the scratch directory was denied by the production sandbox and the installation was correctly rejected; the Intel prototype attempt also hit the test's original 30-second deadline. Logs are retained. Correcting the fixture to use the app's actual managed executable locations makes both real imports pass within two seconds, without changing timeouts or relaxing assertions. The owner's running game was inspected only to distinguish it from test children and was not interrupted.

Native input/overlay behavior is not revalidated by an installer test. Linux/Windows/Android installer behavior remains outside this macOS correction. The source/output hashes, exact commands, logs, failed first run and release checks are in [the companion record](rpcs3-installer-exit.json).

## Owner check and cleanup

Close old Broomm copies normally, open the updated Mac build, and install a newly available PS3 package with **Options → Download Updates and DLC**. Rechecking unchanged content legitimately does no native import. Expect Broomm's completed result and no macOS “RPCS3 quit unexpectedly” notification. Keep real error reporting enabled; a rejected package should still display an actionable Broomm error and retain the existing game/progress.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer devbox run -- bash tool/build_bridges.sh
devbox run -- flutter test tool/check_installer_guard_test.dart --reporter expanded
devbox run -- flutter test tool/check_rpcs3_installer_exit_test.dart --reporter expanded
devbox run -- flutter test tool/check_ps3_firmware_test.dart --reporter expanded
devbox run -- flutter analyze
devbox run -- flutter test
devbox run -- bash tool/build_app.sh --release
```

Native CLI checks require the existing managed RPCS3 pack, Intel Rosetta runtime, cached GT6 PKG/canonical generation and owner-provided PUP. They create private `installer-exit-*` folders under `.tool-cache/research/platform-support/`; guard tests and the firmware check use the existing library-followup evidence area. After their native writers have exited, those disposable folders can be removed. Keep normal `broomm-data` profiles, saves, package receipts and stable lock files. No user ROM, firmware source, server asset or live save was deleted.

Release: `build/releases/Broomm-macOS-arm64-installer-fix.zip`, 19,515,204 bytes, SHA-256 `e66516df85e9b629ac5de9abd0af1ab3a7103d63c3d3443f548f19317d62c76a`. Static analysis is clean; the release build, ZIP integrity, bundled universal-library hashes and fresh extracted deep strict signature pass. The incremental outer seal was refreshed after independently verifying both nested frameworks. This remains the existing checkout-bound Apple Silicon development distribution, without notarization or new emulator installations.
