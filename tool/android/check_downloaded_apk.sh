#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p .tool-cache/research/android
kotlinc android/app/src/main/kotlin/app/broomm/broomm/DownloadedApk.kt \
  tool/android/check_downloaded_apk.kt -jvm-target 17 -include-runtime \
  -d .tool-cache/research/android/downloaded-apk-check.jar
java -jar .tool-cache/research/android/downloaded-apk-check.jar
