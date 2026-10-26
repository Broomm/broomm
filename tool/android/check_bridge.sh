#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
broomm_android_cache="$PWD/.tool-cache/research/android"
mkdir -p "$broomm_android_cache/api"
hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d ' ' -f 1
  else shasum -a 256 "$1" | cut -d ' ' -f 1; fi
}
fetch() {
  local target="$broomm_android_cache/$1" url="$2" expected="$3"
  if [[ ! -f "$target" ]]; then
    curl --fail --location --silent --show-error --max-time 120 "$url" -o "$target.pending"
    [[ "$(hash_file "$target.pending")" == "$expected" ]] || { echo 'Compiler API download hash mismatch' >&2; rm -f "$target.pending"; exit 1; }
    mv "$target.pending" "$target"
  fi
  [[ "$(hash_file "$target")" == "$expected" ]] || { echo 'Compiler API cache hash mismatch' >&2; exit 1; }
}
fetch platform-36-ext19_r01.zip https://dl.google.com/android/repository/platform-36-ext19_r01.zip 55bd3620999428ff13097c982c9f0d40de566d846f0bed153bf8d4e1491b90ff
if [[ ! -f "$broomm_android_cache/api/android.jar" ]]; then
  unzip -p "$broomm_android_cache/platform-36-ext19_r01.zip" '*/android.jar' > "$broomm_android_cache/api/android.jar"
fi
[[ "$(hash_file "$broomm_android_cache/api/android.jar")" == 2642c84655ceb87e009f04b279b4c60edcc1a869de80c707322f6c3da3b687fd ]] || { echo 'Android API jar hash mismatch' >&2; exit 1; }
fetch flutter-embedding.jar https://storage.googleapis.com/download.flutter.io/io/flutter/flutter_embedding_release/1.0.0-5f77625673248ee5846fbcaf5d3e1a3878386fd7/flutter_embedding_release-1.0.0-5f77625673248ee5846fbcaf5d3e1a3878386fd7.jar 99d41bef0e3aa240b310cdaf1df6406e606b841336826cee9c9a5159db58280f
fetch lifecycle-common.jar https://dl.google.com/dl/android/maven2/androidx/lifecycle/lifecycle-common/2.7.0/lifecycle-common-2.7.0.jar 533ded8ee0645a18f6653da53fe1ec5a15430e7f36a737d45e410531f30f3318
kotlinc android/app/src/main/kotlin/app/broomm/broomm/*.kt -jvm-target 17 \
  -classpath "$broomm_android_cache/api/android.jar:$broomm_android_cache/flutter-embedding.jar:$broomm_android_cache/lifecycle-common.jar" \
  -d "$broomm_android_cache/bridge.jar"
