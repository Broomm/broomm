#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p .tool-cache/research/android
kotlinc android/app/src/main/kotlin/app/broomm/broomm/RootInspectionCommand.kt \
  android/app/src/main/kotlin/app/broomm/broomm/PpssppStorageInspection.kt \
  tool/android/check_root_inspection.kt -jvm-target 17 -include-runtime \
  -d .tool-cache/research/android/root-inspection-check.jar
java -jar .tool-cache/research/android/root-inspection-check.jar
