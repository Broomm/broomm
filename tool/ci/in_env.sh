#!/usr/bin/env bash
# Devbox runs in its config directory; every CI command runs at the repo root.
set -euo pipefail
cd "$(dirname "$0")/../.."
broomm_cache_root="$PWD"
if [[ "${RUNNER_OS:-}" == Windows ]]; then broomm_cache_root="$(pwd -W)"; fi
export PUB_CACHE="$broomm_cache_root/.tool-cache/pub"
export GRADLE_USER_HOME="$broomm_cache_root/.tool-cache/android/gradle"
export FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true CI=true
if [[ "${TARGET_PLATFORM:-}" == android ]]; then
  # Ignore the hosted runner's inherited JAVA_HOME; use this Devbox's JDK.
  broomm_java="$(readlink -f "$(command -v java)")"
  JAVA_HOME="$(dirname "$(dirname "$broomm_java")")"
  export JAVA_HOME
  broomm_java_version="$("$JAVA_HOME/bin/java" --version)"
  if [[ "$broomm_java_version" != 'openjdk 21.'* ]]; then
    echo 'Android CI requires the pinned Devbox JDK 21.' >&2; exit 1
  fi
fi
exec "$@"
