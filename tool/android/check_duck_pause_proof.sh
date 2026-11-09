#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p .tool-cache/research/android
kotlinc android/app/src/main/kotlin/app/broomm/broomm/DuckPauseProof.kt tool/android/check_duck_pause_proof.kt \
  -jvm-target 17 -include-runtime -d .tool-cache/research/android/duck-pause-proof-test.jar
java -jar .tool-cache/research/android/duck-pause-proof-test.jar "$@"
