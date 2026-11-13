#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
broomm_cache="$PWD/.tool-cache/research/android"
broomm_d8="$broomm_cache/r8-9.5.29.jar"
broomm_bridge="$broomm_cache/bridge.jar"
[[ -f "$broomm_cache/api/android.jar" && -f "$broomm_bridge" && -f "$broomm_d8" ]]
broomm_hash=$(shasum -a 256 "$broomm_d8" | cut -d ' ' -f 1)
[[ "$broomm_hash" == f8c762ff84640b10083b934a47278758a7665977e618fab0c927fff00521dea3 ]]
kotlinc tool/android/check_prepared_shared_folder.kt -jvm-target 17 -include-runtime \
  -Xfriend-paths="$broomm_bridge" -classpath "$broomm_cache/api/android.jar:$broomm_bridge" \
  -d "$broomm_cache/prepared-shared-folder-test.jar"
java -cp "$broomm_d8" com.android.tools.r8.D8 --min-api 26 \
  --lib "$broomm_cache/api/android.jar" --output "$broomm_cache/prepared-shared-folder-test-dex.zip" \
  "$broomm_cache/prepared-shared-folder-test.jar" "$broomm_bridge"
