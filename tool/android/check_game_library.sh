#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p .tool-cache/research/android
kotlinc android/app/src/main/kotlin/app/broomm/broomm/GameLibraryFile.kt \
  tool/android/check_game_library.kt -jvm-target 17 -include-runtime \
  -d .tool-cache/research/android/game-library-check.jar
java -jar .tool-cache/research/android/game-library-check.jar
