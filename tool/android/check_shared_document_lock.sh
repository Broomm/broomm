#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p .tool-cache/research/android
kotlinc android/app/src/main/kotlin/app/broomm/broomm/SharedDocumentLock.kt \
  tool/android/check_shared_document_lock.kt -jvm-target 17 -include-runtime \
  -d .tool-cache/research/android/shared-document-lock-check.jar
java -jar .tool-cache/research/android/shared-document-lock-check.jar
