#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
broomm_focus_cache="$PWD/.tool-cache/research/android"
# Reuse only the existing verified API and D8 provisioned by check_bridge.sh
# and build_root_save_test.sh. This is a development fixture, never bundled.
verify() {
  local actual
  if command -v sha256sum >/dev/null 2>&1; then actual="$(sha256sum "$1" | cut -d ' ' -f 1)"
  else actual="$(shasum -a 256 "$1" | cut -d ' ' -f 1)"; fi
  [[ "$actual" == "$2" ]] || { echo 'Android test dependency hash mismatch.' >&2; exit 1; }
}
verify "$broomm_focus_cache/api/android.jar" 2642c84655ceb87e009f04b279b4c60edcc1a869de80c707322f6c3da3b687fd
verify "$broomm_focus_cache/r8-9.5.29.jar" f8c762ff84640b10083b934a47278758a7665977e618fab0c927fff00521dea3
kotlinc tool/android/check_focus_highlight.kt -jvm-target 17 -include-runtime \
  -classpath "$broomm_focus_cache/api/android.jar" -d "$broomm_focus_cache/focus-test.jar"
java -cp "$broomm_focus_cache/r8-9.5.29.jar" com.android.tools.r8.D8 --min-api 26 \
  --lib "$broomm_focus_cache/api/android.jar" --output "$broomm_focus_cache/focus-test-dex.zip" \
  "$broomm_focus_cache/focus-test.jar"
echo "Compiled native focus check: $broomm_focus_cache/focus-test-dex.zip"
