#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
broomm_duck_cache="$PWD/.tool-cache/research/android"
broomm_duck_d8="$broomm_duck_cache/r8-9.5.29.jar"
test -f "$broomm_duck_cache/api/android.jar"
if command -v sha256sum >/dev/null 2>&1; then broomm_duck_hash="$(sha256sum "$broomm_duck_d8" | cut -d ' ' -f 1)"
else broomm_duck_hash="$(shasum -a 256 "$broomm_duck_d8" | cut -d ' ' -f 1)"; fi
test "$broomm_duck_hash" = f8c762ff84640b10083b934a47278758a7665977e618fab0c927fff00521dea3
kotlinc android/app/src/main/kotlin/app/broomm/broomm/RootDuckFiles.kt \
  android/app/src/main/kotlin/app/broomm/broomm/RootDuckProcess.kt \
  android/app/src/main/kotlin/app/broomm/broomm/RootProcessKernel.kt \
  android/app/src/main/kotlin/app/broomm/broomm/DuckPauseProof.kt \
  tool/android/check_root_duck_files.kt -jvm-target 17 -include-runtime \
  -classpath "$broomm_duck_cache/api/android.jar" -d "$broomm_duck_cache/root-duck-test.jar"
java -cp "$broomm_duck_d8" com.android.tools.r8.D8 --min-api 30 \
  --lib "$broomm_duck_cache/api/android.jar" --output "$broomm_duck_cache/root-duck-test-dex.zip" \
  "$broomm_duck_cache/root-duck-test.jar"
