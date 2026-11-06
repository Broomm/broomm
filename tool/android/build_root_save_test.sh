#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
broomm_android_cache="$PWD/.tool-cache/research/android"
# Android API jar is verified/provisioned by check_bridge.sh first.
broomm_d8="$broomm_android_cache/r8-9.5.29.jar"
if [[ ! -f "$broomm_d8" ]]; then
  curl --fail --location --silent --show-error --max-time 120 \
    https://dl.google.com/dl/android/maven2/com/android/tools/r8/9.5.29/r8-9.5.29.jar -o "$broomm_d8.pending"
  mv "$broomm_d8.pending" "$broomm_d8"
fi
if command -v sha256sum >/dev/null 2>&1; then broomm_hash="$(sha256sum "$broomm_d8" | cut -d ' ' -f 1)"
else broomm_hash="$(shasum -a 256 "$broomm_d8" | cut -d ' ' -f 1)"; fi
[[ "$broomm_hash" == f8c762ff84640b10083b934a47278758a7665977e618fab0c927fff00521dea3 ]]
kotlinc android/app/src/main/kotlin/app/broomm/broomm/RootSaveFiles.kt \
  android/app/src/main/kotlin/app/broomm/broomm/RetroArchCoreAbi.kt \
  android/app/src/main/kotlin/app/broomm/broomm/RetroArchControllerProfiles.kt \
  android/app/src/main/kotlin/app/broomm/broomm/SharedDocumentLock.kt \
  tool/android/check_root_save_files.kt -jvm-target 17 -include-runtime \
  -classpath "$broomm_android_cache/api/android.jar" -d "$broomm_android_cache/root-save-test.jar"
java -cp "$broomm_d8" com.android.tools.r8.D8 --min-api 26 \
  --lib "$broomm_android_cache/api/android.jar" --output "$broomm_android_cache/root-save-test-dex.zip" \
  "$broomm_android_cache/root-save-test.jar"
echo "Compiled Android root filesystem test: $broomm_android_cache/root-save-test-dex.zip"
