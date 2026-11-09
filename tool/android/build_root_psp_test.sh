#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
broomm_psp_cache="$PWD/.tool-cache/research/android"
broomm_psp_d8="$broomm_psp_cache/r8-9.5.29.jar"
[[ -f "$broomm_psp_cache/api/android.jar" && -f "$broomm_psp_d8" ]]
if command -v sha256sum >/dev/null 2>&1; then broomm_psp_hash="$(sha256sum "$broomm_psp_d8" | cut -d ' ' -f 1)"
else broomm_psp_hash="$(shasum -a 256 "$broomm_psp_d8" | cut -d ' ' -f 1)"; fi
[[ "$broomm_psp_hash" == f8c762ff84640b10083b934a47278758a7665977e618fab0c927fff00521dea3 ]]
kotlinc android/app/src/main/kotlin/app/broomm/broomm/RootPpssppFiles.kt \
  android/app/src/main/kotlin/app/broomm/broomm/RootPpssppProcess.kt \
  android/app/src/main/kotlin/app/broomm/broomm/RootStandaloneProcess.kt \
  android/app/src/main/kotlin/app/broomm/broomm/AndroidShutdownLog.kt \
  android/app/src/main/kotlin/app/broomm/broomm/PpssppShutdownProof.kt \
  tool/android/check_root_psp_files.kt -jvm-target 17 -include-runtime \
  -classpath "$broomm_psp_cache/api/android.jar" -d "$broomm_psp_cache/root-psp-test.jar"
java -cp "$broomm_psp_d8" com.android.tools.r8.D8 --min-api 30 \
  --lib "$broomm_psp_cache/api/android.jar" --output "$broomm_psp_cache/root-psp-test-dex.zip" \
  "$broomm_psp_cache/root-psp-test.jar"
