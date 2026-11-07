#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
broomm_android_cache="$PWD/.tool-cache/research/android"
# check_bridge.sh and build_root_save_test.sh provision these verified tools.
kotlinc tool/android/check_activity_results.kt -jvm-target 17 -include-runtime \
  -classpath "$broomm_android_cache/api/android.jar:$broomm_android_cache/flutter-embedding.jar:$broomm_android_cache/bridge.jar" \
  android/app/src/main/kotlin/app/broomm/broomm/EmulatorUninstall.kt \
  -d "$broomm_android_cache/activity-result-test.jar"
broomm_fixture_classes="$(mktemp -d "$broomm_android_cache/activity-result-classes.XXXXXX")"
trap 'rm -rf "$broomm_fixture_classes"' EXIT
unzip -q "$broomm_android_cache/bridge.jar" \
  'app/broomm/broomm/SharedSaveFolder*' 'app/broomm/broomm/ApkInstallPermission*' -d "$broomm_fixture_classes"
unzip -q "$broomm_android_cache/flutter-embedding.jar" \
  "io/flutter/plugin/common/MethodChannel\$Result.class" -d "$broomm_fixture_classes"
jar cf "$broomm_android_cache/activity-result-mechanisms.jar" -C "$broomm_fixture_classes" .
java -cp "$broomm_android_cache/r8-9.5.29.jar" com.android.tools.r8.D8 --min-api 26 \
  --lib "$broomm_android_cache/api/android.jar" \
  --classpath "$broomm_android_cache/bridge.jar" \
  --output "$broomm_android_cache/activity-result-test-dex.zip" \
  "$broomm_android_cache/activity-result-test.jar" "$broomm_android_cache/activity-result-mechanisms.jar"
echo "Compiled Android activity result test: $broomm_android_cache/activity-result-test-dex.zip"
